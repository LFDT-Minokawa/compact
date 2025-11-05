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
    Arguments,
    compileWithContractPath,
    compile,
    ContractInfo,
    copyFiles,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    logger,
} from '..';
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

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 16 char 1: ${dependencyFilePath} has been modified more recently than ${dependencyFileJsonPath}; try recompiling ${dependencyFilePath}`,
            '',
            255,
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

        expectCompilerResult(returnValue).toReturn(``, '', 0);
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

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 17 char 5: contract declaration has a circuit named get_square, but it is not present in the actual contract definition`,
            '',
            255,
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - empty', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{}');
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: missing association for "contracts"; try recompiling Calculator`,
            '',
            255,
        );
    });

    test('should throw an error when dependency contract contract-info.json file is malformed - circuits not vector', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.writeFileSync(dependencyFileJsonPath, '{"contracts":[],"circuits":{}}');
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: "circuits" is not associated with a vector; try recompiling Calculator`,
            '',
            255,
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

        expectCompilerResult(returnValue).toReturn(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: unrecognized type-name MALFORMED; try recompiling Calculator`,
            '',
            255,
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

        expectCompilerResult(returnValue).toReturn(
            `Exception: malformed contract-info file ${dependencyFileJsonPath} for Calculator: unrecognized type-name MALFORMED; try recompiling Calculator`,
            '',
            255,
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

        expectCompilerResult(returnValue).toReturn('', '', 0);
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should throw an error when dependency contract contract-info.json file is removed', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.rmSync(dependencyFileJsonPath);
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 16 char 1: error opening ${dependencyFileJsonPath}; try (re)compiling ${dependencyFilePath}`,
            '',
            255,
        );
    });

    test('should compile when dependency contract has been accessed after compilation', async () => {
        const mainFileName = 'Main-interface.compact';
        const mainFilePath = contractsDir + mainFileName;
        fs.utimesSync(dependencyFilePath, new Date(), new Date(new Date().getTime() - 10 * 1000));
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn('', '', 0);
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    ///---

    test('should compile on circuit parameter', async () => {
        const mainFileName = 'Main-circuit-parameter.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn('', '', 0);
        expectFiles(`${contractsDir}Main`).thatGeneratedJSCodeIsValid();
    });

    test('should throw an error on exported circuit parameter', async () => {
        const mainFileName = 'Main-export-circuit-parameter.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 21 char 1: ` +
                'invalid type contract Calculator<get_square(Field): Field, get_cube(Field): Field> for circuit calculate_square argument 1: ' +
                'exported circuit arguments cannot include contract values',
            '',
            255,
        );
    });

    test('should compile when contract is in constructor', async () => {
        const mainFileName = 'Main-constructor.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);
        expectCompilerResult(returnValue, contractsDir).toCompileWithoutErrors();
    });

    test('should throw an error when contract type is used in an invalid context', async () => {
        const mainFileName = 'Main-constructor-contract-create.compact';
        const mainFilePath = contractsDir + mainFileName;
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, Arguments.VSCODE, mainFilePath, outputDir]);
        expectCompilerResult(result).toReturn(
            `Exception: ${mainFileName} line 26 char 12: ` +
                'invalid context for reference to contract type name Calculator',
            '',
            255,
        );
    });

    test('should throw an error on missing circuit in interface', async () => {
        const mainFileName = 'Main-missing-circuit.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 16 char 1: ` + 'contract Calculator has no circuit declaration named get_square',
            '',
            255,
        );
    });

    test('should compile on contract reference in ledger', async () => {
        const mainFileName = 'Main-ledger-reference.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);
        expectCompilerResult(returnValue, contractsDir).toCompileWithoutErrors();
    });

    test('should compile on circuit returns contract', async () => {
        const mainFileName = 'Main-circuit-return-contract.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);
        expectCompilerResult(returnValue, contractsDir).toCompileWithoutErrors();
    });

    test('should throw an error on export circuit returns contract', async () => {
        const mainFileName = 'Main-export-circuit-return-contract.compact';
        const mainFilePath = contractsDir + mainFileName;
        const returnValue = await compileWithContractPath(mainFilePath, 'Main', contractsDir);

        expectCompilerResult(returnValue).toReturn(
            `Exception: ${mainFileName} line 23 char 1: ` +
                'invalid type contract Calculator<get_square(Field): Field, get_cube(Field): Field> for circuit get_calc return value: ' +
                'exported circuit return values cannot include contract values',
            '',
            255,
        );
    });
});
