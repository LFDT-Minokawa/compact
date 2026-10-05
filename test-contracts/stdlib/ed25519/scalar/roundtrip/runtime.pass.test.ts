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

import { MAX_CURVE25519_SCALAR } from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

// The encoding stores `value - 1`, wrapping at zero, as 204 low bits then 51
// high bits, so the ends of the range and both sides of the limb boundary are
// the interesting cases.
const VALUES = [
    0n,
    1n,
    12345678901234567890n,
    1n << 204n,
    (1n << 204n) + 1n,
    MAX_CURVE25519_SCALAR,
];

export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);

        for (const value of VALUES) {
            const result = (
                await contract.circuits.ed25519_scalar_roundtrip(ctx, value)
            ).result;

            expect(result).toBe(value);
        }
    },
);
