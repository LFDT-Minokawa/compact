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

import { beforeAll, describe, test } from 'vitest';
import {
    Arguments,
    compile,
    copyFiles,
    createTempFolder,
    ExitCodes,
    expectCommandResult,
    expectCompilerResult,
    expectFiles,
    getFileContent,
    buildPathTo,
    logger,
} from '@';
import { execa, Result } from 'execa';
import fs from 'fs';

const RUNTIME_ROOT = buildPathTo('/', 'runtime');

function saveFile(contractDir: string, fileName: string, fileContent: string): void {
    fs.writeFile(`${contractDir}/${fileName}`, fileContent, 'utf8', (err) => {
        if (err) {
            logger.error('Error writing file:', err);
            return;
        }
        logger.info('File written successfully!');
    });
}

describe('[Runtime] Dry running contract', () => {
    const getRuntimePackage = getFileContent(RUNTIME_ROOT + '/package.json');
    const packageVersion = getRuntimePackage.match(/"version"\s*:\s*"([^"]+)"/);

    const packageJSON = {
        type: 'module',
        devDependencies: {
            '@midnight-ntwrk/compact-runtime': packageVersion?.[1],
        },
    };
    const packageJSONAsString = JSON.stringify(packageJSON);

    const npmrcFile =
        '@midnight-ntwrk:registry=https://npm.pkg.github.com\n' +
        `//npm.pkg.github.com/:_authToken=${process.env['GITHUB_TOKEN']}\n` +
        '@midnight-ntwrk:always-auth=true';

    beforeAll(async () => {
        const nixBuilt = await execa('nix', ['build', '.#compactc', '.#runtime.forPublish'], {
            cwd: '..',
            reject: false,
        });
        expectCommandResult(nixBuilt).toMatchExitCode(ExitCodes.Success);
    }, 180_000);

    test(`using - the official npm runtime`, async () => {
        const outputDir = createTempFolder();
        const contractDir = `${outputDir}/contract`;

        const result: Result = await compile([Arguments.SKIP_ZK, '../examples/counter.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', '');
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        saveFile(contractDir, 'package.json', packageJSONAsString);

        const install = await execa('npm', ['install'], { cwd: contractDir, reject: false });
        expectCommandResult(install).toMatchExitCode(0);

        const run = await execa('node', [`${contractDir}/index.js`], { reject: false });
        expectCommandResult(run).toBeSuccess('', '');
    });

    test('using - the internal github npm runtime', async () => {
        const outputDir = createTempFolder();
        const contractDir = `${outputDir}/contract`;

        const result: Result = await compile([Arguments.SKIP_ZK, '../examples/counter.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', '');
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        saveFile(contractDir, 'package.json', packageJSONAsString);
        saveFile(contractDir, '.npmrc', npmrcFile);

        const install = await execa('npm', ['install'], { cwd: contractDir, reject: false });
        expectCommandResult(install).toMatchExitCode(0);

        const run = await execa('node', [`${contractDir}/index.js`], { reject: false });
        expectCommandResult(run).toBeSuccess('', '');
    });

    test(`using - the nix built runtime`, async () => {
        const outputDir = createTempFolder(false);
        const contractDir = `${outputDir}/contract`;
        const builtLibs = `../result-1/lib/node_modules`;

        const result: Result = await compile([Arguments.SKIP_ZK, '../examples/counter.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', '');
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        saveFile(contractDir, 'package.json', packageJSONAsString);
        copyFiles(builtLibs, contractDir);

        const run = await execa('node', [`${contractDir}/index.js`], { reject: false });
        expectCommandResult(run).toBeSuccess('', '');
    });
});
