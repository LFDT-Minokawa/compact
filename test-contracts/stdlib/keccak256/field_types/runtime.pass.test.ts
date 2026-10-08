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

import { concatBytes, numberToBytesLE } from '@noble/curves/utils.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import { keccak_256 } from '@noble/hashes/sha3.js';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import { runKat } from '@test/crypto';

/** A Field is 32 bytes, little-endian, padded with zeros. */
function fieldToKeccakInput(value: bigint): Uint8Array {
    return numberToBytesLE(value, 32);
}

/** Three Fields end to end, so 96 bytes. */
function vector3ToKeccakInput(values: readonly bigint[]): Uint8Array {
    return concatBytes(...values.map(fieldToKeccakInput));
}

// The empty-input digest, used below as a NEGATIVE control.
const EMPTY_DIGEST =
    'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470';

const fieldVectors = [
    { label: '0 (32 zero bytes)', value: 0n },
    { label: '5 (0x05 then 31 zero bytes)', value: 5n },
    { label: '256 (little-endian 0x00 0x01, padded to 32)', value: 256n },
    { label: '0xdeadbeef', value: 0xdeadbeefn },
    {
        label: '2^248 - 1 (31 bytes of 0xff, then 0x00)',
        value: (1n << 248n) - 1n,
    },
];

const vector3Vectors = [
    { label: '[0, 0, 0] (96 zero bytes)', values: [0n, 0n, 0n] },
    { label: '[1, 2, 3]', values: [1n, 2n, 3n] },
    { label: '[256, 5, 0]', values: [256n, 5n, 0n] },
    {
        label: '[0xdeadbeef, 0xcafebabe, 0x12345678]',
        values: [0xdeadbeefn, 0xcafebaben, 0x12345678n],
    },
];

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat(
            'keccak256<Field> encoding',
            fieldVectors,
            (vector) => `Field ${vector.label}`,
            ({ label, value }) => {
                const expected = bytesToHex(
                    keccak_256(fieldToKeccakInput(value)),
                );
                const actual = bytesToHex(pure.hashField(value));

                if (actual !== expected) {
                    throw new Error(
                        `hashField(${label}) = 0x${actual}, expected 0x${expected} ` +
                            '(keccak of the 32-byte little-endian encoding)',
                    );
                }
            },
        );

        runKat(
            'keccak256<Vector<3, Field>> encoding',
            vector3Vectors,
            (vector) => `Vector<3, Field> ${vector.label}`,
            ({ label, values }) => {
                const expected = bytesToHex(
                    keccak_256(vector3ToKeccakInput(values)),
                );
                const actual = bytesToHex(
                    pure.hashVector3(values as [bigint, bigint, bigint]),
                );

                if (actual !== expected) {
                    throw new Error(
                        `hashVector3(${label}) = 0x${actual}, expected 0x${expected}`,
                    );
                }
            },
        );

        // A `Field` is framed at a full 32 bytes, so `Field` 0 hashes 32 zero
        // bytes. Under a trimmed encoding it would collapse to the empty input.
        const zeroField = bytesToHex(pure.hashField(0n));

        if (zeroField === EMPTY_DIGEST) {
            throw new Error(
                `hashField(0) = 0x${zeroField} collided with the empty-input digest -- ` +
                    'the field encoding is not padded to 32 bytes',
            );
        }

        // Each element occupies its own 32-byte block, so there is no
        // cross-element framing collision: under a trimmed encoding both of
        // these would flatten to 0x01 0x02 0x03.
        const framed = bytesToHex(pure.hashVector3([1n, 2n, 3n]));
        const reframed = bytesToHex(pure.hashVector3([0x030201n, 0n, 0n]));

        if (framed === reframed) {
            throw new Error(
                `hashVector3([1, 2, 3]) = 0x${framed} collided with ` +
                    'hashVector3([0x030201, 0, 0]) -- elements are not padded to 32 bytes',
            );
        }
    },
);
