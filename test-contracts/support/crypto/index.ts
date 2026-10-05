// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

/**
 * Shared harness for the crypto fixtures under `stdlib/`: hex conversion, the
 * known-answer test driver, the `Bytes<N>` width sweep the two hash features
 * share, and loaders for the vendored Wycheproof and ethereum/tests vectors.
 *
 * Imported by fixtures as `@test/crypto`. See `data/README.md` for vector
 * provenance and `vectors.ts` for which oracles are actually independent of the
 * runtime under test.
 */

export {
    buildReport,
    formatFailure,
    runKat,
    runKatAsync,
    type KatOptions,
    type KatOutcome,
    type KatReport,
} from './kat.ts';

export {
    checkWidthVector,
    computed,
    fillerBytes,
    largeWidths,
    packingWidths,
    pinned,
    sweepVectors,
    sweepWidths,
    vectorLabel,
    vectorWidth,
    widthCircuit,
    type DigestFn,
    type LengthVector,
} from './vectors.ts';

export { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';

export {
    assertCoverage,
    ED25519,
    loadCorpus,
    runCorpusKat,
    runEcdsaKat,
    runEddsaKat,
    SECP256K1_BITCOIN,
    SECP256R1,
    type Classified,
    type CorpusRoot,
    type CorpusTest,
    type Coverage,
    type DrivenVector,
    type EcdsaVector,
    type EddsaVector,
    type Excluded,
    type Expectation,
} from './wycheproof/index.ts';

export {
    loadAddressVectors,
    pubkeyPoint,
    ADDRESS_VECTORS_FILENAME,
    type AddressVector,
} from './eth-address.ts';
