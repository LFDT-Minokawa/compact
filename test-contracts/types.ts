// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

export type TestPhase = 'compile' | 'runtime';

export type TestResult = 'pass' | 'fail';

export type TestExpectation = {
    phase: TestPhase;
    result: TestResult;
};

// A fixture test file plus the expectation named by its file name.
export type FixtureTestFile = TestExpectation & {
    filePath: string;
};

// A fixture directory grouped with the compile and runtime files it owns.
export type DiscoveredFixture = {
    fixtureDir: string;
    relativeFixtureDir: string;
    compile?: FixtureTestFile;
    runtime?: FixtureTestFile;
};

// Fixture metadata the orchestrator attaches to each orchestrated test case.
export type FixtureTestMetadata = {
    durationMs?: number;
    filePath: string;
};

export type CompileOutcome = {
    stderr: string;
    stdout: string;
    exitCode: number;
};

export type CompileResult = CompileOutcome & {
    contractPath: string;
    outputDir: string;
};

export type ExpectedCompileError =
    | RegExp
    | ((result: CompileResult) => boolean);

export type CompileTestOptions = {
    compilerArgs?: string[];
    expectedError?: ExpectedCompileError;
};

export type RuntimeTestOptions = {
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

export type ContractPrivateState<Contract> =
    ContractConstructorResult<Contract> extends {
        currentPrivateState: infer PrivateState;
    }
        ? PrivateState
        : any;

export type ContractWitnesses<Contract extends CompactContractConstructor> =
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

export type ContractCircuitContext<Contract> = Contract extends {
    circuits: infer Circuits;
}
    ? ContractCircuitContextFromCircuits<Circuits>
    : Contract extends { impureCircuits: infer Circuits }
      ? ContractCircuitContextFromCircuits<Circuits>
      : any;

export type TestContract<Contract extends CompactContractConstructor> = {
    contract: InstanceType<Contract>;
    ctx: ContractCircuitContext<InstanceType<Contract>>;
};
