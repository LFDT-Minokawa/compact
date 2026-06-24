<!--
This file is part of Compact.
Copyright (C) 2026 Midnight Foundation
SPDX-License-Identifier: Apache-2.0
-->

# Walker-gap closure status — codegen-rust (2026-06-24)

This note documents the cumulative state of the `compactc --rust` walker
gap taxonomy as of the A19 closure. It supersedes the partial taxonomy
in [ADR 0005 (midnight-did-rs)](../../../midnight-did-rs/doc/adr/0005-codegen-gap-handling.md)
and tracks the closures since the M3.5 design (`docs/superpowers/specs/2026-05-29-rust-codegen-m35-design.md`).

## What the walker is

Compact's body-emission pipeline pre-validates each circuit body
against a set of shape predicates (the "walker") before the matching
emitter renders Rust. Each A-step closes one body shape encountered in
real Compact contracts (the `did.compact` source has driven most of
A6–A19). When no predicate matches, the emitter raises
`rust-feature-error 'circuit-body-emission "no walker shape matched
circuit body for <name>"`.

## A-step ledger

| # | Shape | Closed | Trigger contract |
|---|-------|--------|------------------|
| A1–A4 | Multi-PL-call + write body | M3.5 | counter, tiny |
| A5 | Ledger-read decoder for did types | M3.5 | did.compact |
| A6 | Witness call in pure-circuit arg position | M3.5 | did.compact |
| A7 | Assert-only impure body | DID-A | did.compact `assertController` |
| A8 | ADT-read-with-arg lowering | DID-A | did.compact |
| A9 | `rotateControllerKey` Cell.write shape | DID-A | did.compact |
| A10 | Multi-index Cell.write path | DID-A | did.compact |
| A11 | `recordUpdate`: disclose + assignment | DID-A | did.compact |
| A12 | if/else-if body with assert+pl-call branches | DID-A | did.compact `setAlsoKnownAs` |
| A13 | 2-arg if (no else) + `rem` vminstr | DID-A | did.compact |
| A14 | In-branch lifted-let + assert-only if arms | DID-A | did.compact `setVerificationMethod` |
| A15 | Non-pure circuit call in expression position | DID-A | did.compact |
| A16 | Map.insert with struct value + runtime-keyed idx | DID-A | did.compact |
| A17 | `setVerificationMethodRelation`: bare-call arm + multi-stmt pure body + drifted-ctx const-binding | DID-A | did.compact |
| **A18** | **Drop body-needs-streaming? preference gate** | **2026-06-24** | did.compact `insertVerificationMethodRelation`, `removeVerificationMethodRelationFromLedger` |
| **A19** | **Multi-arm if/else-if non-unit body + single-return body** | **2026-06-24** | did.compact `verificationMethodExists`, `verificationMethodRelationMember` |

A1–A19 close every walker rejection on `did.compact`. As of A19,
`compactc --rust ... did.compact ...` succeeds end-to-end, producing a
~2.7k-line `lib.rs`.

## A18 — drop the streaming preference gate

The pre-A18 dispatcher tried, in order:
```
(body-walkable? → emit-body-or-fallback)
∨ (body-streaming-walkable? ∧ body-needs-streaming? → emit-streaming-body)
```

The `body-needs-streaming?` gate was a preference signal — "prefer
emit-body-or-fallback when it can handle this shape." But when
`body-walkable?` rejects a shape that streaming-walker accepts, the
gate caused us to never reach `emit-streaming-body`, surfacing as
"no walker shape matched" instead.

A18 drops the gate. `body-streaming-walkable?` is a strict superset
of `body-walkable?`'s shapes; falling through to streaming when the
simpler walker rejects is always safe. The change in
[rust-passes-emit.ss](../../../compiler/rust-passes-emit.ss) and
[rust-passes-walker.ss](../../../compiler/rust-passes-walker.ss) is
small (~5 LOC).

Unblocks: 5-arm if/else-if dispatch over an enum with a single
pl-call per arm (no asserts) — the `insertVerificationMethodRelation`
and `removeVerificationMethodRelationFromLedger` helpers in
`did.compact`.

## A19 — multi-arm chain + single-return non-unit bodies

Pre-A19, `stmt->if-expression-body` admitted exactly one shape:
single-statement `(if cond then-stmt else-stmt)` with each arm
reducing to a return-expression (tiny.compact's `get()`).

A19 introduces `stmt->if-chain-body` covering three richer shapes:

1. **Single statement-expression** — `return X || Y;` body.
   Closes `verificationMethodExists`.
2. **If/else-if chain with else arm** — n-arm cascade with all paths
   returning a value.
3. **If/else-if chain with trailing return** — n arms with no inner
   else, followed by a final `return default;` statement.
   Closes `verificationMethodRelationMember` (5-arm chain over
   `VerificationMethodRelation` + `return false`).

Returns `(arms else-expr)` where `arms = ((cond-expr then-expr) ...)`.
The companion `emit-if-chain-body` renders the cascade as
`let result = if c1 { t1 } else if c2 { t2 } else { else_expr };`
wrapped in `Ok(CircuitResults { result, context: ctx, gas_cost: RunningCost::default() })`.

Read-only bodies pay no verify cost — these helpers don't mutate
state, so `RunningCost::default()` is correct (matches the existing
`emit-if-expression-body` convention).

`impure-circuit-body-walkable?` was extended to also admit the new
chain shape, so non-exported helpers with these bodies are emitted
as `pub(crate) fn` methods.

## Pre-A18 reachability gate (a.k.a. "silent skip") — still active

`rust-passes.ss:116` gates non-exported impure circuit emission on
`(id-exported? ∨ impure-circuit-body-walkable?)`. Circuits that
fail both are silently skipped, with the contract that "callers
inline them via cond-rust's `inline-circuit-call`, or fail at their
own walker check."

The static-analysis pass on 2026-06-24 confirmed `tiny.compact`'s
`in_state` (a non-exported impure circuit with a `return state == s`
body, non-unit return) still depends on this silent-skip path —
it's inlined into `set`'s assert via `cond-rust`. Removing the
silent skip would require either:

(a) A reachability pre-pass that emits only referenced helpers and
    hard-errors on shape-mismatches, OR
(b) Closing the walker shape for in_state (single-return Boolean body
    that reads a ledger cell with `==`).

A19 closes (b) — `in_state` now matches `stmt->if-chain-body`'s
single-return shape. Future A20 should drop the silent-skip gate
entirely once all current fixtures are confirmed walkable.

## did.compact downstream Rust gaps (post-A19)

The compactc-side walker is now clean for `did.compact`. The
generated `lib.rs` (drop into
`midnight-did-rs/crates/midnight-did-runtime/src/contract/generated.rs`)
still has ~12 unique Rust compile errors, grouped:

### Compiler-side
- ~~**Bug-1**: `id` not in scope inside inlined ADT-read calls~~
  **Closed 2026-06-24** ([1c66b32](../../../compiler/rust-passes-emit.ss)):
  new `current-var-substitution` dynamic parameter mirrors
  ctor-expr-rust's `local-binds`; `expr-rust`'s var-ref clause
  consults it before the default rendering.
- ~~**Bug-2**: `ConstructorContext.current_query_context` missing~~
  **Closed 2026-06-24** ([d551c12](../../../compiler/rust-passes-walker.ss)):
  emit-ctor-body-or-fallback parameterizes `current-qctx-ref` to
  `"&qctx"` before delegating, so in-expr ledger reads in the
  constructor body read from the local qctx (built from the K1 seed)
  instead of `&ctx.current_query_context` (which doesn't exist on
  ConstructorContext).
- ~~**Bug-3**: `compact_runtime::CircuitContext::clone` trait bound
  not satisfied~~ **Closed 2026-06-24** ([1c66b32](../../../compiler/rust-passes-prelude.ss)):
  added `PS: Clone` to the `impl<PS, W> Contract<PS, W>` where-clause
  in `emit-contract-struct`. Upward-compatible.
- ~~**Bug-4**: enum-typed `==` rendered RHS as `Nu8` instead of
  `Enum::Variant` (18 sites)~~ **Closed 2026-06-24**
  ([c58d563](../../../compiler/rust-passes-walker.ss)): the `(==
  src type expr1 expr2)` IR node carries the resolved comparison
  type directly. Prefer it via `tenum-name-of-type` before the
  operand-side heuristics in the `==` / `!=` rendering clauses.
- ~~**Bug-5**: duplicate `let tmp = X` in arm pre-stmts (2-4 sites)~~
  **Closed 2026-06-24** ([0da200a](../../../compiler/rust-passes-streaming.ss)):
  the frontend lift emits the same `(= tmp expr)` more than once
  per arm when the lifted local is read from both the assert cond
  and the terminal pl-call. Dedupe by rendered Rust name during the
  A12/A14 pre-stmts iteration.
- ~~**Bug-6**: non-Copy var-ref / elt-ref lifted to a `let` without
  `.clone()` (~6 sites)~~ **Closed 2026-06-24**
  ([0da200a](../../../compiler/rust-passes-streaming.ss)): route lifted
  RHSs through `expr-rust-arg-cloned` in three places (arm pre-stmts
  emit, top-level const-binding else, emit-body-or-fallback
  const-binding) so partial moves don't break later usage of the
  parent struct/local.
- ~~**Bug-7**: `ctx` moved into a hoisted impure call inside an
  if-arm (2 sites)~~ **Closed 2026-06-24**
  ([0da200a](../../../compiler/rust-passes-walker.ss)):
  `emit-hoisted-impure-calls` now detects arm context by indent
  depth and emits `ctx.clone()` so the surrounding scope's
  post-arm `CircuitContext { ..ctx }` rebind still has ctx
  available. Top-level body keeps the existing move semantics.

### Runtime-side (R5)
- `EmbeddedGroupAffine: FromFieldRepr / field_repr / field_size /
  binary_repr / binary_len` — missing trait impls. **Orphan-rule
  blocked**: both `EmbeddedGroupAffine` and the `FromFieldRepr`
  trait live in upstream `midnight-transient-crypto`, so a downstream
  impl in `compact-runtime` violates Rust's coherence rules. Closing
  this needs either (a) a wrapper newtype around `EmbeddedGroupAffine`
  that compact-runtime owns + a codegen change to use it instead of
  the raw alias, OR (b) an upstream PR adding the impls to
  midnight-transient-crypto. Option (b) is cleaner long-term;
  option (a) is faster locally but locks compact-runtime into the
  wrapper indefinitely.
- `[Fr; 4]: Aligned / FromFieldRepr`, `Value: From<[Fr; 4]>`,
  `binary_repr`, `binary_len` — fixed-size `Fr` array marshalling.
  Same orphan-rule shape. A typed helper-function path (à la
  `field_repr::array_from_field_repr`) already exists for `[T; N]`
  with `T: FromFieldRepr`; codegen would have to route `[Fr; 4]`
  through it instead of emitting raw `<[Fr;4] as FromFieldRepr>`.
- ~~`OpProgramVerify::rem`~~ **Resolved 2026-06-24** by refreshing
  midnight-did-rs's flake input
  (`nix flake update compact`) — the worktree branch had `rem` in
  op_builder.rs:78 the whole time; only the downstream Cargo
  resolution was stale.
- `schnorr_verify` witness method missing — actually a circuit
  module-import issue, not a witness. The `Schnorr_schnorrVerify<#n>`
  generic circuit from the inner schnorr module isn't being emitted
  as a `pub(crate) fn` even though jubjub-schnorr's
  `schnorrVerifyDigest` calls it. Likely a module/generic
  resolution gap — see [project_walker_gaps](#) for the chain.

### Test status
- All `compactc` tests except the pre-existing `test_compact_check_no_param`
  network-update probe pass.
- All `tests-e2e-rust` byte-parity fixtures (24 codegen_regression +
  per-contract byte-parity tests) pass unchanged through A18+A19.

## Cross-references

- ADR 0005 (midnight-did-rs): codegen-gap-handling strategy. Shape
  A–E classification predates the current A-step taxonomy.
- `docs/superpowers/specs/2026-05-29-rust-codegen-m35-design.md`:
  M3.5 design with body-walker dispatch architecture.
- `docs/rust-codegen-user-guide.md`: user-facing guide; mentions
  body shapes the codegen accepts.
