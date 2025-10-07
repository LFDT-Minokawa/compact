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

import { afterAll, beforeAll, describe, test } from 'vitest';
import { compile, compilerDefaultOutput, copyFiles, createTempFolder, expectCompilerResult, expectFiles, removeFolder } from '@';
import { Result } from 'execa';
import { startContract } from './util';
import fs from 'fs';
import * as runtime from '@midnight-ntwrk/compact-runtime';

// TODO: Ask Leszek Lorek if and when to enable the tests in this suite with 'describe.skipIf(isRelease())'
describe.skip('[ZKIR] Verify proof data for vector to bytes and bytes to vector', () => {
    const CONTRACTS_ROOT = '../examples/casts/';
    const filePath = CONTRACTS_ROOT + 'proof_data.compact';
    const outputDir = createTempFolder();

    beforeAll(async () => {
        const result: Result = await compile([filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('Compiling 2 circuits:', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        // copy main node_modules, which include compact runtime
        copyFiles('../node_modules/@midnight-ntwrk', outputDir + '/contract/node_modules');
    });

    afterAll(() => {
        // cleanup
        removeFolder(outputDir + '/contract/node_modules');
    });

    test.skip('check if proof data is valid for bytes to vector - test1', async () => {
        // import contract code dynamically
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractCode = await import(outputDir + '/contract/index.js');

        const [C, InitialContext] = startContract(contractCode, {}, 0);

        const afterTest = C.circuits.test1(InitialContext);

        const zkirFile = outputDir + '/zkir/test1.zkir';
        const zkir = fs.readFileSync(zkirFile, 'utf-8');

        // check proof based on zkir

        runtime.checkProofData(zkir, afterTest.proofData);
    });

    test.skip('check if proof data is valid for vector to bytes - test2', async () => {
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractCode = await import(outputDir + '/contract/index.js');

        // eslint-disable-next-line @typescript-eslint/no-unsafe-return
        const contract = () => new contractCode.Contract({});
        const [C, InitialContext] = startContract(contract, 0);

        const afterTest = C.circuits.test2(InitialContext);

        const zkirFile = outputDir + '/zkir/test2.zkir';
        const zkir = fs.readFileSync(zkirFile, 'utf-8');

        runtime.checkProofData(zkir, afterTest.proofData);
    });
});
