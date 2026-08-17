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
    buildPathTo,
    compileQueue,
    compilerDefaultOutput,
    compileWithContractName,
    copyFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    withContractPath,
} from '@';

describe('[Composable contracts graphs] Compiler', () => {
    let contractsDir: string;

    beforeEach(() => {
        contractsDir = createTempFolder();
    });

    test('should compile - linear', async () => {
        const fixtures = '/composable/graph-linear';

        copyFiles(buildPathTo(`${fixtures}/*.compact`), contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const result = withContractPath(await compileWithContractName('E', contractsDir), buildPathTo(`${fixtures}/E.compact`));
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-1', async () => {
        const fixtures = '/composable/graph-tree-1';

        copyFiles(buildPathTo(`${fixtures}/*.compact`), contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const result = withContractPath(await compileWithContractName('E', contractsDir), buildPathTo(`${fixtures}/E.compact`));
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-2', async () => {
        const fixtures = '/composable/graph-tree-2';

        copyFiles(buildPathTo(`${fixtures}/*.compact`), contractsDir);
        await compileQueue(contractsDir, ['A', 'C', 'B', 'D']);

        const result = withContractPath(await compileWithContractName('E', contractsDir), buildPathTo(`${fixtures}/E.compact`));
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(result).thatGeneratedJSCodeIsValid();
    });
});
