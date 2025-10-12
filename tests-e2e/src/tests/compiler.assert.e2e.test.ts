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
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[Assert] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/assert/';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const readFiles = fs.readdirSync(FOLDER_PATH, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    filesNames.forEach((fileName) => {
        const filePath = path.join(FOLDER_PATH, fileName);

        test(`should be able to compile contract with new assert expression syntax: ${fileName}`, async () => {
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
            expectCompilerResult(result).toReturn('', '', 0);
            expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
        });
    });

    test(`should not be able to compile contract with assert statement syntax: old_assert.compact`, async () => {
        const filePath = path.join(FOLDER_PATH, 'negative', 'old_assert.compact');

        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn(
            'Exception: old_assert.compact line 6 char 10:\n  parse error: found "1" looking for "("',
            '',
            255,
        );
    });
});
