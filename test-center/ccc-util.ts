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
import * as path from 'node:path';
import {
  CircuitContext,
  CallProofData,
  CircuitResults,
  ConstructorResult,
  ContractStateProvider,
  EncodedContractAddress,
  createConstructorContext,
  createCircuitContext,
} from '@midnight-ntwrk/compact-runtime';
import { checkProofData } from './key-provider.js';
import {
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

/**
 * A deployed contract, as returned by {@link TestChain.deploy}. Mirrors the
 * subset of {@link DeployedDependency} a caller needs to reference the contract
 * in subsequent transactions: its address (how `compact-runtime` identifies a
 * contract) and the encoded form used to pass it as a contract-typed argument.
 */
export interface DeployedContract<C extends Contract<any, any> = Contract<any, any>> {
  module: Module<C, any>;
  address: ocrt.ContractAddress;
  encodedAddress: EncodedContractAddress;
}

/**
 * A deploy transaction: run a contract's constructor and persist the resulting
 * ledger state on the chain. Only the root of a call tree may declare witnesses,
 * so `witnesses` defaults to empty.
 */
export interface DeployTransaction<C extends Contract<any, any>> {
  module: Module<C, any>;
  args: InitialStateParams<C>;
  initialPrivateState: unknown;
  address?: ocrt.ContractAddress;
  witnesses?: Witnesses<any>;
  coinPublicKey?: ocrt.CoinPublicKey;
}

/**
 * A call transaction: invoke `circuitId` on the contract deployed at `address`,
 * starting from that contract's *currently persisted* ledger state.
 *
 * `coinPublicKey`, `gasLimit`, `costModel`, `time` and `parentBlockHash` are the
 * usual transaction-context knobs forwarded to {@link createCircuitContext}.
 */
export interface CallTransaction<PS, W extends Witnesses<PS>, C extends Contract<PS, W>> {
  module: Module<C, W>;
  address: ocrt.ContractAddress;
  circuitId: string;
  args: readonly unknown[];
  witnesses: W;
  privateState: PS;
  coinPublicKey?: ocrt.CoinPublicKey;
  gasLimit?: ocrt.RunningCost;
  costModel?: ocrt.CostModel;
  time?: number;
  parentBlockHash?: string;
}

/**
 * An in-memory simulation of the chain for cross-contract-call tests.
 *
 * `TestChain` models a *sequence of independent transactions* against *mutable*
 * persisted state:
 *
 *   - {@link deploy} corresponds to a deploy transaction: it runs a contract's
 *     constructor and stores the resulting {@link ocrt.ContractState}.
 *   - {@link call} corresponds to a call transaction: it builds a fresh
 *     {@link CircuitContext} seeded from the entry contract's *currently
 *     persisted* state, executes the circuit, and then **commits** the
 *     post-execution state of every contract the transaction touched back into
 *     the store. A later transaction therefore observes the effects of an
 *     earlier one.
 *
 * The chain doubles as the {@link ContractStateProvider}: during a call, any
 * *cross-contract* callee not already present in `queryContexts` is fetched via
 * {@link getContractState}. Note that the runtime always seeds `queryContexts`
 * with the *entry* contract's address (see `createCircuitContext`), so the entry
 * contract's state is taken from the seed passed to {@link createCircuitContext}
 * and is never re-fetched from the provider; only genuine cross-contract callees
 * are. The `blockHash` argument is ignored: the chain holds a single, latest
 * snapshot per address rather than a history.
 */
export class TestChain implements ContractStateProvider {
  private readonly states = new Map<ocrt.ContractAddress, ocrt.ContractState>();
  private readonly contractDirByAddress = new Map<ocrt.ContractAddress, string>();

  /** Number of cross-contract state fetches served, keyed by callee address. */
  private readonly fetchCounts = new Map<ocrt.ContractAddress, number>();

  /**
   * {@link ContractStateProvider} implementation. Used by the runtime to resolve
   * cross-contract callees. Records the fetch so tests can assert that a callee's
   * state genuinely came from the provider rather than from a seeded heap entry.
   */
  async getContractState(
    _blockHash: string,
    address: ocrt.ContractAddress,
  ): Promise<ocrt.ContractState | undefined> {
    const state = this.states.get(address);
    if (state !== undefined) {
      this.fetchCounts.set(address, (this.fetchCounts.get(address) ?? 0) + 1);
    }
    return state;
  }

  /** Fail-fast read of a contract's persisted state for use by the harness/tests. */
  getContractStateOrThrow(address: ocrt.ContractAddress): ocrt.ContractState {
    const state = this.states.get(address);
    if (state === undefined) {
      throw new Error(`No contract deployed at address ${address}`);
    }
    return state;
  }

  /** How many times the provider served a fetch for `address` (0 if never). */
  fetchCount(address: ocrt.ContractAddress): number {
    return this.fetchCounts.get(address) ?? 0;
  }

  /**
   * Execute a deploy transaction and persist the contract's initial ledger state.
   */
  async deploy<C extends Contract<any, any>>(
    tx: DeployTransaction<C>,
  ): Promise<DeployedContract<C>> {
    const contract = new tx.module.Contract(
      (tx.witnesses ?? {}) as Record<string, never>,
    );
    const constructorContext = createConstructorContext(
      tx.initialPrivateState,
      tx.coinPublicKey ?? DEFAULT_COIN_PUBLIC_KEY,
    );
    const constructorResult = (await contract.initialState(
      constructorContext,
      ...(tx.args as unknown[]),
    )) as ConstructorResult<unknown>;

    const address = tx.address ?? ocrt.sampleContractAddress();
    this.states.set(address, constructorResult.currentContractState);
    this.contractDirByAddress.set(address, tx.module.contractDir);

    return {
      module: tx.module,
      address,
      encodedAddress: { bytes: ocrt.encodeContractAddress(address) },
    };
  }

  /**
   * Execute a call transaction. Builds a fresh {@link CircuitContext} seeded from
   * the entry contract's persisted state, runs the circuit, schedules proof checks
   * for the whole call tree, then commits every touched contract's post-execution
   * state back to the store.
   */
  async call<PS, W extends Witnesses<PS>, C extends Contract<PS, W>>(
    tx: CallTransaction<PS, W, C>,
  ): Promise<CircuitResults<PS, unknown>> {
    const entryState = this.getContractStateOrThrow(tx.address);
    const contract = new tx.module.Contract(tx.witnesses);

    const now = tx.time ?? Math.floor(Date.now() / 1_000);
    const context = createCircuitContext(
      tx.circuitId,
      tx.address,
      tx.coinPublicKey ?? DEFAULT_COIN_PUBLIC_KEY,
      entryState,
      tx.privateState,
      this,
      tx.gasLimit,
      tx.costModel,
      now,
      tx.parentBlockHash ?? DEFAULT_PARENT_BLOCK_HASH,
    ) as CircuitContext<PS>;

    const circuits = contract.circuits as Circuits<PS>;
    const impureCircuits = contract.impureCircuits as Circuits<PS>;
    const circuit = impureCircuits[tx.circuitId] ?? circuits[tx.circuitId];
    if (circuit === undefined) {
      throw new Error(
        `Circuit '${tx.circuitId}' not found on contract deployed at ${tx.address}`,
      );
    }

    const result = (await circuit(
      context,
      ...tx.args,
    )) as CircuitResults<PS, unknown>;

    // The fresh context starts with an empty trace, so every entry the call
    // produced — the root circuit plus every cross-contract sub-call — is checked.
    scheduleProofChecks(result, 0, this.contractDirByAddress);

    this.commit(result.context);

    return result;
  }

  /**
   * Persist the post-execution ledger state of every contract the transaction
   * touched. After a circuit finishes, `queryContexts[address].state` holds that
   * contract's final {@link ocrt.ChargedState} (the root via
   * `finalizeCallProofData`, each callee via the same path on return). We splice
   * that charged state into the contract's stored {@link ocrt.ContractState}.
   */
  private commit(context: CircuitContext<any>): void {
    for (const [address, queryContext] of Object.entries(context.queryContexts)) {
      const state = this.getContractStateOrThrow(address);
      state.data = queryContext.state;
      this.states.set(address, state);
    }
  }
}
