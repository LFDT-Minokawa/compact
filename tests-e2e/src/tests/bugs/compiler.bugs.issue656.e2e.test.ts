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

import { describe, expect, test } from 'vitest';
import { Arguments, buildPathTo, compile, createTempFolder, expectCompilerResult, getFileContent } from '@';

type ZkirCircuit = {
    version: {
        major: number;
    };
    do_communications_commitment: boolean;
};

const CONTRACT = buildPathTo('/bugs/issue-656/communications-commitment.compact');

const cases = [
    { name: 'v2 default', args: [], version: 2, expected: true },
    {
        name: 'v2 disabled',
        args: [Arguments.NO_COMMUNICATIONS_COMMITMENT],
        version: 2,
        expected: false,
    },
    { name: 'v3 default', args: [Arguments.FEATURE_V3], version: 3, expected: true },
    {
        name: 'v3 disabled',
        args: [Arguments.FEATURE_V3, Arguments.NO_COMMUNICATIONS_COMMITMENT],
        version: 3,
        expected: false,
    },
];

describe('[Bugs] [Issue #656] communications commitment compiler flag', () => {
    test.each(cases)('$name emits $expected', async ({ args, version, expected }) => {
        const outputDir = createTempFolder();
        const result = await compile([...args, Arguments.SKIP_ZK, CONTRACT, outputDir]);

        expectCompilerResult(result).toCompileWithoutErrors();

        const zkir = JSON.parse(getFileContent(`${outputDir}/zkir/set.zkir`)) as ZkirCircuit;
        expect(zkir.version.major).toBe(version);
        expect(zkir.do_communications_commitment).toBe(expected);
    });
});
