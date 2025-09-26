import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const CONTRACTS_ROOT = '../../../examples/adt/exports/';
const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

const files = await fs.promises.readdir(FOLDER_PATH, { recursive: false, withFileTypes: true });

describe('[ADT Exports] Compiler', () => {
    files
        .filter((dirent) => dirent.isFile())
        .map((dirent) => `${dirent.parentPath}${dirent.name}`)
        .forEach((fileName) => {
            test(`should be able to compile contract: '${fileName}'`, async () => {
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], FOLDER_PATH);
                expectCompilerResult(result).toReturn('', '', 0);
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();
            });
        });
});
