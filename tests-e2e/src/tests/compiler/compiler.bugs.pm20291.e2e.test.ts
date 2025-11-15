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
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
    copyFile,
} from '@';

describe('[Bug] [PM-20291] Redundant incompatible functions', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-20291/');

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - multiple compatible functions', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 24 char 54: call site ambiguity (multiple compatible functions) in call to test3; supplied argument types: (Vector<1, Vector<1, Uint<1>>>); compatible functions: line 18 char 3; line 20 char 3; line 21 char 3; line 22 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - same signature, different return types', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 20 char 46: call site ambiguity (multiple compatible functions) in call to test15; supplied argument types: (Uint<1>); compatible functions: line 18 char 3; line 19 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - same signature, more different return types', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 22 char 46: call site ambiguity (multiple compatible functions) in call to test19; supplied argument types: (Uint<1>); compatible functions: line 18 char 3; line 19 char 3; line 20 char 3; line 21 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - same signature, return struct with enum', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 25 char 48: call site ambiguity (multiple compatible functions) in call to test23; supplied argument types: (Boolean); compatible functions: line 23 char 3; line 24 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - same signature, return enum', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_five.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_five.compact line 25 char 45: call site ambiguity (multiple compatible functions) in call to test18; supplied argument types: (Uint<1>); compatible functions: line 22 char 3; line 23 char 3; line 24 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - import module from another file', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_six.compact';

            const outputDir = createTempFolder();
            copyFile(`${CONTRACTS_ROOT}negative/M1.compact`, outputDir);

            const firstContract = await compile([`${outputDir}/M1.compact`, `${outputDir}/M1`]);
            expectCompilerResult(firstContract).toBeSuccess('', compilerDefaultOutput());
            expectFiles(`${outputDir}/M1`).thatGeneratedJSCodeIsValid();

            const secondContract: Result = await compile([Arguments.VSCODE, filePath, outputDir]);
            expectCompilerResult(secondContract).toBeFailure(
                'Exception: example_six.compact line 21 char 57: no compatible function named test1 is in scope at this call; three functions are incomptable with the supplied generic values; supplied generic values: <size 8, type Field>; declared generics for function at M1.compact line 17 char 3: <size>; declared generics for function at line 19 char 3: <size>; declared generics for function at line 20 char 3: <size>',
                compilerDefaultOutput(),
            );
        });
    });
});
