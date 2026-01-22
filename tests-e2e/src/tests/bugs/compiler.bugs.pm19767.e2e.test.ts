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

describe('[Bug] [PM-19767] Large casts in constructor', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-19767/');

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - for in constructor (slice with default Either)', async () => {
            const filePath = CONTRACTS_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 19 char 23: slice length; 197908171978938887506682837333954029155; exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - for in constructor (with default MerkleTreeDigest)', async () => {
            const filePath = CONTRACTS_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 19 char 23: slice length; 3073276899; exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - pad in constructor', async () => {
            const filePath = CONTRACTS_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 19 char 17: pad length 153991381835065054463771822173069549287 exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - slice in constructor (with default NativePoint)', async () => {
            const filePath = CONTRACTS_ROOT + 'example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 19 char 17: slice length; 77695467265087737476458093315063316059; exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - pad in constructor (with string)', async () => {
            const filePath = CONTRACTS_ROOT + 'example_five.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_five.compact line 19 char 17: pad length 2467012933 exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - pad in constructor (with binary)', async () => {
            const filePath = CONTRACTS_ROOT + 'example_six.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_six.compact line 20 char 17: pad length 1186675487 exceeds the maximum supported length 16777216',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
