# Compact toolchain 0.34.0

- **Date:** 2026-08-18
- **Language version:** 0.26.0
- **Compact runtime version:** 0.19.0
- **Environment:** This release works with a Midnight ledger 9 blockchain.  For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.34.0 of the Compact toolchain is a major release.

This release builds on 0.33.0, which added support for ledger version 9, cross-contract calls, events, serialization/deserialization of Compact values, and support for ZKIR version 3.

Ledger version 9 will be, but is not yet, deployed on Midnight Mainnet.  If you are building contracts to be deployed to the current (as of Aug 18) Midnight Mainnet, you should continue to use Compact toolchain 0.31.x.

You can update to version 0.34.0 using the Compact devtools.  `compact update` will update to the latest released version, and `compact update 0.34` will specifically update to the latest patch release of toolchain 0.34.  You can also switch back to toolchain version 0.31.x with `compact update 0.31`.

## Audience

These release notes are intended for Compact smart-contract developers and for DApp developers who use the Compact runtime.

## What changed

## New features

### Shielded (Zswap) coin operations by cross-contract callees

Cross-contract callees may now perform shielded (Zswap) coin operations. Previously the runtime blanked a callee's Zswap local state before invoking it, so `receiveShielded`, `sendShielded`, `mergeCoin` and friends failed with "Zswap local state is undefined for contract". That blocked the pattern the ledger actually requires: a shielded coin addressed to a contract is only credited if that contract claims the receive in the same transaction, which for a callee means running `receiveShielded` during the call.

`CircuitContext` now carries `zswapLocalStates`, a per-contract-address record alongside `queryContexts` and `gasCosts`. Each contract in the call tree keeps its own state — its own `currentIndex`, `inputs` and `outputs` — sharing only the transaction submitter's coin public key. A callee's state is created on first entry, threaded back to the caller on return, and recorded on the call's `CallProofData` as `zswapLocalState` so transaction assembly can attribute every contract-owned input and output to the contract that made it.

This covers all three Zswap natives — `ownPublicKey`, `createZswapInput` and `createZswapOutput`. Note that `ownPublicKey()` always names the transaction submitter, never the calling contract. A callee meaning to pay back its caller wants that caller's `ContractAddress`, not `ownPublicKey()`.

### Infix arithmetic extended to `Secp256k1Base` and `Secp256k1Scalar`

The binary arithmetic operators `+`, `-`, and `*` now work for `Secp256k1Base` and `Secp256k1Scalar`.  The operands must have the same type and the result will have that type.  There is a new runtime function to perform subtraction for these types.

### `--feature-zkir-v3` and `--no-communications-commitment`

The ZKIR v3 printer now respects the --no-communications-commitment flag.

### `Uint<0>` is now a valid type

The type `Uint<0>` is allowed where previously it was a compiler error.  It's equivalent to `Uint<0..1>` by the rule and the fact that 2^0 equals 1. `Uint<0..1>` is allowed so there is no reason to prohibit `Uint<0>` even though it's not super useful.

### Compact runtime `secp256k1EcdsaRecover` function

The Compact JavaScript runtime now exports `secp256k1EcdsaRecover`.  Given a 32-byte message hash, an ECDSA signature, and a recovery id, it returns the corresponding secp256k1 public key.

Recovery runs off-circuit: the intended pattern is to recover the key here, pass it into a circuit as a witness or an argument, and constrain it there with the standard library's `secp256k1EcdsaVerify`.

`secp256k1EcdsaVerify` accepts both low-s and high-s signatures, as [FIPS 186-5](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-5.pdf) section 6.4.2 constrains `s` only to `[1, n - 1]`.

### Support for `Secp256k1Point` identity and comparisons

The compiler now supports secp256k1 identity points.

The identity point can be obtained via `default<Secp256k1Point>`.

Identity points are equal to identity points, and non-identity points are equal if they have the same affine X- and Y- coordinates.

The standard library's `secp256k1EthereumAddress` circuit now asserts that the input is not the secp256k1 identity point, because it does not have a corresponding Ethereum address.

### Compact runtime `toBinaryRepr` function

The new Compact runtime function `toBinaryRepr` replicates the effect of the
on-chain Rust `binary_repr`.  It is now used the runtime for the argument to the
Noble hashes `keccak_256` function to correctly replicate the in-circuit
implementation.  This ensures that trailing zero bytes from byte vectors are
preserved and hashed in JS as well as in circuit.

### Modular reduction in casts to foreign fields

The casting of byte vectors to foreign fields now performs modular reduction by the field modulus rather than failing for byte vectors encoding values out of range. The failure is kept for native fields to avoid a breaking change at this time.

### Faster manifest-file hash computation

The compiler also now hashes manifest files in-process using Common Crypto (OSX) or OpenSSL when available, which tends to be much faster than running a shell command for each hash computation. When neither Common Crypto nor OpenSSL is available, the system tries to run `sha256sum` first, then `shasum -a 256`.

## Breaking changes

### Changes to point and scalar types

The types `JubjubPoint` and `Secp256k1Point` are no longer defined as nominal type aliases for opaque types but rather standard-library names for internally handled types.  They can no longer be exported from a contract's top level.

Similarly, the types `JubjubScalar`, `Secp256k1Base`, and `Secp256k1Scalar` are no longer built-in types but rather standard-library names for internally handled types.  Programs must now import these types from CompactStandardLibrary to use them.

### Run-time checks for opaque types

The generated JS code now has circuit argument and witness return value type checks for the JS opaque types `Opaque<'string'>` and `Opaque<'Uint8Array'>`. Before, we allowed any value at all to be passed or returned.  This is a breaking change for programs that relied on being able to store any random JS value as, say, an `Opaque<'string'>`.

### Equality of `Opaque<'Uint8Array'>` values

Equality of `Opaque<'Uint8Array'>` is now (1) same length and (2) element-wise strict equality (`===`).  It was formerly simple strict equality, which for typed arrays is object reference equality.

This is a breaking change in the language, because `Uint8Arrays` that were formerly not equal in Compact can now compare as equal.

This change brings the JS semantics effectively in line with the ZKIR semantics, which uses equality of the Poseidon hash of the typed array's contents.

### Secp256k1Point accessor change

The JavaScript implementation of the accessors secp256k1PointX and secp256k1PointY now fail with a `CompactError` when passed the identity (`default`) point.  This matches the ZKIR behavior, where these operations fail.

Before, these accessors returned whatever was stored in the x- or y-coordinate of the JS object.  This was not a valid coordinate for this point, and not even a sentinel value like 0 because we don't currently canonicalize identity points.

This is a breaking change for circuits that do not require proofs and thus would not otherwise have failed.

### Compact runtime cleanup

The Compact runtime has been reorganized to reflect the intended structure: types and descriptors needed by the generated code are in `compact-types.ts`, but not redundant and unnecessary implementations; functions used by emitted code are in `built-ins.ts`, but not helpful utility functions; those are in `utils.ts`.

Some unused and unnecessary exported types and descriptors have been deleted. This is a breaking change for programs that accessed these types and descriptors.

### Standard-library `add` and `mul` have been removed

Now that the infix operators `+`, `-`, and `*` can be used for `Secp256k1Base` and
`Secp256k1Scalar` values, the standard library circuits `add` and `mul` have been
removed.

## Fixed defect list

The following defects are fixed by updating to Compact toolchain 0.34.

[Issue #588: persistentHash of a struct with a 0-bit field (single-variant enum / Uint{maxval:0}) emits inconsistent zkir](https://github.com/LFDT-Minokawa/compact/issues/588)

[Issue #590: midnight-events.ss: ShieldedReceive field order does not match CoIP-442 / MIP-0002](https://github.com/LFDT-Minokawa/compact/issues/590)

[Issue #608: keccak256<Secp256k1Point> crashes the compiler](https://github.com/LFDT-Minokawa/compact/issues/608)

[Issue #609: two secp256k1EcdsaVerify calls in one circuit crash the compiler](https://github.com/LFDT-Minokawa/compact/issues/609)

[Issue #704: ZKIR v3 internal error when nesting JubjubPoint within Map or a structured Compact type in the ledger](https://github.com/LFDT-Minokawa/compact/issues/704)

