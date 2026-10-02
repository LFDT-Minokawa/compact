<!--
This file is part of Compact.
Copyright (C) 2026 Midnight Foundation
SPDX-License-Identifier: Apache-2.0
-->

# Crypto test vectors

## keccak256

| circuit                             | vectors                                                                     |
| ----------------------------------- | --------------------------------------------------------------------------- |
| `keccak256<Bytes<N>>`               | 7 published Keccak-256 digests, `N` = 0, 1, 2, 4, 5, 10, 18                 |
| `keccak256<Bytes<N>>`               | 37 widths: 1, 32–63, 93, 94, 376 (CCTP), 1024, vs `@noble/hashes`           |
| `keccak256<Bytes<12>>`              | 7 trailing-zero patterns, 3 against published digests                       |
| `keccak256<Bytes<N>>` vs `Bytes<M>` | 4 zero-padded pairs: 33/32, 63/32, 33/1, 94/93                              |
| `keccak256<T>` over structs         | 5 inputs where `Bytes<12>`, `Triple` and `Uneven` flatten to the same bytes |
| `keccak256<Field>`, `<Vector<3,_>>` | 5 field and 4 vector encodings, plus 2 collision guards                     |
| `keccak256<T>` over 6 type families | `Field`, `Bytes`, `Boolean`, `Uint`, `Vector`, struct                       |
| `keccak256<Counter>`                | rejected at compile time (ADT type)                                         |

## persistentHash (SHA-256)

| circuit                     | vectors                                |
| --------------------------- | -------------------------------------- |
| `persistentHash<Bytes<N>>`  | the same 37 widths, vs `@noble/hashes` |
| `persistentHash<Bytes<12>>` | 6 trailing-zero patterns               |

## secp256k1

| circuit                      | vectors                                                                 |
| ---------------------------- | ----------------------------------------------------------------------- |
| `secp256k1EcdsaVerify`       | Wycheproof Bitcoin corpus, 244 of 463 driven, digest hashed off-circuit |
| `proveBitcoin{N}`            | the same corpus, SHA-256 in-circuit; one circuit per message length     |
| `secp256k1EcdsaRecover` (JS) | recover off-circuit, then verify in-circuit, over every valid vector    |
| `secp256k1EthereumAddress`   | 2 `ethereum/tests` key-to-address vectors                               |
| `Secp256k1Base` round trip   | 0, 1, a mid-range value, `MAX_SECP256K1_BASE`                           |

## secp256r1

| circuit                    | vectors                                                             |
| -------------------------- | ------------------------------------------------------------------- |
| `secp256r1EcdsaVerify`     | Wycheproof corpus, 265 of 484 driven, digest hashed off-circuit     |
| `proveEcdsa{N}`            | the same corpus, SHA-256 in-circuit; one circuit per message length |
| `Secp256r1Base` round trip | 0, 1, a mid-range value, `MAX_SECP256R1_BASE`                       |

## ed25519

| circuit                       | vectors                                                                                    |
| ----------------------------- | ------------------------------------------------------------------------------------------ |
| `verifyEddsa{N}`              | Wycheproof corpus, 120 of 151 driven, SHA-512 in-circuit; one circuit per message length   |
| `Curve25519Base` round trip   | 0, 1, a mid-range value, `MAX_CURVE25519_BASE`                                             |
| `Curve25519Scalar` round trip | 0, 1, a mid-range value, either side of the 204-bit limb boundary, `MAX_CURVE25519_SCALAR` |

## Compile-only

`--feature-zkir-v3` gates: the secp256k1, secp256r1 and ed25519 stdlib is
unbound without it, and `keccak256` in a provable circuit is rejected by ZKIR
v2 and accepted by v3. Two secp256k1 contracts, one secp256r1 contract and one
ed25519 contract also compile through v3 lowering with proving keys.

## Choosing a reference

A known-answer test is worth as much as its reference, and no more:

- **`persistentHash`** runs in the Rust on-chain runtime, so a `@noble/hashes`
  digest is a genuine second implementation.
- **`keccak256`** is implemented _with_ `@noble/hashes`, so a computed digest
  only checks the encoding. Published digests are the real oracle there.
- **`secp256k1EcdsaVerify`**, **`secp256r1EcdsaVerify`** and
  **`ed25519Verify`** are written in Compact, so `@noble/curves`' verify is
  independent, and Wycheproof's own verdicts are a third opinion.
