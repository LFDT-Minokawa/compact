<!--
This file is part of Compact.
Copyright (C) 2026 Midnight Foundation
SPDX-License-Identifier: Apache-2.0
-->

# Vendored crypto test vectors

All four files are copied verbatim from upstream, so they are listed in
`.prettierignore`: reformatting them would change the checksums below.

## `ecdsa_secp256k1_sha256_bitcoin_test.json`

Project Wycheproof ECDSA verification vectors for secp256k1 with SHA-256, in
the Bitcoin variant. Taken from the C2SP fork.

| field           | value                                                                                                |
| --------------- | ---------------------------------------------------------------------------------------------------- |
| Source          | https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json |
| Upstream commit | `e0df04e0c033f2d25c5051dd06230336c7822358` (2025-10-07)                                              |
| Tests           | 463                                                                                                  |
| SHA-256         | `27c848b8cfa4e3f3bfbda27971542dd9b827e393842d5549fdfdf1923771c756`                                   |
| License         | Apache-2.0 (Project Wycheproof)                                                                      |

Read by [`../wycheproof/ecdsa.ts`](../wycheproof/ecdsa.ts).

## `ecdsa_secp256r1_sha256_test.json`

Project Wycheproof ECDSA verification vectors for secp256r1 (P-256) with
SHA-256. Taken from the C2SP fork.

| field           | value                                                                                        |
| --------------- | -------------------------------------------------------------------------------------------- |
| Source          | https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ecdsa_secp256r1_sha256_test.json |
| Upstream commit | `878e5366008753df2064d40c49f8e2f50f9c6af7` (2026-05-12)                                      |
| Tests           | 484                                                                                          |
| SHA-256         | `182db4f3e230f6f9fa9f800d2a614dede30284b8e8438bbfe1171905402e9332`                           |
| License         | Apache-2.0 (Project Wycheproof)                                                              |

Read by [`../wycheproof/ecdsa.ts`](../wycheproof/ecdsa.ts).

## `ed25519_test.json`

Project Wycheproof EdDSA verification vectors for Ed25519 (RFC 8032). Taken
from the C2SP fork.

| field           | value                                                                         |
| --------------- | ----------------------------------------------------------------------------- |
| Source          | https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ed25519_test.json |
| Upstream commit | `5722833ca004983abd1a91bcb6c24596d50ac0f9` (2026-08-11)                       |
| Tests           | 151                                                                           |
| SHA-256         | `752d2ea7d7c6cf4736381b6cbacb61f8182b126ab7cd9b058f00c50084975536`            |
| License         | Apache-2.0 (Project Wycheproof)                                               |

Read by [`../wycheproof/eddsa.ts`](../wycheproof/eddsa.ts).

## `keyaddrtest.json`

Private key to Ethereum address vectors from the ethereum/tests suite.

| field   | value                                                                      |
| ------- | -------------------------------------------------------------------------- |
| Source  | https://github.com/ethereum/tests/blob/develop/BasicTests/keyaddrtest.json |
| Entries | 2 (seeds `cow` and `horse`)                                                |
| SHA-256 | `a1259937aa93b5e9e2682159f380b8d596f91b360a207fe8e95da829a26004d2`         |
| License | MIT (ethereum/tests)                                                       |

Read by [`../eth-address.ts`](../eth-address.ts).

## Refreshing

Download the file again from its source URL, then update the rows above. Run
this from `test-contracts` for the new checksums:

```sh
sha256sum support/crypto/data/*.json
```
