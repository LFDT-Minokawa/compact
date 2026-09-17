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

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
    createCircuitContext,
    createConstructorContext,
    dummyContractAddress,
} from '@midnight-ntwrk/compact-runtime';

import type {
    CompactContractConstructor,
    CompileTestDefinition,
    CompileTestOptions,
    InnerProof,
    ContractCircuitContext,
    ContractPrivateState,
    ContractWitnesses,
    RuntimeTestDefinition,
    RuntimeTestOptions,
    TestContract,
    TestExpectation,
    TestPhase,
    TestResult,
} from './types.ts';
import { compactTestFilePattern, testRoot } from './utils.ts';

const innerProofOutputDir = path.join(
    testRoot,
    'tools',
    'verify-proof-fixtures',
    'out',
);

/**
 * The directory holding the generated keys, as a `--compact-path` entry.
 *
 * `verifyProof` names its key by pathname and the compiler resolves it against
 * the compact path, so a fixture naming `basic.verifier` needs this on that
 * path rather than a relative reach out of the fixture directory.
 */
export const innerProofKeyDir = innerProofOutputDir;

/** The generated key for one inner circuit, as the contract names it. */
export function innerProofKeyPath(circuit: string): string {
    return path.join(innerProofOutputDir, `${circuit}.verifier`);
}

type InnerProofBundle = {
    circuit: string;
    vkHash: string;
    vk: string;
    instance: string[];
    proof: string;
};

/**
 * Reads the generated bundle for one inner circuit.
 *
 * The runner rebuilds every bundle before a run, so a missing one means the
 * generator has not run rather than that the fixture is misconfigured.
 */
export function readInnerProof(circuit: string): InnerProof {
    const bundlePath = path.join(innerProofOutputDir, `${circuit}.json`);
    let bundle: InnerProofBundle;

    try {
        bundle = JSON.parse(
            readFileSync(bundlePath, 'utf8'),
        ) as InnerProofBundle;
    } catch (error) {
        throw new Error(
            `${bundlePath} is missing or unreadable; run yarn test, which rebuilds inner proofs: ${error}`,
        );
    }

    return {
        circuit: bundle.circuit,
        vkHash: bundle.vkHash,
        vk: new Uint8Array(Buffer.from(bundle.vk, 'base64')),
        instance: bundle.instance.map((value) => BigInt(value)),
        proof: new Uint8Array(Buffer.from(bundle.proof, 'base64')),
    };
}

/**
 * Defines a compile-phase Compact fixture.
 *
 * The orchestrator imports this metadata before registering Vitest cases. The
 * expected result is read from the file name, so the fixture outcome stays
 * visible in the directory listing. A fixture that needs a non-default
 * compiler mode declares the extra flags with `compilerArgs`, which are passed
 * ahead of the contract and output paths on every compiler invocation for that
 * fixture.
 */
export function defineCompileTest(
    metaUrl: string,
    options: CompileTestOptions = {},
): CompileTestDefinition {
    const expectation = expectationFromTestFile(metaUrl, 'compile');

    return {
        kind: 'compact-compile-test',
        result: expectation.result,
        options,
    };
}

/**
 * Defines a runtime-phase Compact fixture.
 *
 * Runtime files may type-import generated contract artifacts. The orchestrator
 * imports the generated contract value after compilation and passes it to this
 * callback.
 */
export function defineRuntimeTest<Contract extends CompactContractConstructor>(
    metaUrl: string,
    run: (Contract: Contract) => Promise<void> | void,
    options: RuntimeTestOptions = {},
): RuntimeTestDefinition<Contract> {
    const expectation = expectationFromTestFile(metaUrl, 'runtime');

    return {
        kind: 'compact-runtime-test',
        result: expectation.result,
        options,
        run,
    };
}

/**
 * Creates a generated Compact contract instance and circuit context for
 * runtime fixture assertions while preserving the generated contract type.
 */
export async function createTestContract<
    Contract extends CompactContractConstructor,
>(
    Contract: Contract,
    witnesses: ContractWitnesses<Contract> = {} as ContractWitnesses<Contract>,
    privateState: ContractPrivateState<
        InstanceType<Contract>
    > = undefined as ContractPrivateState<InstanceType<Contract>>,
): Promise<TestContract<Contract>> {
    const contract = new Contract(witnesses) as InstanceType<Contract>;
    const constructorResult = await contract.initialState(
        createConstructorContext(privateState, '0'.repeat(64)),
    );
    const ctx = createCircuitContext({
        circuitId: 'constructor',
        contractAddress: dummyContractAddress(),
        coinPublicKeyOrZswapState: constructorResult.currentZswapLocalState.coinPublicKey,
        contractState: constructorResult.currentContractState,
        privateState: constructorResult.currentPrivateState,
    });

    return {
        contract,
        ctx: ctx as ContractCircuitContext<InstanceType<Contract>>,
    };
}

/**
 * Parses the phase and expected outcome from a test file name.
 */
function expectationFromTestFile(
    metaUrl: string,
    expectedPhase: TestPhase,
): TestExpectation {
    const fileName = path.basename(fileURLToPath(metaUrl));
    const match = compactTestFilePattern.exec(fileName);

    if (match === null) {
        throw new Error(
            `Compact test files must be named compile.pass.test.ts, compile.fail.test.ts, runtime.pass.test.ts, or runtime.fail.test.ts: ${fileName}`,
        );
    }

    const expectation = {
        phase: match[1] as TestPhase,
        result: match[2] as TestResult,
    };

    if (expectation.phase !== expectedPhase) {
        throw new Error(
            `${fileName} declares a ${expectation.phase} test but was registered as a ${expectedPhase} test`,
        );
    }

    return expectation;
}
