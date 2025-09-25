import { compileQueue, compileWithContractName, copyFiles, createTempFolder, expectCompilerResult, expectFiles } from '..';

describe('[Composable contracts graphs] Compiler', () => {
    let contractsDir: string;

    beforeEach(() => {
        contractsDir = createTempFolder();
    });

    test('should compile - linear', async () => {
        copyFiles('../examples/composable/graph-linear/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-1', async () => {
        copyFiles('../examples/composable/graph-tree-1/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'B', 'C', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });

    test('should compile - tree-2', async () => {
        copyFiles('../examples/composable/graph-tree-2/*.compact', contractsDir);
        await compileQueue(contractsDir, ['A', 'C', 'B', 'D']);

        const returnValue = await compileWithContractName('E', contractsDir);
        expectCompilerResult(returnValue).toReturn(``, '', 0);
        expectFiles(`${contractsDir}E`).thatGeneratedJSCodeIsValid();
    });
});
