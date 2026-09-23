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

import { MAX_SECP256K1_BASE } from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

// The wire encoding stores `(value - 1) mod p` split across a 24-byte and an
// 8-byte atom, so the ends of the range are the interesting cases: zero wraps
// to the modulus minus one, one encodes as two empty atoms, and the maximum
// is the largest value the range check admits.
const VALUES = [0n, 1n, 12345678901234567890n, MAX_SECP256K1_BASE];

export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);

        for (const value of VALUES) {
            const result = (
                await contract.circuits.secp256k1_base_roundtrip(ctx, value)
            ).result;

            expect(result).toBe(value);
        }
    },
);
