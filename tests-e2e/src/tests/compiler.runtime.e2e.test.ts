import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles, getFileContent } from '..';

const CONTRACTS_ROOT = '../examples/';
const RUNTIME_ROOT = '../runtime/';

describe('[Runtime] Compiler', () => {
    test(`generated contract should use latest version of runtime`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'counter.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const getRuntimePackage = getFileContent(RUNTIME_ROOT + '/package.json');
        const packageVersion = getRuntimePackage.match(/"version"\s*:\s*"([^"]+)"/);

        const actualContract = getFileContent(outputDir + '/contract/index.cjs');
        const contractVersion = actualContract.match(/expectedRuntimeVersionString\s*=\s*'([^']+)'/);

        expect(contractVersion?.[1]).toEqual(packageVersion?.[1]);
    });
});
