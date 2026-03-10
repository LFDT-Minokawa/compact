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

describe('[Types] [PM-19636] Define type aliases and new disjoint types for existing types', () => {
    const CONTRACTS_ROOT = buildPathTo('/types/');
    const CONTRACTS_NEGATIVE_ROOT = buildPathTo('/types/negative/');

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - define type as existing type', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 16 char 6: parse error: found keyword "Field" looking for an identifier',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - define same custom type twice', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 17 char 1: another binding found for V3U16 in the same scope at line 16 char 1',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - define same custom type twice (with new)', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 17 char 1: another binding found for f1 in the same scope at line 16 char 1',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - custom type cycle', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 17 char 21: cycle involving types t6_u32_b and t6_u32_a',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - custom type cycle (with new)', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_five.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_five.compact line 16 char 32: cycle involving type t7_boolean_b',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - use not defined custom type', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_six.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_six.compact line 16 char 29: unbound identifier t14_u32',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 7 - re-define type from CompactStandardLibrary', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_seven.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_seven.compact line 18 char 1: another binding found for ShieldedCoinInfo in the same scope at line 16 char 1',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 8 - define CompactStandardLibrary as custom type on top of file', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_eight.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_eight.compact line 17 char 1: invalid context for reference to type alias name CompactStandardLibrary',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 9 - non-exported cycle with new', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_nine.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_nine.compact line 16 char 22: cycle involving type t_boolean',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 10 - Uint type with 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_ten.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_ten.compact line 16 char 22: Uint width 0 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 11 - Uint type with range starting 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_eleven.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_eleven.compact line 16 char 22: range end for Uint type is 0 but must be at least 1 (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 12 - Uint type in struct, starting with 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_twelve.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_twelve.compact line 16 char 35: Uint width 0 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 13 - Uint type with range in struct, starting with 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_thirteen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_thirteen.compact line 16 char 35: range end for Uint type is 0 but must be at least 1 (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 14 - Uint type with 249', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_fourteen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_fourteen.compact line 16 char 22: Uint width 249 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 15 - Uint type with range ending 2^248', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_fifteen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_fifteen.compact line 16 char 22: range end; 999999999999999999999999999999999999999999999999999999999999999999999999999; for Uint type exceeds the limit of; 452312848583266388373324160190187140051835877600158453279131187530910662656 (2^248); (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 16 - Uint type in struct, ending with 249', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_sixteen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_sixteen.compact line 16 char 35: Uint width 249 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 17 - Uint type with range in struct, ending with ending 2^248', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_seventeen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_seventeen.compact line 16 char 35: range end; 999999999999999999999999999999999999999999999999999999999999999999999999999; for Uint type exceeds the limit of; 452312848583266388373324160190187140051835877600158453279131187530910662656 (2^248); (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
