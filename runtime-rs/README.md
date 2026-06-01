# `compact-runtime`

Native Rust runtime for contracts emitted by `compactc --rust`. This
crate is the Rust counterpart to the TypeScript package
`@midnight-ntwrk/compact-runtime`. **Generated contract code depends on
it; users typically do not consume it directly.**

## What this crate provides

- **A curated prelude** (`use compact_runtime::*;`). Generated `lib.rs`
  files reference upstream Midnight types via `compact_runtime`'s
  re-exports — never directly. That keeps the codegen's `type-rust`
  mapping in [`compiler/rust-passes-types.ss`](../compiler/rust-passes-types.ss)
  short and stable, and lets us replace upstream symbols without
  regenerating every test fixture.
- **Facade aggregates** for the contract surface area: `Contract`'s
  `ConstructorContext` / `CircuitContext`, the matching `Result`
  envelopes, the `WitnessContext` plumbing, and the `CompactError`
  enum that every generated method returns through.
- **The Compact standard library**, under [`src/std_lib/`](./src/std_lib/) —
  ledger ADT wrappers (`Counter`), per-width decoders, the `Maybe<T>`
  option type, `pad` / `disclose` helpers, byte-and-field-repr
  bridges, Jubjub/EC native shims, Merkle path computation.
- **Builder helpers** in [`src/builders.rs`](./src/builders.rs) —
  `new_cell` / `new_map` / `new_merkle_tree` / `new_list` /
  `new_cell_bounded_uint` etc. The codegen calls these to seed the
  initial `StateValue` for each ledger field.
- **VM op-program builders** in [`src/op_builder.rs`](./src/op_builder.rs) —
  `OpProgramVerify` and `OpProgramGather`. Generated circuit bodies
  chain these calls (`.dup() .idx_at_index(...) .push(...) .ins(...)
  .build()`) to assemble a transcript.

## Layering

```
┌─────────────────────────────────────────────────────────────┐
│  Generated contract (tests-e2e-rust/contracts/*/lib.rs)     │
│  - Uses only items from compact_runtime's prelude.          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  compact-runtime  (this crate)                              │
│  - Curates the prelude.                                     │
│  - Adds the Compact-level facades (Maybe, Counter, …).      │
│  - Wraps upstream so the codegen can stay schema-stable.    │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  Upstream Midnight crates (workspace deps)                  │
│  - midnight-base-crypto    (Aligned, AlignedValue, hash)    │
│  - midnight-transient-crypto  (Fr, MerkleTree, ec curves)   │
│  - midnight-storage       (StateValue, ChargedState, …)     │
│  - midnight-onchain-state / -vm / -runtime                  │
│  - midnight-coin-structure                                  │
│  - midnight-zswap                                           │
└─────────────────────────────────────────────────────────────┘
```

The codegen never names an upstream type directly; it always goes
through `compact_runtime::*`. When upstream renames or relocates a
type, we update the prelude here, not in every generated file.

## Module map

| File | Purpose |
|---|---|
| [`src/lib.rs`](./src/lib.rs) | Prelude re-exports + module declarations. |
| [`src/context.rs`](./src/context.rs) | `ConstructorContext`, `CircuitContext`. |
| [`src/results.rs`](./src/results.rs) | `ConstructorResult`, `CircuitResults`. |
| [`src/witness.rs`](./src/witness.rs) | `WitnessContext`, `NoWitnesses`. |
| [`src/error.rs`](./src/error.rs) | `CompactError`. |
| [`src/version.rs`](./src/version.rs) | `COMPACT_RUNTIME_VERSION` + `check_runtime_version!`. |
| [`src/builders.rs`](./src/builders.rs) | `StateValue` constructors: `new_cell`, `new_map`, `new_merkle_tree`, `new_list`, `new_cell_bounded_uint`, etc. |
| [`src/op_builder.rs`](./src/op_builder.rs) | VM op-program builders: `OpProgramVerify` / `OpProgramGather` with `.dup/.idx_at_index/.push/.ins/.popeq/.member/.eq/.root/.addi/.build`. |
| [`src/query.rs`](./src/query.rs) | `query_for_read` + `query_for_verify` — drive `QueryContext` through an op program. |
| [`src/std_lib/`](./src/std_lib/) | Compact standard library — see below. |

## `std_lib` submodules

| Submodule | What's here |
|---|---|
| [`adts.rs`](./src/std_lib/adts.rs) | `Counter` newtype + per-width decoders (`decode_u8`/`u16`/`u32`/`u64`/`u128`/`bool`/`fr`/`bytes`/`vector_fr`/`via_field_repr`). `serialize_contract_state` lives here too. |
| [`maybe.rs`](./src/std_lib/maybe.rs) | `Maybe<T>` option type + `some` / `none` constructors and trait impls (`Aligned`, `FieldRepr`, `FromFieldRepr`, `From<Maybe<T>>` for `Value`). |
| [`bytes_pad_disclose.rs`](./src/std_lib/bytes_pad_disclose.rs) | `Bytes<N>` alias, `pad(width, s)`, `disclose`, `persistent_hash_aligned`. |
| [`field_repr.rs`](./src/std_lib/field_repr.rs) | `bytes_from_field_repr`, `vec_u8_from_field_repr`, `array_from_field_repr` — the orphan-rule-safe deserialisers the codegen calls from inside generated struct `FromFieldRepr` bodies. |
| [`opaque.rs`](./src/std_lib/opaque.rs) | `OpaqueString` newtype + trait impls. |
| [`jubjub.rs`](./src/std_lib/jubjub.rs) | Jubjub / EC native wrappers: `jubjub_point_x/y`, `ec_add`, `ec_mul`, `ec_mul_generator`, `construct_jubjub_point`, `degrade_to_transient`, `upgrade_from_transient`. |
| [`merkle_path.rs`](./src/std_lib/merkle_path.rs) | `merkle_tree_path_root`, `merkle_tree_path_root_no_leaf_hash`, `default_merkle_path`. |

The codegen routes stdlib symbols through `runtime-rs` based on the
`(rust "...")` annotations in
[`compiler/midnight-natives.ss`](../compiler/midnight-natives.ss). To
add a new stdlib symbol, expose it from `std_lib`, re-export it from
`lib.rs`, and add a mapping entry to the codegen's stdlib lookup
table.

## Versioning

`COMPACT_RUNTIME_VERSION` is a compile-time string in
[`src/version.rs`](./src/version.rs). Every generated `lib.rs` opens
with `compact_runtime::check_runtime_version!("X.Y.Z");` so a mismatch
between the runtime crate and the codegen version surfaces as a
build-time error rather than a runtime mystery.

## Related docs

- [`../compiler/README-rust-passes.md`](../compiler/README-rust-passes.md) — Scheme codegen module map.
- [`../tests-e2e-rust/README.md`](../tests-e2e-rust/README.md) — how byte-parity tests are structured.
- [`../docs/superpowers/specs/2026-05-25-rust-codegen-design.md`](../docs/superpowers/specs/2026-05-25-rust-codegen-design.md) — original design doc.
