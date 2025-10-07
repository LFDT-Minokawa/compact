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

import {
    compileQueue,
    compilerDefaultOutput,
    compileWithContractName,
    copyFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
} from '@';

describe('[Composable contracts graphs] Compiler', () => {
    let contractsDir: string;

    beforeEach(() => {
        contractsDir = createTempFolder();
    });

    test('should compile - linear', async () => {
        copyFiles('../examples/composable/graph-linear/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-1', async () => {
        copyFiles('../examples/composable/graph-tree-1/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-2', async () => {
        copyFiles('../examples/composable/graph-tree-2/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'C', 'B', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });
});
