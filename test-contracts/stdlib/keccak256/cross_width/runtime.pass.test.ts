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
import { fillerBytes, runKat, widthCircuit } from '@test/crypto';

// A wider value padded with zeros must not hash the same as the narrower one,
// because those zeros are hashed too.
const pairs = [
    { wide: 33, narrow: 32, note: 'one padding zero' },
    {
        wide: 63,
        narrow: 32,
        note: '31 padding zeros, across the 2x31 boundary',
    },
    { wide: 33, narrow: 1, note: '32 padding zeros' },
    { wide: 94, narrow: 93, note: 'one padding zero on the 3x31 straddle' },
];

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat(
            'keccak256 zero-padding cross-width distinctness',
            pairs,
            ({ wide, narrow }) => `Bytes<${wide}> vs Bytes<${narrow}>`,
            ({ wide, narrow, note }) => {
                // The same bytes, padded out to the wider size.
                const prefix = fillerBytes(narrow);
                const padded = new Uint8Array(wide);
                padded.set(prefix);

                const wideDigest = bytesToHex(widthCircuit(pure, wide)(padded));
                const narrowDigest = bytesToHex(
                    widthCircuit(pure, narrow)(prefix),
                );
                const wideReference = bytesToHex(keccak_256(padded));
                const narrowReference = bytesToHex(keccak_256(prefix));

                if (narrowDigest !== narrowReference) {
                    throw new Error(
                        `keccak256<Bytes<${narrow}>> = 0x${narrowDigest}, expected 0x${narrowReference}`,
                    );
                }

                if (wideDigest !== wideReference) {
                    const diagnosis =
                        wideDigest === narrowReference
                            ? ' -- this is the narrow prefix digest: the trailing-zero trim is back'
                            : '';

                    throw new Error(
                        `keccak256<Bytes<${wide}>> (${note}) = 0x${wideDigest}, ` +
                            `expected 0x${wideReference}${diagnosis}`,
                    );
                }

                if (wideDigest === narrowDigest) {
                    throw new Error(
                        `keccak256<Bytes<${wide}>> collides with keccak256<Bytes<${narrow}>> ` +
                            `(0x${narrowDigest}); the ${wide - narrow} padding zeros must be hashed`,
                    );
                }
            },
        );
    },
);
