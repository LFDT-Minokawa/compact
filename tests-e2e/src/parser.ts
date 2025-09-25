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

import * as fs from 'fs';
import * as path from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const inputTestFile: string = path.join(__dirname, '../../compiler', 'test.ss');

function extractTestsFromFile(filePath: string): string[] {
    try {
        const fileContent: string = fs.readFileSync(filePath, 'utf-8');
        const testFound = [...fileContent.matchAll(/test\s*['`]\(\s*([\s\S]*?)\s*\)\s*\(/g)];

        if (testFound.length === 0) {
            console.error('-> no tests found in test file');
            return [];
        }

        return testFound.map((match) =>
            match[1]
                .replace(/["'\t]+/g, '')
                .replace(/ {2, }/g, '')
                .trim(),
        );
    } catch (error) {
        console.error('-> error reading or parsing the file: ', error);
        return [];
    }
}

function writeContracts(contracts: string[], outputDir: string): void {
    // for each contract save new file
    contracts.forEach((contractBody, index) => {
        try {
            const newContract = path.join(outputDir, `contract_${index}.compact`);
            fs.writeFileSync(newContract, contractBody, 'utf-8');
            console.log(`-> contract body saved to: ${newContract}`);
        } catch (error) {
            console.error(`-> error saving contract: ${index}`, error);
        }
    });
}

export function extractAndSaveContracts(outputDir: string): string[] {
    const newContracts: string[] = extractTestsFromFile(inputTestFile);

    if (newContracts.length > 0) {
        writeContracts(newContracts, outputDir);
    } else {
        console.log('-> no contracts found to write');
    }

    return fs.readdirSync(outputDir);
}
