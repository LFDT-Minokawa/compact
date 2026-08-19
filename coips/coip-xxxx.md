---
CoIP: X
Title: Rust code generation backend for the Compact compiler
Authors:
  - Pat Losoponkul (patextreme)
  - Yurii Shynbuiev (yshyn-iohk)
Status: Draft
Category: Tooling
Created: 2026-08-11
Requires:
Replaces:
---

<!--
 This file is part of Compact.
 Copyright (C) 2026 Minokawa project contributors
 SPDX-License-Identifier: Apache-2.0
 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 See the License for the specific language governing permissions and
 limitations under the License.
-->

## Abstract

The Compact compiler generates TypeScript. Any application that calls a
Compact contract off-chain must therefore run JavaScript.

This CoIP proposes adding **Rust as a second target language**. A new
`--rust` flag makes `compactc` emit a Rust module beside the TypeScript
one, shaped the same way: a contract type with one method per exported
circuit, a witnesses trait, pure circuits, a typed ledger view, and a
constructor. A companion `compact-runtime` crate does for Rust what
`@midnight-ntwrk/compact-runtime` does for TypeScript.

Nothing changes unless you pass `--rust`. The backend adds emission
passes only — no new IR, no new language semantics, no change to how
Compact is type-checked or lowered. It is deliberately the smallest
addition that gives Rust programs what TypeScript programs already have.

Correctness is defined as *agreement with the TypeScript backend*: a
test harness compiles the same contracts with both backends and compares
the ledger operations they produce, byte for byte, alongside tests that
execute the generated code against the real ledger runtime.

A working implementation exists and is linked below. It has been run
against production contracts, including one with a 19-field ledger.

## Motivation

Today, writing a Compact application in any language other than
TypeScript means one of three things: embed a JavaScript engine, wrap
the WASM SDK and marshal across the boundary, or reimplement Compact's
lowering yourself. All three are poor.

This is not hypothetical. It shows up repeatedly:

- **MPS-0022** states the problem directly: "only JS/TS applications can
  interact with Compact contracts", and SDKs in other languages "have no
  supported path".
- An independent Rust SDK effort (`midnight-rs`) **forked this
  compiler**, because there was no supported way to extend it.
- Much of Midnight is already Rust — the ledger, on-chain runtime, VM,
  and proving stack. The TypeScript SDK reaches that Rust code through
  WASM. A Rust application currently goes Rust → JS → WASM → Rust to do
  what it could do directly.

Rust is also where several classes of Compact consumer naturally live:
backend services, CLIs, embedded targets, and mobile apps whose shared
core is Rust bound to Swift and Kotlin.

The maintainers have already described the shape of the fix. On the
MPS-0022 thread:

> "we're certainly open to adding other supported target language
> backends. You would have to implement only a very small number of
> passes (the TypeScript backend) to target another language, and you
> would need some equivalent of the Compact runtime…"

This CoIP is that suggestion, worked out and implemented.

## Specification

### What a user does

Compile with `--rust` (and optionally `--skip-ts` for Rust-only builds):

```
compactc --rust --skip-ts counter.compact out/
```

Given a contract like:

```compact
export ledger round: Counter;

export circuit increment(): [] {
  round.increment(1);
}
```

the generated Rust is used roughly like this (illustrative — the exact
names follow the emitted code):

```rust
let contract = Contract::new(witnesses);
let result = contract.increment(ctx)?;
let round = ledger(&result.context.state).round()?;
```

The intent is that a Rust developer reads the generated API the way a
TypeScript developer reads theirs today: circuits are methods, ledger
fields are accessors, witnesses are something you implement.

### Emitted layout

| Path | Contents |
|---|---|
| `contract/lib.rs` | the generated bindings |
| `Cargo.toml` | a buildable manifest for the generated crate |
| `compiler/contract-info.json`, `zkir/`, `keys/` | unchanged; the ZK artifact path is shared, not duplicated |

### Generated API surface

Mirrors the TypeScript backend one-for-one:

- **`Contract<PS, W>`** — one method per exported circuit, taking a
  circuit context plus typed arguments, returning typed results and the
  resulting query context (gas, effects, state).
- **`trait Witnesses<PS>`** — one method per declared witness; the
  analogue of the TypeScript witness record.
- **`pure_circuits`** — free functions for exported pure circuits.
- **`ledger(state)`** — a read-only view with one accessor per ledger
  field.
- **`initial_state(...)`** — the constructor, producing the same initial
  ledger layout as TypeScript (including the chunked representation used
  when a contract has more than 16 ledger fields).
- **Typed structs and enums** for the contract's own declarations, with
  the trait implementations needed to move values through cells, maps,
  and circuit arguments.

### The `compact-runtime` crate

What `@midnight-ntwrk/compact-runtime` is for TypeScript, this crate is
for Rust: query-context construction and execution, op-program builders,
standard-library shims (`persistentHash`/`transientHash`, Jubjub
helpers, `Maybe`/opaque/padding codecs), and conversion between Rust
types and `AlignedValue`s.

It **reimplements no ledger semantics**. It calls the same
`midnight-ledger` crates (`onchain-runtime`, `onchain-state`,
`onchain-vm`, `transient-crypto`) that the WASM SDK wraps.

Generated code pins its runtime version exactly, so a contract crate
cannot silently build against a drifted runtime.

### Where the runtime crate should live

We propose **in this repository**, for symmetry with the existing
target:

| TypeScript (today) | Rust (proposed) |
|---|---|
| `runtime/` → `@midnight-ntwrk/compact-runtime` | `runtime-rs/` → `compact-runtime` |
| `tests-e2e/` | `tests-e2e-rust/` |

There is a concrete reason beyond symmetry: `runtime/export-version.ss`
generates the runtime's version file during the compiler build, which is
how compiler and runtime stay in lockstep. A Rust runtime in the same
repository inherits that guarantee. One in a separate repository would
need it replaced by cross-repository release coordination.

**This is an open question for the TSC.** The authors will maintain the
crate wherever the project prefers; the choice affects packaging, not
design. See Rejected Ideas.

### How we know it is correct

"Correct" means **the Rust output drives the ledger exactly as the
TypeScript output does**. Two mechanisms enforce it:

1. **Byte-parity harness** — compile a shared contract corpus with both
   backends; compare the resulting ledger state layouts and op programs.
2. **Executing tests** — run generated constructors and circuits against
   the real ledger runtime and assert on results: state read back, gas
   accounting, and assertion failures.

Anything the backend cannot lower **fails compilation with an explicit
diagnostic**. It never emits code it is unsure of. Coverage grows one
shape at a time, and each closed gap leaves a regression fixture behind.

## Rationale

**Reuse the compiler; add only emission.** The backend consumes the same
analyzed IR as the TypeScript emitter, after the same front-end passes.
No second pipeline, no second definition of what Compact means. This is
also what keeps the change small enough to maintain.

**Generate code rather than interpret.** Interpreting ZKIR at runtime
serves a different goal (many languages from one artifact). Generating
code gives Rust users what TypeScript users have today: typed APIs their
IDE understands, compile-time errors when a contract changes, and no
interpreter to embed, audit, and version. The two approaches complement
each other; see Rejected Ideas.

**Make parity the reviewable property.** Reviewers should not have to
trust the emitter by reading Scheme. The harness demonstrates that the
Rust path and the TypeScript path produce the same ledger effects, and
the executing tests demonstrate behaviour rather than just bytes.

**Pin the runtime exactly.** Compact's TypeScript toolchain gets version
coherence from lockstep package releases. The Rust side gets it from an
exact-version check in generated code — less flexible on purpose,
because a silently mismatched runtime is a very unpleasant failure.

## Backwards Compatibility

**Not a breaking change.** The feature is entirely additive:

- Without `--rust`, compiler output is unchanged.
- No syntax or semantic change to the Compact language.
- No change to ZKIR, proving, or on-chain behaviour.
- The TypeScript backend remains the reference; Rust follows it.

## Security Implications

**No new cryptography and no second ledger implementation.** The
generated Rust performs ledger transitions through the existing
`midnight-ledger` crates — the same code the production WASM SDK wraps.
ZK artifacts come from the existing shared pipeline; this backend does
not touch proving.

The realistic risk is a **defective emitter** silently mis-encoding a
transition. Three things mitigate it: byte-parity against the TypeScript
backend, executing tests against the real runtime, and fail-closed
behaviour for any shape the backend cannot lower.

The supply-chain surface added is one crate in this repository, subject
to the same review, licensing, and sign-off requirements as everything
else here.

## How to Teach This

**For existing (TypeScript) users:** nothing changes, and nothing needs
to be learned.

**For Rust users:** one new documentation section, "Generating Rust
bindings", covering the flag, the emitted layout, and a walkthrough that
compiles `counter.compact` with `--rust --skip-ts` and drives
`increment` from a Rust test. Because the generated API mirrors the
TypeScript one, existing Compact documentation and examples transfer
almost directly — the mental model is unchanged.

**Reference documentation** ships as rustdoc on `compact-runtime` and on
the generated code itself, which carries doc comments.

## Implementation

A complete reference implementation exists and is in production use.

- **Code:** https://github.com/MediaNoxLabs/compact/tree/codegen-rust —
  emission passes in `compiler/rust-passes*.ss`, the runtime crate in
  `runtime-rs/`, the harness in `tests-e2e-rust/`.
- **Validated against real contracts:** the Midnight DID method contract
  (19 ledger fields, 12 circuits, witnesses, maps and sets, Schnorr
  verification) — resolved live against a standalone network from pure
  Rust, producing output byte-identical to the TypeScript resolver — and
  14 of 18 entry-point contracts in the Midnight verifiable-credentials
  suite.
- **Testing:** per-fixture byte-parity regression plus executing
  end-to-end tests, green in CI.

Suggested landing order, as separate reviewable pull requests:

1. `compact-runtime` (+ its proc-macro crate) — standalone, no compiler
   changes.
2. Native routing plumbing — small, and unblocks the rest.
3. The emission passes and the `--rust` / `--skip-ts` flags.
4. The end-to-end harness and its contract corpus.
5. CI wiring and documentation.

**Known limitations today:** a small number of body shapes fail closed
(each tracked with a minimal reproduction), and `Vector<n, T>` ledger
field decoders are incomplete. Neither affects the TypeScript backend.
The published implementation targets the released ledger line; a branch
tracking this repository's current ledger release candidate is in
progress.

## Rejected Ideas

**Interpreting ZKIR, or a new IR, in each target language.** This is
MPS-0022's direction, and a CoIP draft (#700) proposes emitting an
analyzed-IR artifact to support it. It addresses a broader problem — N
languages from one artifact — at the cost of an interpreter per language
and a representation to design, version, and secure. We are **not
proposing this instead**: ahead-of-time code generation and runtime
interpretation coexist comfortably in other ecosystems, and this CoIP
serves the type-safe Rust case now, using only IRs that already exist.

**Shipping the Rust `compact-runtime` from a separate repository.** This
would reduce the footprint here, and the authors will do it if the TSC
prefers. We propose against it because it would make Rust the only
Compact target whose runtime is not co-located with the compiler:
`--rust` would emit code that cannot build without a crate this project
does not control, and the compiler/runtime version guarantee that
`runtime/export-version.ss` provides in-repo would have to be replaced
by cross-repository coordination. Review burden is better addressed by
splitting the work into staged pull requests (see Implementation) than
by splitting the artifact across repositories.

**A standalone transpiler outside the compiler.** Gives up the front
end's analysis and the version lock, and forces a fork — the situation
that motivated this proposal.

**Calling the WASM SDK from Rust.** Round-trips Rust → JavaScript →
WASM(Rust), keeping a JavaScript engine as a permanent runtime
dependency. Unusable for embedded targets and awkward on mobile.

## References

- MPS-0022, *Language-Agnostic Representation of Compiled Compact
  Contracts* — midnightntwrk/midnight-improvement-proposals
- Maintainer discussion of target-language backends (source of the
  quotation above): midnightntwrk/midnight-improvement-proposals#188
- CoIP draft on a language-agnostic contract representation:
  LFDT-Minokawa/compact#700
- Reference implementation:
  https://github.com/MediaNoxLabs/compact/tree/codegen-rust
- A downstream consumer built on the generated bindings:
  https://github.com/MediaNoxLabs/midnight-identity

## Acknowledgements

Thanks to the Minokawa maintainers for the CoIP process and for the
MPS-0022 discussion that clarified where target-language backends
belong, and to the author of MPS-0022 and the `midnight-rs` SDK for
mapping out the non-JavaScript ecosystem need.

## Copyright

This CoIP is licensed under
[Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0).
