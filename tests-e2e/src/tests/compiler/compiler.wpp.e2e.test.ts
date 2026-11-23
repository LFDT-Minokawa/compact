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

import { describe, test } from 'vitest';
import {
    Arguments,
    compile,
    compilerDefaultOutput,
    copyFile,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
} from '@';
import * as fs from 'fs';
import path from 'node:path';

describe('[WPP] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/wpp/');

    const readFiles = fs.readdirSync(CONTRACTS_ROOT, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    beforeAll(async () => {
        copyFile(buildPathTo('/wpp/test/test.compact'), contractsDir);

        await compile([`${contractsDir}/test.compact`, `${contractsDir}/test`]);
    });

    filesNames.forEach((fileName) => {
        const filePath = path.join(CONTRACTS_ROOT, fileName);

        test(`should be able to compile contract: ${fileName}`, async () => {
            const result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);
            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(result).thatGeneratedJSCodeIsValid();
        });
    });

    test(`should not be able to compile contract: pm_16723_neg.compact`, async () => {
        const filePath = path.join(CONTRACTS_ROOT, 'negative', 'pm_16723_neg.compact');
        const result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);

        expectCompilerResult(result).toBeFailure(
            'Exception: pm_16723.compact line 68 char 1:\n' +
                '  constructor cannot call insertCoin on ledger fields that contain a Set ADT type but does so at\n' +
                '  line 74 char 10\n',
            compilerDefaultOutput(),
        );
    });
});
