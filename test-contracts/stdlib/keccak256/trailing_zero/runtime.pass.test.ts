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
import { keccak_256 } from '@noble/hashes/sha3.js';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import { runKat } from '@test/crypto';

// `keccak256<Bytes<12>>` must hash all twelve bytes whatever the trailing-byte
// pattern. Each vector is checked against Keccak-256 of the FULL input, and the
// three published constants below anchor that reference independently.
//
// The discriminating step is `legacyTrimmedDigest`: for any input ending in
// 0x00, it computes what the legacy trim would have produced. If that equals the
// full digest the vector cannot tell the two behaviours apart, so the fixture
// rejects it as a useless vector; if the circuit returns it, the failure says so
// in as many words rather than just printing two hex strings.
type TrailingZeroVector = {
    label: string;
    input: Uint8Array;
    /** Published digest, where one exists, guarding the reference itself. */
    pinned?: string;
};

const vectors: TrailingZeroVector[] = [
    {
        label: 'no trailing zero (control)',
        input: Uint8Array.from({ length: 12 }, (_unused, i) => i + 1),
        pinned: 'e232c64e7136218f5a7d8d41b16bf3f22e74085032aaca77baa5c6c50cc4ca0e',
    },
    {
        label: 'one trailing zero',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 11 ? 0 : i + 1,
        ),
        pinned: 'ed6e483c71bb1e667911203acc659782cc5ad0fb03f78a57febbe599b6a21e8d',
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
        // The degenerate extreme: an all-zero Bytes<12> hashes twelve zero
        // bytes, NOT the empty input the legacy trim collapsed it to.
        label: 'all twelve bytes zero',
        input: new Uint8Array(12),
        pinned: '30e2bfdaad2f3c218a1a8cc54fa1c4e6182b6b7f3bca273390cf587b50b47311',
    },
    {
        // Interior zeros were never special; still hashed in place.
        label: 'interior zero only',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 3 ? 0 : i + 1,
        ),
    },
    {
        // Leading zeros likewise.
        label: 'eleven leading zeros, nonzero last byte',
        input: Uint8Array.from({ length: 12 }, (_unused, i) =>
            i === 11 ? 0xff : 0,
        ),
    },
];

/** What the legacy trim would have hashed, or undefined if it changes nothing. */
function legacyTrimmedDigest(input: Uint8Array): string | undefined {
    let end = input.length;

    while (end > 0 && input[end - 1] === 0) {
        end -= 1;
    }

    return end === input.length
        ? undefined
        : bytesToHex(keccak_256(input.slice(0, end)));
}

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat(
            'keccak256 trailing zeros hashed (no trim)',
            vectors,
            (vector) => vector.label,
            ({ label, input, pinned }) => {
                const expected = bytesToHex(keccak_256(input));

                if (pinned !== undefined && expected !== pinned) {
                    throw new Error(
                        `reference drift: keccak of the full 12 bytes = 0x${expected}, ` +
                            `but the published digest is 0x${pinned}`,
                    );
                }

                const legacy = legacyTrimmedDigest(input);

                if (legacy === expected) {
                    throw new Error(
                        `${label}: the legacy trimmed digest equals the full digest, so ` +
                            'this vector cannot distinguish the two behaviours',
                    );
                }

                const actual = bytesToHex(pure.hashBytes12(input));

                if (actual !== expected) {
                    const diagnosis =
                        actual === legacy
                            ? ' -- this is the LEGACY trimmed digest: the trailing-zero trim is back'
                            : '';

                    throw new Error(
                        `keccak256<Bytes<12>> = 0x${actual}, expected 0x${expected} ` +
                            `(keccak of all 12 bytes)${diagnosis}`,
                    );
                }
            },
        );
    },
);
