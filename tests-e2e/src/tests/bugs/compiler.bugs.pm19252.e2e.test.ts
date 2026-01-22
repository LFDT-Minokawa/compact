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
import { describe, test } from 'vitest';
import {
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
    AssertCircuits,
    Arguments,
} from '@';

describe('[Bug] [PM-19252] Avoid creating zkir for circuits that don`t touch the ledger', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/pm-19252/');

    describe('not exported circuit(s)', () => {
        describe('should not generate zkir keys', () => {
            test('when not touching ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_one.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasNoKeys('test').thatCircuitHasNoZkir('test');
            });

            test('when circuit has pure keyword and is using non-exported ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_one_a.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasNoKeys('test1').thatCircuitHasNoZkir('test1');
            });

            test('when writing to ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_two.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasNoKeys('test').thatCircuitHasNoZkir('test');
            });

            test('when reading from ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_three.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasNoKeys('test').thatCircuitHasNoZkir('test');
            });

            test('with two circuits - one touching ledger variable, one not', async () => {
                const filePath = CONTRACTS_ROOT + 'example_four.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('with two circuits - one writing to, one reading from ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_four_a.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('with two circuits - one writing to, one reading from non-exported ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_four_b.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });
        });
    });

    describe('exported circuit(s)', () => {
        describe('should not generate zkir keys', () => {
            test('when not touching ledger variable (pure)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_five.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual(['test']);

                outputContract.thatCircuitHasNoKeys('test').thatCircuitHasNoZkir('test');
            });
        });

        describe('should generate zkir keys', () => {
            test('when writing to ledger variable (impure)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_six.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('Compiling 1 circuits:', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasKeys('test').thatCircuitHasZkir('test');
            });

            test('when reading from ledger variable (impure)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_seven.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('Compiling 1 circuits:', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract.thatCircuitHasKeys('test').thatCircuitHasZkir('test');
            });

            test('with two circuits - one touching ledger variable, one not', async () => {
                const filePath = CONTRACTS_ROOT + 'example_eight.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('Compiling 1 circuits:', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test']);
                expect(outputContract.getPureCircuits()).toStrictEqual(['test1']);

                outputContract
                    .thatCircuitHasKeys('test')
                    .thatCircuitHasZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('with two circuits - one writing, one reading from exported ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_eight_a.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('Compiling 2 circuits:', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test', 'test1']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasKeys('test')
                    .thatCircuitHasZkir('test')
                    .thatCircuitHasKeys('test1')
                    .thatCircuitHasZkir('test1');
            });

            test('when two circuits - one writing, one reading from non-exported ledger variable', async () => {
                const filePath = CONTRACTS_ROOT + 'example_eight_b.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('Compiling 2 circuits:', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test', 'test1']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasKeys('test')
                    .thatCircuitHasZkir('test')
                    .thatCircuitHasKeys('test1')
                    .thatCircuitHasZkir('test1');
            });
        });
    });

    describe('one exported and one non-exported circuit', () => {
        describe('should not generate zkir keys', () => {
            test('two circuits (not-exported touching ledger variable, exported not)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_nine.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual(['test1']);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('two circuits (both calling witness-like method)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_ten.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test1']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('two circuits (both calling non-exported witness)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_eleven.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test1']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('two circuits (both calling exported witness from module)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_twelve.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual(['test1']);
                expect(outputContract.getPureCircuits()).toStrictEqual([]);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });

            test('two circuits (both with pure keyword, non-exported writing to ledger variable)', async () => {
                const filePath = CONTRACTS_ROOT + 'example_thirteen.compact';

                const outputDir = createTempFolder();
                const result: Result = await compile([filePath, outputDir]);

                expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();

                const outputContract = new AssertCircuits().expect(outputDir);
                expect(outputContract.getImpureCircuits()).toStrictEqual([]);
                expect(outputContract.getPureCircuits()).toStrictEqual(['test1']);

                outputContract
                    .thatCircuitHasNoKeys('test')
                    .thatCircuitHasNoZkir('test')
                    .thatCircuitHasNoKeys('test1')
                    .thatCircuitHasNoZkir('test1');
            });
        });
    });

    describe('should throw proper error', () => {
        test('when circuit have pure keyword and is using ledger variable', async () => {
            const filePath = CONTRACTS_ROOT + 'example_fourteen.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

            expectCompilerResult(result).toBeFailure(
                'Exception: example_fourteen.compact line 18 char 1: circuit test1 is marked pure but is actually impure because it accesses ledger field vara at line 19 char 4',
                compilerDefaultOutput(),
            );
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
