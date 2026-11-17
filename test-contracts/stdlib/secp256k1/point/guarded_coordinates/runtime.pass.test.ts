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

import { expect } from 'vitest';

import { secp256k1MulGenerator } from '@midnight-ntwrk/compact-runtime';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';
import { checkProof } from '@test/proof-check';

// With the branch not taken, getPoint is never called and the coordinates stay
// zero. With it taken, they are the witness point's. Both calls must pass the
// ZKIR check.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const point = secp256k1MulGenerator(2n);
        const { contract, ctx } = await createTestContract(Contract, {
            getPoint: (context) => [context.privateState, point],
        });
        const c = contract.circuits;

        const skipped = await c.secp256k1_point_guarded_coordinates(ctx, false);
        expect(skipped.result).toEqual([0n, 0n]);
        await checkProof(
            import.meta.url,
            'secp256k1_point_guarded_coordinates',
            skipped,
        );

        const taken = await c.secp256k1_point_guarded_coordinates(
            skipped.context,
            true,
        );
        expect(taken.result).toEqual([point.x, point.y]);
        await checkProof(
            import.meta.url,
            'secp256k1_point_guarded_coordinates',
            taken,
        );
    },
);
