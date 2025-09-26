import { Result } from 'execa';
import { describe, expect, test } from 'vitest';
import { Project } from 'ts-morph';
import { Arguments, compile, createTempFolder, expectCompilerResult, expectFiles, getFileContent } from '..';

describe('[Bugs] Compiler', () => {
    const CONTRACTS_ROOT = '../examples/bugs/';

    test.each([
        ['[MFG-413] should compile and not throw internal error - failed assertion', 'mfg-413.compact', '', '', 0],
        ['[PM-8110] should compile and not throw internal error on empty "if" branch', 'pm-8110.compact', '', '', 0],
        [
            '[PM-12371] should compile and not throw internal error on indirect call to a circuit that consists of an indirect chain of access to a ledger field triggers',
            'pm-12371.compact',
            '',
            '',
            0,
        ],
        [
            '[PM-15405] should compile and not throw internal error on broken contract',
            'pm-15405.compact',
            /Exception: pm-15405.compact line 770 char 25: mismatch between actual number 1 and declared number 2 of ADT parameters for Map/,
            '',
            255,
        ],
        [
            '[PM-15733] should compile and not throw internal error on broken contract - field arithmetic semantics',
            'pm-15733.compact',
            /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 102211695604070082112571065507755096754575920209623522239390234855480569854275933742834077002685857629445612735086326265689167708028928 is out of Field range/,
            '',
            255,
        ],
        [
            '[PM-15826] should compile and not throw internal error on broken contract - Field range',
            'pm-15826.compact',
            /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 102211695604070082112571065507755096754575920209623522239390234855480569854275933742834077002685857629445612735086326265689167708028928 is out of Field range/,
            '',
            255,
        ],
        [
            '[PM-16040] should compile and not throw internal error on broken contract - uint field',
            'pm-16040.compact',
            /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 15125442685102050137300359908385509090776288195056543590798777853620826139411544521244637460141441024 is out of Field range/,
            '',
            255,
        ],
        [
            '[PM-16059] should compile and not throw internal error on broken contract - large loop number',
            'pm-16059.compact',
            /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 43590753987470154073008687018949015693739732443847914451724382048030858970499737771427492556824041757676506525608660929336420019966319688777990144 is out of Field range/,
            '',
            255,
        ],
        [
            '[PM-16447] should compile and not throw internal error on broken contract - uint field',
            'pm-16447.compact',
            /Exception: (?<file>.+) line (?<line>\d+) char (?<char>\d+): 30192492844249640516908685114334583612755786273298882851150636427180824258272877734561395968540851470851626455240312288860686093891907031303620444665780482326050833062974334176615752685660058100658717453591143234952925588225439724612328169544114176490568667739659912772461120063716396367251917573830754350134099453129175911245731902153157960499995823247789889855333108830429635042636432286814530993977930509534957855093185234506041580262145441207168974639001160989152456378079583810445347334972539095845971835187714257166637039694233490200183768294306609311937671740481390533345298808870821472516406534880402352237199 is out of Field range/,
            '',
            255,
        ],
        ['[PM-16853] should compile and not throw internal error on if switch', 'pm-16853.compact', '', '', 0],
        [
            '[PM-16999] should return an error if exported circuit name is same, just in different letter cases',
            'pm-16999.compact',
            'Exception: pm-16999.compact line 18 char 1: the exported impure circuit name iNcrement is identical to the exported circuit name "increment" at line 10 char 1 modulo case; please rename to avoid zkir and prover-key filename clashes on case-insensitive filesystems',
            '',
            255,
        ],
    ])('%s (file: %s)', async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
        const filePath = CONTRACTS_ROOT + fileName;
        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);
        expectCompilerResult(result).toReturn(error, output, exitCode);
    });

    test(`[PM-9232] ledger camel case variables should be untouched in generated cjs`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-9232.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        const contractIndexCjs = getFileContent(outputDir + '/contract/index.cjs');
        const contractIndexDCts = getFileContent(outputDir + '/contract/index.d.cts');

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
            ['should compile when contract includes multiple modules', 'main.compact', '', '', 0],
            [
                'should not compile when second binding in the same scope',
                'main_scope.compact',
                /Exception: main_scope.compact line 29 char 1: another binding found for counter in the same scope at line 28 char 1/,
                '',
                255,
            ],
            [
                'should not compile when cycle exist in dependencies tree',
                'main_cycle.compact',
                /Exception: main_cycle.compact line 31 char 5: include cycle involving "three_cycle.compact"/,
                '',
                255,
            ],
            [
                'should not compile when invalid operation is defined in submodule',
                'main_invalid_function.compact',
                /Exception: two_invalid_function.compact line 21 char 12: operation invalid_call undefined for ledger field type Counter/,
                '',
                255,
            ],
        ])(
            '%s (file: %s)',
            async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
                const dirPath = CONTRACTS_ROOT + 'include-pm-9636/';
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.VSCODE, fileName, outputDir], dirPath);
                expectCompilerResult(result).toReturn(error, output, exitCode);
            },
        );
    });

    test(`[PM-16150] export naming with module, should follow same pattern as camel casing`, async () => {
        const outputDir = createTempFolder();
        const contractDir = CONTRACTS_ROOT + 'pm-16150/';

        const result: Result = await compile([Arguments.SKIP_ZK, contractDir + 'pm-16150.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);
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
            [
                'should return proper error while using ADT types with default in for loop',
                'default_in_for.compact',
                'Exception: default_in_for.compact line 4 char 23:\n  expected tuple element 1 type to be an ordinary Compact type but received ADT type Map<[],\n  Boolean>',
                '',
                255,
            ],
            [
                'should return proper error while using default on ADT type (Counter)',
                'default_counter.compact',
                'Exception: default_counter.compact line 4 char 8:\n  expected equality-operator left operand type to be an ordinary Compact type but received ADT\n  type Counter',
                '',
                255,
            ],
        ])(
            '%s (file: %s)',
            async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
                const dirPath = CONTRACTS_ROOT + 'pm-16181/';
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], dirPath);
                expectCompilerResult(result).toReturn(error, output, exitCode);
            },
        );
    });

    describe('[PM-16183]', () => {
        test.each([
            [
                'should return proper error when constructor have multiple return statements (including for loop)',
                'multiple_constructor_returns.compact',
                'Exception: multiple_constructor_returns.compact line 5 char 7:\n  unreachable statement',
                '',
                255,
            ],
            [
                'should return proper error when circuit have multiple return statements (including if)',
                'multiple_circuit_returns.compact',
                'Exception: multiple_circuit_returns.compact line 7 char 9:\n  unreachable statement',
                '',
                255,
            ],
        ])(
            '%s (file: %s)',
            async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
                const dirPath = CONTRACTS_ROOT + 'pm-16183/';
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], dirPath);
                expectCompilerResult(result).toReturn(error, output, exitCode);
            },
        );
    });

    describe('[PM-16349]', () => {
        test.each([
            [
                'should return proper error when using ! in pragma',
                'example_one.compact',
                'Exception: example_one.compact line 1 char 29:\n  parse error: found "<" looking for a version atom',
                '',
                255,
            ],
            [
                'should return proper error when using !>= in pragma',
                'example_two.compact',
                'Exception: example_two.compact line 1 char 39:\n  parse error: found ">=" looking for a version atom',
                '',
                255,
            ],
        ])(
            '%s (file: %s)',
            async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
                const dirPath = CONTRACTS_ROOT + 'pm-16349/';
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], dirPath);
                expectCompilerResult(result).toReturn(error, output, exitCode);
            },
        );
    });

    test(`[PM-16603] should generate proper export names in contract-info.json`, async () => {
        const outputDir = createTempFolder();
        const contractDir = CONTRACTS_ROOT + 'pm-16603/';

        const result: Result = await compile([Arguments.SKIP_ZK, contractDir + 'pm-16603.compact', outputDir]);
        expectCompilerResult(result).toReturn('', '', 0);

        const expectedContractInfo = getFileContent(contractDir + 'contract-info.json');
        const actualContractInfo = getFileContent(outputDir + '/compiler/contract-info.json');
        expect(actualContractInfo).toEqual(expectedContractInfo);
    });

    describe('[PM-16893]', () => {
        test.each([
            [
                'should compile contract without errors when for loop is iterating over empty tuple',
                'example_one.compact',
                '',
                '',
                0,
            ],
            ['should compile contract without errors when using map with empty tuples', 'example_two.compact', '', '', 0],
            ['should compile contract without errors when using fold with empty tuples', 'example_three.compact', '', '', 0],
        ])(
            '%s (file: %s)',
            async (testcase: string, fileName: string, error: RegExp | string, output: string, exitCode: number) => {
                const dirPath = CONTRACTS_ROOT + 'pm-16893/';
                const outputDir = createTempFolder();

                const result: Result = await compile([Arguments.SKIP_ZK, fileName, outputDir], dirPath);
                expectCompilerResult(result).toReturn(error, output, exitCode);
            },
        );
    });
});
