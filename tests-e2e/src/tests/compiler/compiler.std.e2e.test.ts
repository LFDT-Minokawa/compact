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
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
} from '@';
import path from 'node:path';

describe('[Std] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/std_lib/import');
    const contractsDir = createTempFolder();

    test(`should be able to compile contract with valid standard library: test_import_csl.compact`, async () => {
        const filePath = path.join(CONTRACTS_ROOT, 'test_import_csl.compact');

        const result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test(`should be able to compile contract with new block time methods: block_time.compact`, async () => {
        const CONTRACTS_ROOT = buildPathTo('/std_lib');
        const filePath = path.join(CONTRACTS_ROOT, 'block_time.compact');

        const result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });
});
