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

// Resetting a tree, or storing a default tree in the map, leaves the same root
// as a tree that was never written. The harness only passes Contract, so the
// generated ledger reader is imported here, after the fixture has compiled.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { ledger } = await import('./.build/contract/index.js');
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;
        const read = (context: typeof ctx) =>
            ledger(context.callContext.currentQueryContext.state);
        const initial = read(ctx);

        const inserted = (await c.insert(ctx, 5n)).context;
        expect(read(inserted).tree16.root()).not.toEqual(initial.tree16.root());
        expect(read(inserted).tree20.root()).not.toEqual(initial.tree20.root());
        expect(read(inserted).tree32.root()).not.toEqual(initial.tree32.root());

        const reset = (await c.reset(inserted)).context;
        expect(read(reset).tree16.root()).toEqual(initial.tree16.root());
        expect(read(reset).tree20.root()).toEqual(initial.tree20.root());
        expect(read(reset).tree32.root()).toEqual(initial.tree32.root());

        const withDefault = (await c.insert_default(reset, true)).context;
        const withValue = (await c.insert_default_value(withDefault, false))
            .context;
        const trees = read(withValue).trees;
        expect(trees.lookup(true).root()).toEqual(initial.tree32.root());
        expect(trees.lookup(false).root()).toEqual(initial.tree32.root());
    },
);
