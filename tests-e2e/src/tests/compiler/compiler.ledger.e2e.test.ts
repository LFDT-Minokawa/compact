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

import { Result } from 'execa';
import { describe, test } from 'vitest';
import {
    Arguments,
    AssertContract,
    buildPathTo,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
} from '@';

describe('[Contract Info] Ledger added to contract-info.json', async () => {
    const CONTRACT_FILE_PATH = buildPathTo('election.compact');
    const outputDir = createTempFolder();
    const result: Result = await compile([Arguments.SKIP_ZK, CONTRACT_FILE_PATH, outputDir]);
    expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
    const contractAssertion = new AssertContract().expect(outputDir);

    test('ledger for primitive types added correctly', () => {
        // ledger authority: Bytes<32>;
        contractAssertion
            .thatLedgerFieldExists('authority')
            .thatLedgerFieldIndexIs('authority', 0)
            .thatLedgerFieldStorageIs('authority', 'Cell')
            .thatLedgerFieldHasType('authority', { 'type-name': 'Bytes', length: 32 })
            .thatLedgerFieldIsNotExported('authority');
    });

    test('ledger for program defined types added correctly', () => {
        // enum PublicState { setup, commit, reveal, final, }
        // ledger state: PublicState;
        contractAssertion
            .thatLedgerFieldExists('state')
            .thatLedgerFieldIndexIs('state', 1)
            .thatLedgerFieldStorageIs('state', 'Cell')
            .thatLedgerFieldHasType('state', {
                'type-name': 'Enum',
                name: 'PublicState',
                elements: ['setup', 'commit', 'reveal', 'final'],
            })
            .thatLedgerFieldIsNotExported('state');

        // ledger topic: Maybe<Opaque<"string">>;
        contractAssertion
            .thatLedgerFieldExists('topic')
            .thatLedgerFieldIndexIs('topic', 2)
            .thatLedgerFieldStorageIs('topic', 'Cell')
            .thatLedgerFieldHasType('topic', {
                'type-name': 'Struct',
                name: 'Maybe',
                elements: [
                    {
                        name: 'is_some',
                        type: {
                            'type-name': 'Boolean',
                        },
                    },
                    {
                        name: 'value',
                        type: {
                            'type-name': 'Opaque',
                            tsType: 'string',
                        },
                    },
                ],
            })
            .thatLedgerFieldIsNotExported('topic');
    });

    test('ledger for ADT added correctly', () => {
        // ledger tally_yes: Counter;
        contractAssertion
            .thatLedgerFieldExists('tally_yes')
            .thatLedgerFieldIndexIs('tally_yes', 3)
            .thatLedgerFieldStorageIs('tally_yes', 'Counter');

        // ledger committed_votes: MerkleTree<10, Bytes<32>>;
        contractAssertion
            .thatLedgerFieldExists('committed_votes')
            .thatLedgerFieldIndexIs('committed_votes', 5)
            .thatLedgerFieldStorageIs('committed_votes', 'MerkleTree')
            .thatLedgerMerkleTreeDepthIs('committed_votes', 10)
            .thatLedgerFieldHasType('committed_votes', {
                'type-name': 'Bytes',
                length: 32,
            });

        // ledger revealed: Set<Bytes<32>>;
        contractAssertion
            .thatLedgerFieldExists('revealed')
            .thatLedgerFieldIndexIs('revealed', 8)
            .thatLedgerFieldStorageIs('revealed', 'Set')
            .thatLedgerFieldHasType('revealed', {
                'type-name': 'Bytes',
                length: 32,
            });
    });

    test("ledger fields not in contract-info.json don't exist", () => {
        contractAssertion
            .thatLedgerFieldNotInJson('non_existent_field_1')
            .thatLedgerFieldNotInJson('non_existent_field_2')
            .thatLedgerFieldNotInJson('non_existent_field_3');
    });
});
