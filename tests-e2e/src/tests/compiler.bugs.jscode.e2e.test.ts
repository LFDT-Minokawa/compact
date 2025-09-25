import { Result } from 'execa';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';

describe('[Bugs][JS code] Compiler', () => {
    const CONTRACTS_ROOT = '../examples/bugs/';

    test(`[PM-16064] should generate correct index.cjs file, which can be compiled`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-16064.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });

    test(`[PM-16075] should generate correct index.cjs file, which can be compiled`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-16075.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });
});
