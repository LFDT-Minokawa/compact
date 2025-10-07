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
    compileQueueWithFailures,
    compilerDefaultOutput,
    compileWithContractName,
    contractInfoFiles,
    copyFiles,
    createTempFolder,
    ExitCodes,
    expectCompilerResult,
    expectFiles,
    tsFiles,
} from '@';
import { describe } from 'vitest';

describe('[Composable contracts] Compiler', () => {
    let contractsDir: string;

    beforeEach(() => {
        contractsDir = createTempFolder();
    });

    describe('should not compile main contract', () => {
        test('when you call dependent contract method from vector in main contract constructor', async () => {
            copyFiles('../examples/composable/cases/call-from-vector/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 25 char 1:\n  constructor cannot call external contracts but calls circuit up from external contract A at line\n  27 char 7`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when contracts have circular reference - A is main', async () => {
            copyFiles('../examples/composable/cases/circular-reference/*.compact', contractsDir);

            const returnValue = await compileWithContractName('A', contractsDir, true);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: A.compact line 22 char 1: error opening ${contractsDir}B/compiler/contract-info.json; try (re)compiling ${contractsDir}B.compact`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}A`).thatNoFilesAreGenerated();
        });

        test('when contracts have circular reference - B is main', async () => {
            copyFiles('../examples/composable/cases/circular-reference/*.compact', contractsDir);

            const returnValue = await compileWithContractName('B', contractsDir, true);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: B.compact line 22 char 1: error opening ${contractsDir}A/compiler/contract-info.json; try (re)compiling ${contractsDir}A.compact`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}B`).thatNoFilesAreGenerated();
        });

        test('when you use dependent contract as variable in main contract constructor', async () => {
            copyFiles('../examples/composable/cases/contract-as-variable/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 26 char 13:\n  invalid context for reference to contract type name A`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when you define dependent contract in main contract circuit', async () => {
            copyFiles('../examples/composable/cases/contract-in-circuit/*.compact', contractsDir);
            await compileQueue(contractsDir, ['AB']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 20 char 28:\n  parse error: found "{" looking for ":"`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when you define dependent contract in main contract constructor', async () => {
            copyFiles('../examples/composable/cases/contract-in-constructor/*.compact', contractsDir);
            await compileQueue(contractsDir, ['AB']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 22 char 3:\n  parse error: found "contract" looking for a statement or "}"`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when it has duplicated dependent contract definition', async () => {
            copyFiles('../examples/composable/cases/duplicated-contract/*.compact', contractsDir);
            await compileQueue(contractsDir, ['AB']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 25 char 1:\n  another binding found for AB in the same scope at line 20 char 1`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when you try to export dependent contract as ledger value in dependent contract definition', async () => {
            copyFiles('../examples/composable/cases/export-in-definition/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 21 char 3:\n  parse error: found "export" looking for an external contract circuit or "}"`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract circuit definition has invalid parameters', async () => {
            copyFiles('../examples/composable/cases/invalid-definition/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 21 char 3:\n  contract declaration claims the type of circuit up argument 1 is Field, but in the actual\n  contract definition it is Uint<16>`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract circuit definition has invalid return types', async () => {
            copyFiles('../examples/composable/cases/invalid-definition-return/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 21 char 3:\n  contract declaration claims the return type of circuit up is Boolean, but in the actual contract\n  definition it is []`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract compilation order is invalid', async () => {
            copyFiles('../examples/composable/cases/invalid-order/*.compact', contractsDir);

            await compileQueueWithFailures(
                contractsDir,
                ['A', 'C', 'B'],
                [
                    {
                        stderr: `Exception: C.compact line 22 char 1: error opening ${contractsDir}B/compiler/contract-info.json; try (re)compiling ${contractsDir}B.compact`,
                        stdout: compilerDefaultOutput(),
                        exitCode: ExitCodes.Failure,
                        contract: 'C',
                    },
                ],
                true,
            );
        });

        // FIXME: un-skip for CC
        test.skip('when dependent contract is used as ledger ADT value', async () => {
            copyFiles('../examples/composable/cases/ledger-adt-type/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 20 char 1:\n  contract types are not yet implemented`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when you define dependent contract in module', async () => {
            copyFiles('../examples/composable/cases/module-contract/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 29 char 26:\n  unbound identifier $A`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when you try to use dependent contract without contract definition', async () => {
            copyFiles('../examples/composable/cases/no-defined-contract/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 20 char 26:\n  unbound identifier A`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract definition has additional (non-existing) circuit added', async () => {
            copyFiles('../examples/composable/cases/non-existing-circuit/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 23 char 5:\n  contract declaration has a circuit named middle, but it is not present in the actual contract\n  definition`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract does not exist (and it is not compiled)', async () => {
            copyFiles('../examples/composable/cases/non-existing-contract-impl/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A', 'B']);

            const returnValue = await compileWithContractName('main', contractsDir, true);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 30 char 1: error opening ${contractsDir}C/compiler/contract-info.json; try (re)compiling ${contractsDir}C.compact`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract definition has just non-existing circuit', async () => {
            copyFiles('../examples/composable/cases/non-existing-definition/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 21 char 3:\n  contract declaration has a circuit named bobAnderson, but it is not present in the actual\n  contract definition`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract definition has non-exported circuit', async () => {
            copyFiles('../examples/composable/cases/not-exported-circuit/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 21 char 5:\n  contract declaration has a circuit named up, but it is not present in the actual contract\n  definition`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });

        test('when dependent contract is used as witness return value', async () => {
            copyFiles('../examples/composable/cases/witness-return/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeFailure(
                `Exception: main.compact line 25 char 1:\n  invalid type contract A<up(Uint<16>): [], down(Uint<16>): []> for witness bob return value:\n  witness return values cannot include contract values`,
                compilerDefaultOutput(),
            );
            expectFiles(`${contractsDir}main`).thatNoFilesAreGenerated();
        });
    });

    describe('should compile main contract', () => {
        test('when dependent contract is empty', async () => {
            copyFiles('../examples/composable/cases/empty-contract/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
            expectFiles(`${contractsDir}main/`).thatFilesAreGenerated(tsFiles, [], [], contractInfoFiles);
        });

        test('when dependent contract definition is missing exported circuit', async () => {
            copyFiles('../examples/composable/cases/missing-definition-circuit/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A', 'B']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
            expectFiles(`${contractsDir}main/`).thatFilesAreGenerated(tsFiles, [], [], contractInfoFiles);
        });

        test('when dependent contract is used as witness parameter', async () => {
            copyFiles('../examples/composable/cases/witness-param/*.compact', contractsDir);
            await compileQueue(contractsDir, ['A']);

            const returnValue = await compileWithContractName('main', contractsDir);
            expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
            expectFiles(`${contractsDir}main/`).thatFilesAreGenerated(tsFiles, [], [], contractInfoFiles);
        });
    });
});
