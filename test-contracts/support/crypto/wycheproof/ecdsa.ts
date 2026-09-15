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

import type { Secp256k1Point } from '@midnight-ntwrk/compact-runtime';
import { DER } from '@noble/curves/abstract/weierstrass.js';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { bytesToNumberBE } from '@noble/curves/utils.js';
import { sha256 } from '@noble/hashes/sha2.js';
import { hexToBytes } from '@noble/hashes/utils.js';

import {
    loadCorpus,
    runCorpusKat,
    type Classified,
    type Coverage,
    type CorpusRoot,
    type CorpusTest,
    type DrivenVector,
    type Excluded,
    type Expectation,
} from './corpus.ts';

// ECDSA corpora, where signatures are DER and keys are `04 || x || y`.
//
// The circuit takes r, s and a point directly, so each signature and key is
// decoded here and the message is hashed up front. Vectors the circuit cannot
// answer are excluded with a reason. EdDSA works differently and needs its own
// file.

type EcdsaGroup = {
    type: string;
    publicKey: { uncompressed: string; wx: string; wy: string };
    sha?: string;
    tests: CorpusTest[];
};

type EcdsaSuite = {
    /** Short name shown in reports. */
    name: string;
    vectorsFile: string;
    /** The @noble/curves curve used as the reference. */
    curve: typeof secp256k1;
    hash: (msg: Uint8Array) => Uint8Array;
    /** True when the corpus applies a low-s rule the circuit does not. */
    enforcesLowS: boolean;
    /** Vectors whose maths reaches the identity point, so the circuit fails. */
    identityPointTcIds: ReadonlySet<number>;
    /** Failure messages that count as an expected abort. */
    abortMessages: string[];
    coverage: Coverage;
};

export const SECP256K1_BITCOIN: EcdsaSuite = {
    name: 'secp256k1/SHA-256 (Bitcoin)',
    vectorsFile: 'ecdsa_secp256k1_sha256_bitcoin_test.json',
    curve: secp256k1,
    hash: sha256,
    enforcesLowS: true,
    identityPointTcIds: new Set([386, 424, 425, 439, 440]),
    abortMessages: [
        // The verification point is the identity, which has no x-coordinate.
        'cannot extract the x-coordinate of the secp256k1 identity point',
        // `w = inv(s)` has no result for s = 0.
        'Cannot compute inverse on input 0',
    ],
    coverage: {
        total: 463,
        driven: 244,
        excluded: { encoding: 217, malleability: 2 },
    },
};

type EcdsaScalars = {
    r: bigint;
    s: bigint;
};

/** How the runtime writes the point at infinity. */
const IDENTITY_POINT: Secp256k1Point = {
    x: 0n,
    y: 0n,
    identity: true,
};

export type EcdsaVector = DrivenVector & {
    flags: string[];
    /** The message bytes that get hashed. */
    msg: Uint8Array;
    /** The message digest, big-endian. */
    e: Uint8Array;
    sig: EcdsaScalars;
    pk: Secp256k1Point;
    /** False when r or s is out of range, which the circuit rejects up front. */
    scalarsInRange: boolean;
};

/** Decodes a DER signature into r and s, or undefined if it does not parse. */
function decodeSignature(sigHex: string): EcdsaScalars | undefined {
    try {
        return DER.toSig(hexToBytes(sigHex));
    } catch {
        return undefined;
    }
}

/**
 * Decode a SEC1 key. `00` is the point at infinity; otherwise
 * `04 || wx || wy`. The all-zero pair is how the runtime spells the identity.
 */
function parseUncompressedPublicKey(
    suite: EcdsaSuite,
    uncompressed: string,
): Secp256k1Point {
    if (uncompressed === '00') {
        return IDENTITY_POINT;
    }

    const size = suite.curve.Point.Fp.BYTES;

    if (
        uncompressed.length !== 2 + 4 * size ||
        !uncompressed.startsWith('04')
    ) {
        throw new Error(
            `unexpected uncompressed public key: ${uncompressed.slice(0, 10)}...`,
        );
    }

    // Not `Point.fromBytes`, because that rejects keys the corpus wants tested.
    const body = hexToBytes(uncompressed.slice(2));
    const x = bytesToNumberBE(body.subarray(0, size));
    const y = bytesToNumberBE(body.subarray(size));

    return x === 0n && y === 0n ? IDENTITY_POINT : { x, y, identity: false };
}

/** What @noble says about the signature, with the low-s rule turned off. */
function rawEcdsaVerify(
    suite: EcdsaSuite,
    e: Uint8Array,
    { r, s }: EcdsaScalars,
    pk: Secp256k1Point,
): boolean {
    const order = suite.curve.Point.Fn.ORDER;

    if (r <= 0n || r >= order || s <= 0n || s >= order || pk.identity) {
        return false;
    }

    try {
        const sig = new suite.curve.Signature(r, s).toBytes('compact');
        const key = suite.curve.Point.fromAffine({
            x: pk.x,
            y: pk.y,
        }).toBytes(false);

        return suite.curve.verify(sig, e, key, { prehash: false, lowS: false });
    } catch {
        return false;
    }
}

/**
 * Splits a corpus into vectors to run and vectors to leave out.
 *
 * A vector is left out when its signature does not decode, or when the corpus
 * only calls it invalid because of the low-s rule. Any other disagreement with
 * @noble throws, since that would mean something real is wrong.
 */
function classifyEcdsa(suite: EcdsaSuite): Classified<EcdsaVector> {
    const root = loadCorpus<CorpusRoot<EcdsaGroup>>(suite.vectorsFile);
    const order = suite.curve.Point.Fn.ORDER;
    const driven: EcdsaVector[] = [];
    const encoding: number[] = [];
    const malleability: number[] = [];
    let total = 0;

    for (const group of root.testGroups) {
        const pk = parseUncompressedPublicKey(
            suite,
            group.publicKey.uncompressed,
        );

        for (const test of group.tests) {
            total += 1;
            const sig = decodeSignature(test.sig);

            if (sig === undefined) {
                encoding.push(test.tcId);
                continue;
            }

            const msg = hexToBytes(test.msg);
            const e = suite.hash(msg);
            const expectedValid = test.result === 'valid';
            const rawValid = rawEcdsaVerify(suite, e, sig, pk);

            if (rawValid !== expectedValid) {
                const highS = new suite.curve.Signature(
                    sig.r,
                    sig.s,
                ).hasHighS();

                if (suite.enforcesLowS && rawValid && !expectedValid && highS) {
                    malleability.push(test.tcId);
                    continue;
                }

                throw new Error(
                    `${suite.name} tcId ${test.tcId} (${test.comment}): noble raw verdict ` +
                        `${rawValid}, corpus ${expectedValid}, high-s ${highS}. Not a low-s ` +
                        'case; investigate before trusting the KAT.',
                );
            }

            // The circuit aborts instead of returning a verdict when the
            // verification point is the identity, or when s = 0 leaves `inv(s)`
            // undefined. Both are `invalid` upstream, but neither yields a
            // boolean to compare.
            //
            // s = 0 only reaches `inv` when r is in range: the argument
            // type-check runs first, and an out-of-range r is rejected there,
            // which the caller reads as an invalid signature.
            const scalarsInRange = sig.r < order && sig.s < order;
            const aborts =
                suite.identityPointTcIds.has(test.tcId) ||
                (sig.s === 0n && scalarsInRange);
            const expectation: Expectation = aborts
                ? 'abort'
                : expectedValid
                  ? 'valid'
                  : 'invalid';

            driven.push({
                tcId: test.tcId,
                comment: test.comment,
                flags: test.flags ?? [],
                expectation,
                msg,
                e,
                sig,
                pk,
                scalarsInRange,
            });
        }
    }

    const excluded: Excluded[] = [
        { reason: 'encoding', tcIds: encoding },
        { reason: 'malleability', tcIds: malleability },
    ];

    return { total, driven, excluded };
}

/** Sorts the corpus, then runs every vector it kept. */
export function runEcdsaKat(
    suite: EcdsaSuite,
    label: string,
    drive: (vector: EcdsaVector) => boolean,
    notes?: (classified: Classified<EcdsaVector>) => string[],
): Classified<EcdsaVector> {
    return runCorpusKat(
        `${label} [${suite.name}]`,
        classifyEcdsa(suite),
        drive,
        (error) =>
            error instanceof Error &&
            suite.abortMessages.some((message) =>
                error.message.includes(message),
            ),
        notes,
    );
}
