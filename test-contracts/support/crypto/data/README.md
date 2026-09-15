<!--
This file is part of Compact.
Copyright (C) 2026 Midnight Foundation
SPDX-License-Identifier: Apache-2.0
-->

# Vendored crypto test vectors

Both files are vendored **verbatim** from upstream and are listed in
`.prettierignore`: reformatting them would invalidate the checksums below, which
are what makes "vendored verbatim" checkable.

## `ecdsa_secp256k1_sha256_bitcoin_test.json`

Project Wycheproof ECDSA / secp256k1 / SHA-256 **Bitcoin** verification vectors,
from the community-maintained C2SP fork.

| field              | value                                                                                                |
| ------------------ | ---------------------------------------------------------------------------------------------------- |
| Source             | https://github.com/C2SP/wycheproof/blob/main/testvectors_v1/ecdsa_secp256k1_sha256_bitcoin_test.json |
| Upstream commit    | `e0df04e0c033f2d25c5051dd06230336c7822358` (2025-10-07)                                              |
| `generatorVersion` | `0.9rc5`                                                                                             |
| `numberOfTests`    | 463 (162 `valid`, 301 `invalid`) across 99 groups                                                    |
| SHA-256            | `27c848b8cfa4e3f3bfbda27971542dd9b827e393842d5549fdfdf1923771c756`                                   |
| Schema             | `ecdsa_bitcoin_verify_schema.json` (group `type: EcdsaBitcoinVerify`)                                |
| License            | Apache-2.0 (Project Wycheproof)                                                                      |

Each group fixes one secp256k1 public key (`publicKey.uncompressed` =
`04 ‖ wx ‖ wy`); each test is `{ tcId, comment, flags[], msg, sig, result }`,
where `sig` is the DER `SEQUENCE { INTEGER r, INTEGER s }`, `msg` is the raw
message, and the signed digest is `e = SHA-256(msg)` (single SHA-256 —
"bitcoin" refers to low-s enforcement, not double hashing).

Consumed by [`../wycheproof.ts`](../wycheproof.ts).

## `keyaddrtest.json`

Canonical secp256k1 key to Ethereum address vectors, from the official Ethereum
consensus-test suite.

| field   | value                                                                      |
| ------- | -------------------------------------------------------------------------- |
| Source  | https://github.com/ethereum/tests/blob/develop/BasicTests/keyaddrtest.json |
| SHA-256 | `a1259937aa93b5e9e2682159f380b8d596f91b360a207fe8e95da829a26004d2`         |
| License | MIT (ethereum/tests)                                                       |
| Entries | 2 (`seed`s `cow`, `horse`)                                                 |

Each entry is `{ seed, key, addr, sig_of_emptystring{v,r,s} }`, where `key` is
the 32-byte private scalar (`= keccak256(seed)`, brain-wallet style), `addr` is
the real Ethereum address `keccak256(x_be ‖ y_be)[12:32)`, and
`sig_of_emptystring` is an ECDSA signature over `keccak256("")` (`r`/`s` as
decimal, `v` in {27, 28}).

Consumed by [`../eth-address.ts`](../eth-address.ts).

## Refreshing

Re-download from the source URL, then update the commit and SHA-256 rows:

```sh
sha256sum support/crypto/data/*.json
```
