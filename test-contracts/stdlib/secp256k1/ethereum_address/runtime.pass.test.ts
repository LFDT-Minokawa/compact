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

import { bytesToHex } from '@noble/hashes/utils.js';
import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import { loadAddressVectors, runKat } from '@test/crypto';

// The stdlib address circuit checked against published ethereum/tests
// addresses. It follows the real Ethereum rule, so these must match exactly.
//
// The addresses come from a file rather than being worked out here, so this
// does not lean on the runtime's own keccak.
const vectors = loadAddressVectors();

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        if (vectors.length === 0) {
            throw new Error('keyaddrtest.json produced no vectors');
        }

        runKat(
            'secp256k1EthereumAddress vs ethereum/tests',
            vectors,
            (vector) => `seed "${vector.seed}"`,
            ({ seed, point, ethAddr }) => {
                const address = pure.ethereumAddress(point);

                if (address.length !== 20) {
                    throw new Error(
                        `seed "${seed}": expected a 20-byte address, got ${address.length} bytes`,
                    );
                }

                const actual = `0x${bytesToHex(address)}`;

                if (actual !== ethAddr) {
                    throw new Error(
                        `seed "${seed}": got ${actual}, expected ${ethAddr}`,
                    );
                }
            },
        );
    },
);
