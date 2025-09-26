import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[Std] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/std_lib/import';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const contractsDir = createTempFolder();

    test.each([
        {
            output: {
                stderr: 'Exception: test_import_csl_quotes.compact line 1 char 1:\n  failed to locate file \"CompactStandardLibrary.compact\"',
                stdout: '',
                exitCode: 255,
            },
            file: 'test_import_csl_quotes.compact',
        },
        {
            output: {
                stderr: 'Exception: test_import_std.compact line 1 char 1:\n  failed to locate file \"std.compact\"',
                stdout: '',
                exitCode: 255,
            },
            file: 'test_import_std.compact',
        },
        {
            output: {
                stderr: 'Exception: test_include_std.compact line 1 char 1:\n  failed to locate file \"std.compact\": possibly replace include with import CompactStandardLibrary',
                stdout: '',
                exitCode: 255,
            },
            file: 'test_include_std.compact',
        },
    ])(`should not be able to compile contract with invalid standard library: $file`, async ({ output, file }) => {
        const result: Result = await compile([Arguments.SKIP_ZK, file, contractsDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
    });

    test(`should be able to compile contract with valid standard library: test_import_csl.compact`, async () => {
        const filePath = path.join(FOLDER_PATH, 'test_import_csl.compact');

        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
    });
});
