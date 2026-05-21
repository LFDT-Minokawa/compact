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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v3';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  CircuitContext,
  CallProofData,
  CallProofDataTrace,
  CircuitResults,
  ConstructorResult,
  ContractStateProvider,
  EncodedContractAddress,
  createConstructorContext,
  createCircuitContext,
} from '@midnight-ntwrk/compact-runtime';
import { checkProofData } from './key-provider.js';
import {
  Circuit,
  Circuits,
  Contract,
  InitialStateParams,
  Module,
  Witnesses,
  registerProofCheck,
} from './util.js';

export { registerProofCheck, flushProofChecks } from './util.js';
export type {
  Circuit,
  Circuits,
  Contract,
  InitialStateParams,
  Module,
  Witness,
  Witnesses,
} from './util.js';

const DEFAULT_COIN_PUBLIC_KEY: ocrt.CoinPublicKey = '0'.repeat(64);

const DEFAULT_PARENT_BLOCK_HASH = '0'.repeat(64);

export class RecordContractStateProvider implements ContractStateProvider {
  private readonly states: Record<ocrt.ContractAddress, ocrt.ContractState>;

  constructor(initial: Record<ocrt.ContractAddress, ocrt.ContractState> = {}) {
    // Shallow copy so later mutations to `initial` don't affect us.
    this.states = { ...initial };
  }

  async getContractState(_blockHash: string, address: ocrt.ContractAddress): Promise<ocrt.ContractState | undefined> {
    return this.states[address];
  }
}

/**
 * Specification for deploying a single non-root contract.
 */
export interface DependencyDeployment<C extends Contract<any, any>> {
  module: Module<C, any>;
  args: InitialStateParams<C>;
  address?: ocrt.ContractAddress;
  coinPublicKey?: ocrt.CoinPublicKey;
  initialPrivateState?: unknown;
}

/**
 * The result of deploying a single dependency
 */
export interface DeployedDependency<C extends Contract<any, any> = Contract<any, any>> {
  contract: C;
  module: Module<C, any>;
  address: ocrt.ContractAddress;
  encodedAddress: EncodedContractAddress;
  constructorResult: ConstructorResult<unknown>;
}

/**
 * Specification for the root contract — the only contract permitted to declare witnesses
 */
export interface RootDeployment<PS, W extends Witnesses<PS>, C extends Contract<PS, W>> {
  module: Module<C, W>;
  witnesses: W;
  initialPrivateState: PS;
  args: InitialStateParams<C>;
  address?: ocrt.ContractAddress;
  coinPublicKey?: ocrt.CoinPublicKey;
  stateProvider?: ContractStateProvider;
  gasLimit?: ocrt.RunningCost;
  costModel?: ocrt.CostModel;
  time?: number;
  parentBlockHash?: string;
}

/**
 * Deploy a single dependency contract.
 */
export const deployDependency = async <C extends Contract<any, any>>(
  spec: DependencyDeployment<C>,
): Promise<DeployedDependency<C>> => {
  const contract = new spec.module.Contract({} as Record<string, never>);
  const constructorContext = createConstructorContext(
    spec.initialPrivateState,
    spec.coinPublicKey ?? DEFAULT_COIN_PUBLIC_KEY,
  );
  const constructorResult = (await contract.initialState(
    constructorContext,
    ...(spec.args as unknown[]),
  )) as ConstructorResult<unknown>;
  const address = spec.address ?? ocrt.sampleContractAddress();
  return {
    contract,
    module: spec.module,
    address,
    encodedAddress: { bytes: ocrt.encodeContractAddress(address) },
    constructorResult,
  };
};

/**
 * Start a CCC-aware test environment.
 */
export const startContractGroup = async <
  PS,
  W extends Witnesses<PS>,
  C extends Contract<PS, W>
>(
  root: RootDeployment<PS, W, C>,
  deps: ReadonlyArray<DeployedDependency> = [],
): Promise<readonly [C, CircuitContext<PS>]> => {

  const now = root.time ?? Math.floor(Date.now() / 1_000);

  const contract = new root.module.Contract(root.witnesses);
  const constructorContext = createConstructorContext(
    root.initialPrivateState,
    root.coinPublicKey ?? DEFAULT_COIN_PUBLIC_KEY,
  );
  const constructorResult = await contract.initialState(
    constructorContext,
    ...(root.args as unknown[]),
  );

  const rootAddress = root.address ?? ocrt.sampleContractAddress();

  const stateProvider: ContractStateProvider =
    root.stateProvider ??
    new RecordContractStateProvider(
      Object.fromEntries(
        deps.map((dep) => [
          dep.address,
          dep.constructorResult.currentContractState,
        ]),
      ),
    );

  const parentBlockHash = root.parentBlockHash ?? DEFAULT_PARENT_BLOCK_HASH;
  const circuitContext = createCircuitContext(
    'constructor',
    rootAddress,
    constructorResult.currentZswapLocalState.coinPublicKey,
    constructorResult.currentContractState,
    constructorResult.currentPrivateState,
    stateProvider,
    root.gasLimit,
    root.costModel,
    now,
    parentBlockHash,
  );

  const contractDirByAddress = new Map<ocrt.ContractAddress, string>();
  contractDirByAddress.set(rootAddress, root.module.contractDir);
  for (const dep of deps) {
    contractDirByAddress.set(dep.address, dep.module.contractDir);
  }

  const wrappedImpureCircuits = {} as Circuits<PS>;
  for (const [circuitId, circuit] of Object.entries(contract.impureCircuits)) {
    const wrapped: Circuit<PS> = async (context, ...cArgs) => {
      context.callContext.circuitId = circuitId;
      const traceLengthBefore = context.callProofDataTrace.length;
      const circuitResult = await (circuit as Circuit<PS>)(context, ...cArgs);
      scheduleProofChecks(circuitResult, traceLengthBefore, contractDirByAddress);
      return circuitResult;
    };
    (wrappedImpureCircuits as Record<string, Circuit<PS>>)[circuitId] = wrapped;
  }
  const wrappedCircuits = {
    ...contract.circuits,
    ...wrappedImpureCircuits,
  } as Circuits<PS>;
  Object.assign(contract, {
    impureCircuits: wrappedImpureCircuits,
    circuits: wrappedCircuits,
  });

  return [contract as C, circuitContext as CircuitContext<PS>] as const;
};

export const scheduleProofChecks = (
  circuitResults: CircuitResults<unknown, unknown>,
  traceLengthBefore: number,
  contractDirByAddress: ReadonlyMap<ocrt.ContractAddress, string>,
): void => {
  const trace = circuitResults.context.callProofDataTrace;
  for (let i = traceLengthBefore; i < trace.length; i++) {
    const entry = trace[i];
    const contractDir = contractDirByAddress.get(entry.contractAddress);
    if (contractDir === undefined) {
      throw new Error(`Contract directory undefined for ${entry.contractAddress}`)
    }
    const zkirFile = path.join(contractDir, 'zkir', `${entry.circuitId}.zkir`);
    if (!fs.existsSync(zkirFile)) {
      // A circuit produces a .zkir file only when it performs public
      // operations (ledger access or cross-contract calls). A witness-only
      // circuit — one whose proof obligations are entirely private — has an
      // empty public transcript and legitimately produces no zkir, so there
      // is nothing to check against; skip it. Any other missing zkir means a
      // circuit that should have one does not: a genuine harness/compiler
      // failure we still want to surface.
      if (entry.publicTranscript.length === 0) {
        continue;
      }
      throw new Error(`ZKIR file not found for circuit ${entry.circuitId} at expected path ${zkirFile}`);
    }
    registerProofCheck(checkCallProofData(entry, contractDir));
  }
};

export const checkCallProofData = async (
  entry: CallProofData,
  contractDir: string,
): Promise<void> => {
  await checkProofData(contractDir, entry.circuitId, entry);
};
