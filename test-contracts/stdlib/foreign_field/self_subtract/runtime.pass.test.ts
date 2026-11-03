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

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

// Each circuit computes zero of its field, whatever the inputs.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;
        const k = 12345n;
        const z = 678n;

        expect((await c.self_subtract(ctx, k)).result).toBe(0n);
        expect((await c.inlined_self_subtract(ctx, k)).result).toBe(0n);
        expect((await c.multiply_self_subtract(ctx, k, z)).result).toBe(0n);
        expect((await c.secp256r1_self_subtract(ctx, k)).result).toBe(0n);
        expect((await c.curve25519_self_subtract(ctx, k)).result).toBe(0n);
    },
);
