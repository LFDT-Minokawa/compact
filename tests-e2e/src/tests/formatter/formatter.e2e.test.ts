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
import { createTempFolder, expectCommandResult, format, getFileContent, buildPathTo } from '@';
import path from 'node:path';
import fs from 'fs';

const contractsDir = buildPathTo('/formatter/input');
const oracleDir = buildPathTo('/formatter/output');
const inputContracts = fs.readdirSync(contractsDir);

describe('[E2E] Example contract tests for formatter tool', () => {
    inputContracts.forEach((fileName) => {
        const filePath = path.join(contractsDir, fileName);
        const oraclePath = path.join(oracleDir, fileName);
        const oracleContent = getFileContent(oraclePath);

        test(`should properly format contract: '${fileName}'`, async () => {
            const outputDir = createTempFolder();
            const formattedContract = `${outputDir}/formatted.compact}`;

            const result: Result = await format([filePath, formattedContract]);

            expectCommandResult(result).toBeSuccess('', '');
            expect(getFileContent(formattedContract)).toEqual(oracleContent);
        });
    });
});
