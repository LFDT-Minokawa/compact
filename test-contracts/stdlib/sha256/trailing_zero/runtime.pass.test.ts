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
import { sha256 } from '@noble/hashes/sha2.js';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import { runKat } from '@test/crypto';

// All twelve bytes are hashed, including zeros at the end.
//
// Bytes are sent without their trailing zeros and the width is put back on the
// other side, so this checks nothing is lost on the way.
const inputs: { label: string; input: Uint8Array }[] = [
    {
        label: 'no trailing zero (control)',
        input: Uint8Array.from({ length: 12 }, (_unused, i) => i + 1),
    },
    {
        label: 'one trailing zero',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 11 ? 0 : i + 1,
        ),
    },
    {
        label: 'four trailing zeros',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i < 8 ? i + 1 : 0,
        ),
    },
    {
        label: 'eleven trailing zeros',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 0 ? 1 : 0,
        ),
    },
    {
        label: 'all twelve bytes zero',
        input: new Uint8Array(12),
    },
    {
        label: 'interior zero only',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 3 ? 0 : i + 1,
        ),
    },
];

/** What dropping the trailing zeros would have hashed, if it makes a difference. */
function trimmedDigest(input: Uint8Array): string | undefined {
    let end = input.length;

    while (end > 0 && input[end - 1] === 0) {
        end -= 1;
    }

    return end === input.length
        ? undefined
        : bytesToHex(sha256(input.slice(0, end)));
}

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat(
            'persistentHash trailing zeros hashed (no trim)',
            inputs,
            (vector) => vector.label,
            ({ label, input }) => {
                const expected = bytesToHex(sha256(input));
                const trimmed = trimmedDigest(input);

                if (trimmed === expected) {
                    throw new Error(
                        `${label}: the trimmed digest equals the full digest, so this ` +
                            'vector cannot distinguish the two behaviours',
                    );
                }

                const actual = bytesToHex(pure.hashBytes12(input));

                if (actual !== expected) {
                    const diagnosis =
                        actual === trimmed
                            ? ' -- this is the TRIMMED prefix digest: the width is not restored'
                            : '';

                    throw new Error(
                        `persistentHash<Bytes<12>> = 0x${actual}, expected 0x${expected} ` +
                            `(SHA-256 of all 12 bytes)${diagnosis}`,
                    );
                }
            },
        );
    },
);
