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
import { describe, expect, test } from 'vitest';
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles } from '..';
import fs from 'fs';
import path from 'path';

describe('[Filesystem] Compiler', () => {
    const CONTRACT_SOURCE_FILE = '../examples/tiny.compact';

    const prepareTempContract = () => {
        const output = createTempFolder() + 'test.compact';
        fs.copyFileSync(CONTRACT_SOURCE_FILE, output);
        return output;
    };

    test('should throw error when input file does not exist', async () => {
        const outputDir: string = createTempFolder();

        const result: Result = await compile([Arguments.VSCODE, 'doesNotExist.compact', outputDir]);
        expectCompilerResult(result).toReturn(
            'Exception: error opening source file: failed for doesNotExist.compact: no such file or directory',
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('[PM-10017] should throw error when input file is not readable', async () => {
        const outputDir = createTempFolder();
        const inputFile = prepareTempContract();
        fs.chmodSync(inputFile, '333');

        const result: Result = await compile([Arguments.VSCODE, inputFile, outputDir]);
        expectCompilerResult(result).toReturn(
            `Exception: error opening source file: failed for ${inputFile}: permission denied`,
            '',
            255,
        );
    });

    test('[PM-10018] should throw error when input file folder is not readable', async () => {
        const outputDir = createTempFolder();
        const inputFile = prepareTempContract();
        fs.chmodSync(path.dirname(inputFile), '000');

        const result: Result = await compile([Arguments.VSCODE, inputFile, outputDir]);
        expectCompilerResult(result).toReturn(
            `Exception: error opening source file: failed for ${inputFile}: permission denied`,
            '',
            255,
        );
    });

    test('[PM-10019] should throw error when output folder is not writeable', async () => {
        const outputDir = createTempFolder();
        const inputFile = prepareTempContract();
        fs.chmodSync(outputDir, '444');

        const result: Result = await compile([Arguments.VSCODE, inputFile, outputDir]);
        expectCompilerResult(result).toReturn(
            `Exception: error creating output directory: cannot create "${outputDir}/compiler": permission denied`,
            '',
            255,
        );
    });

    test('[PM-10020] should throw error when input file is a directory', async () => {
        const outputDir = createTempFolder();
        const contractPath = createTempFolder();

        const result: Result = await compile([Arguments.VSCODE, contractPath, outputDir]);
        expectCompilerResult(result).toReturn(
            `Exception: error opening source file: ${contractPath} is a directory`,
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('[PM-10021] should throw error when input file has the same absolute path as output', async () => {
        const inputFile = prepareTempContract();

        const result: Result = await compile([Arguments.VSCODE, inputFile, inputFile]);
        expectCompilerResult(result, inputFile).toReturn(
            `Exception: error creating output directory: cannot create "${inputFile}": file exists`,
            '',
            255,
        );
    });

    test('[PM-10022] should throw error when any of the already existing files in output folder is not writeable', async () => {
        const outputDir = createTempFolder();
        const inputFile = prepareTempContract();

        const result: Result = await compile([Arguments.VSCODE, inputFile, outputDir]);
        expect(result.exitCode).toEqual(0);
        fs.chmodSync(outputDir + 'contract/', '444');

        const result2: Result = await compile([Arguments.VSCODE, inputFile, outputDir]);
        expectCompilerResult(result2, outputDir).toReturn(
            `Exception: error creating output file: failed for ${outputDir}/contract/index.cjs.map: permission denied`,
            '',
            255,
        );
    }, 300000);
});
