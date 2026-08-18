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
import { createHash } from 'node:crypto';
import * as fs from 'node:fs';
import * as path from 'node:path';
import {
  CircuitContext,
  CallProofData,
  CircuitResults,
  ConstructorResult,
  ContractModuleProvider,
  ContractStateProvider,
  EncodedContractAddress,
  Module as RuntimeModule,
  ModuleThunk,
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

/**
 * A real compiled verifier key, kept for its envelope alone. The ledger validates the envelope and
 * never parses the payload, so {@link deployedVerifierKey} can replace the payload and know nothing
 * about the format. See `fixtures/verifier-keys/README.md`.
 */
const VERIFIER_KEY_TEMPLATE: Uint8Array = new Uint8Array(
  fs.readFileSync(new URL('./fixtures/verifier-keys/template.verifier', import.meta.url)),
);

/**
 * How many trailing bytes {@link deployedVerifierKey} replaces: one SHA-256 digest. Taken from the
 * end, so the tag and the prefix survive without being located, and the length never changes.
 */
const VERIFIER_KEY_FILL_LENGTH = 32;

// The tail fill assumes that the tail is payload rather than envelope.
if (VERIFIER_KEY_TEMPLATE.length < 256) {
  throw new Error(
    `The verifier key template is ${VERIFIER_KEY_TEMPLATE.length} bytes, and its last ` +
      `${VERIFIER_KEY_FILL_LENGTH} are taken to be payload. Replace it with a real compiled key.`,
  );
}

/**
 * The key the harness installs on one deployed operation: the template, with its tail replaced by a
 * digest of `(contractDir, circuitId)`. Keyed the way a real verifier key is derived, so two
 * deployments of one contract carry the same keys and two circuits never do.
 */
const deployedVerifierKey = (contractDir: string, circuitId: string): Uint8Array => {
  const key = Uint8Array.from(VERIFIER_KEY_TEMPLATE);
  const fill = createHash('sha256').update(`${contractDir}:${circuitId}`).digest();
  key.set(fill.subarray(0, VERIFIER_KEY_FILL_LENGTH), key.length - VERIFIER_KEY_FILL_LENGTH);
  return key;
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
      // Only a circuit with public operations gets a zkir, so an empty public transcript means
      // there is nothing to check. A missing zkir with a non-empty one is a real failure.
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

/** A deployed contract, as returned by {@link TestChain.deploy}. */
export interface DeployedContract<C extends Contract<any, any> = Contract<any, any>> {
  /**
   * The module the provider returns for {@link address}. Its `expectedVk` is the harness's: this
   * suite compiles with `skip-zk`, so the staged module's own is `{}`.
   */
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
 * A call transaction: invoke `circuitId` on the contract deployed at `address`, starting from that
 * contract's currently persisted ledger state. The optional fields are forwarded to
 * {@link createCircuitContext}.
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
 * An in-memory chain for cross-contract-call tests: a sequence of independent transactions against
 * mutable persisted state. A call commits the post-execution state of every contract it touched, so
 * a later transaction sees an earlier one's effects.
 *
 * It serves as both providers. As {@link ContractStateProvider} it answers for cross-contract
 * callees only — the runtime seeds the entry contract itself — and ignores `blockHash`, since it
 * holds one snapshot per address rather than a history. As {@link ContractModuleProvider} it binds
 * each deployed address to its module, and installs verifier keys so key agreement has both sides to
 * compare.
 */
export class TestChain implements ContractStateProvider, ContractModuleProvider {
  private readonly states = new Map<ocrt.ContractAddress, ocrt.ContractState>();
  private readonly contractDirByAddress = new Map<ocrt.ContractAddress, string>();
  private readonly moduleByAddress = new Map<ocrt.ContractAddress, ModuleThunk>();

  /** Number of cross-contract state fetches served, keyed by callee address. */
  private readonly fetchCounts = new Map<ocrt.ContractAddress, number>();

  /**
   * {@link ContractStateProvider}. Records the fetch, so a test can assert a callee's state came
   * from the provider rather than a seeded entry.
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

  /**
   * {@link ContractModuleProvider}. A deploy records its module, so the chain can hand it back when
   * a call resolves that address. An address nothing was deployed at returns `undefined`.
   */
  resolve(calleeAddress: ocrt.ContractAddress): ModuleThunk | undefined {
    return this.moduleByAddress.get(calleeAddress);
  }

  /**
   * Binds an address to a module the chain did not deploy, so a test can hand the runtime a callee
   * that disagrees with what is on chain.
   */
  overrideModule(address: ocrt.ContractAddress, module: RuntimeModule): void {
    this.moduleByAddress.set(address, () => Promise.resolve(module));
  }

  /**
   * Installs a verifier key on every operation of a fresh contract state, and returns the
   * fingerprints of the bytes installed. Two deployments of one contract get the same keys, as they
   * would on chain, so a disagreeing module is one for different code rather than a numbering
   * artifact.
   *
   * The fingerprints are computed here rather than with the runtime's `verifierKeyHashOf`, so a
   * deployment whose two sides agree is two implementations agreeing rather than one repeated.
   */
  private installVerifierKeys(state: ocrt.ContractState, contractDir: string): Record<string, string> {
    const expectedVk: Record<string, string> = {};
    for (const entryPoint of state.operations()) {
      const circuitId = typeof entryPoint === 'string' ? entryPoint : Buffer.from(entryPoint).toString();
      const operation = state.operation(entryPoint);
      if (operation === undefined) {
        throw new Error(`Operation '${circuitId}' vanished between listing and lookup`);
      }
      const key = deployedVerifierKey(contractDir, circuitId);
      operation.verifierKey = key;
      state.setOperation(entryPoint, operation);
      expectedVk[circuitId] = createHash('sha256').update(key).digest('hex');
    }
    return expectedVk;
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
    const expectedVk = this.installVerifierKeys(constructorResult.currentContractState, tx.module.contractDir);
    const module: Module<C, any> = { ...tx.module, expectedVk };
    this.states.set(address, constructorResult.currentContractState);
    this.contractDirByAddress.set(address, tx.module.contractDir);
    this.moduleByAddress.set(address, () => Promise.resolve(module));

    return {
      module,
      address,
      encodedAddress: { bytes: ocrt.encodeContractAddress(address) },
    };
  }

  /**
   * Executes a call transaction: seeds a context from the entry contract's persisted state, runs the
   * circuit, schedules proof checks for the call tree, then commits every touched contract.
   */
  async call<PS, W extends Witnesses<PS>, C extends Contract<PS, W>>(
    tx: CallTransaction<PS, W, C>,
  ): Promise<CircuitResults<PS, unknown>> {
    const entryState = this.getContractStateOrThrow(tx.address);
    const contract = new tx.module.Contract(tx.witnesses);

    const now = tx.time ?? Math.floor(Date.now() / 1_000);
    const context = createCircuitContext({
      circuitId: tx.circuitId,
      contractAddress: tx.address,
      coinPublicKeyOrZswapState: tx.coinPublicKey ?? DEFAULT_COIN_PUBLIC_KEY,
      contractState: entryState,
      privateState: tx.privateState,
      gasLimit: tx.gasLimit,
      costModel: tx.costModel,
      time: now,
      parentBlockHash: tx.parentBlockHash ?? DEFAULT_PARENT_BLOCK_HASH,
      crossContract: { stateProvider: this, moduleProvider: this },
    }) as CircuitContext<PS>;

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
   * Persists every touched contract's final ledger state. `queryContexts[address].state` holds it
   * once a circuit finishes, and it is spliced into the stored {@link ocrt.ContractState}.
   */
  private commit(context: CircuitContext<any>): void {
    for (const [address, queryContext] of Object.entries(context.queryContexts)) {
      const state = this.getContractStateOrThrow(address);
      state.data = queryContext.state;
      this.states.set(address, state);
    }
  }
}
