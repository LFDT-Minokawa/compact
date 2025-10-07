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
import { Arguments, buildPathTo, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles } from '@';

describe('[Bugs] PM-7010 Merkle Tree and Historic Merkle Tree Bounds', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-7010/');

    describe('max and min merkle and historic merkle tree depth examples', () => {
        test('should be compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'historic_and_merkle_tree.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });

    describe('should fail with proper error in certain cases - merkle tree', () => {
        test('example 1 - merkle tree size 0', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/merkle_tree_too_small_0.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: merkle_tree_too_small_0.compact line 18 char 38: MerkleTree depth 0 does not fall in 2 <= depth <= 32/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - merkle tree size 1', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/merkle_tree_too_small_1.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: merkle_tree_too_small_1.compact line 18 char 38: MerkleTree depth 1 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - merkle tree size 33', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/merkle_tree_too_big_33.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: merkle_tree_too_big_33.compact line 18 char 36: MerkleTree depth 33 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - merkle tree size 100', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/merkle_tree_too_big_100.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: merkle_tree_too_big_100.compact line 18 char 36: MerkleTree depth 100 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });

    describe('should fail with proper error in certain cases - historic merkle tree', () => {
        test('example 1 - historic merkle tree size 0', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/historic_merkle_tree_too_small_0.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: historic_merkle_tree_too_small_0.compact line 18 char 47: HistoricMerkleTree depth 0 does not fall in 2 <= depth <= 32/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - historic merkle tree size 1', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/historic_merkle_tree_too_small_1.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: historic_merkle_tree_too_small_1.compact line 18 char 47: HistoricMerkleTree depth 1 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - historic merkle tree size 33', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/historic_merkle_tree_too_big_33.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: historic_merkle_tree_too_big_33.compact line 18 char 45: HistoricMerkleTree depth 33 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - historic merkle tree size 100', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/historic_merkle_tree_too_big_100.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: historic_merkle_tree_too_big_100.compact line 18 char 45: HistoricMerkleTree depth 100 does not fall in 2 <= depth <= 32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
