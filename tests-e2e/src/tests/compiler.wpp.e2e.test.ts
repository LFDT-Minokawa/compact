import { Result } from 'execa';
import { describe, test } from 'vitest';
import { Arguments, compile, copyFile, createTempFolder, expectCompilerResult, expectFiles } from '..';
import * as fs from 'fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

describe('[WPP] Compiler', () => {
    const CONTRACTS_ROOT = '../../../examples/wpp/';
    const FOLDER_PATH = path.join(__dirname, CONTRACTS_ROOT);

    const readFiles = fs.readdirSync(FOLDER_PATH, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    beforeAll(async () => {
        copyFile('../examples/wpp/test/test.compact', contractsDir);

        await compile([`${contractsDir}/test.compact`, `${contractsDir}/test`]);
    });

    filesNames.forEach((fileName) => {
        const filePath = path.join(FOLDER_PATH, fileName);

        test(`should be able to compile contract: ${fileName}`, async () => {
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);
            expectCompilerResult(result).toReturn('', '', 0);
            expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
        });
    });

    test(`should not be able to compile contract: contract_wpp.compact`, async () => {
        const filePath = path.join(FOLDER_PATH, 'contract', 'contract_wpp.compact');
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);

        expectCompilerResult(result).toReturn(
            // FIXME once zkir is generated for CC fix this test
            // 'Exception: contract_wpp.compact line 17 char 4:\n  contract types are not yet implemented',
            'Internal error (please report): Exception in print-zkir: unreachable',
            '',
            // 255,
            254,
        );
    });

    test(`should not be able to compile contract: pm_16723_neg.compact`, async () => {
        const filePath = path.join(FOLDER_PATH, 'negative', 'pm_16723_neg.compact');
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], FOLDER_PATH);

        expectCompilerResult(result).toReturn(
            'Exception: pm_16723_neg.compact line 8 char 10:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit adolf at line 7 char 22\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of = at line 8 char 10\n' +
                'Exception: pm_16723_neg.compact line 13 char 11:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter b of exported circuit damian at line 12 char 23\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of += at line 13 char 11\n' +
                'Exception: pm_16723_neg.compact line 17 char 11:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit gary at line 16 char 21\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of -= at line 17 char 11\n' +
                'Exception: pm_16723_neg.compact line 21 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit edmund at line 20 char 23\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the argument to lookup at line 21 char 7\n' +
                'Exception: pm_16723_neg.compact line 25 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit barbara at line 24 char 24\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the second argument to insert at line 25 char 7\n' +
                'Exception: pm_16723_neg.compact line 30 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit katie at line 29 char 22\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the argument to remove at line 30 char 7',
            '',
            255,
        );
    });
});
