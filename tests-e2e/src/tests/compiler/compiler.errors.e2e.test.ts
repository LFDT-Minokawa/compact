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

import { describe, test } from 'vitest';
import {
    Arguments,
    compile,
    compilerDefaultOutput,
    createTempFolder,
    expectCompilerResult,
    expectFiles,
    buildPathTo,
    escapeRegExp,
} from '@';

describe('[Errors] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/errors/');

    test.each([
        {
            file: 'missing.compact',
            error: new RegExp(
                `Exception: error opening source file: failed for ${escapeRegExp(CONTRACTS_ROOT + 'missing.compact')}: no such file or directory`,
            ),
        },
        {
            file: 'spreadParams.compact',
            error: /Exception: spreadParams.compact line 21 char 22: spread initializer found after positional or named initializers in struct creation syntax/,
        },
        {
            file: 'tuple.compact',
            error: /Exception: tuple.compact line 21 char 11: expected right-hand side of = to have type \[Field, Boolean] but received \[Field, Field]/,
        },
        {
            file: 'counter_direct_assignment.compact',
            error: /Exception: counter_direct_assignment.compact line 21 char 5: operation = undefined for ledger field type Counter/,
        },
        {
            file: 'duplicate_ledger_binding.compact',
            error: /Exception: duplicate_ledger_binding.compact line 18 char 1: another binding found for c in the same scope at line 17 char 1/,
        },
        {
            file: 'invalid_cast_to_map_type.compact',
            error: /Exception: invalid_cast_to_map_type.compact line 20 char 13: cannot cast from type Uint<64> to type Map<Field, Field>/,
        },
        {
            file: 'sealed_ledger_mutation.compact',
            error: /Exception: sealed_ledger_mutation.compact line 20 char 1: exported circuits cannot modify sealed ledger fields but test calls \(directly or indirectly\) test, which modifies sealed field c at line 21 char 3/,
        },
    ])(`should throw: $error for contract: $file`, async ({ file, error }) => {
        const filePath = CONTRACTS_ROOT + file;

        const outputDir = createTempFolder();
        const result = await compile([Arguments.VSCODE, filePath, outputDir]);

        expectCompilerResult(result).toBeFailure(error, compilerDefaultOutput());
        expectFiles(result).thatNoFilesAreGenerated();
    });
});
