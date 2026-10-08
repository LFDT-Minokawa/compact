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
    runEcdsaKat,
    SECP256K1_BITCOIN,
    type EcdsaVector,
} from '@test/crypto';

function drive(pure: PureCircuits, vector: EcdsaVector): boolean {
    const name = `proveBitcoin${vector.msg.length}`;
    const circuit = (pure as Record<string, unknown>)[name] as
        | ((msg: Uint8Array, sig: unknown, pk: unknown) => boolean)
        | undefined;

    if (typeof circuit !== 'function') {
        throw new Error(
            `no ${name} circuit for tcId ${vector.tcId}; add one for each message length`,
        );
    }

    // Out-of-range r or s never reach the circuit, and count as a bad signature.
    return vector.scalarsInRange && circuit(vector.msg, vector.sig, vector.pk);
}

/** How many vectors there are of each message length. */
function lengthBreakdown(vectors: readonly EcdsaVector[]): string {
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
        const classified = runEcdsaKat(
            SECP256K1_BITCOIN,
            'Bitcoin flow (SHA-256 in-circuit + verify)',
            (vector) => drive(pure, vector),
            ({ driven }) => [`by msg length: ${lengthBreakdown(driven)}`],
        );

        assertCoverage(
            SECP256K1_BITCOIN.name,
            classified,
            SECP256K1_BITCOIN.coverage,
        );
    },
);
