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

import { curve25519MulGenerator } from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

// The absent value is the default of its type: zero for the fields and the
// identity point, which is the generator multiplied by zero, for the point.
// Running the circuits checks that the JavaScript side agrees.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);

        const point = (await contract.circuits.none_point(ctx)).result;
        const scalar = (await contract.circuits.none_scalar(ctx)).result;
        const base = (await contract.circuits.right_of_base(ctx, 1n)).result;

        expect(point).toEqual({
            is_some: false,
            value: curve25519MulGenerator(0n),
        });
        expect(scalar).toEqual({ is_some: false, value: 0n });
        expect(base).toEqual({ is_left: false, left: 0n, right: 1n });
    },
);
