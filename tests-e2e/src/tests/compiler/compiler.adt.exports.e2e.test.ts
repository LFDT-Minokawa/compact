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
import * as fs from 'fs';

const CONTRACTS_ROOT = buildPathTo('/adt/exports/');
const files = await fs.promises.readdir(CONTRACTS_ROOT, { recursive: false, withFileTypes: true });

describe('[ADT Exports] Compiler', () => {
    files
        .filter((dirent) => dirent.isFile())
        .map((dirent) => `${dirent.name}`)
        .forEach((fileName) => {
            test(`should be able to compile contract: '${fileName}'`, async () => {
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], CONTRACTS_ROOT);
                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();
            });
        });
});
