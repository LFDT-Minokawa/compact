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

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import {
    assertCoverage,
    ED25519,
    runEddsaKat,
    type EddsaVector,
} from '@test/crypto';

// Checks signatures over the Wycheproof vectors (see
// support/crypto/data/README.md); each expected answer comes from both the
// vectors and @noble/curves.

function drive(pure: PureCircuits, vector: EddsaVector): boolean {
    const name = `verifyEddsa${vector.msg.length}`;
    const circuit = (pure as Record<string, unknown>)[name] as
        | ((msg: Uint8Array, sig: unknown, pk: unknown) => boolean)
        | undefined;

    if (typeof circuit !== 'function') {
        throw new Error(
            `no ${name} circuit for tcId ${vector.tcId}; add one for each message length`,
        );
    }

    // The runtime refuses an s at or above the group order and an R outside the
    // prime-order subgroup, so these count as bad signatures.
    return (
        vector.scalarInRange &&
        vector.rInSubgroup &&
        circuit(vector.msg, vector.sig, vector.pk)
    );
}

/** How many vectors there are of each message length. */
function lengthBreakdown(vectors: readonly EddsaVector[]): string {
    const byLength = new Map<number, number>();

    for (const vector of vectors) {
        byLength.set(
            vector.msg.length,
            (byLength.get(vector.msg.length) ?? 0) + 1,
        );
    }

    return [...byLength.entries()]
        .sort(([a], [b]) => a - b)
        .map(([length, count]) => `${length}B=${count}`)
        .join(', ');
}

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        const classified = runEddsaKat(
            ED25519,
            'SHA-512 in-circuit + verify',
            (vector) => drive(pure, vector),
            ({ driven }) => [`by msg length: ${lengthBreakdown(driven)}`],
        );

        assertCoverage(ED25519.name, classified, ED25519.coverage);
    },
);
