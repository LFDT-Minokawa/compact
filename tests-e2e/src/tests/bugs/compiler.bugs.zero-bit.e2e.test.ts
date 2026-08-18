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
import { Arguments, buildPathTo, compile, createTempFolder, expectCompilerResult, expectFiles, getFileContent } from '@';

type Alignment = {
    tag: string;
    value: {
        length: number;
        tag: string;
    };
};

type ZkirInstruction = {
    op: string;
    alignment?: Alignment[];
    inputs?: unknown[];
};

type ZkirCircuit = {
    version: {
        major: number;
    };
    instructions: ZkirInstruction[];
};

const ZERO_MAXIMUM_LEDGER = buildPathTo('/bugs/issue-285/zero-maximum-ledger.compact');
const ATTESTATION = buildPathTo('/bugs/issue-588/attestation.compact');

function getZkir(outputDir: string, circuitName: string): ZkirCircuit {
    return JSON.parse(getFileContent(`${outputDir}/zkir/${circuitName}.zkir`)) as ZkirCircuit;
}

function expectPersistentHashAlignment(outputDir: string, version: number): void {
    const zkir = getZkir(outputDir, 'attest');
    const instruction = zkir.instructions.find(({ op }) => op === 'persistent_hash');

    expect(zkir.version.major).toBe(version);
    expect(instruction).toBeDefined();
    expect(instruction?.alignment?.map(({ value }) => value.length)).toEqual([1, 8]);
    expect(instruction?.inputs).toHaveLength(2);
}

describe('[Bugs] Zero-bit fields use consistent one-byte alignment', () => {
    test('[Issue #285] Uint<0..1> ledger descriptors use one byte', async () => {
        const outputDir = createTempFolder();
        const result = await compile([Arguments.SKIP_ZK, ZERO_MAXIMUM_LEDGER, outputDir]);

        expectCompilerResult(result).toCompileWithoutErrors();
        expectFiles(result).thatGeneratedJSCodeIsValid();

        const generatedContract = getFileContent(`${outputDir}/contract/index.js`);
        expect(generatedContract).toContain('new __compactRuntime.CompactTypeUnsignedInteger(0n, 1)');
        expect(getZkir(outputDir, 'foo1').version.major).toBe(2);
        expect(getZkir(outputDir, 'foo2').version.major).toBe(2);
        expect(getZkir(outputDir, 'foo3').version.major).toBe(2);
    });

    test('[Issue #588] persistentHash inputs match their v2 alignment', async () => {
        const outputDir = createTempFolder();
        const result = await compile([Arguments.SKIP_ZK, ATTESTATION, outputDir]);

        expectCompilerResult(result).toCompileWithoutErrors();
        expectFiles(result).thatGeneratedJSCodeIsValid();
        expectPersistentHashAlignment(outputDir, 2);
    });

    test('[Issue #615] the reproduction compiles with the v3 backend', async () => {
        const outputDir = createTempFolder();
        const result = await compile([Arguments.FEATURE_V3, Arguments.SKIP_ZK, ATTESTATION, outputDir]);

        expectCompilerResult(result).toCompileWithoutErrors();
        expectFiles(result).thatGeneratedJSCodeIsValid();
        expectPersistentHashAlignment(outputDir, 3);
    });
});
