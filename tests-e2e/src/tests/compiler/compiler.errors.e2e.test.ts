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
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles } from '@';

describe('[Errors] Compiler', () => {
    const CONTRACTS_ROOT = '../examples/errors/';

    test.each([
        {
            file: 'unbound.compact',
            error: /Exception: unbound.compact line 16 char 59: unbound identifier Maybe/,
        },
        {
            file: 'maybe.compact',
            error: /Exception: maybe.compact line 19 char 3: mismatch between type struct Maybe<is_some: Boolean, value: Field> and type \[] of condition branches/,
        },
        {
            file: 'multiSource.compact',
            error: /Exception: multiSource.compact line 28 char 10: no compatible function named enabledPower is in scope at this call; one function is incompatible with the supplied argument types; supplied argument types: \(Uint<0..1>, Field\); declared argument types for function at line 19 char 1: \(Boolean, Field\)/,
        },
        {
            file: 'multiSource2.compact',
            error: /Exception: multiSource2.compact line 21 char 47: call site ambiguity \(multiple compatible functions\) in call to foo; supplied argument types: \(\); compatible functions: line 17 char 12; line 19 char 1/,
        },
        {
            file: 'multiSource4.compact',
            error: /Exception: multiSource4.compact line 18 char 10: incompatible arguments in call to anonymous circuit; supplied argument types: \(Uint<0..1>, Field\); declared circuit type: \(Field, Field, Field\)/,
        },
        {
            file: 'typeParams.compact',
            error: /Exception: typeParams.compact line 22 char 10: no compatible function named none is in scope at this call; one function is incompatible with the supplied generic values; supplied generic values: <>; declared generics for function at <standard library>: <type>/,
        },
        {
            file: 'missing.compact',
            error: /Exception: error opening source file: failed for ..\/examples\/errors\/missing.compact: no such file or directory/,
        },
        {
            file: 'missing-include.compact',
            error: /Exception: missing-include.compact line 17 char 1: failed to locate file "missing file {2}with {3}spaces.compact"/,
        },
        {
            file: 'spreadParams.compact',
            error: /Exception: spreadParams.compact line 21 char 22: spread initializer found after positional or named initializers in struct creation syntax/,
        },
        {
            file: 'tuple.compact',
            error: /Exception: tuple.compact line 21 char 11: expected right-hand side of = to have type \[Field, Boolean] but received \[Field, Field]/,
        },
    ])(`should throw: $error for contract: $file`, async ({ file, error }) => {
        const filePath = CONTRACTS_ROOT + file;

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.VSCODE, filePath, outputDir]);

        expectCompilerResult(result).toBeFailure(error, compilerDefaultOutput());
        expectFiles(outputDir).thatNoFilesAreGenerated();
    });
});
