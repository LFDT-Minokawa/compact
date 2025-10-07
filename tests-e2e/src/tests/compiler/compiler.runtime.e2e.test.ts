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
import {
    Arguments,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getFileContent,
    buildPathTo,
} from '@';

const CONTRACTS_ROOT = buildPathTo('/');
const RUNTIME_ROOT = buildPathTo('', 'runtime');

describe('[Runtime] Compiler', () => {
    test(`generated contract should use latest version of runtime`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'counter.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const getRuntimePackage = getFileContent(RUNTIME_ROOT + '/package.json');
        const packageVersion = getRuntimePackage.match(/"version"\s*:\s*"([^"]+)"/);

        const actualContract = getFileContent(outputDir + '/contract/index.js');
        const contractVersion = actualContract.match(/expectedRuntimeVersionString\s*=\s*'([^']+)'/);

        expect(contractVersion?.[1]).toEqual(packageVersion?.[1]);
    });
});
