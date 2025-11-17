// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { execa, Result } from 'execa';
import { describe, expect, test } from 'vitest';
import {
    Arguments,
    AssertOptions,
    compile,
    compilerDefaultOutput,
    compilerManualPage,
    contractInfoFiles,
    createTempFolder,
    ExitCodes,
    expectCompilerResult,
    expectFiles,
    getAllFilesRecursively,
    getCompactcBinary,
    getCrLfFileCopy,
    buildPathTo,
    HELP_REGEX,
    isRelease,
    keysFiles,
    saveContract,
    tsFiles,
    VERSION_REGEX,
    zkirFiles,
} from '@';

describe('[Smoke] Compiler', () => {
    const CONTRACT_FILE_PATH = buildPathTo('/compact/test.compact', 'test-center');
    const CONTRACT_WITH_ERRORS_FILE_PATH = buildPathTo('/errors/multiSource.compact');

    const ignoreOutput: AssertOptions = {
        contract: '',
        ignoreStdErr: false,
        ignoreStdOut: true,
    };

    test('should show help option', async () => {
        const result: Result = await compile([]);

        expectCompilerResult(result).toBeError(HELP_REGEX, compilerDefaultOutput());
    });

    test('should get man page', async () => {
        const result: Result = await compile([Arguments.HELP]);

        expectCompilerResult(result).toBeSuccess('', compilerManualPage());
    });

    test('should fail on unknown', async () => {
        const result: Result = await compile(['--unknown']);

        expectCompilerResult(result).toBeError(HELP_REGEX, compilerDefaultOutput());
    });

    test('should get compiler version', async () => {
        const result: Result = await compile([Arguments.VERSION]);

        expectCompilerResult(result).toBeSuccess('', VERSION_REGEX);
    });

    test('should get language version', async () => {
        const result: Result = await compile([Arguments.LANGUAGE_VERSION]);

        expectCompilerResult(result).toBeSuccess('', VERSION_REGEX);
    });

    test('should get first argument only - version then help', async () => {
        const result: Result = await compile([Arguments.VERSION, Arguments.HELP]);

        expectCompilerResult(result).toBeSuccess('', VERSION_REGEX);
    });

    test('should get first argument only - help then version', async () => {
        const result: Result = await compile([Arguments.HELP, Arguments.VERSION]);

        expectCompilerResult(result).toBeSuccess('', compilerManualPage());
    });

    test('should throw single line error with --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCompilerResult(result).toBeFailure(
            'Exception: multiSource.compact line 28 char 10: no compatible function named enabledPower is in scope at this call; one function is incompatible with the supplied argument types; supplied argument types: (Uint<0..1>, Field); declared argument types for function at line 19 char 1: (Boolean, Field)',
            compilerDefaultOutput(),
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

    test('should throw multi line error without --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCompilerResult(result).toBeFailure(
            'Exception: multiSource.compact line 28 char 10:\n' +
                '  no compatible function named enabledPower is in scope at this call\n' +
                '    one function is incompatible with the supplied argument types\n' +
                '      supplied argument types:\n' +
                '        (Uint<0..1>, Field)\n' +
                '      declared argument types for function at line 19 char 1:\n' +
                '        (Boolean, Field)',
            compilerDefaultOutput(),
        );

        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

    test('should transpile with --skip-zk', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatFilesAreGenerated(tsFiles, zkirFiles, [], contractInfoFiles);
    });

    test('should transpile with --trace-passes', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.TRACE_PASSES, CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result, ignoreOutput)
            .stdOutToContain(['MerkleTree', 'HistoricMerkleTree'])
            .stdErrToContain(['Compiling'])
            .toMatchExitCode(ExitCodes.Success);
        expectFiles(outputDir).thatFilesAreGenerated(tsFiles, zkirFiles, keysFiles, contractInfoFiles);
    });

    test('should transpile file with --skip-zk and --trace-passes', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, Arguments.TRACE_PASSES, CONTRACT_FILE_PATH, outputDir]);

        // BUG: https://input-output.atlassian.net/browse/PM-8070
        expectCompilerResult(result, ignoreOutput)
            .toMatchStdError('')
            .stdOutToContain(['HistoricMerkleTree'])
            .stdOutToNotContain(['bar: Uses around 2^11 out of 2^20 constraints (rounded up to the nearest power of two).'])
            .toMatchExitCode(ExitCodes.Success);

        expectFiles(outputDir).thatFilesAreGenerated(tsFiles, zkirFiles, [], contractInfoFiles);
    });

    test('should transpile', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile([CONTRACT_FILE_PATH, outputDir]);

        expectCompilerResult(result).toBeSuccess('Compiling 1 circuits:', compilerDefaultOutput());
        expectFiles(outputDir).thatFilesAreGenerated(tsFiles, zkirFiles, keysFiles, contractInfoFiles);
    });

    test('should transpile file with CRLF', async () => {
        const outputDir = createTempFolder();
        const contractPath = createTempFolder();
        const crlfFilePath = getCrLfFileCopy(CONTRACT_FILE_PATH, contractPath);

        const result: Result = await compile([crlfFilePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('Compiling 1 circuits:', compilerDefaultOutput());
        expectFiles(outputDir).thatFilesAreGenerated(tsFiles, zkirFiles, keysFiles, contractInfoFiles);
    });

    //BUG: https://input-output.atlassian.net/browse/PM-9531
    test('should throw error when transpiling binary', async () => {
        const outputDir = createTempFolder();
        const result: Result = await compile(['/bin/sh', outputDir]);

        expectCompilerResult(result).toBeFailure(
            /Exception: sh line 1 char 1:\n {2}unexpected character '.'/,
            compilerDefaultOutput(),
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
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

        //should be changed after fixing PM-16607
        const result1: Result = await compile([contractFilePath, outputDir]);
        expectCompilerResult(result1).toMatchStdOut(compilerDefaultOutput()).toMatchExitCode(ExitCodes.Success);

        //should be changed after fixing PM-16607
        const result2: Result = await compile([contract2FilePath, outputDir]);
        expectCompilerResult(result2).toMatchStdOut(compilerDefaultOutput()).toMatchExitCode(ExitCodes.Success);

        const outputFiles = getAllFilesRecursively(outputDir);
        expect(outputFiles).toContain('keys/add.verifier');
        expect(outputFiles).toContain('keys/add.prover');
        expect(outputFiles).not.toContain('keys/increment.verifier');
        expect(outputFiles).not.toContain('keys/increment.prover');
    });

    test.runIf(!isRelease())('should throw error when zkir is not available', async () => {
        const outputDir = createTempFolder();

        const result = await execa(getCompactcBinary(), [CONTRACT_FILE_PATH, outputDir], {
            env: { COMPACT_HOME: 'non_existing_path' },
            reject: false,
            extendEnv: false,
        });
        expectCompilerResult(result)
            .toMatchStdOut(compilerDefaultOutput())
            .toMatchStdError('Warning: ZKIR not found; skipping final circuit compilation.')
            .toMatchExitCode(ExitCodes.Success);
    });
});
