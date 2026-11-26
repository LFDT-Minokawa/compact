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

import { concatBytes, numberToBytesLE } from '@noble/curves/utils.js';
import { MAX_JUBJUB_SCALAR } from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

const R = MAX_JUBJUB_SCALAR + 1n;
const MAX_BYTES32 = (1n << 256n) - 1n;
const le = (n: bigint) => numberToBytesLE(n, 32);

export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;

        const values = [MAX_JUBJUB_SCALAR, 0n, 1n];
        expect((await c.serialize_vector(ctx, values)).result).toEqual(
            concatBytes(...values.map(le)),
        );

        const bytes = concatBytes(le(R + 1n), le(MAX_BYTES32), le(7n));
        expect((await c.deserialize_vector(ctx, bytes)).result).toEqual([
            1n,
            MAX_BYTES32 % R,
            7n,
        ]);
    },
);
