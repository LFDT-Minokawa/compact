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

import { secp256k1MulGenerator } from '@midnight-ntwrk/compact-runtime';
import { secp256k1 } from '@noble/curves/secp256k1.js';

import type { Contract } from './.build/contract/index.js';
import { createTestContract, defineRuntimeTest } from '@test/compact-test';
import { checkProof } from '@test/proof-check';

// With the branch not taken, a zero signature and the identity key are never
// verified. With it taken, a real signature verifies. Both calls must pass the
// ZKIR check.
export default defineRuntimeTest<typeof Contract>(
    import.meta.url,
    async (Contract) => {
        const { contract, ctx } = await createTestContract(Contract);
        const c = contract.circuits;
        const digest = new Uint8Array(32).fill(0xab);
        const secretKey = 7n;
        const signature = secp256k1.Signature.fromBytes(
            secp256k1.sign(digest, secp256k1.Point.Fn.toBytes(secretKey), {
                prehash: false,
            }),
        );

        const skipped = await c.secp256k1_guarded_ecdsa_verify(
            ctx,
            false,
            digest,
            { r: 0n, s: 0n },
            secp256k1MulGenerator(0n),
        );
        expect(skipped.result).toBe(false);
        await checkProof(
            import.meta.url,
            'secp256k1_guarded_ecdsa_verify',
            skipped,
        );

        const taken = await c.secp256k1_guarded_ecdsa_verify(
            skipped.context,
            true,
            digest,
            { r: signature.r, s: signature.s },
            secp256k1MulGenerator(secretKey),
        );
        expect(taken.result).toBe(true);
        await checkProof(
            import.meta.url,
            'secp256k1_guarded_ecdsa_verify',
            taken,
        );
    },
);
