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
    AssertContract,
    buildPathTo,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getCompilerVersion,
    getLanguageVersion,
} from '@';

describe('[PM-21414] Compiler and language versions added to contract-info.json', () => {
    const CONTRACT_FILE_PATH = buildPathTo('counter.compact');

    test('should match both compiler and language versions', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const compilerVersion = await getCompilerVersion();
        const languageVersion = await getLanguageVersion();

        new AssertContract().expect(outputDir).thatCompilerVersionIs(compilerVersion).thatLanguageVersionIs(languageVersion);
    });
});
