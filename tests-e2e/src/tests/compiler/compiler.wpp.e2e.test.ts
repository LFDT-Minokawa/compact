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
import { describe, test } from 'vitest';
import {
    Arguments,
    compile,
    compilerDefaultOutput,
    copyFile,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
} from '@';
import * as fs from 'fs';
import path from 'node:path';

describe('[WPP] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/wpp/');

    const readFiles = fs.readdirSync(CONTRACTS_ROOT, { withFileTypes: true });
    const filesNames = readFiles.filter((file) => file.isFile()).map((file) => file.name);
    const contractsDir = createTempFolder();

    beforeAll(async () => {
        copyFile('../examples/wpp/test/test.compact', contractsDir);

        await compile([`${contractsDir}/test.compact`, `${contractsDir}/test`]);
    });

    filesNames.forEach((fileName) => {
        const filePath = path.join(CONTRACTS_ROOT, fileName);

        test(`should be able to compile contract: ${fileName}`, async () => {
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);
            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(contractsDir).thatGeneratedJSCodeIsValid();
        });
    });

    //  FIXME: un-skip for CC
    test.skip(`should not be able to compile contract: contract_wpp.compact`, async () => {
        const filePath = path.join(CONTRACTS_ROOT, 'contract', 'contract_wpp.compact');
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);

        expectCompilerResult(result).toBeFailure(
            'Exception: contract_wpp.compact line 32 char 4:\n  contract types are not yet implemented',
            compilerDefaultOutput(),
        );
    });

    test(`should not be able to compile contract: pm_16723_neg.compact`, async () => {
        const filePath = path.join(CONTRACTS_ROOT, 'negative', 'pm_16723_neg.compact');
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, contractsDir], CONTRACTS_ROOT);

        expectCompilerResult(result).toBeFailure(
            'Exception: pm_16723_neg.compact line 23 char 10:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit adolf at line 22 char 22\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of = at line 23 char 10\n' +
                'Exception: pm_16723_neg.compact line 28 char 11:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter b of exported circuit damian at line 27 char 23\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of += at line 28 char 11\n' +
                'Exception: pm_16723_neg.compact line 32 char 11:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit gary at line 31 char 21\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the right-hand side of -= at line 32 char 11\n' +
                'Exception: pm_16723_neg.compact line 36 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit edmund at line 35 char 23\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the argument to lookup at line 36 char 7\n' +
                'Exception: pm_16723_neg.compact line 40 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit barbara at line 39 char 24\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the second argument to insert at line 40 char 7\n' +
                'Exception: pm_16723_neg.compact line 45 char 7:\n' +
                '  potential witness-value disclosure must be declared but is not:\n' +
                '    witness value potentially disclosed:\n' +
                '      the value of parameter a of exported circuit katie at line 44 char 22\n' +
                '    nature of the disclosure:\n' +
                '      ledger operation might disclose the witness value\n' +
                '    via this path through the program:\n' +
                '      the argument to remove at line 45 char 7',
            compilerDefaultOutput(),
        );
    });
});
