import { describe, test } from 'vitest';
import { compile, compileWithContractName, copyFiles, createTempFolder, expectCompilerResult, expectFiles } from '..';
import fs from 'fs';

describe('[Composable contracts dependency graph] Compiler', () => {
    let contractsDir: string;

    beforeAll(() => {
        contractsDir = createTempFolder();
        copyFiles('../examples/composable/graph/*.compact', contractsDir);
    });

    test('should compile when A and B are referenced in MAIN', async () => {
        expectCompilerResult(await compileWithContractName('A', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('B', contractsDir)).toCompileWithoutErrors();

        const returnValue = await compileWithContractName('Main-A-and-B', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}Main-A-and-B`).thatGeneratedJSCodeIsValid();
    });

    test('should compile when A is referenced in C, B and C are referenced in MAIN', async () => {
        expectCompilerResult(await compileWithContractName('A', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('B', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('C', contractsDir)).toCompileWithoutErrors();

        const returnValue = await compileWithContractName('Main-B-and-C-on-A', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}Main-B-and-C-on-A`).thatGeneratedJSCodeIsValid();
    });

    test('should fail when A is referenced in C, B and C are referenced in MAIN and A is deleted', async () => {
        expectCompilerResult(await compileWithContractName('B', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('A', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('C', contractsDir)).toCompileWithoutErrors();
        fs.rmSync(`${contractsDir} + A`, { recursive: true, force: true });

        const returnValue = await compileWithContractName('Main-B-and-C-on-A', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}Main-B-and-C-on-A`).thatGeneratedJSCodeIsValid();
    });

    test('should fail when A and B are referenced in MAIN, and MAIN is compiled to output directory A', async () => {
        expectCompilerResult(await compileWithContractName('B', contractsDir)).toCompileWithoutErrors();
        expectCompilerResult(await compileWithContractName('A', contractsDir)).toCompileWithoutErrors();

        const returnValueMain = await compile([contractsDir + 'Main-A-and-B.compact', contractsDir + 'A']);
        expectCompilerResult(returnValueMain).toReturn(``, '', 0);
        expectFiles(`${contractsDir}Main-A-and-B`).thatGeneratedJSCodeIsValid();
    });
});
