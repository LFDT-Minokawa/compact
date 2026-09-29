// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
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

// @ts-ignore - generated at test time
import { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

export default defineRuntimeTest(import.meta.url, async () => {
    const { contract, ctx } = await createTestContract(Contract, {
        vector_witness: (context) => [context.privateState, [5n, 6n, 7n, 8n]],
    });
    const result = (
        await contract.circuits.vector_witness_return_semantics(ctx)
    ).result;

    expect(result).toEqual([]);
});
