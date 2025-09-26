import { Result } from 'execa';
import { Arguments, compile, copyFile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[Commas] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/commas/';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const files = fs.readdirSync(FOLDER_PATH);
    const contractsDir = createTempFolder();

    beforeAll(async () => {
        copyFile('../examples/commas/test.compact', contractsDir);

        await compile([`${contractsDir}/test.compact`, `${contractsDir}/test`]);
    });

    test(`should be able to compile contract: commas.compact which contains additional commas`, async () => {
        const result: Result = await compile([Arguments.SKIP_ZK, files[0], contractsDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
    });

    test(`should be able to compile contract: more-commas.compact which contains additional commas`, async () => {
        const result: Result = await compile([Arguments.SKIP_ZK, files[1], contractsDir], FOLDER_PATH);
        expectCompilerResult(result, contractsDir).toReturn('', '', 0);
        expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
    });
});
