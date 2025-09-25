import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import {
    Arguments,
    compile,
    compilerDefaultOutput,
    compilerManualPage,
    compilerUsageMessageHeader,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    getAllFilesRecursively,
    getCrLfFileCopy,
    saveContract,
} from '..';

describe('[Smoke] Compiler', () => {
    const HELP_REGEX = new RegExp(
        `${compilerUsageMessageHeader()} <flag> ... <source-pathname> <target-directory-pathname>\n.*--help displays detailed usage information`,
    );
    const VERSION_REGEX = /(\d+)\.(\d+).(\d+)/;

    const CONTRACT_FILE_PATH = '../test-center/compact/test.compact';
    const CONTRACT_WITH_ERRORS_FILE_PATH = '../examples/errors/multiSource.compact';

    test('should show help option', async () => {
        const result: Result = await compile([]);

        expectCompilerResult(result).toReturn(HELP_REGEX, compilerDefaultOutput(), 1);
    });

    test('should get man page', async () => {
        const result: Result = await compile([Arguments.HELP]);

        expectCompilerResult(result).toReturn('', compilerManualPage(), 0);
    });

    test('should fail on unknown', async () => {
        const result: Result = await compile(['--unknown']);

        expectCompilerResult(result).toReturn(HELP_REGEX, compilerDefaultOutput(), 1);
    });

    test('should get compiler version', async () => {
        const result: Result = await compile([Arguments.VERSION]);

        expectCompilerResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get language version', async () => {
        const result: Result = await compile([Arguments.LANGUAGE_VERSION]);

        expectCompilerResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get first argument only - version then help', async () => {
        const result: Result = await compile([Arguments.VERSION, Arguments.HELP]);

        expectCompilerResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get first argument only - help then version', async () => {
        const result: Result = await compile([Arguments.HELP, Arguments.VERSION]);

        expectCompilerResult(result).toReturn('', compilerManualPage(), 0);
    });

    test('should throw single line error with --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCompilerResult(result).toReturn(
            'Exception: multiSource.compact line 28 char 10: no compatible function named enabledPower is in scope at this call; one function is incompatible with the supplied argument types; supplied argument types: (Uint<0..0>, Field); declared argument types for function at line 19 char 1: (Boolean, Field)',
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('should throw multi line error without --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCompilerResult(result).toReturn(
            'Exception: multiSource.compact line 28 char 10:\n' +
                '  no compatible function named enabledPower is in scope at this call\n' +
                '    one function is incompatible with the supplied argument types\n' +
                '      supplied argument types:\n' +
                '        (Uint<0..0>, Field)\n' +
                '      declared argument types for function at line 19 char 1:\n' +
                '        (Boolean, Field)',
            compilerDefaultOutput(),
            255,
        );

        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('should transpile with --skip-zk', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result).toReturn('', compilerDefaultOutput(), 0);
        expectFiles(outputDir).thatFilesAreGenerated(true, false);
    });

    test('should transpile with --trace-passes', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.TRACE_PASSES, CONTRACT_FILE_PATH, outputDir]);

        expect(result.stdout).toContain('MerkleTree');
        expect(result.stdout).toContain('HistoricMerkleTree');
        expect(result.stderr).toContain('Compiling');
        expect(result.exitCode).toEqual(0);
        expectFiles(outputDir).thatFilesAreGenerated(true, true);
    });

    test('should transpile file with --skip-zk and --trace-passes', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, Arguments.TRACE_PASSES, CONTRACT_FILE_PATH, outputDir]);

        expect(result.stderr).toEqual('');
        expect(result.stdout).toContain('HistoricMerkleTree');
        // BUG: https://input-output.atlassian.net/browse/PM-8070
        expect(result.stdout).not.toContain(
            'bar: Uses around 2^11 out of 2^20 constraints (rounded up to the nearest power of two).',
        );
        expect(result.exitCode).toEqual(0);
        expectFiles(outputDir).thatFilesAreGenerated(true, false);
    });

    test('should transpile', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result).toReturn('Compiling', '', 0);
        expectFiles(outputDir).thatFilesAreGenerated(true, true);
    });

    test('should transpile file with CRLF', async () => {
        const outputDir = createTempFolder();
        const contractPath = createTempFolder();
        const crlfFilePath = getCrLfFileCopy(CONTRACT_FILE_PATH, contractPath);

        const result: Result = await compile([crlfFilePath, outputDir]);

        expectCompilerResult(result).toReturn('Compiling', '', 0);
        expectFiles(outputDir).thatFilesAreGenerated(true, true);
    });

    //BUG: https://input-output.atlassian.net/browse/PM-9531
    test('should throw error when transpiling binary', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile(['/bin/sh', outputDir]);

        expectCompilerResult(result).toReturn(
            /Exception: sh line 1 char 1:\n {2}unexpected character '.'/,
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    //BUG: https://shielded.atlassian.net/browse/PM-16582
    test('should override previous output', async () => {
        const contractText =
            'import CompactStandardLibrary;\n' +
            'export ledger c: Counter;\n' +
            'export circuit increment(amount: Uint<16>): [] {\n' +
            '  return c.increment(disclose(amount));\n' +
            '}';
        const outputDir = createTempFolder();
        const contractFilePath = saveContract(contractText);
        const contract2FilePath = saveContract(contractText.replaceAll('circuit increment(', 'circuit add('));

        const result1: Result = await compile([contractFilePath, outputDir]);
        //should be changed after fixing PM-16607
        expect(result1.stdout).toEqual(compilerDefaultOutput());
        expect(result1.exitCode).toEqual(0);

        const result2: Result = await compile([contract2FilePath, outputDir]);
        //should be changed after fixing PM-16607
        expect(result2.stdout).toEqual(compilerDefaultOutput());
        expect(result2.exitCode).toEqual(0);

        const outputFiles = getAllFilesRecursively(outputDir);
        expect(outputFiles).toContain('keys/add.verifier');
        expect(outputFiles).toContain('keys/add.prover');
        expect(outputFiles).not.toContain('keys/increment.verifier');
        expect(outputFiles).not.toContain('keys/increment.prover');
    });
});
