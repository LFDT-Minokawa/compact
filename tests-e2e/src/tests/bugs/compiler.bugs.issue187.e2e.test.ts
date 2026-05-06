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
    buildPathTo,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getFileContent,
} from '@';

type CircuitName = 'less_than' | 'less_than_or_equal' | 'greater_than' | 'greater_than_or_equal';

type ZkirInstruction = {
    op: string;
    var?: number;
    a?: number;
    b?: number;
    bits?: number;
};

type ZkirCircuit = {
    instructions: ZkirInstruction[];
};

type ExpectedLessThanOperands = {
    a: 'firstPrivateInput' | 'secondPrivateInput';
    b: 'firstPrivateInput' | 'secondPrivateInput';
};

const CONTRACTS_ROOT = buildPathTo('/bugs/issue-187/');

function getExpectedLessThanOperands(circuitName: CircuitName): ExpectedLessThanOperands {
    switch (circuitName) {
        case 'less_than':
        case 'greater_than_or_equal':
            return { a: 'firstPrivateInput', b: 'secondPrivateInput' };
        case 'less_than_or_equal':
        case 'greater_than':
            return { a: 'secondPrivateInput', b: 'firstPrivateInput' };
    }
}

function getZkir(outputDir: string, circuitName: CircuitName): ZkirCircuit {
    return JSON.parse(getFileContent(`${outputDir}/zkir/${circuitName}.zkir`)) as ZkirCircuit;
}

function getPrivateInputVars(zkir: ZkirCircuit): number[] {
    return zkir.instructions.flatMap((instruction, index, instructions) => {
        const nextInstruction = instructions[index + 1];

        if (
            instruction.op === 'private_input' &&
            nextInstruction?.op === 'constrain_bits' &&
            nextInstruction.var !== undefined &&
            nextInstruction.bits === 8
        ) {
            return [nextInstruction.var];
        }

        return [];
    });
}

function getLessThanInstruction(zkir: ZkirCircuit): ZkirInstruction {
    const lessThanInstruction = zkir.instructions.find((instruction) => instruction.op === 'less_than');

    expect(lessThanInstruction).toBeDefined();
    return lessThanInstruction as ZkirInstruction;
}

function expectComparisonToUsePrivateInputsInOrder(outputDir: string, circuitName: CircuitName): void {
    const zkir = getZkir(outputDir, circuitName);
    const privateInputVars = getPrivateInputVars(zkir);
    const [firstPrivateInput, secondPrivateInput] = privateInputVars;
    const lessThanInstruction = getLessThanInstruction(zkir);
    const expectedLessThanOperands = getExpectedLessThanOperands(circuitName);
    const privateInputs = {
        firstPrivateInput,
        secondPrivateInput,
    };

    expect(privateInputVars).toHaveLength(2);
    expect(lessThanInstruction.a).toBe(privateInputs[expectedLessThanOperands.a]);
    expect(lessThanInstruction.b).toBe(privateInputs[expectedLessThanOperands.b]);
}

describe('[Bugs] [Issue #187] comparison operators preserve operand evaluation order in ZKIR', () => {
    test('provided comparison operators should compile left and right witness inputs in source order', async () => {
        const filePath = CONTRACTS_ROOT + 'comparisons.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess(/Compiling 4 circuits:/, compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        expectComparisonToUsePrivateInputsInOrder(outputDir, 'less_than');
        expectComparisonToUsePrivateInputsInOrder(outputDir, 'less_than_or_equal');
        expectComparisonToUsePrivateInputsInOrder(outputDir, 'greater_than');
        expectComparisonToUsePrivateInputsInOrder(outputDir, 'greater_than_or_equal');
    });
});
