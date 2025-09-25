import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { createTempFolder, expectCommandResult, format, getFileContent, isRelease } from '..';
import path from 'node:path';
import fs from 'fs';

const contractsDir = '../examples/formatter/input';
const oracleDir = '../examples/formatter/output';
const inputContracts = fs.readdirSync(contractsDir);

describe.skipIf(isRelease())('[E2E] Example contract tests for formatter tool', () => {
    inputContracts.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const oraclePath = path.join(oracleDir, fileName);
        const oracleContent = getFileContent(oraclePath);

        test(`should properly format contract: '${fileName}'`, async () => {
            const outputDir = createTempFolder();
            const formattedContract = `${outputDir}/formatted.compact}`;

            const result: Result = await format([filePath, formattedContract]);

            expectCommandResult(result).toReturn('', '', 0);
            expect(getFileContent(formattedContract)).toEqual(oracleContent);
        });
    });
});
