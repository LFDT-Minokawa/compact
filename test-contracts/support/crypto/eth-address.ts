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

import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import type { Secp256k1Point } from '@midnight-ntwrk/compact-runtime';
import { secp256k1 } from '@noble/curves/secp256k1.js';

// The ethereum/tests key-to-address vectors kept in ./data.
//
// Each entry pairs a private key with the Ethereum address it belongs to. The
// stdlib circuit derives that same address, so the fixture expects a match.

type KeyAddrEntry = {
    readonly seed: string;
    readonly key: string;
    readonly addr: string;
};

export type AddressVector = {
    readonly seed: string;
    /** The public key point for this entry's private key. */
    readonly point: Secp256k1Point;
    /** The Ethereum address for this entry. */
    readonly ethAddr: string;
};

export const ADDRESS_VECTORS_FILENAME = 'keyaddrtest.json';

const dataDir = path.join(path.dirname(fileURLToPath(import.meta.url)), 'data');

/** The public key point for a private key given as hex. */
export function pubkeyPoint(privHex: string): Secp256k1Point {
    const { x, y } = secp256k1.Point.fromBytes(
        secp256k1.getPublicKey(hexToBytes(privHex), false),
    ).toAffine();

    return { x, y, identity: false };
}

/** Loads the vectors and works out each public key. */
export function loadAddressVectors(): AddressVector[] {
    const raw = JSON.parse(
        fs.readFileSync(path.join(dataDir, ADDRESS_VECTORS_FILENAME), 'utf8'),
    ) as KeyAddrEntry[];

    return raw.map((entry) => ({
        seed: entry.seed,
        point: pubkeyPoint(entry.key),
        ethAddr: `0x${entry.addr.toLowerCase()}`,
    }));
}
