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

import { displayPath, getAllFilesRecursively, getFileContent } from './file-utils';
import fs from 'fs';
import path from 'node:path';
import { logger } from './logger-utils';
import * as acorn from 'acorn';
import { expect } from 'vitest';
import { ESLint } from 'eslint';
import js from '@eslint/js';
import { CompilationPaths } from './types';

export const tsFiles = [`contract/index.js`, `contract/index.js.map`, `contract/index.d.ts`];
export const zkirFiles = ['zkir/bar.zkir'];
export const keysFiles = ['keys/bar.prover', 'keys/bar.verifier', 'zkir/bar.bzkir'];
export const contractInfoFiles = ['compiler/contract-info.json', 'compiler/contract-manifest.json'];
export const allExpectedFiles = [...tsFiles, ...zkirFiles, ...keysFiles, ...contractInfoFiles];

export class AssertGeneratedFiles {
    private compilationPaths: CompilationPaths;

    expect(compilationPaths: CompilationPaths): AssertGeneratedFiles {
        if (compilationPaths.outputDir === undefined) {
            throw new Error('expectFiles: that compilation had no output directory');
        }

        this.compilationPaths = compilationPaths;
        return this;
    }

    private get context(): string {
        const { contractPath, outputDir } = this.compilationPaths;
        const output = outputDir === undefined ? '(none)' : displayPath(outputDir);

        if (contractPath === undefined) {
            return `[output: ${output}]`;
        }
        return `[contract: ${displayPath(contractPath)}] [output: ${output}]`;
    }

    private get folderPath() {
        const { outputDir } = this.compilationPaths;

        if (outputDir === undefined) {
            throw new Error('expectFiles: that compilation had no output directory');
        }

        return outputDir.endsWith('/') ? outputDir : `${outputDir}/`;
    }

    thatOnlyExpectedFilesArePresent(expectedFiles: string[] = allExpectedFiles) {
        const files = getAllFilesRecursively(this.folderPath);
        expect(files.length, `${this.context} | Files: ${files.toString()}`).toBeLessThanOrEqual(expectedFiles.length);
        expect(
            files.every((file) => expectedFiles.includes(file)),
            `${this.context} | Files found: [${files.toString()}], should match: [${expectedFiles.toString()}]`,
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
        expect(files.length, `${this.context} | Files: ${files.toString()}`).toEqual(0);
    }

    // acorn
    thatGeneratedJSCodeIsValid(valid: boolean = true) {
        const jsFile = path.resolve(this.folderPath, 'contract/index.js');
        const syntaxError = this.parseGeneratedJSCode(getFileContent(jsFile));
        const detail = syntaxError === undefined ? 'it parsed cleanly' : syntaxError;

        expect(syntaxError === undefined, `${this.context} | ${displayPath(jsFile)} -- ${detail}`).toEqual(valid);

        return this;
    }

    /** Returns the syntax error, or undefined when the code parses. */
    private parseGeneratedJSCode(code: string): string | undefined {
        try {
            acorn.parse(code, { ecmaVersion: 'latest', sourceType: 'module' });

            logger.info('No errors in generated js file');
            return undefined;
        } catch (error) {
            const message = (error as Error).message;
            logger.error(`${error instanceof SyntaxError ? 'Syntax' : 'Unknown'} error: ${message}`);
            return message;
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
        // using the recommended list of rules instead of disabling
        // lots of them based on the result of testing artifacts upon a release
        const rules = js.configs.recommended.rules;
        const eslint = new ESLint({
            overrideConfigFile: true,
            overrideConfig: {
                languageOptions: {
                    ecmaVersion: 'latest',
                    sourceType: 'module',
                },
                rules: {
                    ...rules,
                    'no-unused-vars': 'warn',
                    eqeqeq: 'warn',
                    'no-var': 'warn',
                    'no-constant-condition': 'warn',
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

export function expectFiles(paths: CompilationPaths): AssertGeneratedFiles {
    const target = paths.outputDir;
    if (target === undefined) {
        throw new Error('expectFiles: that compilation had no output directory');
    }

    logger.info(`AssertFiles: ${target}`);
    return new AssertGeneratedFiles().expect(paths);
}
