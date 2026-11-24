# Compact toolchain 0.37.0

- **Date:** 2026-11-30
- **Language version:** 0.29.0
- **Compact runtime version:** 0.22.0
- **Environment:** This release works with a Midnight ledger 9 blockchain.  For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview).

## High-level summary

Version 0.37.0 of the Compact toolchain is a major release.  It contains a number of bug fixes, two new features, and some breaking changes; see "Breaking changes" and the fixes marked breaking in the "Fixed defect" list.  If you are using an earlier ledger 9 compiler, you should update to 0.37.

You can update to version 0.37.0 using the Compact devtools.  `compact update` will update to the latest released version, and `compact update 0.37` will specifically update to the latest patch release of toolchain 0.37.

## Audience

These release notes are intended for Compact smart-contract developers and for DApp developers who use the Compact runtime.

## New features

### Casts are allowed in both directions between `JubjubScalar` and `Bytes<32>`

New casts are allowed between `JubjubScalar` and `Bytes<32>` in both directions, following the same rules as the foreign field casts.  Casting to `Bytes<32>` always succeeds, and casting to `JubjubScalar` reduces the value modulo the field order if it is too large.  The `Bytes<32>` representation is the little-endian encoding of the value.

### `canonicalContractAddress` is exported by the Compact runtime

The Compact runtime now exports `canonicalContractAddress`, which checks that its argument is a valid contract address and returns its canonical lowercase spelling.

## Breaking changes

### `createCircuitContext` rejects an invalid contract address

`createCircuitContext` in the Compact runtime now rejects an invalid `contractAddress` and throws a `CompactError`.

### Constructors that rely on initialized ledger state are rejected

The compiler now rejects constructors that call operations requiring the contract's state to be already initialized.  This includes certain standard library functions and ledger operations; see the [Compact language reference](https://docs.midnight.network/compact/reference/compact-reference#contract-constructor) for the full list.

## Fixed defect list

The following defects are fixed by updating to Compact toolchain 0.37.

- Fixed an internal compiler error when calling `resetToDefault()` on a `MerkleTree` or `HistoricMerkleTree` of depth 16–32, or when storing a default tree of such depth in a `Map` via `insertDefault()` or `insert()`.  ([#879](https://github.com/LFDT-Minokawa/compact/issues/879))

- Fixed an internal compiler error when calling `serialize` on certain deeply nested structures.  ([#943](https://github.com/LFDT-Minokawa/compact/issues/943))

- Fixed serialization and deserialization of `JubjubScalar` values, which failed with an internal compiler error.  Serialization and deserialization tried to use `Bytes<32>` casts which were not provided by the language.  ([#938](https://github.com/LFDT-Minokawa/compact/issues/938))

- Fixed the compiler's check that exported circuits do not modify `sealed` ledger fields, which did not look inside tuple and vector literals or the arguments of `map` and `fold`, including `for` loops over a computed vector.  Contracts that incorrectly compiled before will now fail to compile, so this is a **breaking** fix.  ([#932](https://github.com/LFDT-Minokawa/compact/issues/932))

- Fixed `sha512` so it disallows inputs that contain opaque types.  They cannot be hashed correctly in circuit.  They are now rejected, just as they already are rejected by the other byte-oriented hashing functions (`persistentHash`, `persistentCommit`, and `keccak256`).  Contracts that incorrectly compiled before will now fail to compile, so this is a **breaking** fix.

- Fixed the Compact runtime's stripping of a leading U+FEFF, as if it were a byte order mark, when reading an `Opaque<'string'>` value from ledger state.  The resulting string no longer matched the bytes stored on the ledger, so circuits that returned it, wrote it back, compared it, or used it as a map key could not be proven.

- Fixed the Compact runtime's rejection of shielded coins with values that did not fit in 64 bits when creating or looking up their commitments, even though `ShieldedCoinInfo.value` is a `Uint<128>`.  Circuits that received, merged, or sent such coins through the standard library failed before they could be proven.

- Fixed the Compact runtime's treatment of different hex spellings of the same contract address as different contracts.  `createCircuitContext` and `crossContractCall` keyed per-contract state and the re-entrancy guard by the address as spelled, so a re-entrant call using a differently-cased address was not refused and ran against a second copy of the contract's state.

- The Compact runtime's ledger decoding of `enum` types has been hardened to avoid a bug involving JavaScript's left-shift operation.  This could cause encoded values to be decoded incorrectly.  Such encodings were impractical to create in Compact, so this can only affect a DApp that used the runtime to decode `enum` types with more than `2^32` values.

- Fixed the Compact runtime's descriptor for `JubjubScalar`, which previously accepted values outside the `JubjubScalar` range.  Out-of-range values are now rejected on both encoding and decoding.  Compact code never wrote such values to the ledger, so this can only affect a DApp that used the runtime to encode or decode out-of-range `JubjubScalar` values.

## Links and references

- The [Compact documentation portal](https://docs.midnight.network/compact),
  including the [language reference](https://docs.midnight.network/compact/reference/compact-reference),
  the [standard library documentation](https://docs.midnight.network/compact/standard-library),
  and the [ledger ADT documentation](https://docs.midnight.network/compact/data-types/ledger-adt)
- The [Compact runtime TypeScript API](https://docs.midnight.network/api-reference/compact-runtime) for DApps
- [Compact compiler usage](https://docs.midnight.network/compact/reference/tools/compiler-usage)
- The [open-source project](https://github.com/LFDT-Minokawa/compact) on GitHub for bug reports and feature requests
