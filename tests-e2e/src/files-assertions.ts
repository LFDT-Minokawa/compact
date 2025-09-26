import { getAllFilesRecursively, getFileContent } from './file-utils';
import fs from 'fs';
import { logger } from './logger-utils';
import * as acorn from 'acorn';
import { expect } from 'vitest';

export const contractAndZkirFiles = ['contract/index.cjs', 'contract/index.cjs.map', 'contract/index.d.cts', 'zkir/bar.zkir'];
export const keysFiles = ['keys/bar.prover', 'keys/bar.verifier', 'zkir/bar.bzkir'];
export const contractInfoFiles = ['compiler/contract-info.json'];
export const allExpectedFiles = [...contractAndZkirFiles, ...keysFiles, ...contractInfoFiles];

export class AssertGeneratedFiles {
    private folderPath: string;

    expect(folder: string): AssertGeneratedFiles {
        this.folderPath = folder;
        return this;
    }

    thatOnlyExpectedFilesArePresent() {
        const files = getAllFilesRecursively(this.folderPath);
        expect(files.length, 'Files:' + files.toString()).toBeLessThanOrEqual(allExpectedFiles.length);
        expect(
            files.every((file) => allExpectedFiles.includes(file)),
            `Files found: [${files.toString()}], should match: [${allExpectedFiles.toString()}]`,
        ).toBeTruthy();
    }

    thatFilesAreGenerated(tsAndZkir: boolean, keys: boolean) {
        this.thatOnlyExpectedFilesArePresent();
        contractAndZkirFiles.forEach((filePath) => {
            expect(fs.existsSync(this.folderPath + filePath), this.folderPath + filePath).toBe(tsAndZkir);
        });
        keysFiles.forEach((filePath) => {
            expect(fs.existsSync(this.folderPath + filePath), this.folderPath + filePath).toBe(keys);
        });
    }

    thatNoFilesAreGenerated() {
        const files = getAllFilesRecursively(this.folderPath);
        expect(files.length, 'Files:' + files.toString()).toEqual(0);
    }

    thatGeneratedJSCodeIsValid(valid: boolean = true) {
        const actualContractInfo = getFileContent(this.folderPath + '/contract/index.cjs');
        expect(this.validateGeneratedJSCode(actualContractInfo)).toEqual(valid);
    }

    private validateGeneratedJSCode(code: string): boolean {
        try {
            acorn.parse(code, { ecmaVersion: 'latest' });

            logger.info('No errors in generated cjs file');
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
}

const assertFiles = new AssertGeneratedFiles();

export function expectFiles(folder: string): AssertGeneratedFiles {
    logger.info(`AssertFiles: ${folder}`);

    return assertFiles.expect(folder);
}
