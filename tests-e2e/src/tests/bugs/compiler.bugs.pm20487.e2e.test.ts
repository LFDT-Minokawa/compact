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

describe('[Bug] [PM-20487] Return from for loops is not supported', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-20487/');
    const CONTRACTS_NEGATIVE_ROOT = buildPathTo('/bugs/pm-20487/negative/');

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - for loop with return in constructor', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 17 char 25: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - for loop with return in exported circuit', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 18 char 5: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - call circuit with for loop from exported circuit', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 22 char 5: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - for loop with return in exported module circuit', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 17 char 25: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - for loop with return in code block', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 18 char 5: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - for loop with return in if branches', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 22 char 5: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 7 - for loop with return in fold', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_seven.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_seven.compact line 17 char 58: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 8 - for loop with return in map', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_eight.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_eight.compact line 17 char 47: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 9 - for loop with return in generic circuit', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_nine.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_nine.compact line 17 char 25: return is not supported within for loops',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
