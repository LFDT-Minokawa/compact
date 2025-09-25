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
import { Arguments, compile, createTempFolder, ExitCodes, expectCompilerResult, expectFiles, getFileContent, isRelease } from '@';
import path from 'node:path';
import fs from 'fs';
import { generate } from '../fuzzer/fuzzers.cjs';

const contractsDir: string = createTempFolder();
generate(contractsDir, process.env.NO_OF_FUZZER_TESTS || 1000);
const generatedContracts = fs.readdirSync(contractsDir);

describe.skipIf(isRelease())('[E2E] Fuzzer tests for compiler', () => {
    generatedContracts.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const contractContent = getFileContent(filePath);

        test(`should be able to compile synthetic contract: '${fileName}'`, async () => {
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);
            expectCompilerResult(result, {
                contract: contractContent,
                ignoreStdOut: false,
                ignoreStdErr: false,
            }).stdErrToNotContain(['Internal']);

            if (result.exitCode == ExitCodes.Success) {
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();
            }
        });
    });
});
