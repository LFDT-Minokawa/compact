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

- **A curated prelude** (`use midnight_compact_runtime::*;`). Generated
  `lib.rs` files reach upstream Midnight types through this crate's re-exports
  and never directly, so an upstream rename is absorbed here rather than in
  every generated file.
- **Facade aggregates** for the contract surface area: `Contract`'s
  `ConstructorContext` / `CircuitContext`, the matching `Result`
  envelopes, the `WitnessContext` plumbing, and the `CompactError`
  enum that every generated method returns through.
- **The Compact standard library**, under [`src/std_lib/`](./src/std_lib/) —
  ledger ADT wrappers (`Counter`), the ledger decoders, the `Maybe<T>`
  option type, `pad` / `disclose` helpers, byte-and-field-repr bridges,
  Jubjub/EC natives, Merkle path computation.
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
│  Generated contract  (emitted by `compactc --rust`)         │
│  - Uses only items from this crate's prelude.               │
└────────────────────────┬────────────────────────────────────┘
                         │
                         ▼
┌─────────────────────────────────────────────────────────────┐
│  midnight-compact-runtime  (this crate)                     │
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

## Relationship to the TypeScript runtime

`@midnight-ntwrk/compact-runtime` is normative. Where this crate and it could
disagree, this crate is wrong by definition — the TypeScript runtime is what
deployed contracts and the chain already agree on. Every rule below was read
out of `runtime/src/` and is pinned by a test in
[`tests/typescript_parity.rs`](./tests/typescript_parity.rs).

That constraint settled, the two runtimes are not equivalent in what they can
express, and the difference is concentrated in one place: **how much of a
Compact type survives into the host language.**

### Compact types across the two runtimes

| Compact type | TypeScript | Rust |
|---|---|---|
| `Field` | `bigint` | `Fr` |
| `Uint<0..255>` | `bigint` | `u8` |
| `Uint<0..2^64-1>` | `bigint` | `u64` |
| `Secp256k1Base` | `bigint` | its own type |
| `Secp256k1Scalar` | `bigint` | its own type |
| `Vector<3, Field>` | `bigint[]` | `[Fr; 3]` |
| `Bytes<32>` | `Uint8Array` | `[u8; 32]` |
| enum tag | `number` (floating point) | `u8` |
| `JubjubPoint` | `{ x: bigint, y: bigint }` | `JubjubPoint { x: Fr, y: Fr }` |
| witnesses | `Record<string, …>` | a `Witnesses<PS>` trait |
| `WitnessContext` | `WitnessContext<L = any, PS = any>` | `WitnessContext<PS>` |

The first five rows are the interesting ones. In TypeScript, `CompactTypeField`,
`CompactTypeUnsignedInteger`, `CompactTypeSecp256k1Base` and
`CompactTypeSecp256k1Scalar` are **all** declared as `CompactType<bigint>`, so
four distinct Compact types share one host type. Passing a `Field` where a
`Secp256k1Scalar` is expected type-checks; whether it then throws or silently
succeeds depends on the runtime value. In Rust they are different types and the
mix-up does not compile.

### What that buys, concretely

The TypeScript runtime contains **60 `throw` sites**. They fall into two groups,
and the split is what this crate is for.

**Checks that stop existing.** These are `toValue` failures — a program handing
the runtime a value its own Compact type excludes:

| TypeScript check | Why Rust cannot reach it |
|---|---|
| `expected ${this.length}-element array` | `[T; N]` — the length is in the type |
| `expected Bytes[${this.length}]` | `[u8; N]` — same |
| `!Number.isInteger(value)` on an enum tag | `u8` is an integer by construction; `number` is a float |
| `value < 0n` on any unsigned type | `u8`/`u64`/`u128` have no negative values |
| a missing or misspelled witness | `Witnesses<PS>` is a trait; the impl must be complete |
| a runtime/compiler version mismatch | `check_runtime_version!` is a `const` assertion, so `cargo build` fails |

The witness row is the clearest of these, because both backends emit code for
it and the two can be read side by side. The TypeScript backend generates one
runtime check per witness, plus one for the bag itself
([`print-typescript.ss`](../compiler/typescript-passes/print-typescript.ss),
`witness-checks`):

```js
if (typeof(witnesses) !== 'object') {
  throw new CompactError('first (witnesses) argument to Contract constructor is not an object');
}
if (typeof(witnesses.getSchnorrReduction) !== 'function') {
  throw new CompactError('… does not contain a function-valued field named getSchnorrReduction');
}
// … one more per witness
```

The Rust backend generates a trait and no checks at all:

```rust
pub trait Witnesses<PS> {
    fn get_schnorr_reduction<'a>(
        &self,
        ctx: &WitnessContext<Ledger<'a>, PS>,
        challenge_hash: Fr,
    ) -> (PS, (u8, u128));
    // … one method per witness
}
```

A contract with *n* witnesses therefore ships *n + 1* generated checks in
TypeScript and zero in Rust. The trait is also strictly stronger than what
those checks test: `typeof x === 'function'` says nothing about how many
arguments the witness takes or what it returns, whereas the signature above
pins both — a witness that returns the wrong type fails to compile rather than
producing a malformed transcript at proving time.

`checkRuntimeVersion(…)` follows the same pattern. It is a statement in the
generated TypeScript module, so it throws when the contract loads;
`check_runtime_version!` expands to `const _: () = assert!(…)` and fails
`cargo build`.

**Checks that remain, but move into the signature.** Decoding ledger bytes is a
genuine I/O boundary and stays fallible in any language. The difference is that
TypeScript's `fromValue(value): bigint` promises a `bigint` and throws instead —
nothing at the call site says it can fail — while these return
`Result<_, CompactError>`, which a caller cannot silently drop.

There is a second difference in that boundary. The TypeScript `CompactType`
interface documents `fromValue` as converting *"destructively; (partially)
consuming the input, and ignoring superfluous data for chaining"* — it calls
`value.shift()` on the caller's array, at 12 sites. Decoding is therefore
order-dependent, stateful, and not repeatable: the same value decoded twice
gives different answers. The decoders here take `&AlignedValue`, so decoding
cannot disturb what the caller still holds, and doing it twice gives the same
result both times.

### Where the two must not diverge

Type safety does not help with encoding rules, and that is exactly where the
subtle bugs live. Three worth knowing about, each with a test:

- **`hashToCurve` hashes the field-aligned value, not the Rust `FieldRepr`.**
  For a `Compress`-aligned type — `Opaque<"string">`, `Opaque<"Uint8Array">` —
  those are different functions, so the two runtimes would return different
  curve points for the same Compact value.
- **A Compact type's domain is not its storage width.** `Uint<0..100>` and
  `Uint<0..255>` are both one byte; `200` belongs to only one of them. Both the
  reader and the writer take the declared bound.
- **`JubjubPoint` is a coordinate pair, not a validated group element.**
  `constructJubjubPoint` performs no curve check in either runtime, and a ledger
  cell can hold any two field elements. Validation happens in
  `JubjubPoint::to_group`, at the operations that need a group element.

## `std_lib` submodules

| Submodule | What's here |
|---|---|
| [`adts.rs`](./src/std_lib/adts.rs) | `Counter`, and `serialize_contract_state`. |
| [`decode.rs`](./src/std_lib/decode.rs) | The width-typed ledger decoders — `decode_bounded_uint`, `decode_u8`/`u16`/`u32`/`u64`/`u128`, `decode_bool`, `decode_fr`, `decode_bytes`, `decode_vector_*`, `decode_jubjub_point`. |
| [`decode_field_repr.rs`](./src/std_lib/decode_field_repr.rs) | `decode_via_field_repr` and the alignment walk behind it, for composite types whose leaves span more than one field element. |
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
