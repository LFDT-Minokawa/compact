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
import { Arguments, compile, compilerDefaultOutput, createTempFolder, expectCompilerResult, expectFiles, buildPathTo } from '@';

const CONTRACTS_ROOT = buildPathTo('/casts/');

describe('[Casts] PM-15536 - Casts between Bytes and Vectors', () => {
    describe('casts between Bytes and Vectors', () => {
        test('should be respected by compiler and compiled successfully', async () => {
            const filePath = CONTRACTS_ROOT + 'vector_to_bytes.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });

        test('should not fail on zkir generation', async () => {
            const filePath = CONTRACTS_ROOT + 'zkir_generation.compact';

            const outputDir = createTempFolder();
            const result: Result = await compile([filePath, outputDir]);

            expectCompilerResult(result).toBeSuccess('Compiling 3 circuits:', compilerDefaultOutput());
            expectFiles(outputDir).thatGeneratedJSCodeIsValid();
        });
    });
});

describe('[Advanced casts] PM-17427 - Casts between more advanced types', () => {
    test('should be respected by compiler and compiled successfully', async () => {
        const filePath = CONTRACTS_ROOT + 'advanced_casts.compact';

        const outputDir = createTempFolder();
        const result: Result = await compile([Arguments.SKIP_ZK, filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();
    });
});
