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
import { Arguments, buildPathTo, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles } from '@';

describe('[Bugs][JS code] Compiler', () => {
    const CONTRACTS_ROOT = buildPathTo('/bugs/');

    test(`[PM-16064] should generate correct index.js file, which can be compiled`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-16064.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        await expectFiles(outputDir).thatGeneratedJSCodeIsValid().thatGeneratedJSCodeIsLinted();
    });

    test(`[PM-16075] should generate correct index.js file, which can be compiled`, async () => {
        const outputDir = createTempFolder();

        const result: Result = await compile([Arguments.SKIP_ZK, CONTRACTS_ROOT + 'pm-16075.compact', outputDir]);
        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        await expectFiles(outputDir).thatGeneratedJSCodeIsValid().thatGeneratedJSCodeIsLinted();
    });
});
