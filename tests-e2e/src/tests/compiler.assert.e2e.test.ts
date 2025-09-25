import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[Assert] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/assert/';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const readFiles = fs.readdirSync(FOLDER_PATH, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    filesNames.forEach((fileName) => {
        const filePath = path.join(FOLDER_PATH, fileName);

        test(`should be able to compile contract with new assert expression syntax: ${fileName}`, async () => {
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
            expectCompilerResult(result).toReturn('', '', 0);
            expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
        });
    });

    test(`should not be able to compile contract with assert statement syntax: old_assert.compact`, async () => {
        const filePath = path.join(FOLDER_PATH, 'negative', 'old_assert.compact');

        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn(
            'Exception: old_assert.compact line 6 char 10:\n  parse error: found "1" looking for "("',
            '',
            255,
        );
    });
});
