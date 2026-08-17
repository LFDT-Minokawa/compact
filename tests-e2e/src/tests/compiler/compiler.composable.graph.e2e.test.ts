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
    compile,
    compilerDefaultOutput,
    compileQueue,
    compileWithContractName,
    copyFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
} from '@';
import fs from 'fs';

describe('[Composable contracts dependency graph] Compiler', () => {
    let contractsDir: string;

    beforeAll(() => {
        contractsDir = createTempFolder();
        copyFiles('../examples/composable/graph/*.compact', contractsDir);
    });

    test('should compile when A and B are referenced in MAIN', async () => {
        await compileQueue(contractsDir, ['A', 'B']);

        const result = await compileWithContractName('Main-A-and-B', contractsDir);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test('should compile when A is referenced in C, B and C are referenced in MAIN', async () => {
        await compileQueue(contractsDir, ['A', 'B', 'C']);

        const result = await compileWithContractName('Main-B-and-C-on-A', contractsDir);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test('should fail when A is referenced in C, B and C are referenced in MAIN and A is deleted', async () => {
        await compileQueue(contractsDir, ['B', 'A', 'C']);
        fs.rmSync(`${contractsDir} + A`, { recursive: true, force: true });

        const result = await compileWithContractName('Main-B-and-C-on-A', contractsDir);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test('should fail when A and B are referenced in MAIN, and MAIN is compiled to output directory A', async () => {
        await compileQueue(contractsDir, ['B', 'A']);

        const result = await compile([contractsDir + 'Main-A-and-B.compact', contractsDir + 'A']);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles({ outputDir: `${contractsDir}Main-A-and-B` }).thatGeneratedJSCodeIsValid();
    });
});
