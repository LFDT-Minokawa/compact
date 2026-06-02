# compactc --rust: Rust backend for the Compact compiler

Branch: `codegen-rust`
Base: `main` (`LFDT-Minokawa/compact`)

## Summary

This PR adds a Rust target to `compactc`: a `.compact` contract compiled with
`compactc --rust` lowers to a native Rust crate that depends on a new
`compact-runtime` crate. The generated Rust mirrors the TypeScript backend
shape one-for-one (a `Contract<PS, W>` struct, `Contract::initial_state`
constructor, one method per impure circuit returning
`Result<CircuitResults<PS, R>, CompactError>`, a generated `Witnesses<PS>`
trait, and a `Ledger<'_>` view) so a host program can mix Rust contracts
with TypeScript clients on the same ledger without any representation drift.

Byte-parity with the TypeScript backend is the primary correctness gate:
the on-chain `ContractState.serialize()` output produced after running
`initial_state` and every circuit is asserted byte-identical against
captured TS reference bytes. The 39 byte-parity integration tests in
`tests-e2e-rust` plus 44 unit tests in `compact-runtime` give 83 passing
tests total. A `codegen_regression` integration test additionally
regenerates every committed fixture with the host `compactc` and asserts
the on-disk `lib.rs` is byte-identical, so the 21 generated fixture crates
under `tests-e2e-rust/contracts/*/lib.rs` never drift from emitter output.

CI lives at `.github/workflows/rust-runtime-test.yml` and gates
`cargo fmt --all --check`, `cargo clippy ... -- -D warnings`, and
`cargo test -p compact-runtime -p tests-e2e-rust` on Linux + macOS for
every PR that touches Rust paths.

## Why now

Rust services in the Midnight ecosystem currently cannot consume Compact
contracts: the TypeScript backend is the only target `compactc` supports,
so any Rust client that wants to construct, dispatch, or verify a
Compact-defined state transition has to call out to a Node.js process or
re-implement the contract in Rust by hand. This PR closes that gap for the
structural backbone of the language — the feature surface exercised by the
upstream byte-parity test corpus — so a Rust host can drive a Compact
contract directly.

## What's included

### Codegen (Scheme)

- `compiler/rust-passes-*.ss` — 6,656 LOC of Chez Scheme across 7 logical
  modules:
  - `rust-passes-helpers.ss` (351 LOC) — `rust-feature-error` helper,
    string utilities, ledger-slot indexing.
  - `rust-passes-types.ss` (222 LOC) — Compact type → Rust type lowering.
  - `rust-passes-prelude.ss` (284 LOC) — generated `use` clauses, native
    function bindings.
  - `rust-passes-decls.ss` (354 LOC) — top-level declaration emission
    (structs, enums, witnesses trait, Ledger view).
  - `rust-passes-walker.ss` (2,828 LOC) — multi-stage circuit-body walker
    (interleaved `const`/`assert`/`insert`/`if` statements,
    cross-circuit calls, ADT method dispatch).
  - `rust-passes-emit.ss` (2,078 LOC) — expression emission, ledger-read
    paths, persistent-hash arg encoding, struct-literal lowering.
  - `rust-passes-streaming.ss` (539 LOC) — streaming-token walker for
    constructor body and exported impure circuits.
- `compiler/passes.ss:188-200` — post-emit rustfmt hook that pipes the
  written `lib.rs` through `rustfmt --edition 2021` when rustfmt is on
  PATH (soft-dep — missing rustfmt is non-fatal so the unit-test fast
  path is unaffected).
- `compiler/cli.ss` — `--rust` flag (emit the Rust crate alongside the TS
  output) and `--skip-ts` flag (Rust-only output).

### Runtime crate (`runtime-rs/`)

- `runtime-rs/src/lib.rs` — curated prelude that re-exports the subset of
  `midnight-ledger`, `midnight-base-crypto`, `midnight-transient-crypto`,
  and `midnight-onchain-runtime` APIs the codegen actually emits against,
  so generated `lib.rs` files open with `use compact_runtime::*;` and
  nothing else.
- `runtime-rs/src/std_lib/` — submodules split by concern:
  - `adts.rs` — `Counter`, `Cell`, `Map`, `Set`, `MerkleTree`,
    `HistoricMerkleTree`, `List` wrappers.
  - `bytes_pad_disclose.rs` — `pad(N, "str")`, `disclose(x)` lowering
    helpers.
  - `field_repr.rs` — orphan-safe `bytes_from_field_repr`,
    `vec_u8_from_field_repr`, `array_from_field_repr`.
  - `jubjub.rs` — `hash_to_curve`, `ec_add`, `ec_mul`.
  - `maybe.rs` — `Maybe<T>` + `some<T>(v)` / `none<T>()`.
  - `merkle_path.rs` — `MerkleTreePath` unified with upstream
    `MerklePath`.
  - `opaque.rs` — `OpaqueString` + generic `Opaque<T>`.
- `runtime-rs/src/op_builder.rs` — typed `OpProgramVerify` /
  `OpProgramGather` builders that replace ad-hoc `vec![]` of `Op`
  enum variants at call sites.
- `runtime-rs/src/builders.rs` — `empty_charged_state`,
  `initial_cost_model`, helpers around upstream-API friction points.
- `runtime-rs/src/context.rs` — `CircuitContext`, `ConstructorContext`,
  `WitnessContext`.
- `runtime-rs/src/results.rs` — `CircuitResults`, `ConstructorResult`
  aggregates.
- `runtime-rs/src/version.rs` + `check_runtime_version!` macro —
  compile-time exact-version pin between `compactc` and the linked
  runtime.
- `runtime-rs/src/error.rs` — `CompactError` + `compact_assert!` macro.
- `runtime-rs/src/witness.rs` — `WitnessContext`, `NoWitnesses` marker.

### Test surface (`tests-e2e-rust/`)

- 21 generated fixture crates under `tests-e2e-rust/contracts/*/lib.rs`
  — every file is regenerated by `compactc --rust` and locked in by the
  `codegen_regression` integration test; no hand-edited generated files.
- 39 byte-parity integration tests under `tests-e2e-rust/tests/*.rs` —
  drive each fixture's constructor + every circuit and assert
  `ContractState.serialize()` output is byte-identical to TS reference
  bytes captured under `tests-e2e-rust/ts-reference/`.
- `tests-e2e-rust/tests/witness_leak_check.rs` — negative regression
  test that drives `tiny.compact` with a sentinel `[0x07; 32]` witness
  return value and asserts the 32-byte (and 16-byte prefix) pattern
  never appears as a contiguous subsequence in serialised
  `ContractState` bytes at any step.

### CI

`.github/workflows/rust-runtime-test.yml` adds the **Rust runtime + e2e
tests** workflow with two jobs:
- `pre-check` (Linux): `cargo fmt --all --check`, then
  `cargo clippy -p compact-runtime -p compact-runtime-macros -p tests-e2e-rust --all-targets -- -D warnings`.
- `test` (Linux + macOS):
  `cargo test -p compact-runtime -p tests-e2e-rust`.

Triggered on every push to `main` and every PR that touches
`runtime-rs/**`, `runtime-rs-macros/**`, `tests-e2e-rust/**`,
`compiler/rust-passes*.ss`, `compiler/rust-passes/**`, `examples/**`,
or the workspace `Cargo.toml`/`Cargo.lock`.

### Documentation

- `doc/rust-codegen-user-guide.md` — end-user guide: quick start,
  feature support matrix, troubleshooting, versioning.
- `compiler/README-rust-passes.md` — Scheme module map for codegen
  contributors.
- `runtime-rs/README.md` — runtime prelude + `std_lib` layout for runtime
  contributors.
- `tests-e2e-rust/README.md` — byte-parity test recipe (how to add a new
  fixture).
- `docs/superpowers/research/2026-06-02-upstream-parity-gap-report.md` —
  feature-by-feature parity gap report (the source of truth for the
  matrix below).
- `docs/superpowers/research/2026-06-02-witness-threading-audit.md` —
  security audit of private-state threading; verdict Sound.

## Coverage matrix

Condensed from `doc/rust-codegen-user-guide.md`. **Supported** means
exercised by at least one byte-parity test. **Partial** means the
codegen accepts the construct but with caveats. **Not yet** means
`compactc --rust` aborts with a tagged feature-error.

### Primitives

| Feature | Status |
|---|---|
| `Field` / `Boolean` / `Bytes<N>` / `Vector<N,T>` / `Uint<8..128>` | Supported |
| `Uint<L..U>` (bounded range) | Supported — lowered to smallest fixed-width Uint by frontend (Iter 8) |
| `Opaque<"string">` / `Opaque<T>` | Supported |
| `Maybe<T>` | Supported |

### Compact standard-library ADTs

| ADT | Status |
|---|---|
| `Counter` / `Cell<T>` | Supported |
| `Map<K, V>` (incl. nested `Map<K, Map<...>>`) | Supported — `.insert` / `.lookup` / `.member` emit; nested chained lookup not exercised |
| `Set<T>` | Supported — `.insert` / `.member` emit; `.size()` / `.isEmpty()` not exercised |
| `MerkleTree<H, T>` | Supported |
| `HistoricMerkleTree<H, T>` | Supported — `.checkRoot` works; `.insertIndexDefault` not yet |
| `List<T>` | Supported — `pushFront` / `popFront` / `head` / `length` / `isEmpty` (Iter 3) |

### User-defined types

| Feature | Status |
|---|---|
| `struct S { ... }` (exported + non-exported) | Supported — `Aligned` / `FieldRepr` / `FromFieldRepr` / `BinaryHashRepr` impls auto-emit |
| Generic structs `struct S<a, #n> { ... }` | Not yet |
| `enum E { ... }` | Supported — `default<E>` lowers to first variant |
| `type Alias = ...` (transparent + nominal newtype) | Supported |

### Circuits and witnesses

| Feature | Status |
|---|---|
| `export circuit f(...): T { ... }` | Supported |
| Non-exported circuit (called locally) | Supported |
| Cross-circuit call to exported impure circuit | Supported |
| `pure circuit f(...): T { ... }` | Supported — emitter does not branch on the `pure` keyword, so `pure` compiles but is treated the same as impure |
| Generic circuits `circuit f<#N>(...)` | Supported — `expand-modules-and-types` monomorphises pre-Rust-IR (Iter 11). Generic stdlib calls (`merkleTreePathRoot<N, T>`) exercised by zerocash + election. User-defined generic circuits called in body position blocked by the same gap as non-generic user circuit calls in body position. |
| Constructor with parameters / implicit zero-arg | Supported |
| Top-level `witness f(...): T;` | Supported — one method per declaration in generated `Witnesses<PS>` trait |
| Module-local `witness` | Supported — inlined by frontend |

### Control flow

| Feature | Status |
|---|---|
| `if`/`else`, ternary | Supported |
| `for (const i of L..U) { ... }` (range loop) | Supported — unrolled at codegen time when bounds are static literals (Iter 4) |
| `for (const x of iterable) { ... }` (element loop) | Supported — same compile-time unrolling (Iter 5) |
| `fold((acc, x) => ..., init, vec)` | Supported (basic) — closed-over variables + side-effect-free accumulators (Iter 6) |
| `map(fn, arr)` | Supported — including non-identity arithmetic lambdas over `Uint` widths for `+ - *` (Iter 7 + follow-up) |
| Bare lambdas in expression position | Supported in `map` / `fold` contexts; standalone IIFE not yet |
| Comma-sequenced exprs | Supported |
| `assert(cond, "msg")` | Supported — lowers to `compact_assert!` |

### Modules

| Feature | Status |
|---|---|
| `module M { ... }` / `import M` / `import M prefix P_` / nested modules | Supported — inlined pre-Rust-IR by `expand-modules-and-types` (Iter 10). No codegen-side work; `module_fixture.compact` byte-parity locks the invariant in. |
| `export { ... }` block | Supported |

### Natives

| Feature | Status |
|---|---|
| `persistentHash` / `persistentCommit` / `transientHash` / `transientCommit` | Supported |
| `hashToCurve` | Mapped; no byte-parity fixture |
| Jubjub / EC primitives, Zswap witnesses | Supported |
| `keccak256` / `sha256` | Mapped (untested — not exercised by upstream corpus) |
| `pad(N, "str")` | Supported — byte-parity confirmed identical (Prod-15 finding overturned earlier diagnosis) |
| `disclose(x)` | Supported |

### Casts and miscellaneous

| Feature | Status |
|---|---|
| `as Uint<...>` / `as Bytes<...>` / `as Field` (trivial cases) | Supported |
| `Bytes[1, 2, 3, ...]` literal | Supported |
| `[a, b, c]` array literal (homogeneous) | Supported |
| `[a, b, c]` array literal (mixed type) | Not yet |
| Compound `+=` / indexed read `v[i]` | Supported |
| `contract C {}` declarations | Not yet |

## Compile-time safety

The Prod-3 finding: rather than emit `unimplemented!()` Rust for
constructs the codegen does not lower (which would produce a runtime
panic with no compiler diagnostic), `compactc --rust` aborts at compile
time with

```
compactc --rust: unsupported Compact construct (TAG): <details>
```

where `TAG` names the offending node kind. This was promoted from
`unimplemented!()` to hard-error at 19 distinct emission sites — every
known gap surfaces at compile time, never at runtime. The TypeScript
backend continues to work in parallel; the error is fatal only for the
Rust target.

Tagged feature gates (alphabetised):

- `adt-read-with-arg-lowering`
- `circuit-body-emission`
- `downcast-unsigned-width`
- `enum-ref-non-tenum`
- `expr-variant`
- `ledger-op-non-read`
- `ledger-read-decoder-missing`
- `ledger-read-non-index-path`
- `map-mvp-shape`
- `native-binding-missing`
- `non-native-call`
- `persistent-hash-arity`
- `pure-circuit-body-emission`
- `quote-variant`
- `struct-literal-field-count-mismatch`
- `struct-literal-mismatch`
- `struct-literal-non-tstruct`
- `tuple-spread`
- `witness-inline`

The helper is at `compiler/rust-passes-helpers.ss:34`.

## Architectural decisions worth flagging

### Compile-time loop unrolling

`for`-range, `for`-iter, `fold`, and `map` all unroll at codegen time
when bounds are static literals. The unrolled sequence is then handed
to the same expression emitter the rest of the body uses. This works
for the upstream test corpus (loop bounds are uniformly small constants),
but does **not** scale to large `N` — a 256-iteration constructor inlines
256 `OpProgramVerify` chains into `initial_state`. A runtime-loop
construct that emits the loop as a `for` in Rust (carrying state through
the loop body) is a follow-up. The current shape is sound; it just
generates more code than necessary at larger bounds.

### Generated fixtures, no hand edits

Every committed `tests-e2e-rust/contracts/*/lib.rs` is the output of
`compactc --rust` on the matching `.compact` source. The
`codegen_regression` integration test (run on every CI invocation)
regenerates each fixture and asserts the on-disk file is byte-identical.
Reviewers can take this as: if the test passes, no fixture has been
hand-edited away from emitter output.

### rustfmt post-emit

`compactc --rust` pipes the freshly-written `lib.rs` through
`rustfmt --edition 2021` (see `compiler/passes.ss:188-200`). This is a
soft dep — when `rustfmt` is not on PATH the emit succeeds anyway and
the unformatted output is left in place. Production environments will
have rustfmt; the soft-fail keeps the compiler self-test path
(no Rust toolchain required) functional.

### License headers

The codegen emits the full Apache-2.0 + Midnight Foundation copyright
header on every generated `lib.rs`, matching the repo's
`python3 add_headers.py --validate` gate. Every new hand-written file
(runtime sources, test sources, the workflow YAML, the contributor
READMEs) also carries the header. Prod-10 verified by running
`add_headers.py --validate` against the full set; all files pass.

### Witness threading: audited Sound

`docs/superpowers/research/2026-06-02-witness-threading-audit.md`
documents the Prod-8 code-review audit of private-state (`PS`) threading
through generated code. Verdict: **Sound** — `PS` values never enter the
serialised `ContractState` bytes. The verdict is locked in operationally
by `tests-e2e-rust/tests/witness_leak_check.rs` (Prod-11), which drives
`tiny.compact` with a sentinel `[0x07; 32]` secret-key witness return and
asserts the 32-byte (and 16-byte prefix) pattern never appears as a
contiguous subsequence of serialised state at any step.

### Exact-version pin

Generated `lib.rs` files open with
`compact_runtime::check_runtime_version!("0.16.100")`. This is a
compile-time `const_assert`: linking a contract emitted by one `compactc`
version against a different `compact-runtime` version produces a build
error, not a runtime ABI mismatch. The pin is exact, not semver-ranged
— the assumption is that any prelude change might shift generated-code
ABI.

## Known limitations

Specific items from the gap report that this PR does not close:

- **Generic structs** — `struct S<a, #n> { ... }`. `compactc --rust`
  aborts with a feature-error.
- **`map()` over `Field` arithmetic** — non-identity arithmetic in `map`
  lambdas works for `+ - *` on `Uint` widths but not for `Field` (`Fr`)
  arithmetic.
- **Nested Map chained lookup** — `m.lookup(k1).lookup(k2)` in expression
  position. Honourable mention.
- **`HistoricMerkleTree.insertIndexDefault`** — only `.checkRoot` is
  exercised. Honourable mention.
- **`hashToCurve` byte-parity** — the symbol is mapped through the
  runtime but no byte-parity fixture exercises it.
- **Standalone IIFE / lambda in arbitrary expression position** —
  lambdas work as arguments to `map` and `fold` but not as
  expression-position values themselves.
- **Large-`N` loop bodies** — see "Compile-time loop unrolling" above.
- **`contract C {}` declarations** — `compactc --rust` aborts.
- **Mixed-type array literals** — `[Uint<8>, Bytes<8>]` style.

Module / generic-circuit / pure-circuit support is "free from frontend
desugaring" — no codegen-side work was needed. `expand-modules-and-types`
at `compiler/analysis-passes.ss:43` (`Lpreexpand → Lexpanded`) strips
`(module ...)` / `(import ...)` from the IR entirely and monomorphises
generics, so the Rust emitter only ever sees flat, fully-monomorphised
declarations (Iter 10 + Iter 11 findings).

## How to review

Suggested reading order:

1. `doc/rust-codegen-user-guide.md` — end-user perspective. Quick-start,
   feature support matrix, troubleshooting. Best entry point to see
   what the surface looks like to a downstream Rust developer.
2. `compiler/README-rust-passes.md` — Scheme module map. Which pass
   does what, where to add code.
3. `runtime-rs/README.md` — runtime prelude + `std_lib` layout. Where
   to add stdlib helpers and how the curated re-exports keep generated
   code small.
4. One generated fixture — `tests-e2e-rust/contracts/tiny/lib.rs` —
   to see actual emitter output shape.
5. `tests-e2e-rust/tests/codegen_regression.rs` — the byte-parity
   guarantee for the fixture corpus. Pair with one of the per-fixture
   tests (e.g. `tests-e2e-rust/tests/tiny.rs`) to see the
   `ContractState.serialize()` comparison loop.

For the security-sensitive bits:
- `docs/superpowers/research/2026-06-02-witness-threading-audit.md`
- `tests-e2e-rust/tests/witness_leak_check.rs`

## Test plan

- `cargo test -p compact-runtime -p tests-e2e-rust` → 83 passed
  (44 runtime unit + 39 e2e integration).
- `cargo fmt --all --check` → clean.
- `cargo clippy -p compact-runtime -p compact-runtime-macros -p tests-e2e-rust --all-targets -- -D warnings` → clean.
- `python3 add_headers.py --validate` → all files validated.
- `cargo test -p tests-e2e-rust --test codegen_regression` → 21 fixtures
  regenerated byte-identical.
- CI workflow `Rust runtime + e2e tests` → green on Linux + macOS.

## Commit history

The branch carries ~50 commits grouped by phase. A condensed view:

### M1 + M2 — compiler scaffolding and counter byte-parity
- `bb801db` design docs, `17c169c` implementation plan.
- `c825c2a` scaffold compact-runtime, `ebff33d` curated re-exports.
- `e92d311` … `f206ab8` `--rust` CLI flag + scaffold `rust-passes.ss`.
- `9a0875b` → `4c31f27` emit `Contract<PS,W>` + `initial_state` +
  per-circuit method + ledger view for `counter.compact`.
- `5991038` byte-parity test for counter, `8550363` snapshot test.

### M3 — multi-contract surface coverage
- `H5–H7` (user struct emission), `R1` (ADT runtime), `R2` (native
  mapping), `R3` (alignment-aware persistent-hash args), `R4` (ledger
  view decoders).
- `E2` → `E6.2` exported / cross-circuit / if-statement-body shapes.
- `F1.1`, `F1.2`, `F2.1`, `F2.2` zerocash + election multi-step
  byte-parity.

### M3.5 — emitter validation closure (commit `f6e2f1a`)
- Streaming walker, BinaryHashRepr, defensive `.clone()`, MerkleTree
  harness, decoupled fixture constants.
- All 23 e2e tests passing, 0 ignored.

### Iter 1-12 — parity gap closure
- Iter 1 (`f6e2f1a`) split rust-passes.ss into 7 modules.
- Iter 2 (`c92c668`) upstream parity gap report.
- Iter 3-8 List, for-range, for-iter, fold, map+lambda, bounded uints.
- Iter 9-12 pure circuit modifier, modules (closed by frontend),
  generic circuits (closed by frontend), mop-up.

### Prod-1 through Prod-16 — hardening for upstream submission
- Prod-1+2 (`0fee454`, `8e38680`) CI workflow.
- Prod-3 (`9bc9e13`, `27b3d61`) hard-fail on the 19 emission sites.
- Prod-4 (`cc60f90`, `cd219fa`, `d3505a9`) user guide + rustdoc +
  README badges.
- Prod-5a (`bcd4dbf`) sealed-ledger byte-parity.
- Prod-6 (`c426462`) toolchain version bump + changelog.
- Prod-7 (`06e689e`) rustfmt post-emit.
- Prod-8 + Prod-11 (`78fdc8f`, `eaf4074`) witness-threading audit +
  negative regression test.
- Prod-9 (`72b352a`) `Fr::from(N)` for Field-typed integer literals.
- Prod-10 (`60aae92`) Apache-2.0 license headers.
- Prod-12-15 (`0e7a990`, `bc410af`) snapshot refresh, Uint literal RHS,
  gensym tmp, Bytes<N>-from-pad encoding.
- Prod-16 (`732c2f1`) crates.io publication plan.

## What's NOT in this PR

- **Publication to crates.io.** Planned separately. See the publication
  plan at
  `docs/superpowers/notes/2026-06-02-crates-io-publication-plan.md`.
- **Honourable-mention follow-ups** — nested Map chained lookup,
  `HistoricMerkleTree.insertIndexDefault`, `hashToCurve` byte-parity
  fixture, generic structs, standalone-position lambdas. To be filed as
  separate issues once this lands.
- **Runtime-loop codegen** — the compile-time unrolling shape works for
  the upstream test corpus but doesn't scale to large `N`. A
  runtime-loop construct is a follow-up.
- **Mixed-type array literals**, **`contract C {}` declarations** —
  feature-gated; tracked separately.
