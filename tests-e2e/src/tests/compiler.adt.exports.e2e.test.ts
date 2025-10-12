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

const CONTRACTS_ROOT = '../../../examples/adt/exports/';
const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

const files = await fs.promises.readdir(FOLDER_PATH, { recursive: false, withFileTypes: true });

describe('[ADT Exports] Compiler', () => {
    files
        .filter((dirent) => dirent.isFile())
        .map((dirent) => `${dirent.parentPath}${dirent.name}`)
        .forEach((fileName) => {
            test(`should be able to compile contract: '${fileName}'`, async () => {
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], FOLDER_PATH);
                expectCompilerResult(result).toReturn('', '', 0);
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();
            });
        });
});
