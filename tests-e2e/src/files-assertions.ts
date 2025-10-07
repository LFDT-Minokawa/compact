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

import { getAllFilesRecursively, getFileContent } from './file-utils';
import fs from 'fs';
import { logger } from './logger-utils';
import * as acorn from 'acorn';
import { expect } from 'vitest';
import { ESLint } from 'eslint';
import js from '@eslint/js';

export const tsFiles = [`contract/index.js`, `contract/index.js.map`, `contract/index.d.ts`];
export const zkirFiles = ['zkir/bar.zkir'];
export const keysFiles = ['keys/bar.prover', 'keys/bar.verifier', 'zkir/bar.bzkir'];
export const contractInfoFiles = ['compiler/contract-info.json'];
export const allExpectedFiles = [...tsFiles, ...zkirFiles, ...keysFiles, ...contractInfoFiles];

export class AssertGeneratedFiles {
    private folderPath: string;

    expect(folder: string): AssertGeneratedFiles {
        this.folderPath = folder;
        return this;
    }

    thatOnlyExpectedFilesArePresent(expectedFiles: string[] = allExpectedFiles) {
        const files = getAllFilesRecursively(this.folderPath);
        expect(files.length, 'Files:' + files.toString()).toBeLessThanOrEqual(expectedFiles.length);
        expect(
            files.every((file) => expectedFiles.includes(file)),
            `Files found: [${files.toString()}], should match: [${expectedFiles.toString()}]`,
        ).toBeTruthy();
    }

    thatFilesAreGenerated(tsFiles: string[], zkirFiles: string[], keysFiles: string[], contractInfoFiles: string[]) {
        this.thatOnlyExpectedFilesArePresent([...tsFiles, ...zkirFiles, ...keysFiles, ...contractInfoFiles]);

        [...tsFiles, ...zkirFiles, ...keysFiles, ...contractInfoFiles].forEach((filePath) => {
            expect(fs.existsSync(this.folderPath + filePath), this.folderPath + filePath).toBe(true);
        });
    }

    thatNoFilesAreGenerated() {
        const files = getAllFilesRecursively(this.folderPath);
        expect(files.length, 'Files:' + files.toString()).toEqual(0);
    }

    // acorn
    thatGeneratedJSCodeIsValid(valid: boolean = true) {
        const actualContractInfo = getFileContent(this.folderPath + '/contract/index.js');
        expect(this.validateGeneratedJSCode(actualContractInfo)).toEqual(valid);

        return this;
    }

    private validateGeneratedJSCode(code: string): boolean {
        try {
            acorn.parse(code, { ecmaVersion: 'latest', sourceType: 'module' });

            logger.info('No errors in generated js file');
            return true;
        } catch (error) {
            if (error instanceof SyntaxError) {
                logger.error(`Syntax error: ${error.message}`);
            } else {
                logger.error(`Unknown error: ${(error as Error).message}`);
            }
            return false;
        }
    }

    // eslint
    async thatGeneratedJSCodeIsLinted(): Promise<void> {
        const actualContractInfo = getFileContent(this.folderPath + '/contract/index.js');
        const lintResult = await this.lintGeneratedJSCode(actualContractInfo);

        expect(lintResult[0]).toBeDefined();
    }

    private async lintGeneratedJSCode(code: string): Promise<ESLint.LintResult[]> {
        // Full list: https://eslint.org/docs/latest/rules
        const rules = js.configs.all.rules;
        const eslint = new ESLint({
            overrideConfigFile: true,
            overrideConfig: {
                languageOptions: {
                    ecmaVersion: 'latest',
                    sourceType: 'module',
                },
                rules: {
                    ...rules,
                    camelcase: 'off',
                    'class-methods-use-this': 'off',
                    curly: 'off',
                    eqeqeq: 'warn',
                    'id-length': 'off',
                    'max-classes-per-file': 'off',
                    'max-lines': 'off',
                    'max-lines-per-function': 'off',
                    'no-magic-numbers': 'off',
                    'no-underscore-dangle': 'off',
                    'no-var': 'warn',
                    'one-var': 'off',
                    'sort-keys': 'off',
                    radix: 'off',
                    'vars-on-top': 'off',
                },
            },
        });

        const results = await eslint.lintText(code);
        const formatter = await eslint.loadFormatter('stylish');
        const resultText = await formatter.format(results);

        logger.info(resultText);
        return results;
    }
}

const assertFiles = new AssertGeneratedFiles();

export function expectFiles(folder: string): AssertGeneratedFiles {
    logger.info(`AssertFiles: ${folder}`);

    return assertFiles.expect(folder);
}
