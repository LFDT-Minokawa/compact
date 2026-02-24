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
import { createTempFolder, expectCommandResult, fixup, buildPathTo, getFileContent } from '@';
import path from 'node:path';

const contractsDir = buildPathTo('/fixup/bugs');

describe('[Bugs] Fixup', () => {
    test('[Issue #64] structured directory with files/modules', async () => {
        const filePath = path.join(contractsDir, '/structured/main.compact');
        const oraclePath = path.join(contractsDir, '/structured/fixed_main.compact');

        const outputDir = createTempFolder();
        const fixedContract = `${outputDir}/fixed.compact}`;

        const result: Result = await fixup([filePath, fixedContract]);

        expectCommandResult(result).toBeSuccess('', '');
        expect(getFileContent(fixedContract)).toEqual(getFileContent(oraclePath));
    });
});
