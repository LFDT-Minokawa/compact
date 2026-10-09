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

import { describe, test } from 'vitest';
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles, buildPathTo } from '@';

describe('[Types] [PM-19636] Define type aliases and new disjoint types for existing types', () => {
    const CONTRACTS_ROOT = buildPathTo('/types/');
    const CONTRACTS_NEGATIVE_ROOT = buildPathTo('/types/negative/');

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        // Example 10 was a negative test for Uint<0> which is now allowed.

        test('example 11 - Uint type with range starting 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_eleven.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_eleven.compact line 16 char 22: range end for Uint type is 0 but must be at least 1 (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });

        // Example 12 was a negative test for Uint<0> which is now allowed.

        test('example 13 - Uint type with range in struct, starting with 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_thirteen.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_thirteen.compact line 16 char 35: range end for Uint type is 0 but must be at least 1 (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });

        test('example 14 - Uint type with 249', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_fourteen.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_fourteen.compact line 16 char 22: Uint width 249 exceeds the maximum Uint width 248',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });

        test('example 15 - Uint type with range ending 2^248', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_fifteen.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_fifteen.compact line 16 char 22: range end; 999999999999999999999999999999999999999999999999999999999999999999999999999; for Uint type exceeds the limit of; 452312848583266388373324160190187140051835877600158453279131187530910662656 (2^248); (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });

        test('example 16 - Uint type in struct, ending with 249', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_sixteen.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_sixteen.compact line 16 char 35: Uint width 249 exceeds the maximum Uint width 248',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });

        test('example 17 - Uint type with range in struct, ending with ending 2^248', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_seventeen.compact';

            const outputDir = createTempFolder();
            const result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_seventeen.compact line 16 char 35: range end; 999999999999999999999999999999999999999999999999999999999999999999999999999; for Uint type exceeds the limit of; 452312848583266388373324160190187140051835877600158453279131187530910662656 (2^248); (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(result).thatNoFilesAreGenerated();
        });
    });
});
