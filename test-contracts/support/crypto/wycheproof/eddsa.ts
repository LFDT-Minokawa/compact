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

import type { Curve25519Point } from '@midnight-ntwrk/compact-runtime';
import { ed25519 } from '@noble/curves/ed25519.js';
import { bytesToNumberLE } from '@noble/curves/utils.js';
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

// EdDSA corpora, where a signature is `R || s` and R and the key are
// compressed points. They are decoded here, since the circuit takes points,
// and the message goes through untouched, since the circuit hashes it.

type EddsaGroup = {
    type: string;
    publicKey: { type: string; curve: string; keySize: number; pk: string };
    tests: CorpusTest[];
};

type EddsaSuite = {
    /** Short name shown in reports. */
    name: string;
    vectorsFile: string;
    /** Failure messages that count as an expected abort. */
    abortMessages: string[];
    coverage: Coverage;
};

export const ED25519: EddsaSuite = {
    name: 'Ed25519',
    vectorsFile: 'ed25519_test.json',
    abortMessages: [
        'Curve25519Point identity is not a permitted ed25519Verify verification key',
    ],
    coverage: {
        total: 151,
        driven: 120,
        excluded: { encoding: 31 },
    },
};

/** The group order, which s must stay below. */
const ORDER = ed25519.Point.Fn.ORDER;

/** How the runtime writes the identity point. */
const IDENTITY_POINT: Curve25519Point = { x: 0n, y: 1n };

type EddsaSignature = {
    r: Curve25519Point;
    s: bigint;
};

export type EddsaVector = DrivenVector & {
    flags: string[];
    /** The message, which the circuit hashes. */
    msg: Uint8Array;
    sig: EddsaSignature;
    pk: Curve25519Point;
    /** False when s is not below the group order. */
    scalarInRange: boolean;
    /** False when R is outside the prime-order subgroup. */
    rInSubgroup: boolean;
};

/** Decodes a compressed point, or undefined if the bytes are not one. */
function decodePoint(bytes: Uint8Array): Curve25519Point | undefined {
    try {
        // Strict RFC 8032 decoding, not the looser ZIP 215.
        const { x, y } = ed25519.Point.fromBytes(bytes, false).toAffine();

        return { x, y };
    } catch {
        return undefined;
    }
}

/** R and s of a 64-byte signature, or undefined if it does not decode. */
function decodeSignature(sig: Uint8Array): EddsaSignature | undefined {
    if (sig.length !== 64) {
        return undefined;
    }

    const r = decodePoint(sig.subarray(0, 32));

    return r === undefined
        ? undefined
        : { r, s: bytesToNumberLE(sig.subarray(32)) };
}

/** What @noble says about the signature, without ZIP 215 leniency. */
function referenceVerify(
    sig: Uint8Array,
    msg: Uint8Array,
    pk: Uint8Array,
): boolean {
    try {
        return ed25519.verify(sig, msg, pk, { zip215: false });
    } catch {
        return false;
    }
}

/**
 * Splits a corpus into vectors to run and vectors to leave out.
 *
 * A vector is left out when its signature does not decode. Any disagreement
 * with @noble throws, since that would mean something real is wrong.
 */
function classifyEddsa(suite: EddsaSuite): Classified<EddsaVector> {
    const root = loadCorpus<CorpusRoot<EddsaGroup>>(suite.vectorsFile);
    const driven: EddsaVector[] = [];
    const encoding: number[] = [];
    let total = 0;

    for (const group of root.testGroups) {
        const pkBytes = hexToBytes(group.publicKey.pk);
        const pk = decodePoint(pkBytes);

        if (pk === undefined) {
            throw new Error(
                `${suite.name}: public key ${group.publicKey.pk.slice(0, 10)}... does not decode`,
            );
        }

        for (const test of group.tests) {
            total += 1;
            const sigBytes = hexToBytes(test.sig);
            const sig = decodeSignature(sigBytes);

            if (sig === undefined) {
                encoding.push(test.tcId);
                continue;
            }

            const msg = hexToBytes(test.msg);
            const expectedValid = test.result === 'valid';
            const referenceValid = referenceVerify(sigBytes, msg, pkBytes);

            if (referenceValid !== expectedValid) {
                throw new Error(
                    `${suite.name} tcId ${test.tcId} (${test.comment}): noble verdict ` +
                        `${referenceValid}, corpus ${expectedValid}. Investigate before ` +
                        'trusting the KAT.',
                );
            }

            // The circuit aborts instead of returning a verdict when the key
            // is the identity.
            const aborts =
                pk.x === IDENTITY_POINT.x && pk.y === IDENTITY_POINT.y;
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
                sig,
                pk,
                scalarInRange: sig.s < ORDER,
                rInSubgroup: ed25519.Point.fromAffine(sig.r).isTorsionFree(),
            });
        }
    }

    const excluded: Excluded[] = [{ reason: 'encoding', tcIds: encoding }];

    return { total, driven, excluded };
}

/** Sorts the corpus, then runs every vector it kept. */
export function runEddsaKat(
    suite: EddsaSuite,
    label: string,
    drive: (vector: EddsaVector) => boolean,
    notes?: (classified: Classified<EddsaVector>) => string[],
): Classified<EddsaVector> {
    return runCorpusKat(
        `${label} [${suite.name}]`,
        classifyEddsa(suite),
        drive,
        (error) =>
            error instanceof Error &&
            suite.abortMessages.some((message) =>
                error.message.includes(message),
            ),
        notes,
    );
}
