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
    AssertContract,
    buildPathTo,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getFileContent,
} from '@';

type ZkirInstruction = {
    op: string;
    bits?: number;
};

type ZkirCircuit = {
    instructions: ZkirInstruction[];
};

const CONTRACTS_ROOT = buildPathTo('/bugs/issue-226/');

function getZkir(outputDir: string, circuitName: string): ZkirCircuit {
    return JSON.parse(getFileContent(`${outputDir}/zkir/${circuitName}.zkir`)) as ZkirCircuit;
}

describe('[Bugs] [Issue #226] conditional downcasts are safe in generated ZKIR', () => {
    test('conditional Uint<32> to Uint<8> downcast should not emit an unconditional Uint<8> constraint', async () => {
        const circuitName = 'guarded_downcast';
        const filePath = CONTRACTS_ROOT + 'conditional-downcast.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess(/Compiling 1 circuits:/, compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        new AssertContract().expect(outputDir).thatCircuitIsImpureExported(circuitName);

        const instructions = getZkir(outputDir, circuitName).instructions;

        expect(instructions).toContainEqual(expect.objectContaining({ op: 'less_than', bits: 32 }));
        expect(instructions).toContainEqual(expect.objectContaining({ op: 'cond_select' }));
        expect(instructions).not.toContainEqual(expect.objectContaining({ op: 'constrain_bits', bits: 8 }));
    });
});
