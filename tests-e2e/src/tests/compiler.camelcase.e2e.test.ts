import { Result } from 'execa';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[CamelCase] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/camelCase/all';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const files = fs.readdirSync(FOLDER_PATH);

    test(`should be able to compile updated ledger types and methods`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, files[0], outputDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    test(`should be able to compile updated standard types and methods`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, files[1], outputDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });
});
