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

import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';

import { expect } from 'vitest';

import {
    createTestContract,
    defineRuntimeTest,
    innerProofKeyPath,
    readInnerProof,
} from '@test/compact-test';

// Built by the runner's prepare pass before typecheck, which is what makes the
// generated circuit and witness signatures available here.
import type { Contract as GeneratedContract } from './.build/contract/index.js';

export default defineRuntimeTest<typeof GeneratedContract>(
    import.meta.url,
    async (Contract) => {
        const inner = readInnerProof('basic');

        // The contract names `basic.verifier` and the bundle's proof was made
        // against whatever is in that file, so the two drifting apart is what
        // this catches -- a stale key would otherwise surface as an opaque
        // verification failure.
        const keyOnDisk = createHash('sha256')
            .update(readFileSync(innerProofKeyPath('basic')))
            .digest('hex');
        expect(keyOnDisk).toBe(inner.vkHash);

        // One public input: the statement is `attestedValue == 123`.
        expect(inner.instance).toHaveLength(1);

        const { contract, ctx } = await createTestContract(Contract, {
            innerProof: (context) => [context.privateState, inner.proof],
        });

        await contract.circuits.verifyProofBasic(ctx, inner.instance[0]);

        // The proof is checked, not merely carried: a corrupted one has to fail
        // here, at circuit-run time, or `verifyProof` is doing nothing.
        const corrupted = Uint8Array.from(inner.proof);
        corrupted[corrupted.length - 1] ^= 0xff;

        const { contract: corruptedContract, ctx: corruptedCtx } =
            await createTestContract(Contract, {
                innerProof: (context) => [context.privateState, corrupted],
            });

        const failure = await corruptedContract.circuits
            .verifyProofBasic(corruptedCtx, inner.instance[0])
            .then(
                () => undefined,
                (error: unknown) => error,
            );

        // Only the proof bytes differ from the run above, and they reach
        // exactly one place, so this is `checkInnerProof` rejecting rather than
        // something upstream of it. `TypeError` is excluded because a plumbing
        // bug would also throw, and would otherwise read as a pass.
        expect(failure).toBeInstanceOf(Error);
        expect(failure).not.toBeInstanceOf(TypeError);

        // The attested value is the instance, so attesting to the wrong one is
        // a well-formed proof of the wrong statement -- `plonk::prepare`
        // returns `Ok` on it, and only the pairing rejects it.
        const { contract: mismatchedContract, ctx: mismatchedCtx } =
            await createTestContract(Contract, {
                innerProof: (context) => [context.privateState, inner.proof],
            });

        const mismatch = await mismatchedContract.circuits
            .verifyProofBasic(mismatchedCtx, inner.instance[0] + 1n)
            .then(
                () => undefined,
                (error: unknown) => error,
            );

        // Asserted on the message, not just on throwing: the corrupted proof
        // above throws too, from `plonk::prepare`, so only the wording tells
        // the two layers apart. This one is `verify_inner_proof`'s own.
        expect(mismatch).toBeInstanceOf(Error);
        expect((mismatch as Error).message).toContain('does not hold');
    },
);
