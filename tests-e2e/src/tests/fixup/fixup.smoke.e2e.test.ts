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
    createTempFolder,
    expectCommandResult,
    expectFiles,
    fixup,
    FIXUP_HELP_REGEX,
    fixupManualPage,
    buildPathTo,
    isMacOS,
    VERSION_REGEX,
} from '@';

const CONTRACT_WITH_ERRORS_FILE_PATH = buildPathTo('/errors/multiSource.compact');
const CONTRACT_NO_ERRORS = buildPathTo('/adt/exports/counter.compact');

function matchError(): string {
    if (isMacOS()) {
        return 'operation not permitted';
    }

    return 'is a directory';
}

describe('[Smoke] Fixup', () => {
    test('should show help option', async () => {
        const result: Result = await fixup([]);

        expectCommandResult(result).toBeError(FIXUP_HELP_REGEX, '');
    });

    test('should get man page', async () => {
        const result: Result = await fixup([Arguments.HELP]);

        expectCommandResult(result).toBeSuccess('', fixupManualPage());
    });

    test('should get compiler version', async () => {
        const result: Result = await fixup([Arguments.VERSION]);

        expectCommandResult(result).toBeSuccess('', VERSION_REGEX);
    });

    test('should get language version', async () => {
        const result: Result = await fixup([Arguments.LANGUAGE_VERSION]);

        expectCommandResult(result).toBeSuccess('', VERSION_REGEX);
    });

    test('should throw single line error with --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCommandResult(result).toBeFailure(
            'Exception: multiSource.compact line 28 char 10: no compatible function named enabledPower is in scope at this call; one function is incompatible with the supplied argument types; supplied argument types: (Uint<0..0>, Field); declared argument types for function at line 19 char 1: (Boolean, Field)',
            '',
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

    test('should throw multi line error without --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCommandResult(result).toBeFailure(
            'Exception: multiSource.compact line 28 char 10:\n' +
                '  no compatible function named enabledPower is in scope at this call\n' +
                '    one function is incompatible with the supplied argument types\n' +
                '      supplied argument types:\n' +
                '        (Uint<0..0>, Field)\n' +
                '      declared argument types for function at line 19 char 1:\n' +
                '        (Boolean, Field)',
            '',
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

    test('should throw an error when output is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, CONTRACT_NO_ERRORS, outputDir]);

        expectCommandResult(result).toBeFailure(
            `Exception: error creating output file: failed for ${outputDir}: ${matchError()}`,
            '',
        );
    });

    test('should throw an error when input is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, outputDir, outputDir]);

        expectCommandResult(result).toBeFailure(`Exception: error opening source file: ${outputDir} is a directory`, '');
    });

    test('should throw an error when file does not exist', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, 'bob.compact', outputDir]);

        expectCommandResult(result).toBeFailure(
            `Exception: error opening source file: failed for bob.compact: no such file or directory`,
            '',
        );
    });
});
