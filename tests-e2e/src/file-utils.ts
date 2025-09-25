import fs from 'fs';
import { copySync, removeSync } from 'fs-extra';
import path from 'path';
import os from 'os';
import { logger } from './logger-utils';
import { globSync } from 'glob';

export const createdFolders: string[] = [];

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
        logger.error(`Error copying ${fileName}:`, copyErr);
    }
}

export function copyFiles(globPattern: string, destinationDir: string): void {
    const files = globSync(globPattern);
    files.forEach((file) => {
        copyFile(file, destinationDir);
    });
}

export function saveContract(content: string): string {
    logger.info('Saving contract');
    const contractPath = createTempFolder();
    const contractFilePath = contractPath + 'random.compact';
    fs.writeFileSync(contractFilePath, content, 'utf8');
    logger.info(`Contract saved to ${contractFilePath}`);
    return contractFilePath;
}
