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

describe('[Bug] [PM-20028] [PM-20222] Unsigned range changes', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-20028/');

    test('example contract should be compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'examples.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    describe('should fail with proper error in certain cases', () => {
        test('example 1 - adding two Uint<248>', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_one.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_one.compact line 17 char 12: resulting value might exceed largest representable Uint value (for Field semantics, cast either operand to Field)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 2 - return default<Uint<254>>', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_two.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_two.compact line 16 char 25: Uint width 254 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 3 - return default<Uint<0>>', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_three.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_three.compact line 16 char 25: Uint width 0 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 4 - cast Uint<249> to Uint<64>', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_four.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_four.compact line 17 char 20: Uint width 249 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 5 - multiply two Uint<248>', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_five.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_five.compact line 17 char 12: resulting value might exceed largest representable Uint value (for Field semantics, cast either operand to Field)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('example 6 - constructor', async () => {
            const filePath = CONTRACTS_ROOT + 'negative/example_six.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_six.compact line 17 char 23: Uint width 249 is not between 1 and the maximum Uint width 248 (inclusive)',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
