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

import { secp256r1ScalarMul } from '@midnight-ntwrk/compact-runtime';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';
import { checkProof } from '@test/proof-check';

// With the branch not taken, v comes back unchanged even though it is zero.
// With it taken, the result is the inverse of v. Both calls must pass the
// ZKIR check.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;

        const skipped = await c.secp256r1_scalar_guarded_inv(ctx, false, 0n);
        expect(skipped.result).toBe(0n);
        await checkProof(
            import.meta.url,
            'secp256r1_scalar_guarded_inv',
            skipped,
        );

        const taken = await c.secp256r1_scalar_guarded_inv(
            skipped.context,
            true,
            2n,
        );
        expect(secp256r1ScalarMul(taken.result, 2n)).toBe(1n);
        await checkProof(
            import.meta.url,
            'secp256r1_scalar_guarded_inv',
            taken,
        );
    },
);
