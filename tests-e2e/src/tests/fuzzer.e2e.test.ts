import { Result } from 'execa';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles, getFileContent, isRelease } from '..';
import path from 'node:path';
import fs from 'fs';
import { generate } from '../fuzzer/fuzzers.cjs';

const contractsDir: string = createTempFolder();
generate(contractsDir, process.env.NO_OF_FUZZER_TESTS || 1000);
const generatedContracts = fs.readdirSync(contractsDir);

describe.skipIf(isRelease())('[E2E] Fuzzer tests for compiler', () => {
    generatedContracts.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const contractContent = getFileContent(filePath);

        test(`should be able to compile synthetic contract: '${fileName}'`, async () => {
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);
            expectCompilerResult(result, contractContent).toNotContainSpecificError('Internal');

            if (result.exitCode == 0) {
                expectFiles(outputDir).thatGeneratedJSCodeIsValid();
            }
        });
    });
});
