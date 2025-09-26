import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[ADT] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/adt/tests/';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const files = fs.readdirSync(FOLDER_PATH);

    files.forEach((fileName) => {
        const filePath = path.join(FOLDER_PATH, fileName);

        test(`should be able to compile contract: '${CONTRACTS_ROOT}${fileName}'`, async () => {
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir], FOLDER_PATH);
            expectCompilerResult(result).toReturn('', '', 0);
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });
});
