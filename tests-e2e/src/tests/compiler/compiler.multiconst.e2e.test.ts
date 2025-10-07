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

describe('[Multi const] PM-15976 - Multi-variable const assignments', () => {
    const CONTRACTS_ROOT = buildPathTo('/multiconst/');
    const CONTRACTS_ROOT_NEGATIVE = buildPathTo('/multiconst/negative/');

    describe('multi-variable const assignments', () => {
        test('should be respected by compiler and compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'multiconst.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        describe('should fail with proper error in certain cases', () => {
            test('example 1 - multiple bindings in same block', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'multiple_bindings_in_same_block.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: multiple_bindings_in_same_block.compact line 18 char 25: found multiple bindings for a in the same block/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 2 - multiple bindings in same block', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'multiple_bindings_in_same_block_2.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: multiple_bindings_in_same_block_2.compact line 19 char 11: found multiple bindings for a in the same block/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 3 - multiple bindings in same block', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'multiple_bindings_in_same_block_3.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: multiple_bindings_in_same_block_3.compact line 18 char 9: found multiple bindings for _ in the same block/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 4 - no commas between variables', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'no_commas.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    'Exception: no_commas.compact line 18 char 17: parse error: found "b" looking for ",", ";", "||", "&&", "==", "!=", "as", "+", "-", "*", "[", ".", "?", "=", "+=", "-=", "<", "<=", ">=", or ">"',
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 5 - trailing comma, with no variable after', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'trailing_comma.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: trailing_comma.compact line 17 char 24: parse error: found ";" looking for a const binding/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 6 - variable referenced before being assigned', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'reference_before_assignment.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: reference_before_assignment.compact line 18 char 5: identifier x might be referenced before it is assigned/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 7 - variable referenced before being assigned', async () => {
                const filePath = CONTRACTS_ROOT_NEGATIVE + 'reference_before_assignment_2.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: reference_before_assignment_2.compact line 18 char 15: identifier y might be referenced before it is assigned/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });
        });
    });
});
