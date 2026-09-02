# `midnight-compact-runtime`

[![CI](https://github.com/LFDT-Minokawa/compact/actions/workflows/midnight-compact-runtime.yml/badge.svg)](https://github.com/LFDT-Minokawa/compact/actions/workflows/midnight-compact-runtime.yml)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](../LICENSE)

Native Rust runtime for contracts emitted by `compactc --rust`. This
crate is the Rust counterpart to the TypeScript package
`@midnight-ntwrk/compact-runtime`. **Generated contract code depends on
it; users typically do not consume it directly.**

The compiler side of this — the `compactc` flag that emits Rust, and the
walkthrough for wiring a generated crate — is not in the tree yet. This crate
lands first, on its own, because nothing depends on it and it can be reviewed
without any Compact knowledge: it is an ordinary Rust library over the
`midnight-ledger` crates.

## What this crate provides

- **A curated prelude** (`use midnight_compact_runtime::*;`). Generated `lib.rs`
  files reference upstream Midnight types via `midnight_compact_runtime`'s
  re-exports — never directly. That keeps the codegen's `type-rust`
  mapping lives in the compiler's Rust emitter, which is not in the tree yet
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
│  - Uses only items from midnight_compact_runtime's prelude.          │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  midnight-compact-runtime  (this crate)                              │
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
through `midnight_compact_runtime::*`. When upstream renames or relocates a
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

## Testing

139 tests, unit and integration, run on Linux and macOS. Both platforms on
purpose: this crate's job is producing bytes a chain will agree with, and an
endianness or alignment mistake would pass on one and fail on the other.

The tests target the places where a mistake produces a *wrong answer* rather
than a crash, and coverage is uneven by design rather than by neglect:

| Area | Why it is tested the way it is |
|---|---|
| TypeScript parity | `tests/typescript_parity.rs` asserts Rust results against the normative TypeScript rule, one test per place the two once disagreed. This class of bug — a wrapper written against a real upstream primitive with the right-sounding name, which turned out to be a different function — is invisible to any test that only reads the Rust side. |
| Curve operations | Asserted as algebraic laws — commutativity, `p + (-p) = O`, `ec_mul` agreeing with repeated addition — so a transcription error cannot pass by coincidence. Separately, that `JubjubPoint::to_group` rejects every non-subgroup pair without panicking, since a `JubjubPoint` can come straight from a ledger cell. |
| Field representation | Round-trips, plus the boundaries of the 31-byte packing, plus rejection of short slices. A truncated ledger value must not decode into a plausible array. |
| Ledger-read decoders | Values, not just success. Every width at its extremes, because a width mistake shows up at `u64::MAX`, not at 7. |
| Merkle path folding | The `goes_left` argument order asserted against hand-computed hashes. Inverting it yields a different root that still looks valid. |
| `Maybe<T>` | That `Some(default)` and `None` encode *differently* — otherwise every `None` reads back as `Some`. |
| Version check | `const_str_eq` asserted inside `const` blocks, so it fails at compile time if const evaluation is wrong. |

**What is deliberately not covered**, and why chasing it would be worse than
leaving it:

- **The op-program builder's fluent setters.** Each is `self.ops.push(Op::X{…}); self`. A test asserting that `.push()` pushes is a test of the test. What actually matters is whether an assembled op program matches what the chain expects — and that is verified end-to-end against TypeScript-generated reference state, in the byte-parity corpus that arrives with the compiler side of this work.
- **Trivial constructors and accessors** in `context.rs`, `witness.rs`, `results.rs`.
- **`narrowing`'s `TryFrom` fallback**, documented as unreachable while the emitter picks the target width, and reported rather than unwrapped precisely so a future emitter change surfaces instead of panicking.

## Versioning

**This crate is versioned in lockstep with the TypeScript runtime it mirrors.**
`runtime/package.json` is at `0.19.100` and so is this crate, deliberately: the
two are the same runtime for two languages, and a reader comparing them should
not have to work out which pair of versions correspond.

`COMPACT_RUNTIME_VERSION` is a compile-time string in
[`src/version.rs`](./src/version.rs). Every generated `lib.rs` opens
with `midnight_compact_runtime::check_runtime_version!("X.Y.Z");` so a mismatch
between the runtime crate and the codegen version surfaces as a
build-time error rather than a runtime mystery.

## Related

- [`@midnight-ntwrk/compact-runtime`](https://www.npmjs.com/package/@midnight-ntwrk/compact-runtime)
  — the TypeScript runtime this crate is the counterpart to. Where the two
  disagree on emitted state, TypeScript is normative and this crate has the
  bug.
- The `midnight-ledger` crates this is layered over —
  `midnight-onchain-state`, `midnight-onchain-vm`, `midnight-transient-crypto`,
  `midnight-storage` — are re-exported from `lib.rs` so generated code needs
  only this one dependency.
