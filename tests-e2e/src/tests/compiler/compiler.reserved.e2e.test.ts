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
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, buildPathTo, expectFiles } from '@';

describe('[Reserved] PM-14357 - Reserved keywords', () => {
    const CONTRACTS_ROOT = buildPathTo('/reserved/');

    describe('using reserved keywords should throw an error', () => {
        test.each([
            {
                testcase: 'await keyword',
                file: 'example_1.compact',
                output: {
                    stderr: 'Exception: example_1.compact line 16 char 15: parse error: found keyword "await" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'break keyword',
                file: 'example_2.compact',
                output: {
                    stderr: 'Exception: example_2.compact line 16 char 9: parse error: found keyword "break" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'case keyword',
                file: 'example_3.compact',
                output: {
                    stderr: 'Exception: example_3.compact line 16 char 8: parse error: found keyword "case" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'catch keyword',
                file: 'example_4.compact',
                output: {
                    stderr: 'Exception: example_4.compact line 16 char 14: parse error: found keyword "catch" (which is reserved for future use) looking for a typed pattern or ")"',
                },
            },
            {
                testcase: 'class keyword',
                file: 'example_5.compact',
                output: {
                    stderr: 'Exception: example_5.compact line 16 char 6: parse error: found keyword "class" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'const keyword',
                file: 'example_6.compact',
                output: {
                    stderr: 'Exception: example_6.compact line 16 char 28: parse error: found keyword "const" looking for a const binding',
                },
            },
            {
                testcase: 'continue keyword',
                file: 'example_7.compact',
                output: {
                    stderr: 'Exception: example_7.compact line 16 char 28: parse error: found keyword "continue" (which is reserved for future use) looking for a type',
                },
            },
            {
                testcase: 'debugger keyword',
                file: 'example_8.compact',
                output: {
                    stderr: 'Exception: example_8.compact line 16 char 10: parse error: found keyword "debugger" (which is reserved for future use) looking for a generic parameter or ">"',
                },
            },
            {
                testcase: 'default keyword',
                file: 'example_9.compact',
                output: {
                    stderr: 'Exception: example_9.compact line 16 char 26: parse error: found keyword "default" looking for a type size',
                },
            },
            {
                testcase: 'delete keyword',
                file: 'example_10.compact',
                output: {
                    stderr: 'Exception: example_10.compact line 16 char 25: parse error: found keyword "delete" (which is reserved for future use) looking for a string',
                },
            },
            {
                testcase: 'do keyword',
                file: 'example_11.compact',
                output: {
                    stderr: 'Exception: example_11.compact line 16 char 37: parse error: found keyword "do" (which is reserved for future use) looking for a non-negative numeric constant or an expression sequence',
                },
            },
            {
                testcase: 'else keyword',
                file: 'example_12.compact',
                output: {
                    stderr: 'Exception: example_12.compact line 16 char 8: parse error: found keyword "else" looking for an identifier',
                },
            },
            {
                testcase: 'enum keyword',
                file: 'example_13.compact',
                output: {
                    stderr: 'Exception: example_13.compact line 16 char 6: parse error: found keyword "enum" looking for an identifier',
                },
            },
            {
                testcase: 'export keyword',
                file: 'example_14.compact',
                output: {
                    stderr: 'Exception: example_14.compact line 16 char 15: parse error: found keyword "export" looking for an identifier',
                },
            },
            {
                testcase: 'extends keyword',
                file: 'example_15.compact',
                output: {
                    stderr: 'Exception: example_15.compact line 16 char 8: parse error: found keyword "extends" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'false keyword',
                file: 'example_16.compact',
                output: {
                    stderr: 'Exception: example_16.compact line 16 char 10: parse error: found keyword "false" looking for an import element or "}"',
                },
            },
            {
                testcase: 'finally keyword',
                file: 'example_17.compact',
                output: {
                    stderr: 'Exception: example_17.compact line 17 char 17: parse error: found keyword "finally" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'for keyword',
                file: 'example_18.compact',
                output: {
                    stderr: 'Exception: example_18.compact line 16 char 1: parse error: found keyword "for" looking for a program element or end of file',
                },
            },
            {
                testcase: 'function keyword',
                file: 'example_19.compact',
                output: {
                    stderr: 'Exception: example_19.compact line 18 char 11: parse error: found keyword "function" (which is reserved for future use) looking for a const binding',
                },
            },
            {
                testcase: 'if keyword',
                file: 'example_20.compact',
                output: {
                    stderr: 'Exception: example_20.compact line 17 char 16: parse error: found keyword "if" looking for an identifier',
                },
            },
            {
                testcase: 'import keyword',
                file: 'example_21.compact',
                output: {
                    stderr: 'Exception: example_21.compact line 16 char 8: parse error: found keyword "import" looking for an identifier',
                },
            },
            {
                testcase: 'in keyword',
                file: 'example_22.compact',
                output: {
                    stderr: 'Exception: example_22.compact line 17 char 9: parse error: found keyword "in" (which is reserved for future use) looking for a const binding',
                },
            },
            {
                testcase: 'instanceof keyword',
                file: 'example_23.compact',
                output: {
                    stderr: 'Exception: example_23.compact line 16 char 9: parse error: found keyword "instanceof" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'new keyword',
                file: 'example_24.compact',
                output: {
                    stderr: 'Exception: example_24.compact line 16 char 22: parse error: found keyword "new" looking for an identifier',
                },
            },
            {
                testcase: 'null keyword',
                file: 'example_25.compact',
                output: {
                    stderr: 'Exception: example_25.compact line 17 char 21: parse error: found keyword "null" (which is reserved for future use) looking for a type',
                },
            },
            {
                testcase: 'return keyword',
                file: 'example_26.compact',
                output: {
                    stderr: 'Exception: example_26.compact line 16 char 16: parse error: found keyword "return" looking for a type',
                },
            },
            {
                testcase: 'super keyword',
                file: 'example_27.compact',
                output: {
                    stderr: 'Exception: example_27.compact line 16 char 13: parse error: found keyword "super" (which is reserved for future use) looking for a typed pattern or ")"',
                },
            },
            {
                testcase: 'switch keyword',
                file: 'example_28.compact',
                output: {
                    stderr: 'Exception: example_28.compact line 16 char 13: parse error: found keyword "switch" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'this keyword',
                file: 'example_29.compact',
                output: {
                    stderr: 'Exception: example_29.compact line 17 char 14: parse error: found keyword "this" (which is reserved for future use) looking for a tuple argument or "]"',
                },
            },
            {
                testcase: 'throw keyword',
                file: 'example_30.compact',
                output: {
                    stderr: 'Exception: example_30.compact line 16 char 17: parse error: found keyword "throw" (which is reserved for future use) looking for a type',
                },
            },
            {
                testcase: 'true keyword',
                file: 'example_31.compact',
                output: {
                    stderr: 'Exception: example_31.compact line 16 char 9: parse error: found keyword "true" looking for an identifier',
                },
            },
            {
                testcase: 'try keyword',
                file: 'example_32.compact',
                output: {
                    stderr: 'Exception: example_32.compact line 16 char 9: parse error: found keyword "try" (which is reserved for future use) looking for a string',
                },
            },
            {
                testcase: 'typeof keyword',
                file: 'example_33.compact',
                output: {
                    stderr: 'Exception: example_33.compact line 22 char 18: parse error: found keyword "typeof" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'var keyword',
                file: 'example_34.compact',
                output: {
                    stderr: 'Exception: example_34.compact line 16 char 6: parse error: found keyword "var" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'void keyword',
                file: 'example_35.compact',
                output: {
                    stderr: 'Exception: example_35.compact line 16 char 10: parse error: found keyword "void" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'while keyword',
                file: 'example_36.compact',
                output: {
                    stderr: 'Exception: example_36.compact line 16 char 5: parse error: found keyword "while" (which is reserved for future use) looking for "type"',
                },
            },
            {
                testcase: 'with keyword',
                file: 'example_37.compact',
                output: {
                    stderr: 'Exception: example_37.compact line 17 char 13: parse error: found keyword "with" (which is reserved for future use) looking for a type',
                },
            },
            {
                testcase: 'yield keyword',
                file: 'example_38.compact',
                output: {
                    stderr: 'Exception: example_38.compact line 17 char 10: parse error: found keyword "yield" (which is reserved for future use) looking for a const binding',
                },
            },
            {
                testcase: 'implements keyword',
                file: 'example_39.compact',
                output: {
                    stderr: 'Exception: example_39.compact line 16 char 32: parse error: found keyword "implements" (which is reserved for future use) looking for a generic argument or ">"',
                },
            },
            {
                testcase: 'interface keyword',
                file: 'example_40.compact',
                output: {
                    stderr: 'Exception: example_40.compact line 16 char 13: parse error: found keyword "interface" (which is reserved for future use) looking for a generic parameter or ">"',
                },
            },
            {
                testcase: 'package keyword',
                file: 'example_41.compact',
                output: {
                    stderr: 'Exception: example_41.compact line 16 char 13: parse error: found keyword "package" (which is reserved for future use) looking for an identifier',
                },
            },
            {
                testcase: 'private keyword',
                file: 'example_42.compact',
                output: {
                    stderr: 'Exception: example_42.compact line 16 char 1: parse error: found keyword "private" (which is reserved for future use) looking for a program element or end of file',
                },
            },
            {
                testcase: 'protected keyword',
                file: 'example_43.compact',
                output: {
                    stderr: 'Exception: example_43.compact line 16 char 1: parse error: found keyword "protected" (which is reserved for future use) looking for a program element or end of file',
                },
            },
            {
                testcase: 'public keyword',
                file: 'example_44.compact',
                output: {
                    stderr: 'Exception: example_44.compact line 16 char 1: parse error: found keyword "public" (which is reserved for future use) looking for a program element or end of file',
                },
            },
            {
                testcase: 'let keyword',
                file: 'example_45.compact',
                output: {
                    stderr: 'Exception: example_45.compact line 17 char 3: parse error: found keyword "let" (which is reserved for future use) looking for a statement or "}"',
                },
            },
            {
                testcase: 'static keyword',
                file: 'example_46.compact',
                output: {
                    stderr: 'Exception: example_46.compact line 16 char 1: parse error: found keyword "static" (which is reserved for future use) looking for a program element or end of file',
                },
            },
            {
                testcase: 'as keyword',
                file: 'example_47.compact',
                output: {
                    stderr: 'Exception: example_47.compact line 22 char 18: parse error: found keyword "as" looking for an identifier',
                },
            },
            {
                testcase: 'of keyword',
                file: 'example_48.compact',
                output: {
                    stderr: 'Exception: example_48.compact line 16 char 37: parse error: found keyword "of" looking for a non-negative numeric constant or an expression sequence',
                },
            },
        ])(`$testcase`, async ({ file, output }) => {
            const filePath = CONTRACTS_ROOT + file;
            const outputDir = createTempFolder();

            const result: Result = await compile([Arguments.SKIP_ZK, Arguments.VSCODE, filePath, outputDir]);
            expectCompilerResult(result).toBeFailure(output.stderr, compilerDefaultOutput());
            expectFiles(outputDir).thatNoFilesAreGenerated();
        });
    });
});
