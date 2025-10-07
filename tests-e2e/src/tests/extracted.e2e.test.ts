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
    createTempFolder,
    ExitCodes,
    expectCompilerResult,
    expectFiles,
    extractAndSaveContracts,
    getFileContent,
    isRelease,
} from '@';
import path from 'node:path';

const contractsDir: string = createTempFolder();
const extractedFiles: string[] = extractAndSaveContracts(contractsDir);

describe.skipIf(isRelease())('[E2E] Extracted unit tests for compiler', () => {
    extractedFiles.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const contractContent = getFileContent(filePath);

        test(`should be able to compile extracted contract: '${contractsDir}${fileName}'`, async () => {
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir], contractsDir);
            expectCompilerResult(result).stdErrToNotContain(['Internal']);

            if (result.exitCode == ExitCodes.Success) {
                if (contractContent.includes('if (b()) S { w(), w() }') || contractContent.includes('if (b) S { w(), w() };')) {
                    expectFiles(outputDir).thatGeneratedJSCodeIsValid(false);
                } else {
                    expectFiles(outputDir).thatGeneratedJSCodeIsValid();
                }
            }
        });
    });
});
