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

// The top byte of MAX_JUBJUB_SCALAR is not zero, so a wrong byte order or a
// short encoding changes the bytes.
const VALUES = [0n, 1n, MAX_JUBJUB_SCALAR];

export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { ledger } = await import('./.build/contract/index.js');
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;

        for (const value of VALUES) {
            const encoding = numberToBytesLE(value, 32);
            const roundtrip = await c.serialize_roundtrip(ctx, value);

            expect(roundtrip.result).toBe(value);
            // A round trip can hide a wrong encoding, so check the stored bytes too.
            expect(
                ledger(roundtrip.context.callContext.currentQueryContext.state)
                    .encoded,
            ).toEqual(encoding);
            expect((await c.serialize_padded(ctx, value)).result).toEqual(
                concatBytes(encoding, new Uint8Array(8)),
            );
        }

        const value = MAX_JUBJUB_SCALAR - 1n;
        const tail = new Uint8Array(8).fill(0xff);
        const bytes = concatBytes(numberToBytesLE(value, 32), tail);
        expect((await c.deserialize_padded(ctx, bytes)).result).toBe(value);
    },
);
