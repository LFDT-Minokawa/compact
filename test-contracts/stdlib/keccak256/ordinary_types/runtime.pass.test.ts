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

import { bytesToHex } from '@noble/hashes/utils.js';
import { expect } from 'vitest';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import { runKat } from '@test/crypto';

// For each kind of type: the digest is 32 bytes, it is the same every time, and
// different inputs give different digests. Encodings are in ../field_types and
// published digests in ../known_vectors.
const probes: { name: string; a: unknown; b: unknown }[] = [
    { name: 'hashField', a: 0n, b: 123456789n },
    {
        name: 'hashBytes32',
        a: new Uint8Array(32),
        b: Uint8Array.from({ length: 32 }, (_unused, i) => i + 1),
    },
    { name: 'hashBool', a: false, b: true },
    { name: 'hashUint', a: 0n, b: 0xdeadbeefn },
    { name: 'hashVector', a: [0n, 0n, 0n, 0n], b: [1n, 2n, 3n, 4n] },
    {
        name: 'hashStruct',
        a: { tag: new Uint8Array(8), count: 0n, flag: false },
        b: {
            tag: Uint8Array.from({ length: 8 }, (_unused, i) => i + 1),
            count: 7n,
            flag: true,
        },
    },
];

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat(
            'keccak256 ordinary-type probes',
            probes,
            (probe) => probe.name,
            ({ name, a, b }) => {
                const circuit = (pure as Record<string, unknown>)[name] as (
                    value: unknown,
                ) => Uint8Array;
                const first = circuit(a);
                const repeat = circuit(a);
                const other = circuit(b);

                for (const [which, digest] of [
                    ['a', first],
                    ['a (repeat)', repeat],
                    ['b', other],
                ] as const) {
                    expect(
                        digest,
                        `${name}(${which}) digest width`,
                    ).toHaveLength(32);
                }

                if (bytesToHex(first) !== bytesToHex(repeat)) {
                    throw new Error(
                        `${name} is not deterministic: the same input gave different digests`,
                    );
                }

                if (bytesToHex(first) === bytesToHex(other)) {
                    throw new Error(
                        `${name}: distinct inputs produced the same digest 0x${bytesToHex(first)}`,
                    );
                }
            },
        );
    },
);
