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
    contractInfoFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
    tsFiles,
} from '@';

describe('[Errors] PM-14770', () => {
    const CONTRACTS_ROOT = buildPathTo('/errors/');

    describe('contract with file name which', () => {
        // this is how you cat the file on macOS - with all these slashes
        test('include spaces and passed with slashes - is compiled', async () => {
            const filePath = CONTRACTS_ROOT + 'existing\ file\ with\ \ spaces\ \ \ in\ \ \ \ name.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        test('include spaces and passed with no quotes - is compiled', async () => {
            const filePath = CONTRACTS_ROOT + 'existing file with  spaces   in    name.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatFilesAreGenerated(tsFiles, [], [], contractInfoFiles);
        });

        /*
         * the file that the test gets here will appear as "'existing file with  spaces in    name.compact'" and so
         * the compiler looks for 'existing file with  spaces in    name.compact' which it cannot find and thus
         * throws the exception to no such file or directory.
         */
        test('include spaces and passed with double quotes - is not compiled', async () => {
            const filePath = '../examples/errors/existing file with  spaces in    name.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, `"${filePath}"`, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: error opening source file: failed for "..\/examples\/errors\/existing file with  spaces in    name.compact": no such file or directory/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });

        test('include spaces and passed with single quotes - is not compiled', async () => {
            const filePath = '../examples/errors/existing file with  spaces in    name.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, `'${filePath}'`, outputDir]);

            expectCompilerResult(result).toBeFailure(
                /Exception: error opening source file: failed for '..\/examples\/errors\/existing file with  spaces in    name.compact': no such file or directory/,
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
