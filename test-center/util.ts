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

import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import * as fs from 'node:fs';
import {
  Executables,
  WitnessSets,
  CircuitContext,
  createConstructorContext,
  createCircuitContext,
  checkProofData,
  ConstructorContext,
  WitnessContext
} from '@midnight-ntwrk/compact-runtime';

export type StateConstructorParams<
  E extends Executables
> = E['initialState'] extends (c: ConstructorContext, ...a: infer A) => any ? A : never;

export type Module<E extends Executables> = {
  executables: (witnessSets: any) => E;
  zkirDir: string;
}

export const getRandomBytes = (size: number): Uint8Array => {
  const randomBytes = new Uint8Array(size);
  crypto.getRandomValues(randomBytes);
  return randomBytes;
};

export const sampleCoinPublicKey = () =>
    Buffer.from(getRandomBytes(32)).toString('hex');

type ExtractPS<E extends Executables<any>> = E extends Executables<infer PS> ? PS : never;

export function startContract<
    E extends Executables<any>
>(
    module: { executables: (w: any) => E, zkirDir: string },
    witnessSets: any,
    privateState: ExtractPS<E>,
    ...args: StateConstructorParams<E>
): readonly [E, CircuitContext<ExtractPS<E>>] {

  const exec = module.executables(witnessSets);
  const coinPublicKey = sampleCoinPublicKey();
  const address = ocrt.sampleContractAddress();

  const {
    currentContractState,
    currentPrivateState,
  } = exec.initialState(createConstructorContext(coinPublicKey, privateState), ...args);

  const contractStates = {
    [address]: currentContractState.data,
  };
  const privateStates = {
    [address]: currentPrivateState,
  };

  const context = createCircuitContext(exec.contractId, '', address, coinPublicKey, contractStates, privateStates);

  const wrappedImpureCircuits = {} as E['impureCircuits'];

  for (const [circuitId, circuit] of Object.entries(exec.impureCircuits)) {
    (wrappedImpureCircuits as any)[circuitId] = (context: CircuitContext, ...args: any[]): any => {
      // To prevent from having to specify the circuit being invoked in each 'startContract' usage in the tests, we map circuits to circuits that automatically
      // set the circuit ID. Normally, the user would pass the circuit ID into 'createCircuitContext'.
      context.circuitId = circuitId;
      const circuitResult = (circuit as any)(context, ...args);

      if (!fs.existsSync(module.zkirDir)) {
        throw new Error(`Expected to find ZKIR directory ${module.zkirDir} but it does not exist.`);
      }

      const zkirFile = `${module.zkirDir}/${circuitId}.zkir`;
      if (!fs.existsSync(zkirFile)) {
        throw new Error(`Expected to find ZKIR file ${zkirFile} for circuit ${circuitId} but it does not exist.`);
      }

      const zkir = fs.readFileSync(zkirFile, 'utf-8');
      const proofDataFrame = circuitResult.context.proofDataTrace.at(-1);
      if (!proofDataFrame) {
        throw new Error(`Expected proof data trace to be defined for called circuit ${circuitId}`)
      }
      checkProofData(zkir, proofDataFrame);

      return circuitResult;
    };
  }

  Object.assign(exec, {
    impureCircuits: wrappedImpureCircuits,
    circuits: { ...exec.circuits, ...wrappedImpureCircuits },
  });

  return [exec as unknown as E, context as CircuitContext<ExtractPS<E>>] as const;
}