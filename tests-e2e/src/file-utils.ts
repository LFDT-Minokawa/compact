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

import fs from 'fs';
import { copySync, removeSync } from 'fs-extra';
import path from 'path';
import os from 'os';
import { logger } from './logger-utils';
import { globSync } from 'glob';
import { fileURLToPath } from 'node:url';

export const createdFolders: string[] = [];

/*
 * Build path to examples (by default). As this folder is in src, the path should be easier to get.
 */
export function buildPathTo(fileOrFolder: string, baseFolder: string = 'examples'): string {
    const currentDir = path.dirname(fileURLToPath(import.meta.url));
    const examplesDir = path.resolve(currentDir, '..', '..');

    return path.join(examplesDir, baseFolder, fileOrFolder);
}

/*
 * Create and remove temp folders
 */
export function createTempFolder(addForCleanup: boolean = true): string {
    const tempPath = fs.mkdtempSync(path.join(fs.realpathSync(os.tmpdir()), 'temp-test-')) + '/';
    logger.info(`Creating temp folder: ${tempPath}`);
    if (addForCleanup) createdFolders.push(tempPath);
    return tempPath;
}

export function removeFolder(folder: string): void {
    logger.info(`Cleaning folder: ${folder}`);
    const path: fs.PathLike = folder;

    try {
        logger.info(`Deleting: ${path}`);
        removeSync(path);
    } catch (err) {
        logger.error(err);
    }
}

export function cleanupTempFolders(): void {
    logger.info(`Cleaning up temp folders`);
    createdFolders.forEach((folder) => {
        chmodRecursively(folder, '777');
        removeFolder(folder);
    });
}

export function chmodRecursively(folder: string, mode: string): void {
    const stats = fs.lstatSync(folder);
    fs.chmodSync(folder, mode);

    if (stats.isDirectory()) {
        const entries = fs.readdirSync(folder);
        for (const entry of entries) {
            const filePath = path.join(folder, entry);
            chmodRecursively(filePath, mode);
        }
    }
}

/*
 * Get directory list and file content
 */
export function getAllFilesRecursively(folderPath: string): string[] {
    logger.info(`Listing files in directory: ${folderPath}`);
    const paths: string[] = globSync(`${folderPath}/**/*`, { nodir: true, absolute: true });
    return paths.map((path) => path.replace(folderPath, ''));
}

export function getFileContent(file: string): string {
    return fs.readFileSync(file, 'utf-8');
}

/*
 * Copy file or files
 */
export function getCrLfFileCopy(CONTRACT_FILE_PATH: string, tempPath: string) {
    const content = fs.readFileSync(CONTRACT_FILE_PATH, 'utf8');
    const crlfContent = content.replaceAll(/\n/g, '\r\n');
    const crlfFilePath = tempPath + 'crlf-contract.compact';
    fs.writeFileSync(crlfFilePath, crlfContent, 'utf8');
    const emptyFilePath = tempPath + 'empty.compact';
    fs.writeFileSync(emptyFilePath, '', 'utf8');
    return crlfFilePath;
}

export function copyFile(testContract: string, contractsDir: string): void {
    const fileName = path.basename(testContract);
    const destPath = path.join(contractsDir, fileName);

    try {
        copySync(testContract, destPath);
        logger.info(`${fileName} was copied to ${contractsDir}`);
    } catch (copyErr) {
        logger.error(copyErr, `Error copying ${fileName}:`);
    }
}

export function copyFiles(globPattern: string, destinationDir: string): void {
    const files = globSync(globPattern);
    files.forEach((file) => {
        copyFile(file, destinationDir);
    });
}

/*
 * Save contract for generative tests.
 */
export function saveContract(content: string): string {
    logger.info('Saving contract');
    const contractPath = createTempFolder();
    const contractFilePath = contractPath + 'random.compact';
    fs.writeFileSync(contractFilePath, content, 'utf8');
    logger.info(`Contract saved to ${contractFilePath}`);
    return contractFilePath;
}
