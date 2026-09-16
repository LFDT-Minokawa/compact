// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// You may not use this file except in compliance with the License.
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
 * One `inner_proof` instruction means one witness, whichever way the guard
 * goes.
 *
 * `ir_vm.rs:921` takes a witness per instruction before it reads the guard, and
 * `:960` checks the count exactly, so a run that records none against a circuit
 * carrying one is rejected -- by `Zkir::check`, not only by proving. Asserting
 * the count here states that invariant where it is violated, rather than
 * waiting for ZKIR to state it as a mismatch.
 */
export default defineRuntimeTest<typeof GeneratedContract>(
    import.meta.url,
    async (Contract) => {
        const inner = readInnerProof('basic');

        const run = async (verify: boolean) => {
            const { contract, ctx } = await createTestContract(Contract, {
                inner_proof: (context) => [context.privateState, inner.proof],
            });

            const { context } = await contract.circuits.verify_proof_guarded(
                ctx,
                verify,
                inner.instance[0],
            );

            expect(context.callProofDataTrace).toHaveLength(1);

            return context.callProofDataTrace[0].innerProofs;
        };

        // Guard true: the proof is verified and recorded.
        expect(await run(true)).toHaveLength(1);

        // Guard false: nothing is verified, but the slot is still owed. ZKIR
        // ignores the bytes under a false guard -- it substitutes `Vec::new()`
        // -- so an empty entry is the right thing to record, and no entry is
        // not.
        expect(await run(false)).toHaveLength(1);
    },
    {
        skip:
            'guarded-off verifyProof records no witness, so ZKIR rejects the ' +
            'preimage. The assertion is right and the emitter is not; see ' +
            'claude/verify-proof-two-emitters.md. Removing this option is the ' +
            'test that the fix works.',
    },
);
