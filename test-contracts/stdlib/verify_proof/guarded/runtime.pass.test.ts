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

import {
    createTestContract,
    defineRuntimeTest,
    readInnerProof,
} from '@test/compact-test';

import type { Contract as GeneratedContract } from './.build/contract/index.js';

/**
 * A guarded-off `verifyProof` records no inner proof, and owes none.
 *
 * `inner_proof` consumes a witness only where its guard is on, as the other
 * three preimage-consuming instructions do -- so lowering a guarded
 * `verifyProof` to a JavaScript `if` is right, and the count `Zkir::check`
 * enforces is over the instructions actually taken. Both settings are asserted
 * here because nothing checks the two emitters agree at compile time.
 */
export default defineRuntimeTest<typeof GeneratedContract>(
    import.meta.url,
    async (Contract) => {
        const inner = readInnerProof('basic');

        const run = async (verify: boolean) => {
            const { contract, ctx } = await createTestContract(Contract, {
                innerProof: (context) => [context.privateState, inner.proof],
            });

            const { context } = await contract.circuits.verifyProofGuarded(
                ctx,
                verify,
                inner.instance[0],
            );

            expect(context.callProofDataTrace).toHaveLength(1);

            return context.callProofDataTrace[0].innerProofs;
        };

        // Guard true: the proof is verified and recorded.
        expect(await run(true)).toHaveLength(1);

        // Guard false: the branch is not taken, so nothing is verified and
        // no slot is owed.
        expect(await run(false)).toHaveLength(0);
    },
);
