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

describe('[Commas] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/commas/');

    const files = fs.readdirSync(CONTRACTS_ROOT);
    const contractsDir = createTempFolder();

    beforeAll(async () => {
        copyFile('../examples/commas/test.compact', contractsDir);

        await compile([`${contractsDir}/test.compact`, `${contractsDir}/test`]);
    });

    test(`should be able to compile contract: commas.compact which contains additional commas`, async () => {
        const result: Result = await compile([Arguments.SKIP_ZK, files[0], contractsDir], CONTRACTS_ROOT);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
    });

    test(`should be able to compile contract: more-commas.compact which contains additional commas`, async () => {
        const result: Result = await compile([Arguments.SKIP_ZK, files[1], contractsDir], CONTRACTS_ROOT);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
    });
});
