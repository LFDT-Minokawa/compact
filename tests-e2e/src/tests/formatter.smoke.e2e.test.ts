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
import path from 'node:path';
import {
    Arguments,
    compilerDefaultOutput,
    createTempFolder,
    expectCommandResult,
    format,
    formatterManualPage,
    isMacOS,
    isRelease,
} from '..';

const CONTRACT_WITH_ERRORS_FILE_PATH = '../examples/errors/multiSource.compact';
const CONTRACT_NO_ERRORS = '../examples/adt/exports/counter.compact';

function matchError(): string {
    if (isMacOS()) {
        return 'operation not permitted';
    }

    return 'is a directory';
}

describe.skipIf(isRelease())('[Smoke] Formatter', () => {
    const HELP_REGEX =
        /Usage: format-compact <flag> ... <source-pathname> \[ <target-pathname> ]\n.*--help displays detailed usage information/;

    const VERSION_REGEX = /(\d+)\.(\d+).(\d+)/;

    test('should show help option', async () => {
        const result: Result = await format([]);

        expectCommandResult(result).toReturn(HELP_REGEX, '', 1);
    });

    test('should get man page', async () => {
        const result: Result = await format([Arguments.HELP]);

        expectCommandResult(result).toReturn('', formatterManualPage(), 0);
    });

    test('should get compiler version', async () => {
        const result: Result = await format([Arguments.VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get language version', async () => {
        const result: Result = await format([Arguments.LANGUAGE_VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    // TODO: need to check if it is right
    test('should not return any errors with --vscode', async () => {
        const outputFile = path.join(createTempFolder(), 'formatted.compact');
        const result: Result = await format([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputFile]);

        expectCommandResult(result).toReturn('', compilerDefaultOutput(), 0);
    });

    test('should throw an error when output is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, CONTRACT_NO_ERRORS, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error creating output file: failed for ${outputDir}: ${matchError()}`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when input is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, outputDir, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: ${outputDir} is a directory`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when file does not exist', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, 'bob.compact', outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: failed for bob.compact: no such file or directory`,
            compilerDefaultOutput(),
            255,
        );
    });
});
