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
  CircuitContext,
  createConstructorContext,
  createCircuitContext,
  checkProofData,
  WitnessContext,
  ConstructorContext,
  CircuitResults,
  ConstructorResult
} from '@midnight-ntwrk/compact-runtime';

export type Witness<PS> = (context: WitnessContext<any, PS>, ...rest: any[]) => [PS, any];

export type Witnesses<PS> = Record<string, Witness<PS>>;

export type Circuit<PS> = (context: CircuitContext<PS>, ...args: any[]) => CircuitResults<PS, any>;

export type Circuits<PS> = Record<string, Circuit<PS>>;

export type Contract<PS, W extends Witnesses<PS>> = {
  witnesses: W;
  impureCircuits: Circuits<PS>;
  circuits: Circuits<PS>;
  initialState(ctx: ConstructorContext<PS>, ...args: any[]): ConstructorResult<PS>;
}

export type InitialStateParams<
  C extends Contract<any, any>
> = C['initialState'] extends (c: ConstructorContext, ...a: infer A) => any ? A : never;

export type Module<C, W> = {
  Contract: new (witnesses: W) => C;
  zkirDir: string;
}

export function startContract<
  PS,
  W extends Witnesses<PS>,
  C extends Contract<PS, W>
>(module: Module<C, W>,
  witnesses: W,
  privateState: PS,
  ...args: InitialStateParams<C>
): readonly [C, CircuitContext<PS>] {

  const contract = new module.Contract(witnesses);
  const constructorContext = createConstructorContext(privateState, '0'.repeat(64));
  const constructorResult = contract.initialState(constructorContext, ...args);

  const circuitContext = createCircuitContext(
    ocrt.dummyContractAddress(),
    constructorResult.currentZswapLocalState.coinPublicKey,
    constructorResult.currentContractState,
    constructorResult.currentPrivateState,
  );

  const wrappedImpureCircuits = {} as C['impureCircuits'];

  for (const [circuitId, circuit] of Object.entries(contract.impureCircuits)) {
    (wrappedImpureCircuits as any)[circuitId] = (context: any, ...args: any[]): any => {
      const circuitResult = (circuit as any)(context, ...args);

      if (!fs.existsSync(module.zkirDir)) {
        throw new Error(`Expected to find ZKIR directory ${module.zkirDir} but it does not exist.`);
      }

      const zkirFile = `${module.zkirDir}/${circuitId}.zkir`;
      if (!fs.existsSync(zkirFile)) {
        throw new Error(`Expected to find ZKIR file ${zkirFile} for circuit ${circuitId} but it does not exist.`);
      }

      const zkir = fs.readFileSync(zkirFile, 'utf-8');
      checkProofData(zkir, circuitResult.proofData);

      return circuitResult;
    };
  }

  Object.assign(contract, {
    impureCircuits: wrappedImpureCircuits,
    circuits: { ...contract.circuits, ...wrappedImpureCircuits },
  });

  return [contract, circuitContext as CircuitContext<PS>] as const;
}