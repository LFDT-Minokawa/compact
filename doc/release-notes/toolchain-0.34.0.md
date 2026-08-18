# Compact toolchain 0.34.0

- **Date:** 2026-08-18
- **Language version:** 0.26.0
- **Compact runtime version:** 0.19.0
- **Environment:** This release works with a Midnight ledger 9 blockchain.  For the full compatibility matrix, see the [release notes overview](https://docs.midnight.network/relnotes/overview)

## High-level summary

Version 0.34.0 of the Compact toolchain is a major release.

Ledger version 9 will be, but is not yet, deployed on Midnight Mainnet.  If you are building contracts to be deployed to the current (as of Aug 18) Midnight Mainnet, you should continue to use Compact toolchain 0.31.x.

You can update to version 0.34.0 using the Compact devtools.  `compact update` will update to the latest released version, and `compact update 0.34` will specifically update to the latest patch release of toolchain 0.34.  You can also switch back to toolchain version 0.31.x with `compact update 0.31`.

## Audience

These release notes are intended for Compact smart contract developers and for DApp developers who use the Compact runtime.

## What changed

## [Toolchain 0.33.122, language 0.25.107, runtime 0.18.107]

### Fixed

- Issue #704, where nested ZKIR v3 native-typed values did not have proper
  ledger conversions in-circuit.  The underlying issue was that we give these
  types a "pseudo-alignment" of `anative` in `flatten-datatypes`, and this
  alignment cannot appear in the ledger.  Consequently, we translate this into
  ledger alignments and ZKIR encoding instructions (essentially, flattening
  further) in the ZKIR v3 backend.
  
  There were three places that had near duplicates of this code: (1) for ZKIR
  hashing instructions that need an alignment, (2) for Impact `popeq`, (3) and
  for all other Impact instructions.  Only number (1) of those correctly handled
  nested ZKIR-typed values.
  
  The fix is to reuse the correct code everywhere.
  
  This revealed a different issue with the descriptors for secp256k1 points and
  field types, they did not properly nest inside Compact types because they did
  not consume the FAB encoding in `fromValue`.

## [Toolchain 0.33.121, language 0.25.107, runtime 0.18.106]

### Changed

- The compiler now hashes manifest files in-process using Common Crypto or
  OpenSSL when available.

## [Toolchain 0.33.120, language 0.25.107, runtime 0.18.106]

### Changed

- Pull in a version of the ledger with some ZKIR 3.1 features in it.

### Internal notes

- Update the ZKIR v3 ledger dependency (on `main`, the development branch) to
  pull in a version of the ledger that has the ZKIR 3.x features secp256r1 and
  Curve25519.  The `zkir-v3` and `zkir-v3-wasm` dependencies are changed to
  include the new features.  The `onchain-runtime-v4` dependency is kept to
  track the tag `ledger-9.1.0.0-rc.3`.

  The toolchain version is bumped (if nothing else, it reports a different
  string for `--feature-zkir-v3 --ledger-version`).

## [Toolchain 0.33.119, language 0.25.107, runtime 0.18.106]

### Changed

- Cross-contract callees may now perform shielded (Zswap) coin operations.
  Previously the runtime blanked a callee's Zswap local state before invoking
  it, so `receiveShielded`, `sendShielded`, `mergeCoin` and friends failed with
  "Zswap local state is undefined for contract". That blocked the pattern the
  ledger actually requires: a shielded coin addressed to a contract is only
  credited if that contract claims the receive in the same transaction, which
  for a callee means running `receiveShielded` during the call.

  `CircuitContext` now carries `zswapLocalStates`, a per-contract-address record
  alongside `queryContexts` and `gasCosts`. Each contract in the call tree keeps
  its own state — its own `currentIndex`, `inputs` and `outputs` — sharing only
  the transaction submitter's coin public key. A callee's state is created on
  first entry, threaded back to the caller on return, and recorded on the call's
  `CallProofData` as `zswapLocalState` so transaction assembly can attribute
  every contract-owned input and output to the contract that made it.

  This covers all three Zswap natives — `ownPublicKey`, `createZswapInput` and
  `createZswapOutput`. Note that `ownPublicKey()` always names the transaction submitter,
  never the calling contract. A callee meaning to pay back its caller wants that caller's
  `ContractAddress`, not `ownPublicKey()`.

  Addresses [#658](https://github.com/LFDT-Minokawa/compact/issues/658); the
  transaction-assembly half lives in `compact-js` and `midnight-js`.

## [Toolchain 0.33.118, language 0.25.107, runtime 0.18.105]

### Changed

- The types `JubjubPoint` and `Secp256k1Point` are no longer defined as
  nominal type aliases for opaque types but rather standard-library names for
  internally handled types.  They can no longer be exported from a contract's
  top level.  This is a **breaking** change.

- Similarly, the types `JubjubScalar`, `Secp256k1Base`, and `Secp256k1Scalar`
  are no longer built-in types but rather standard-library names for
  internally handled types.  This is a **breaking** change, since programs
  must now import these types from CompactStandardLibrary to use them.

### Internal notes

- Previously, there were builtin types `Opaque<'JubjubPoint'>` and
  `Opaque<'Secp256k1Point'>` and the standard library exported nominal type
  aliases `JubjuPoint` and `Secp256k1Point` for these.  The compiler now
  injects definitions for these points from midnight-natives.ss and
  zkir-v3-natives.ss into the standard library and expands them into built-in types.
  Similarly, it injects definitions for `JubjubScalar`, `Secp256k1Base`, and
  `Secp256k1Scalar` from midnight-natives.ss and zkir-v3-natives.ss into the
  standard lbirary and expands them into built-in types.

## [Toolchain 0.33.117, language 0.25.106, runtime 0.18.105]

### Changed

- The generated JS code now has circuit argument and witness return value type
  checks for the JS opaque types `Opaque<'string'>` and `Opaque<'Uint8Array'>`.
  Before, we allowed any value at all to be passed or returned.  This is a
  **breaking change** for programs that relied on being able to store any random
  JS value as, say, an `Opaque<'string'>`.

## [Toolchain 0.33.116, language 0.25.106, runtime 0.18.105]

### Changed

- Equality of `Opaque<'Uint8Array'>` is now (1) same length and (2) element-wise
  strict equality (`===`).  It was formerly simple strict equality, which for
  typed arrays is object reference equality.

  This is a breaking change in the language, because `Uint8Arrays` that were
  formerly not equal in Compact can now compare as equal.

  This change brings the JS semantics more in line with the ZKIR semantics,
  which uses equality of the Poseidon hash of the typed array's contents.

## [Toolchain 0.33.115, language 0.25.105, runtime 0.18.105]

### Changed

- The JS implementation of the accessors secp256k1PointX and secp256k1PointY now
  fail with a `CompactError` when passed the identity (`default`) point.  This
  matches the ZKIR behavior, where these operations fail.

  Before, these accessors returned whatever was stored in the x- or y-coordinate
  of the JS object.  This was not a valid coordinate for this point, and not
  even a sentinel value like 0 because we don't currently canonicalize identity
  points.

### Internal notes

- This is a **breaking change** in the language.  Though it's a bug fix, the
  language version is still correctly incremented.

## [Toolchain 0.33.114, language 0.25.104, runtime 0.18.104]

### Changed

- Clean up the Compact runtime to reflect the intended structure: types and
  descriptors needed by the generated code are in `compact-types.ts`, but not
  redundant and unnecessary implementations; functions used by emitted code are
  in `built-ins.ts`, but not helpful utility functions; those are in `utils.ts`.

### Internal notes

- This is a breaking change because some unused and unnecessary exported types
  and descriptors have been deleted.

## [Toolchain 0.33.113, language 0.25.104, runtime 0.18.103]

### Added/Changed

- The binary arithmetic operators `+`, `-`, and `*` now work for `Secp256k1Base`
  and `Secp256k1Scalar`.  The operands must have the same type and the result
  will have that type.  There is a new runtime function to perform subtraction
  for these types.  The standard library circuits `add` and `mul` have been
  removed.

## [Toolchain 0.33.112, language 0.25.103, runtime 0.18.102]

### Fixed

- The ZKIR v3 printer now respects the --no-communications-commitment flag.

## [Toolchain 0.33.111, language 0.25.103, runtime 0.18.102]

### Changed

- The type `Uint<0>` is allowed where previously it was a compiler error.  It's
  equivalent to `Uint<0..1>` by the rule and the fact that 2^0 equals 1.
  `Uint<0..1>` is allowed so there is no reason to prohibit `Uint<0>` even
  though it's not super useful.

## [Toolchain 0.33.110, language 0.25.102, runtime 0.18.102]

### Added

- Add `secp256k1EcdsaRecover` to the Compact JavaScript runtime. Given a
  32-byte message hash, an ECDSA signature and a recovery,
  it returns the corresponding secp256k1 public key.

  Recovery runs off-circuit: the intended pattern is to recover the key here,
  pass it into a circuit as a witness or an argument, and
  constrain it there with the standard library's `secp256k1EcdsaVerify`.

  `secp256k1EcdsaVerify` accepts both low-s and high-s signatures, as
  [FIPS 186-5](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.186-5.pdf)
  section 6.4.2 constrains `s` only to `[1, n - 1]`.

## [Toolchain 0.33.109, language 0.25.102, runtime 0.18.101]

### Internal notes

- Each of the compiler passes now resides in its own file.  For example,
  infer-types used to reside in analysis-passes.ss along with the other
  analysis passes.  It now resides in analysis-passes/infer-types.ss, which
  analysis-passes.ss now includes.

## [Toolchain 0.33.108, language 0.25.102, runtime 0.18.101]

- Fix issue [#588](https://github.com/LFDT-Minokawa/compact/issues/588).  For
  the type `Uint<0..1>` (and enums with a single variant, which get lowered to
  `Uint<0..1>`), we used an alignment of `bytes:0`.  The ledger and ZKIR expects
  **no** values for such an alignment, but we provided one (always zero) value
  in the transcripts.
  
### Internal notes

- The fix is to use an alignment of `bytes:1` for the type `Uint<0..1>`, so that
  the ZKIR code will expect the value provided by JS.

## [Toolchain 0.33.107, language 0.25.102, runtime 0.18.101]

### Fixed

- Modify the standard library's `secp256k1EthereumAddress` circuit to `assert`
  that the input is not the secp256k1 identity point, because it does not have a
  corresponding Ethereum address.  This required two other fixes:
  - ZKIR code generation for `default<Secp256k1Point>` was not yet implemented
    and is needed, and
  - `persistentHash` and `keccak256` hashing functions need to properly handle
    alignment for `JubjubScalar`, `Secp256k1Base`, and `Secp256k1Scalar` in the
    ZKIR v3 backend.

### Internal notes

- The standard library behavior is changed (to reject the secp256k1 identity
  point) but this is deemed a bug fix and not a language version change.

## [Toolchain 0.33.106, language 0.25.102, runtime 0.18.101]

### Fixed

- Fix issue [#609](https://github.com/LFDT-Minokawa/compact/issues/609).
  Successive calls to `secp256k1EcdsaVerify` triggered a failure in the circuit
  optimizer where the secp256k1 base and scalar fields were not handled in a
  comparison predicate.

## [Toolchain 0.33.105, language 0.25.102, runtime 0.18.101]

### Fixed

- Fix issue [#608](https://github.com/LFDT-Minokawa/compact/issues/608).  The
  ZKIR v3 backend did not properly handle alignment for JubjubPoint and
  Secp256k1Point when passed to the hashing function `persistentHash`,
  `persistentCommit`, or `keccak256`.

## [Toolchain 0.33.104, language 0.25.102, runtime 0.18.101]

### Fixed

- Implement proper equality comparison for `Secp256k1Point`.  Identity points
  are equal to identity points, and non-identity points are equal if they have
  the same affine X- and Y- coordinates.

### Internal notes

- JS code for `JubjubPoint` equality is simplified, and `Uint` types now use
  direct `===` comparisons, rather than a helper that performs only `===`
  comparison.

## [Toolchain 0.33.103, language 0.25.101, runtime 0.18.101]

### Changed

- Pulls in ledger-9.1.0.0-rc.3

## [Toolchain 0.33.102, language 0.25.101, runtime 0.18.100]

### Fixed

- Add a `toBinaryRepr` to the Compact runtime that replicates the effect of the
  on-chain Rust `binary_repr`.  Use it in the runtime for the argument to the
  Noble hashes `keccak_256` function, to correctly replicate the in-circuit
  implementation.  This ensures that trailing zero bytes from byte vectors are
  preserved and hashed in JS as well as in circuit.

- Change casting of byte vectors to foreign fields so that they perform modular
  reduction by the field modulus rather than failing for byte vectors encoding
  values out of range.  The failure is kept for native fields to avoid a
  breaking change at this time.

### Internal notes

- There is a Compact runtime change, so when this change is cherry-picked to the
  0.33 release, there should be another Compact runtime release candidate
  release.

## [Toolchain 0.33.101, language 0.25.100, runtime 0.18.0]

### Changed

- The compiler now tries sha256sum first, then shasum -a 256 when looking
  for a program to compute a sha256 hash.

## [Toolchain 0.33.100, language 0.25.100, runtime 0.18.0]

### Fixed

- The `ShieldedReceive` standard event now serializes its fields in the order
  specified by CoIP-442 and MIP-0002: `commitment`, `ciphertext`,
  `contractAddress` (previously `contractAddress` preceded `ciphertext`).
  Serialized size is unchanged (578). Fixes #590.

### Changed

- The standard library ECDSA circuits `secp256k1EcdsaVerify` and
  `secp256k1EcdsaRecover` deserialize the message hash as a big endian
  secp256k1 scalar `z` internally, following the ECDSA convention (RFC 6979).

- The circuit `secp256k1EcdsaRecover` and struct
  `Secp256k1EcdsaSignatureWithRecovery` have been removed from the standard
  library.

