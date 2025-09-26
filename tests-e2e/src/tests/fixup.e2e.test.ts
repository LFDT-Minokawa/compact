import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { createTempFolder, expectCommandResult, fixup, getFileContent, isRelease } from '..';
import path from 'node:path';
import fs from 'fs';

const contractsDir = '../examples/camelCase/old';
const oracleDir = '../examples/camelCase/new';
const inputContracts = fs.readdirSync(contractsDir);

describe.skipIf(isRelease())('[E2E] Example contract tests for fixup tool', () => {
    inputContracts.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const oraclePath = path.join(oracleDir, fileName);
        const oracleContent = getFileContent(oraclePath);

        test(`should properly fix contract: '${fileName}'`, async () => {
            const outputDir = createTempFolder();
            const fixedContract = `${outputDir}/fixed.compact}`;

            const result: Result = await fixup([filePath, fixedContract]);

            expectCommandResult(result).toReturn('', '', 0);
            expect(getFileContent(fixedContract)).toEqual(oracleContent);
        });
    });
});
