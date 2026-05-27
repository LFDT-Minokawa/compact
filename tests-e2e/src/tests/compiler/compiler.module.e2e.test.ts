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

describe('[Module] PM-13947 - Selective import module exports', () => {
    const CONTRACTS_ROOT = buildPathTo('/modules/');
    const CONTRACTS_ROOT_NEGATIVE = buildPathTo('/modules/negative/');

    describe('usage of selective import of module exports', () => {
        test('should be respected by compiler and compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'selective_examples.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        test('should work with shadow import of CompactStandardLibrary', async () => {
            const filePath = CONTRACTS_ROOT + 'shadowing_example.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - import non-existing method', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: example_one.compact line 31 char 10: no export named test2a in module Test1a/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - import from wrapped module', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: example_two.compact line 38 char 13: unbound identifier t1a/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - import as already existing import', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: example_three.compact line 38 char 10: another binding found for vt2a in the same scope at line 34 char 10/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - import from non-existing module', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 35 char 1: failed to locate file "NonExistingModule.compact"',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - different way to import from non-existing module', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_five.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_five.compact line 34 char 1: failed to locate file "NonExistingModule.compact"',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - local import module (not-implemented)', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_six.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_six.compact line 19 char 3: parse error: found keyword "import" looking for a statement or "}"',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 7 - use original enum name instead of the new identifier it is bound to in import statement', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_seven.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_seven.compact line 48 char 17: unbound identifier Direction',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 8 - import generic method twice with different types', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_eight.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_eight.compact line 28 char 12: call site ambiguity (multiple compatible functions) in call to t6a; supplied argument types: (Bytes<1>); compatible functions: line 18 char 3; line 18 char 3',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 9 - import non-exported name', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_nine.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_nine.compact line 45 char 40: no export named t3a in module Test3b',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 10 - import as CompactStandardLibrary', async () => {
            const filePath = CONTRACTS_ROOT_NEGATIVE + 'example_ten.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_ten.compact line 25 char 1: invalid context for reference to function name CompactStandardLibrary',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
