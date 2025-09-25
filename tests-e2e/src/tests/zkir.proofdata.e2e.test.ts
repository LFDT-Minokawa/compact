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

import { afterAll, beforeAll, describe, test } from 'vitest';
import { compile, compilerDefaultOutput, copyFiles, createTempFolder, expectCompilerResult, expectFiles,
    isRelease, removeFolder } from '@';
import { Result } from 'execa';
import fs from 'fs';
import * as runtime from '@midnight-ntwrk/compact-runtime';

// this is stuff from runtime
type StatefulContract = {
    witnesses: unknown;
    circuits: unknown;
    impureCircuits: unknown;
    initialState(context: runtime.ConstructorContext<unknown>, ...args: unknown[]): runtime.ConstructorResult<unknown>;
};

type ContractLike<T> = T extends StatefulContract
    ? {
          witnesses: T['witnesses'];
          circuits: T['circuits'];
          impureCircuits: T['impureCircuits'];
          initialState: (...args: Parameters<T['initialState']>) => ReturnType<T['initialState']>;
      }
    : never;

type ContractPrivateState<T extends StatefulContract> =
    Parameters<T['initialState']> extends [runtime.ConstructorContext<infer PS>, ...any] ? PS : never;

type ContractConstructorParameters<T extends StatefulContract> =
    Parameters<T['initialState']> extends [runtime.ConstructorContext<any>, ...infer P] ? P : never;

function startContract<TContract extends StatefulContract>(
    contract: () => TContract,
    privateState: ContractPrivateState<TContract>,
    ...args: ContractConstructorParameters<TContract>
): [ContractLike<TContract>, runtime.CircuitContext<ContractPrivateState<TContract>>] {
    const C = contract();
    const constructorResult = C.initialState(runtime.constructorContext(privateState, '0'.repeat(64)), ...args);
    const queryContext = new runtime.QueryContext(constructorResult.currentContractState.data, runtime.dummyContractAddress());
    const Ctxt = {
        originalState: constructorResult.currentContractState,
        currentPrivateState: constructorResult.currentPrivateState,
        currentZswapLocalState: runtime.emptyZswapLocalState('0'.repeat(64)),
        transactionContext: queryContext,
    };
    return [C as unknown as ContractLike<TContract>, Ctxt as unknown as runtime.CircuitContext<ContractPrivateState<TContract>>];
}

describe.skipIf(isRelease())('[ZKIR] Verify proof data for vector to bytes and bytes to vector', () => {
    const CONTRACTS_ROOT = '../examples/casts/';
    const filePath = CONTRACTS_ROOT + 'proof_data.compact';
    const outputDir = createTempFolder();

    beforeAll(async () => {
        const result: Result = await compile([filePath, outputDir]);

        expectCompilerResult(result).toBeSuccess('Compiling 2 circuits:', compilerDefaultOutput());
        expectFiles(outputDir).thatGeneratedJSCodeIsValid();

        // copy main node_modules, which include compact runtime
        copyFiles('../node_modules/@midnight-ntwrk', outputDir + '/contract/node_modules');
    });

    afterAll(() => {
        // cleanup
        removeFolder(outputDir + '/contract/node_modules');
    });

    test('check if proof data is valid for bytes to vector - test1', async () => {
        // import contract code dynamically
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractCode = await import(outputDir + '/contract/index.cjs');

        // eslint-disable-next-line @typescript-eslint/no-unsafe-return
        const contract = () => new contractCode.Contract({});
        const [C, InitialContext] = startContract(contract, 0);

        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const afterTest = C.circuits.test1(InitialContext);

        const zkirFile = outputDir + '/zkir/test1.zkir';
        const zkir = fs.readFileSync(zkirFile, 'utf-8');

        // check proof based on zkir
        // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
        runtime.checkProofData(zkir, afterTest.proofData);
    });

    test('check if proof data is valid for vector to bytes - test2', async () => {
        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const contractCode = await import(outputDir + '/contract/index.cjs');

        // eslint-disable-next-line @typescript-eslint/no-unsafe-return
        const contract = () => new contractCode.Contract({});
        const [C, InitialContext] = startContract(contract, 0);

        // eslint-disable-next-line @typescript-eslint/no-unsafe-assignment
        const afterTest = C.circuits.test2(InitialContext);

        const zkirFile = outputDir + '/zkir/test2.zkir';
        const zkir = fs.readFileSync(zkirFile, 'utf-8');

        // eslint-disable-next-line @typescript-eslint/no-unsafe-argument
        runtime.checkProofData(zkir, afterTest.proofData);
    });
});
