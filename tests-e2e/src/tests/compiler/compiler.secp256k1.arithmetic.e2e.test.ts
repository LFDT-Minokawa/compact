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
    buildPathTo,
    compile,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getFileContent,
} from '@';

type ZkirCircuit = {
    inputs: {
        type: string;
    }[];
    outputs: string[];
    instructions: {
        op: string;
    }[];
};

type ArithmeticCase = {
    circuit: string;
    type: string;
    operations: string[];
};

const CONTRACT = buildPathTo('/secp256k1/arithmetic.compact');
const cases: ArithmeticCase[] = [
    { circuit: 'add_base', type: 'Base<Secp256k1>', operations: ['add'] },
    { circuit: 'subtract_base', type: 'Base<Secp256k1>', operations: ['neg', 'add'] },
    { circuit: 'multiply_base', type: 'Base<Secp256k1>', operations: ['mul'] },
    { circuit: 'add_scalar', type: 'Scalar<Secp256k1>', operations: ['add'] },
    { circuit: 'subtract_scalar', type: 'Scalar<Secp256k1>', operations: ['neg', 'add'] },
    { circuit: 'multiply_scalar', type: 'Scalar<Secp256k1>', operations: ['mul'] },
];

function getZkir(outputDir: string, circuitName: string): ZkirCircuit {
    return JSON.parse(getFileContent(`${outputDir}/zkir/${circuitName}.zkir`)) as ZkirCircuit;
}

describe('[Compiler] secp256k1 arithmetic operators', () => {
    test('v3 emits arithmetic for base and scalar fields', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.FEATURE_V3, Arguments.SKIP_ZK, CONTRACT, outputDir]);

        expectCompilerResult(result).toCompileWithoutErrors();
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        for (const { circuit, type, operations } of cases) {
            const zkir = getZkir(outputDir, circuit);
            const emittedOperations = zkir.instructions.map(({ op }) => op);

            expect(zkir.inputs.map((input) => input.type)).toEqual([type, type]);
            expect(zkir.outputs).toEqual([type]);
            expect(emittedOperations).toEqual(expect.arrayContaining(operations));
        }

        const generatedContract = getFileContent(`${outputDir}/contract/index.js`);
        expect(generatedContract).toContain('__compactRuntime.secp256k1BaseAdd');
        expect(generatedContract).toContain('__compactRuntime.secp256k1BaseSub');
        expect(generatedContract).toContain('__compactRuntime.secp256k1BaseMul');
        expect(generatedContract).toContain('__compactRuntime.secp256k1ScalarAdd');
        expect(generatedContract).toContain('__compactRuntime.secp256k1ScalarSub');
        expect(generatedContract).toContain('__compactRuntime.secp256k1ScalarMul');
    });
});
