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

describe('[Bug] [PM-15797] Unsigned range changes', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-15797/');
    const CONTRACTS_NEGATIVE_ROOT = buildPathTo(`/bugs/pm-15797/negative/`);

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - range lower bound must start at 0', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 18 char 13: range start for Uint type is 7 but must be 0',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - range upper bound must be at least 1', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 18 char 13: range end for Uint type is 0 but must be at least 1 (the range end is exclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - lower bound cant be bigger than upper bound', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 18 char 5: end bound 1 is less than start bound 7',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - cast between type and range', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 19 char 9: mismatch between actual type Uint<13> and declared type Uint<0..13> of const binding',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
