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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';
import * as fs from 'node:fs';
import {
  CircuitContext,
  createConstructorContext,
  createCircuitContext,
  WitnessContext,
  ConstructorContext,
  CircuitResults,
  ConstructorResult
} from '@midnight-ntwrk/compact-runtime';
import { checkProofData } from './key-provider.js';

export type Witness<PS> = (context: WitnessContext<any, PS>, ...rest: any[]) => [PS, any];
export type Witnesses<PS> = Record<string, Witness<PS>>;
export type Circuit<PS> = (context: CircuitContext<PS>, ...args: any[]) => CircuitResults<PS, any>;
export type Circuits<PS> = Record<string, Circuit<PS>>;

export type Contract<PS, W extends Witnesses<PS>> = {
  witnesses: W;
  impureCircuits: Circuits<PS>;
  circuits: Circuits<PS>;
  initialState(ctx: ConstructorContext<PS>, ...args: any[]): ConstructorResult<PS>;
};

export type InitialStateParams<
  C extends Contract<any, any>
> = C['initialState'] extends (c: ConstructorContext, ...a: infer A) => any ? A : never;

export type Module<C, W> = {
  Contract: new (witnesses: W) => C;
  contractDir: string;
};

/** Pending proof validations scheduled by circuit calls (module-singleton). */
const pending = new Set<Promise<void>>();

/**
 * Register a proof-check promise so we can fail a test at a controlled boundary.
 * Attaches handlers immediately to avoid unhandled-rejection noise and
 * auto-removes the promise from the queue upon settlement.
 */
export const registerProofCheck = (p: Promise<void>): void => {
  let wrapped: Promise<void>;
  wrapped = p.then(
    () => { pending.delete(wrapped); },
    (e) => { pending.delete(wrapped); throw e; }
  );
  pending.add(wrapped);
}

/**
 * Wait for all scheduled proof checks. If any failed, throw the first error.
 * Call this once per-test from a Vitest `afterEach` in your setup file.
 */
export const flushProofChecks = async (): Promise<void> => {
  const results = await Promise.allSettled(Array.from(pending));
  pending.clear();
  const rejected = results.find((r): r is PromiseRejectedResult => r.status === 'rejected');
  if (rejected) throw rejected.reason;
}

export const startContract = <
  PS,
  W extends Witnesses<PS>,
  C extends Contract<PS, W>
>(
  module: Module<C, W>,
  witnesses: W,
  privateState: PS,
  ...args: InitialStateParams<C>
): readonly [C, CircuitContext<PS>] => {

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
    (wrappedImpureCircuits as any)[circuitId] = (context: any, ...cArgs: any[]): any => {
      // Execute the original circuit synchronously.
      const circuitResult = (circuit as any)(context, ...cArgs);

      // For circuits subject to proving, schedule async proof validation and register it globally.
      const zkirFile = `${module.contractDir}/zkir/${circuitId}.zkir`;
      if (fs.existsSync(zkirFile)) {
        const validation = (async () => {
          await checkProofData(module.contractDir, circuitId, circuitResult.proofData);
        })();

        registerProofCheck(validation);
      }

      return circuitResult;
    };
  }

  // Pure circuits go through as-is (no validation).
  const wrappedCircuits = { ...contract.circuits, ...wrappedImpureCircuits } as C['circuits'];

  Object.assign(contract, {
    impureCircuits: wrappedImpureCircuits,
    circuits: wrappedCircuits,
  });

  return [contract as C, circuitContext as CircuitContext<PS>] as const;
}
