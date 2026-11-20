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
import {
    CompactTypeBytes,
    MAX_JUBJUB_SCALAR,
} from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    async (Contract, pure) => {
        const { contract, ctx } = await createTestContract(Contract);
        const entry = { id: 0xbeefn, scalar: MAX_JUBJUB_SCALAR };
        const { context } = await contract.circuits.emit_entry(ctx, entry);

        expect(context.events).toHaveLength(1);
        const [event] = context.events;
        expect(event.eventType).toBe('misc');
        if (event.data.tag !== 'cell') {
            throw new Error(`expected a cell, got ${event.data.tag}`);
        }
        const data = new CompactTypeBytes(288).fromValue([
            ...event.data.content.value,
        ]);

        const name = new TextEncoder().encode('jubjub-entry');
        expect(data).toEqual(
            concatBytes(
                name,
                new Uint8Array(32 - name.length),
                numberToBytesLE(0xbeefn, 2),
                numberToBytesLE(MAX_JUBJUB_SCALAR, 32),
                new Uint8Array(256 - 34),
            ),
        );
        expect(pure.decode_entry_event(data)).toEqual(entry);
    },
);
