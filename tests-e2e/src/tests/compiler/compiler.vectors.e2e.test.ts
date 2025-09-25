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
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles, buildPathTo } from '@';

describe('[Vectors] PM-13684/PM-17201/PM-18328 - Vector slice & spread', () => {
    const CONTRACTS_ROOT = buildPathTo('/vectors/');

    describe('different examples of vector slice', () => {
        test('should be compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'slice_part_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });

    describe('different examples of vector spread', () => {
        test('should be compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'spread_part_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 [slice] - invalid index length (out-of-bounds)', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/invalid_index_length.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: invalid_index_length.compact line 19 char 31: slice index 100 plus size 4 is out-of-bounds for a vector of length 8/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 [slice] - non-constant index', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/non_constant_index.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: non_constant_index.compact line 17 char 30: tuple slice with a non-constant index should be a vector but has a tuple type [Boolean, Boolean, Field] that cannot be converted to a vector because its element types are unrelated',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 [slice] - non-negative constant index', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/non_negative_index.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: non_negative_index.compact line 22 char 13: slice index did not reduce to a constant nonnegative value at compile time',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 [spread] - non-negative constant index', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/non_vector_type.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: non_vector_type.compact line 18 char 14: expected tuple/vector spread expression to have a tuple, Vector, or Bytes type but received Boolean',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
