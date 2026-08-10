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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import * as fs from 'node:fs';
import {
  CircuitContext,
  createConstructorContext,
  createCircuitContext,
  WitnessContext,
  ConstructorContext,
  CircuitResults,
  ConstructorResult,
  Module as RuntimeModule
} from '@midnight-ntwrk/compact-runtime';
import { checkProofData } from './key-provider.js';

export type Witness<PS> = (context: WitnessContext<any, PS>, ...rest: any[]) => [PS, any];
export type Witnesses<PS> = Record<string, Witness<PS>>;
export type Circuit<PS> = (context: CircuitContext<PS>, ...args: any[]) => Promise<CircuitResults<PS, any>>;
export type Circuits<PS> = Record<string, Circuit<PS>>;

/**
 * An instance of a generated `Contract` class, as a test uses one. Wider than the runtime's
 * `ContractInstance`, which needs only `provableCircuits` because a cross-contract callee is entered
 * through nothing else. A test also constructs the contract and calls its circuits directly.
 */
export type Contract<PS, W extends Witnesses<PS>> = {
  witnesses: W;
  impureCircuits: Circuits<PS>;
  circuits: Circuits<PS>;
  provableCircuits: Circuits<PS>;
  initialState(ctx: ConstructorContext<PS>, ...args: any[]): Promise<ConstructorResult<PS>>;
};

export type InitialStateParams<
  C extends Contract<any, any>
> = C['initialState'] extends (c: ConstructorContext, ...a: infer A) => any ? A : never;

/**
 * A generated contract module as `stage-javascript` hands it to a test: everything the runtime
 * resolves a cross-contract callee to, plus where the compiled output was staged.
 */
export type Module<C, W> = Omit<RuntimeModule, 'Contract'> & {
  Contract: new (witnesses: W) => C;
  contractDir: string;
};

/** Pending proof validations scheduled by circuit calls (module-singleton). */
const pending = new Set<Promise<void>>();

/**
 * How long one proof check may run before it counts as a failure. A wasm trap can leave its promise
 * permanently unsettled, and `Promise.allSettled` would then wait forever. Keep it under vitest's
 * `hookTimeout` so this fires first, with a precise message; a real check finishes in well under a
 * second.
 */
const PROOF_CHECK_TIMEOUT_MS = 10_000;

/** Races `p` against a timeout, so a check that never settles rejects instead of hanging. */
const withTimeout = (p: Promise<void>, ms: number): Promise<void> => {
  let timer: ReturnType<typeof setTimeout> | undefined;
  const timeout = new Promise<void>((_, reject) => {
    timer = setTimeout(
      () => reject(new Error(`proof check timed out after ${ms}ms`)),
      ms,
    );
  });
  return Promise.race([p, timeout]).finally(() => clearTimeout(timer));
};

/**
 * Queues a proof check to be reported by {@link flushProofChecks}. Handlers are attached now, so a
 * rejection is never unhandled, and the promise drops out of the queue once it settles.
 */
export const registerProofCheck = (p: Promise<void>): void => {
  const guarded = withTimeout(p, PROOF_CHECK_TIMEOUT_MS);
  let wrapped: Promise<void>;
  wrapped = guarded.then(
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

export const startContract = async <
  PS,
  W extends Witnesses<PS>,
  C extends Contract<PS, W>
>(
  module: Module<C, W>,
  witnesses: W,
  privateState: PS,
  ...args: InitialStateParams<C>
): Promise<readonly [C, CircuitContext<PS>]> => {

  const contract = new module.Contract(witnesses);

  const constructorContext = createConstructorContext(privateState, '0'.repeat(64));
  const constructorResult = await contract.initialState(constructorContext, ...args);

  const circuitContext = createCircuitContext(
    'constructor',
    ocrt.sampleContractAddress(),
    constructorResult.currentZswapLocalState.coinPublicKey,
    constructorResult.currentContractState,
    constructorResult.currentPrivateState,
  );

  const wrappedImpureCircuits = {} as C['impureCircuits'];

  for (const [circuitId, circuit] of Object.entries(contract.impureCircuits)) {
    (wrappedImpureCircuits as any)[circuitId] = async (context: any, ...cArgs: any[]): Promise<any> => {
      context.callContext.circuitId = circuitId;
      const circuitResult = await (circuit as any)(context, ...cArgs);
      // For circuits subject to proving, schedule async proof validation and register it globally.
      const zkirFile = `${module.contractDir}/zkir/${circuitId}.zkir`;
      if (fs.existsSync(zkirFile)) {
        const validation = (async () => {
          await checkProofData(module.contractDir, circuitId, circuitResult.context.callProofDataTrace.at(-1));
        })();

        registerProofCheck(validation);
      }

      return circuitResult;
    };
  }

  // Pure circuits go through as-is (no validation).
  const wrappedCircuits = { ...contract.circuits, ...wrappedImpureCircuits } as C['circuits'];

  // `provableCircuits` is left unwrapped: a cross-contract callee is entered through it, and those
  // are checked through `TestChain`.
  Object.assign(contract, {
    impureCircuits: wrappedImpureCircuits,
    circuits: wrappedCircuits,
  });

  return [contract as C, circuitContext as CircuitContext<PS>] as const;
}
