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
import path from 'node:path';
import fs from 'fs';

describe('[Bug] [PM-20295] Non-constant Vector and Bytes indices are not bounds-checked in the constructor', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-20295/');
    const CONTRACTS_NEGATIVE_ROOT = buildPathTo('/bugs/pm-20295/negative/');

    const readFiles = fs.readdirSync(CONTRACTS_ROOT, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    filesNames.forEach((fileName) => {
        const filePath = path.join(CONTRACTS_ROOT, fileName);

        test(`should be able to compile contract: ${fileName}`, async () => {
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);
            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
        });
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - index out of bounds', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 19 char 14: index 11 is out-of-bounds for a vector of length 10',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - slice index out of bounds', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 19 char 14: slice index 0 plus length 10 is out-of-bounds for a vector of length 5',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - nonnegative constant value as index', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 19 char 14: slice index did not reduce to a constant nonnegative value at compile time',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - slice index out of bounds (max value)', async () => {
            const filePath = CONTRACTS_NEGATIVE_ROOT + 'example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 19 char 14: slice index 255 plus length 1 is out-of-bounds for a vector of length 10',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
