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
    compilerDefaultOutput,
    compileWithContractPath,
    ContractInfo,
    copyFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    logger,
} from '@';
import fs from 'fs';

describe('[Composable contracts direct] Compiler', () => {
    const DEPENDENCY_CONTRACT_NAME = 'Calculator';

    let contractsDir: string;
    let dependencyFilePath: string;
    let dependencyFileJsonPath: string;

    beforeAll(() => {
        contractsDir = createTempFolder();
        copyFiles('../examples/composable/direct/*.compact', contractsDir);
        dependencyFilePath = contractsDir + `${DEPENDENCY_CONTRACT_NAME}.compact`;
        dependencyFileJsonPath = contractsDir + `${DEPENDENCY_CONTRACT_NAME}/compiler/contract-info.json`;
    });

    beforeEach(async () => {
        // compile before each test, because output files can be modified in test
        expectCompilerResult(
            await compileWithContractPath(dependencyFilePath, `${DEPENDENCY_CONTRACT_NAME}`, contractsDir),
        ).toCompileWithoutErrors();
    });

    test('should throw an error when dependency contract has been modified after compilation', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        const currentTime = new Date();
        fs.utimesSync(dependencyFilePath, currentTime, currentTime);
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: ${dependencyFilePath} has been modified more recently than ${dependencyFileJsonPath}; try recompiling ${dependencyFilePath}`,
            compilerDefaultOutput(),
        );
    });

    test('should compile when dependency contract contract-info.json file is malformed - add item', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        contractInfo.circuits[0].counter = 'value';
        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        logger.info(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - delete item', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractInfo: ContractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        contractInfo.circuits.splice(0, 1);
        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        logger.info(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 17 char 5: contract declaration has a circuit named get_square, but it is not present in the actual contract definition`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - empty', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{}');

        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: missing association for "contracts"; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - missing contracts', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{"circuits":[],\n"witnesses":[]}');
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: missing association for "contracts"; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - missing circuits', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{"witnesses":[],\n"contracts":[]}');
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: missing association for "circuits"; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - missing witnesses', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;

        const contractInfo: ContractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8')) as ContractInfo;
        delete (contractInfo as { witnesses?: [] }).witnesses;

        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: missing association for "witnesses"; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - circuits not vector', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{"circuits":{},\n"witnesses":[],\n"contracts":[]}');
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: "circuits" is not associated with a vector; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - change item', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractInfo: ContractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        contractInfo.circuits[0]['result-type']['type-name'] = 'MALFORMED';
        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        logger.info(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: unrecognized type-name MALFORMED; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - change item 2', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractInfo: ContractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        contractInfo.circuits[0].arguments[0].type['type-name'] = 'MALFORMED';
        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        logger.info(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: unrecognized type-name MALFORMED; try recompiling Calculator`,
            compilerDefaultOutput(),
        );
    });

    test('should compile when dependency contract contract-info.json file is malformed - change item - argument name', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractInfo: ContractInfo = JSON.parse(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        contractInfo.circuits[0].arguments[0].name = 'MALFORMED';
        fs.writeFileSync(dependencyFileJsonPath, JSON.stringify(contractInfo, null, 2));
        logger.info(fs.readFileSync(dependencyFileJsonPath, 'utf8'));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should throw an error when dependency contract contract-info.json file is removed', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.rmSync(dependencyFileJsonPath);
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: error opening ${dependencyFileJsonPath}; try (re)compiling ${dependencyFilePath}`,
            compilerDefaultOutput(),
        );
    });

    test('should compile when dependency contract has been accessed after compilation', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.utimesSync(dependencyFilePath, new Date(), new Date(new Date().getTime() - 10 * 1000));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should compile on circuit parameter', async () => {
        const mainFileName = 'Main-circuit-parameter.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeSuccess('', compilerDefaultOutput());
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should throw an error on exported circuit parameter', async () => {
        const mainFileName = 'Main-export-circuit-parameter.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 21 char 1: ` +
                'invalid type contract Calculator<get_square(Field): Field, get_cube(Field): Field> for circuit calculate_square argument 1: ' +
                'exported circuit arguments cannot include contract values',
            compilerDefaultOutput(),
        );
    });

    //  FIXME: un-skip for CC
    test.skip('should throw an error when contract is in constructor', async () => {
        const mainFileName = 'Main-constructor.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: ` + 'contract types are not yet implemented',
            compilerDefaultOutput(),
        );
    });

    //  FIXME: un-skip for CC
    test.skip('should throw an error when contract is created in constructor', async () => {
        const mainFileName = 'Main-constructor-contract-create.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 26 char 12: ` + 'invalid context for reference to contract type name Calculator',
            compilerDefaultOutput(),
        );
    });

    test('should throw an error on missing circuit in interface', async () => {
        const mainFileName = 'Main-missing-circuit.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: ` + 'contract Calculator has no circuit declaration named get_square',
            compilerDefaultOutput(),
        );
    });

    // FIXME: un-skip for CC
    test.skip('should throw an error on contract reference in ledger', async () => {
        const mainFileName = 'Main-ledger-reference.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: ` + 'contract types are not yet implemented',
            compilerDefaultOutput(),
        );
    });

    // FIXME: un-skip for CC
    test.skip('should throw an error on circuit returns contract', async () => {
        const mainFileName = 'Main-circuit-return-contract.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 16 char 1: ` + 'contract types are not yet implemented',
            compilerDefaultOutput(),
        );
    });

    test('should throw an error on export circuit returns contract', async () => {
        const mainFileName = 'Main-export-circuit-return-contract.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toBeFailure(
            `Exception: ${mainFileName} line 23 char 1: ` +
                'invalid type contract Calculator<get_square(Field): Field, get_cube(Field): Field> for circuit get_calc return value: ' +
                'exported circuit return values cannot include contract values',
            compilerDefaultOutput(),
        );
    });
});
