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
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles, saveContract } from '@';

const strings = generateStrings();

function generateStrings(): string[] {
    const strings: string[] = [];
    const alphabet = 'abcdefghijklmnopqrstuvwxyz';

    for (let i = 0; i < 1000; i++) {
        const firstChar = alphabet[Math.floor(i / 26 / 26 / 26 / 26) % 26];
        const secondChar = alphabet[Math.floor(i / 26 / 26 / 26) % 26];
        const thirdChar = alphabet[Math.floor(i / 26 / 26) % 26];
        const fourthChar = alphabet[Math.floor(i / 26) % 26];
        const fifthChar = alphabet[i % 26];
        const sixthChar = alphabet[(i + 1) % 26];

        strings.push(`${firstChar}${secondChar}${thirdChar}${fourthChar}${fifthChar}${sixthChar}`);
    }

    return strings;
}

function getMinimumContractContent() {
    let content: string = '';
    content = content.concat('pragma language_version > 0.12.1;\n');
    content = content.concat('import CompactStandardLibrary;\n');
    return content;
}

function generateContractExports(): string {
    let content = getMinimumContractContent();
    generateStrings().forEach((s) => {
        content = content.concat(`export circuit ${s} (a: Boolean, b: Field): Boolean { return false; }\n`);
    });
    return content;
}

function generateContractEnums(): string {
    let content = getMinimumContractContent();
    const enums = ['a', 'b', 'c'].join(', ');
    strings.forEach((s) => {
        content = content.concat(`enum PublicState${s} { ${enums} }\n`);
    });
    return content;
}

describe('[Generated] Compiler', () => {
    test('should transpile minimum', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(getMinimumContractContent());
        const result: Result = await compile([contractFilePath, tempPath]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });

    test('should transpile with 10 000 circuits', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(generateContractExports());
        // skipping ZK, otherwise this takes a lot of time with new implementation
        const result: Result = await compile([Arguments.SKIP_ZK, contractFilePath, tempPath]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });

    test('should transpile with 10 000 enums', async () => {
        const tempPath = createTempFolder();
        const contractFilePath = saveContract(generateContractEnums());
        const result: Result = await compile([contractFilePath, tempPath]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(tempPath).thatGeneratedJSCodeIsValid();
    });
});
