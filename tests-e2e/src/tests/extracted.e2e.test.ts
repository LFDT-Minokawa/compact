import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles, getFileContent, isRelease } from '..';
import path from 'node:path';
import { extractAndSaveContracts } from '../parser';

const contractsDir: string = createTempFolder();
const extractedFiles: string[] = extractAndSaveContracts(contractsDir);

describe.skipIf(isRelease())('[E2E] Extracted unit tests for compiler', () => {
    extractedFiles.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const contractContent = getFileContent(filePath);

        test(`should be able to compile extracted contract: '${contractsDir}${fileName}'`, async () => {
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir], contractsDir);
            expectCompilerResult(result).toNotContainSpecificError('Internal');

            if (result.exitCode == 0) {
                if (contractContent.includes('if (b()) S { w(), w() }') || contractContent.includes('if (b) S { w(), w() };')) {
                    expectFiles(outputDir).thatGeneratedJSCodeIsValid(false);
                } else {
                    expectFiles(outputDir).thatGeneratedJSCodeIsValid();
                }
            }
        });
    });
});
