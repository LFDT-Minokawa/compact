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

import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
    createCircuitContext,
    createConstructorContext,
    dummyContractAddress,
} from '@midnight-ntwrk/compact-runtime';

type TestPhase = 'compile' | 'runtime';
export type TestResult = 'pass' | 'fail';

type TestExpectation = {
    phase: TestPhase;
    result: TestResult;
};

export type CompileResult = {
    contractPath: string;
    outputDir: string;
    stderr: string;
    stdout: string;
    exitCode: number;
};

export type CompactContract<PrivateState = any> = {
    initialState(
        context: any,
        ...args: any[]
    ):
        | Promise<CompactConstructorResult<PrivateState>>
        | CompactConstructorResult<PrivateState>;
};

type CompactConstructorResult<PrivateState = any> = {
    currentContractState: any;
    currentPrivateState: PrivateState;
    currentZswapLocalState: {
        coinPublicKey: any;
    };
};

export type CompactContractConstructor<
    Contract extends CompactContract<any> = CompactContract<any>,
    Witnesses = any,
> = new (witnesses: Witnesses) => Contract;

type ContractConstructorResult<Contract> = Contract extends {
    initialState(context: any, ...args: any[]): infer Result;
}
    ? Awaited<Result>
    : {
          currentContractState: any;
          currentPrivateState: any;
          currentZswapLocalState: {
              coinPublicKey: any;
          };
      };

type ContractPrivateState<Contract> =
    ContractConstructorResult<Contract> extends {
        currentPrivateState: infer PrivateState;
    }
        ? PrivateState
        : any;

type ContractWitnesses<Contract extends CompactContractConstructor> =
    ConstructorParameters<Contract> extends [infer Witnesses, ...unknown[]]
        ? Witnesses
        : never;

type ContractCircuitContextFromCircuits<Circuits> =
    Circuits[keyof Circuits] extends (
        context: infer Context,
        ...args: any[]
    ) => any
        ? Context
        : any;

type ContractCircuitContext<Contract> = Contract extends {
    circuits: infer Circuits;
}
    ? ContractCircuitContextFromCircuits<Circuits>
    : Contract extends { impureCircuits: infer Circuits }
      ? ContractCircuitContextFromCircuits<Circuits>
      : any;

type TestContract<Contract extends CompactContractConstructor> = {
    contract: InstanceType<Contract>;
    ctx: ContractCircuitContext<InstanceType<Contract>>;
};

type ExpectedCompileError = RegExp | ((result: CompileResult) => boolean);

type CompileTestOptions = {
    expectedError?: ExpectedCompileError;
};

type RuntimeTestOptions = {
    expectedError?: RegExp | ((error: unknown) => boolean);
};

export type CompileTestDefinition = {
    kind: 'compact-compile-test';
    result: TestResult;
    options: CompileTestOptions;
};

export type RuntimeTestDefinition<
    Contract extends CompactContractConstructor = CompactContractConstructor,
> = {
    kind: 'compact-runtime-test';
    result: TestResult;
    options: RuntimeTestOptions;
    run: (Contract: Contract) => Promise<void> | void;
};

const compactTestFilePattern = /^(compile|runtime)\.(pass|fail)\.test\.ts$/;

/**
 * Defines a compile-phase Compact fixture.
 *
 * The orchestrator imports this metadata before registering Vitest cases. The
 * expected result is read from the file name, so the fixture outcome stays
 * visible in the directory listing.
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
    const ctx = createCircuitContext(
        'constructor',
        dummyContractAddress(),
        constructorResult.currentZswapLocalState.coinPublicKey,
        constructorResult.currentContractState,
        constructorResult.currentPrivateState,
    );

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
