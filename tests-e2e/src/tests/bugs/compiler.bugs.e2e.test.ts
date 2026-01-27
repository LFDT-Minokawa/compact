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

import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { Project } from 'ts-morph';
import {
    Arguments,
    buildPathTo,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    ExitCodes,
    expectCompilerResult,
    expectFiles,
    getFileContent,
} from '@';

describe('[Bugs] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('bugs/');

    test.each([
        {
            testcase: '[MFG-413] should compile and not throw internal error - failed assertion',
            file: 'mfg-413.compact',
            output: {
                stderr: 'Compiling 1 circuits:',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Success,
            },
        },
        {
            testcase: '[PM-8110] should compile and not throw internal error on empty "if" branch',
            file: 'pm-8110.compact',
            output: {
                stderr: 'Compiling 1 circuits:',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Success,
            },
        },
        {
            testcase:
                '[PM-12371] should compile and not throw internal error on indirect call to a circuit that consists of an indirect chain of access to a ledger field triggers',
            file: 'pm-12371.compact',
            output: {
                stderr: 'Compiling 2 circuits:',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Success,
            },
        },
        {
            testcase: '[PM-15405] should compile and not throw internal error on broken contract',
            file: 'pm-15405.compact',
            output: {
                stderr: /Exception: pm-15405.compact line 770 char 25: mismatch between actual number 1 and declared number 2 of ADT parameters for Map/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-15733] should compile and not throw internal error on broken contract - field arithmetic semantics',
            file: 'pm-15733.compact',
            output: {
                stderr: /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 102211695604070082112571065507755096754575920209623522239390234855480569854275933742834077002685857629445612735086326265689167708028928 is out of Field range/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-15826] should compile and not throw internal error on broken contract - Field range',
            file: 'pm-15826.compact',
            output: {
                stderr: /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 102211695604070082112571065507755096754575920209623522239390234855480569854275933742834077002685857629445612735086326265689167708028928 is out of Field range/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-16040] should compile and not throw internal error on broken contract - uint field',
            file: 'pm-16040.compact',
            output: {
                stderr: /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 15125442685102050137300359908385509090776288195056543590798777853620826139411544521244637460141441024 is out of Field range/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-16059] should compile and not throw internal error on broken contract - large loop number',
            file: 'pm-16059.compact',
            output: {
                stderr: /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 43590753987470154073008687018949015693739732443847914451724382048030858970499737771427492556824041757676506525608660929336420019966319688777990144 is out of Field range/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-16447] should compile and not throw internal error on broken contract - uint field',
            file: 'pm-16447.compact',
            output: {
                stderr: /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 30192492844249640516908685114334583612755786273298882851150636427180824258272877734561395968540851470851626455240312288860686093891907031303620444665780482326050833062974334176615752685660058100658717453591143234952925588225439724612328169544114176490568667739659912772461120063716396367251917573830754350134099453129175911245731902153157960499995823247789889855333108830429635042636432286814530993977930509534957855093185234506041580262145441207168974639001160989152456378079583810445347334972539095845971835187714257166637039694233490200183768294306609311937671740481390533345298808870821472516406534880402352237199 is out of Field range/,
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-16853] should compile and not throw internal error on if switch',
            file: 'pm-16853.compact',
            output: {
                stderr: 'Compiling 2 circuits:',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Success,
            },
        },
        {
            testcase: '[PM-16999] should return an error if exported circuit name is same, just in different letter cases',
            file: 'pm-16999.compact',
            output: {
                stderr: 'Exception: pm-16999.compact line 33 char 1: the exported impure circuit name iNcrement is identical to the exported circuit name "INcrement" at line 29 char 1 modulo case; please rename to avoid zkir and prover-key filename clashes on case-insensitive filesystems',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Failure,
            },
        },
        {
            testcase: '[PM-19205] should properly compile transientCommit without disclose',
            file: 'pm-19205.compact',
            output: {
                stderr: 'Compiling 1 circuits:',
                stdout: compilerDefaultOutput(),
                exitCode: ExitCodes.Success,
            },
        },
        {
            testcase: '[PM-19287] should now properly compile instead of throwing an internal error',
            file: 'pm-19287.compact',
            output: {
                stderr: 'Compiling 11 circuits:',
                stdout: '',
                exitCode: ExitCodes.Success,
            },
        },
    ])(`$testcase`, async ({ file, output }) => {
        const filePath = CONTRACTS_ROOT + file;
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);
        expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
    });

    test(`[PM-9232] ledger camel case variables should be untouched in generated js`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-9232.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const contractIndexCjs = getFileContent(outputDir + '/contract/index.js');
        const contractIndexDCts = getFileContent(outputDir + '/contract/index.d.ts');

        // ledger variables
        ['foo_Bar', 'fOO_bAr', 'fooBar', 'fOOBAR', 'foo_bAr'].forEach((value) => {
            expect(contractIndexCjs).toContain(value);
            expect(contractIndexDCts).toContain(value);
        });

        // exported circuits
        ['iNCREment'].forEach((value) => {
            expect(contractIndexCjs).toContain(value);
            expect(contractIndexDCts).toContain(value);
        });
    });

    describe('[PM-9636]', () => {
        test.each([
            {
                testcase: 'should compile when contract includes multiple modules',
                file: 'main.compact',
                output: {
                    stderr: '',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Success,
                },
            },
            {
                testcase: 'should not compile when second binding in the same scope',
                file: 'main_scope.compact',
                output: {
                    stderr: /Exception: main_scope.compact line 29 char 1: another binding found for counter in the same scope at line 28 char 1/,
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not compile when cycle exist in dependencies tree',
                file: 'main_cycle.compact',
                output: {
                    stderr: /Exception: main_cycle.compact line 31 char 5: include cycle involving "three_cycle.compact"/,
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not compile when invalid operation is defined in submodule',
                file: 'main_invalid_function.compact',
                output: {
                    stderr: /Exception: two_invalid_function.compact line 21 char 12: operation invalid_call undefined for ledger field type Counter/,
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'include-pm-9636/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.VSCODE, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });

    test(`[PM-16065] default large vector error should be handled gracefully`, async () => {
        const filePath = CONTRACTS_ROOT + 'pm-16065.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

        expectCompilerResult(result).toBeFailure(
            /Exception: pm-16065.compact line 19 char 25: vector type length; 43590753987470154073008687018949015693739732443847; exceeds the maximum supported length 16777216/,
            compilerDefaultOutput(),
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

    test(`[PM-16150] export naming with module, should follow same pattern as camel casing`, async () => {
        const outputDir = createTempFolder();
        const contractDir = CONTRACTS_ROOT + 'pm-16150/';

        const result: Result = await compile([Arguments.SKIP_ZK, contractDir + 'pm-16150.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const project = new Project();
        const file = project.addSourceFileAtPath(contractDir + 'index.ts');

        // parse AST types from ts
        const tsEnum = file.getEnumOrThrow('AccessControl_Role');
        const memberNames = tsEnum.getMembers().map((m) => m.getName());

        // enum check
        ['Admin', 'Lp', 'Trader', 'None'].forEach((name) => {
            expect(memberNames).toContain(name);
        });

        const ledgerType = file.getTypeAliasOrThrow('Ledger');
        const ledgerMembers = ledgerType
            .getType()
            .getProperties()
            .map((m) => m.getName());

        // ledger names
        ['AccessControl_roleCommits', 'AccessControl_hashUserRole'].forEach((name) => {
            expect(ledgerMembers).toContain(name);
        });
    });

    describe('[PM-16181]', () => {
        test.each([
            {
                testcase: 'should return proper error while using ADT types with default in for loop',
                file: 'default_in_for.compact',
                output: {
                    stderr: 'Exception: default_in_for.compact line 19 char 24:\n  expected tuple element type to be an ordinary Compact type but received ADT type Map<[],\n  Boolean>',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should return proper error while using default on ADT type (Counter)',
                file: 'default_counter.compact',
                output: {
                    stderr: 'Exception: default_counter.compact line 19 char 8:\n  expected equality-operator left operand type to be an ordinary Compact type but received ADT\n  type Counter',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'pm-16181/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });

    describe('[PM-16183]', () => {
        test.each([
            {
                testcase: 'should return proper error when constructor have multiple return statements (including for loop)',
                file: 'multiple_constructor_returns.compact',
                output: {
                    stderr: 'Exception: multiple_constructor_returns.compact line 24 char 5:\n  return is not supported within for loops',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should return proper error when circuit have multiple return statements (including if)',
                file: 'multiple_circuit_returns.compact',
                output: {
                    stderr: 'Exception: multiple_circuit_returns.compact line 22 char 9:\n  unreachable statement',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'pm-16183/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });

    describe('[PM-16349]', () => {
        test.each([
            {
                testcase: 'should return proper error when using ! in pragma',
                file: 'example_one.compact',
                output: {
                    stderr: 'Exception: example_one.compact line 16 char 29:\n  parse error: found "<" looking for a version atom',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should return proper error when using !>= in pragma',
                file: 'example_two.compact',
                output: {
                    stderr: 'Exception: example_two.compact line 16 char 39:\n  parse error: found ">=" looking for a version atom',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'pm-16349/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });

    test(`[PM-16440] out of memory internal error should be handled gracefully`, async () => {
        const filePath = CONTRACTS_ROOT + 'pm-16440.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

        expectCompilerResult(result).toBeFailure(
            /Exception: pm-16440.compact line 17 char 30: MerkleTree depth 159390502094656647950333731871572319422 does not fall in 2 <= depth <= 32/,
            compilerDefaultOutput(),
        );
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });

//     test(`[PM-16603] should generate proper export names in contract-info.json`, async () => {
//         const outputDir = createTempFolder();
//         const contractDir = CONTRACTS_ROOT + 'pm-16603/';
// 
//         const result: Result = await compile([Arguments.SKIP_ZK, contractDir + 'pm-16603.compact', outputDir]);
//         expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
// 
//         const expectedContractInfo = getFileContent(contractDir + 'contract-info.json');
//         const actualContractInfo = getFileContent(outputDir + '/compiler/contract-info.json');
//         expect(actualContractInfo).toEqual(expectedContractInfo);
//     });

    describe('[PM-16893]', () => {
        test.each([
            {
                testcase: 'should compile contract without errors when for loop is iterating over empty tuple',
                file: 'example_one.compact',
                output: {
                    stderr: '',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Success,
                },
            },
            {
                testcase: 'should compile contract without errors when using map with empty tuples',
                file: 'example_two.compact',
                output: {
                    stderr: '',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Success,
                },
            },
            {
                testcase: 'should compile contract without errors when using fold with empty tuples',
                file: 'example_three.compact',
                output: {
                    stderr: '',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Success,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'pm-16893/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });

    describe('[PM-17347]', () => {
        test.each([
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (ledger variable)',
                file: 'example_one.compact',
                output: {
                    stderr: 'Exception: example_one.compact line 16 char 1:\n  parse error: found "9" looking for a program element or end of file',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (include)',
                file: 'example_two.compact',
                output: {
                    stderr: 'Exception: example_two.compact line 16 char 1:\n  parse error: found "7" looking for a program element or end of file',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (circuit name)',
                file: 'example_three.compact',
                output: {
                    stderr: 'Exception: example_three.compact line 16 char 16:\n  parse error: found "7" looking for an identifier',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (struct name)',
                file: 'example_four.compact',
                output: {
                    stderr: 'Exception: example_four.compact line 16 char 8:\n  parse error: found "7" looking for an identifier',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (import)',
                file: 'example_five.compact',
                output: {
                    stderr: 'Exception: example_five.compact line 16 char 1:\n  failed to locate file "7๓ؒNJe&.compact"',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (constant name)',
                file: 'example_six.compact',
                output: {
                    stderr: 'Exception: example_six.compact line 17 char 11:\n  parse error: found "7" looking for a const binding',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (witness name)',
                file: 'example_seven.compact',
                output: {
                    stderr: 'Exception: example_seven.compact line 16 char 9:\n  parse error: found "7" looking for an identifier',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
            {
                testcase: 'should not trigger internal error when contract contains non utf-8 characters (enum name)',
                file: 'example_eight.compact',
                output: {
                    stderr: 'Exception: example_eight.compact line 16 char 6:\n  parse error: found "9" looking for an identifier',
                    stdout: compilerDefaultOutput(),
                    exitCode: ExitCodes.Failure,
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const dirPath = CONTRACTS_ROOT + 'pm-17347/';
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, file, outputDir], dirPath);
            expectCompilerResult(result).toReturn(output.stderr, output.stdout, output.exitCode);
        });
    });
});
