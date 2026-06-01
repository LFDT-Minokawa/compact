# `compactc --rust` codegen — module map

This document is a roadmap of the Scheme pass that emits Rust crates from
Compact source. It's for engineers landing changes in `rust-passes-*.ss` —
the design background lives in
[`docs/superpowers/specs/2026-05-25-rust-codegen-design.md`](../docs/superpowers/specs/2026-05-25-rust-codegen-design.md).

## Where in the pipeline

`compactc --rust` runs the standard frontend (parse → expand → type
infer → desugar modules → monomorphise → resolve natives → lower for
the codegen target) and then hands an `Ltypescript` IR program to the
`print-rust` pass defined in [`rust-passes.ss`](./rust-passes.ss). That
pass walks the IR top-down and writes a single `contract/lib.rs` plus
a `contract/Cargo.toml` to the output directory.

`Ltypescript` is the same IR the TypeScript backend consumes — see
[`langs.ss`](./langs.ss) line 846. Reading the TS emitter
([`typescript-passes.ss`](./typescript-passes.ss)) is often the fastest
way to understand what a given IR node should produce, because the TS
codegen has full coverage and the Rust codegen is catching up.

## Module map

The `print-rust` pass is split into seven Scheme files included from
[`rust-passes.ss`](./rust-passes.ss). They cooperate via shared
identifiers from `(pass-helpers)` and from each other; the include
order in `rust-passes.ss` is the loading order, so a helper defined
later may be referenced by an earlier file as long as the call site
isn't reached during macro expansion.

| File | LOC | Purpose | Touch when... |
|---|---:|---|---|
| `rust-passes.ss` | ~100 | Entry point. Defines `print-rust` + the `Program` clause that drives top-level emission. | Reordering top-level emission stages (typedefs → witnesses → contract struct → initial-state → circuits → ledger view → Cargo.toml). |
| `rust-passes-helpers.ss` | ~250 | Identifier helpers (casing, sym ⇄ rust id), parameters/fluids, stdlib lookup tables. | Renaming conventions, adding a new fluid/parameter, registering a new stdlib mapping. |
| `rust-passes-types.ss` | ~210 | `type-rust` and per-field encoding helpers (`Aligned` / `FieldRepr` / `FromFieldRepr` field emission). | Adding support for a new Compact type variant (e.g. `Uint<L..U>`, `List<T>`, generic structs). |
| `rust-passes-prelude.ss` | ~250 | File header, `emit-witnesses`, `emit-contract-struct`, `program-*` IR collectors. | Changing the file preamble, witness trait shape, or contract-struct layout. |
| `rust-passes-decls.ss` | ~340 | `collect-pure-circuit-tdefns` + `emit-type-decls` (user enums and structs with their `Aligned`/`FieldRepr`/`FromFieldRepr` impls). | Adding a new declaration kind (e.g. nominal aliases get rust newtype wrappers) or fixing user-type encoding. |
| `rust-passes-walker.ss` | ~2400 | Body walker. `body-walkable?` predicates and `emit-body-or-fallback` central dispatch — translates Compact statements to Rust expressions on the `OpProgramVerify` / `OpProgramGather` builder chain. Also: constructor body emission, for-range / for-iter / fold expansion, loop-var substitution. | Adding a new statement shape, a new RHS form for `const` bindings, a new ledger op, or extending control flow. **The main hub** — most circuit-body features land here. |
| `rust-passes-streaming.ss` | ~520 | Multi-stage body walker — handles bodies that interleave gather (ledger read) and verify (ledger write) ops, plus mid-body `if` statements that mix the two. | Touching bodies where impure `if`s appear between ledger reads and writes. Otherwise the simpler walker is enough. |
| `rust-passes-emit.ss` | ~1850 | `emit-initial-state` + circuit body assembly + ledger-view emission. Renders the actual Rust text — VM-instruction → builder-method translations live here. | Changing how an ADT seeds its initial StateValue (`new_map` / `new_merkle_tree` / `new_list`), or how a VM op renders as a builder call. |

## How a new feature lands

For most upstream-parity gaps, the path is:

1. **Reproduce the IR shape.** Run `./result/bin/compactc --trace-passes
   --skip-zk examples/<fixture>.compact /tmp/<out>/ 2>&1 | grep -A5
   "after print-rust"` (or earlier passes) to see what `Ltypescript`
   shape the construct lowers to. The IR shape determines which file
   you touch.
2. **Add the dispatch.** Most features mean a new `[(...) ...]` clause
   in either `body-walkable?` or `emit-body-or-fallback` in
   `rust-passes-walker.ss`. Mirror an existing clause that does
   something similar.
3. **Add runtime support if needed.** New types or builders go in
   `runtime-rs/src/{builders,std_lib}.rs` and get re-exported from
   `lib.rs`.
4. **Add a fixture.** Drop a small `.compact` source in `examples/`,
   wire a new crate under `tests-e2e-rust/contracts/<name>-fixture/`,
   capture the TS reference state, and add a Rust byte-parity test.
   The recipe is in [`tests-e2e-rust/README.md`](../tests-e2e-rust/README.md).
5. **Verify regen.** `cargo test -p tests-e2e-rust --test
   codegen_regression` re-runs `compactc --rust` against every example
   and asserts the emitted `lib.rs` is byte-identical to the committed
   one. This is the regression guard that protects against the
   "Scheme doesn't compile but tests pass" failure mode.

## Conventions

- Every new pattern match begins with the cheapest predicate. Walkers
  bail to `unimplemented!()` rather than producing wrong code.
- Defensive `.clone()` is preferred over borrow gymnastics on
  generated code — the cost is paid once at compile time, never at
  runtime.
- Stdlib symbols carry `(rust "name")` annotations in
  [`midnight-natives.ss`](./midnight-natives.ss); the codegen routes
  them through `runtime-rs::std_lib`. Don't hard-code stdlib names in
  the walker — extend the lookup table in `rust-passes-helpers.ss`.
- Section comments inside the large modules (`walker.ss`, `emit.ss`)
  follow a `;; --- NAME ----------------------------------------` form
  so they show up in editor outlines. Add one whenever you introduce
  a new logical section.

## When something breaks

- **Codegen builds but emits malformed Rust.** Run `./result/bin/compactc
  --rust --skip-zk examples/<failing>.compact /tmp/regen/` and read
  `/tmp/regen/contract/lib.rs`. Diff against a known-good fixture.
- **Codegen Scheme doesn't compile.** Most often: pattern-matching against
  a non-terminal that's been removed at the current language layer.
  Check [`langs.ss`](./langs.ss) for `(- (form ...))` markers that
  remove forms in the language hierarchy.
- **`codegen_regression` test fails.** The committed `lib.rs` in
  `tests-e2e-rust/contracts/<name>-fixture/lib.rs` has drifted from
  what `compactc` now emits. Regenerate and inspect the diff — either
  fix the Scheme or update the committed `lib.rs` (whichever reflects
  the intended change).
