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

const CONTRACTS_ROOT = buildPathTo('/casts/');
const CONTRACT_NEGATIVE_ROOT = buildPathTo('/casts/negative/');

describe('[Casts] PM-15536 - Casts between Bytes and Vectors', () => {
    describe('casts between Bytes and Vectors', () => {
        test('should be respected by compiler and compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'vector_to_bytes.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        test('should not fail on zkir generation', async () => {
            const filePath = CONTRACTS_ROOT + 'zkir_generation.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('Compiling 3 circuits:', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        describe('should fail with proper error in certain cases', () => {
            test('example 1 - can`t cast vector Uint<16> to bytes', async () => {
                const filePath = CONTRACT_NEGATIVE_ROOT + 'cannot_cast_higher_2.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: cannot_cast_higher_2.compact line 17 char 10: cannot cast from type Vector<1024, Uint<16>> to type Bytes<1024>/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });

            test('example 2 - can`t cast bytes to vector Uint<7>', async () => {
                const filePath = CONTRACT_NEGATIVE_ROOT + 'cannot_cast_lower.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeFailure(
                    /Exception: cannot_cast_lower.compact line 17 char 10: cannot cast from type Bytes<1024> to type Vector<1024, Uint<7>>/,
                    compilerDefaultOutput(),
                );
                expectFiles(outputDir).thatNoFilesAreGenerated();
            });
        });
    });
});

describe('[Advanced casts] PM-17427 - Casts between more advanced types', () => {
    test('should be respected by compiler and compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'advanced_casts.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - can`t cast vector with 6 elements to vector with 4 elements', async () => {
            const filePath = CONTRACT_NEGATIVE_ROOT + 'cannot_cast_six_to_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: cannot_cast_six_to_four.compact line 17 char 17: cannot cast from type [Boolean, Boolean, Boolean, Boolean, Boolean, Boolean] to type Vector<4, Boolean>',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
