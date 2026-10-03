// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  emptyZswapLocalState,
  EncodedCoinPublicKey,
  EncodedZswapLocalState,
  ZswapLocalState,
  encodeZswapLocalState,
} from './zswap.js';
import { PartialProofData, ProofData } from './proof-data.js';
import { CompactError, assertDefined } from './error.js';
import { createLocalQueryContext } from './local-state.js';
import { ContractModuleProvider, ContractStateProvider, HostInterfaceProvider, LocalStateProvider } from './providers.js';

export type CircuitId = string;

export interface CommunicationCommitmentData {
  /**
   * Communication commitment computed by the parent.
   */
  commComm: ocrt.CommunicationCommitment;
  /**
   * Randomness used by the parent in the commitment.
   */
  commCommRand: ocrt.CommunicationCommitmentRand;
}

export interface CallProofData extends ProofData {
  /**
   * The ID of the circuit that was called.
   */
  circuitId: CircuitId;
  /**
   * The address of the contract defining the circuit for which this proof data is pertinent.
   */
  contractAddress: ocrt.ContractAddress;
  /**
   * The ledger state of the contract before the circuit was called.
   */
  initialQueryContext: ocrt.QueryContext;
  /**
   * The ledger state of the contract when the circuit finished.
   */
  finalQueryContext: ocrt.QueryContext;
  /**
   * The shielded coins this contract consumed and produced. Recorded per call, not just for the
   * root, so an input or output can be attributed to the contract that made it.
   */
  zswapLocalState: EncodedZswapLocalState;
  /**
   * Data included by the parent call only if this was a sub-call
   */
  commCommData?: CommunicationCommitmentData;
}

export interface CallContext {
  /**
   * The ID of the circuit that was called.
   */
  circuitId: CircuitId;
  /**
   * The address of the contract defining the circuit for which this proof data is pertinent.
   */
  contractAddress: ocrt.ContractAddress;
  /**
   * The initial query context of the currently executing contract.
   */
  initialQueryContext: ocrt.QueryContext;
  /**
   * The current query context of the currently executing contract.
   */
  currentQueryContext: ocrt.QueryContext;
  /**
   * The current running gas cost of the currently executing contract.
   */
  currentGasCost: ocrt.RunningCost;
  /**
   * The current Zswap local state. Tracks inputs and outputs produced during circuit execution.
   */
  currentZswapLocalState: EncodedZswapLocalState | undefined;
  /**
   * The contract's local (private) state, threaded through {@link queryLocalState}, and aliased by
   * {@link CircuitContext.localQueryContexts} under the contract's address. For the entry contract it
   * is the `localState` option; for a cross-contract callee it is installed before the callee's
   * wrapper runs, from the account's {@link LocalStateProvider} or, at the capsule's first touch,
   * the callee's declaration defaults. Absent when the contract keeps no local state, so a contract
   * without a local half pays nothing.
   */
  currentLocalQueryContext: ocrt.QueryContext | undefined;
  /**
   * The hash of the parent block on which we're building this transaction. Used to fetch contract states dynamically.
   */
  parentBlockHash?: string;
  /**
   * The current time the circuits will assume.
   */
  time: number;
}

/**
 * List of data needed to construct proofs and transactions for all circuit calls
 * resulting from executing a root circuit. The calls are in depth-first traversal order.
 * In other words, the first circuit to complete execution is first, and the last circuit
 * to complete execution (the root circuit) is last.
 */
export type CallProofDataTrace = CallProofData[];

/**
 * A `GatherResult` narrowed to log emissions, tagged with the address of the contract
 * that emitted it; `content` is the encoded `VersionedLogItem` array.
 */
export type LogEvent = Extract<ocrt.GatherResult, { tag: 'log' }>['content'] & {
  address: ocrt.ContractAddress;
};

/**
 * The external information accessible from within a Compact circuit call
 */
export interface CircuitContext {
  /**
   * The context for the current call.
   */
  callContext: CallContext;
  /**
   * The current query context of every contract in the call tree.
   */
  queryContexts: Record<ocrt.ContractAddress, ocrt.QueryContext>;
  /**
   * The current gas costs for every contract in the call tree.
   */
  gasCosts: Record<ocrt.ContractAddress, ocrt.RunningCost>;
  /**
   * The current Zswap local state of every contract in the call tree, keyed like
   * {@link queryContexts}. Each contract has its own `currentIndex`, `inputs` and `outputs`; only
   * the submitter's `coinPublicKey` is shared, since one wallet pays for the transaction.
   */
  zswapLocalStates: Record<ocrt.ContractAddress, EncodedZswapLocalState>;
  /**
   * The current local state of every contract in the call tree that keeps one, keyed like
   * {@link queryContexts}: each entry is the capsule `(this account, address)` as the call tree has
   * advanced it. The entry contract's is seeded from the `localState` option; a callee's is installed
   * at its first entry in the transaction and reused by a later sequential call to the same address.
   * `.state.state` of an entry is the `StateValue` an application persists or folds against.
   */
  localQueryContexts: Record<ocrt.ContractAddress, ocrt.QueryContext>;
  /**
   * The deployed state of every cross-contract callee, keyed by address and filled on first
   * resolution. The cached query context keeps only ledger data, so this is where a callee's
   * verifier keys are read from, for any of its circuits and on every call. The entry contract is
   * always on the call stack, so the re-entrancy guard keeps it out of callee position and it never
   * appears here.
   */
  contractStates?: Record<ocrt.ContractAddress, ocrt.ContractState>;
  /**
   * The cost model to use for the execution.
   */
  costModel: ocrt.CostModel;
  /**
   * Sequence of calls made during the execution of the circuit (including the call for the root circuit).
   */
  callProofDataTrace: CallProofDataTrace;
  /**
   * The gas limit for this circuit.
   */
  gasLimit?: ocrt.RunningCost;
  /**
   * Can fetch the current state of a contract from the blockchain.
   */
  stateProvider?: ContractStateProvider;
  /**
   * The {@link ContractModuleProvider}. Absent unless the execution can make cross-contract calls;
   * reaching {@link crossContractCall} without one is a `ModuleProviderAbsent` failure.
   */
  moduleProvider?: ContractModuleProvider;
  /**
   * The {@link LocalStateProvider}. Absent unless the execution can call into contracts that keep
   * local state; resolving such a callee without one is a `LocalStateProviderAbsent` failure.
   */
  localStateProvider?: LocalStateProvider;
  /**
   * The {@link HostInterfaceProvider} answering every host call in the call tree, the root's and
   * its callees'. Absent unless some contract in the tree declares host functions: a root that
   * does fails at entry without one, a callee at resolution (`HostInterfaceProviderAbsent`).
   */
  hostInterfaceProvider?: HostInterfaceProvider;
  /**
   * The contract addresses currently executing: the entry contract, plus every callee whose call
   * has not returned. Shared by reference across the call tree, so {@link crossContractCall} can
   * reject re-entry (`A -> A`, `A -> B -> A`) from any depth.
   */
  activeContracts?: Set<ocrt.ContractAddress>;
  /**
   * Events the VM emitted from `log` operations, each tagged with the contract that emitted it.
   * One list for the whole call tree, threaded like {@link callProofDataTrace}.
   */
  events: LogEvent[];
}

/**
 * The inputs that let an execution make cross-contract calls.
 */
export type CrossContractInputs = {
  /** Fetches a callee's deployed state at {@link CircuitContextOptions.parentBlockHash}. */
  readonly stateProvider: ContractStateProvider;
  /** The {@link ContractModuleProvider}. */
  readonly moduleProvider: ContractModuleProvider;
  /**
   * The {@link LocalStateProvider}: this account's capsules, for callees that keep local state.
   * Optional because an execution whose callees keep none needs no account; a callee that does
   * fails resolution without one.
   */
  readonly localStateProvider?: LocalStateProvider;
};

/** The inputs to {@link createCircuitContext}. */
export type CircuitContextOptions = {
  /** The name of the circuit being executed. */
  readonly circuitId: CircuitId;
  /** The address of the contract defining the circuit being executed. */
  readonly contractAddress: ocrt.ContractAddress;
  /** The initial Zswap local state, for tracking shielded coin transfers. */
  readonly coinPublicKeyOrZswapState:
    | ocrt.CoinPublicKey
    | EncodedCoinPublicKey
    | ZswapLocalState
    | EncodedZswapLocalState;
  /** The ledger state to execute against — most often a snapshot fetched from the chain. */
  readonly contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState;
  /**
   * The contract's local state, as a `StateValue` — most often a snapshot reconstructed by folding
   * local transcripts. Omit it for a contract with no local half.
   */
  readonly localState?: ocrt.StateValue;
  /** The maximum gas this contract should consume. */
  readonly gasLimit?: ocrt.RunningCost;
  /** The model capturing how much ledger operations cost. */
  readonly costModel?: ocrt.CostModel;
  /** The current time, for the block-time kernel operations. Defaults to now. */
  readonly time?: number;
  /**
   * The hash of the block this transaction is built on. Reaches the VM's block context, and pins
   * the block a cross-contract callee's state is fetched at.
   */
  readonly parentBlockHash?: string;
  /**
   * Resolves the host interfaces the contracts in the call tree declare — the wallet's answer for
   * the account that is transacting. Required when any of them declares host functions, the
   * standard library's coin operations included.
   */
  readonly hostInterfaceProvider?: HostInterfaceProvider;
  /** Present exactly when this execution may make cross-contract calls. */
  readonly crossContract?: CrossContractInputs;
};

/**
 * Entry point for constructing the {@link CircuitContext} to pass as an argument to a circuit. Always
 * use this function to set up the initial circuit context.
 */
export const createCircuitContext = ({
  circuitId,
  contractAddress,
  coinPublicKeyOrZswapState,
  contractState,
  localState,
  gasLimit,
  costModel,
  time,
  parentBlockHash,
  hostInterfaceProvider,
  crossContract,
}: CircuitContextOptions): CircuitContext => {
  const callContext = createCallContext(
    circuitId,
    contractAddress,
    coinPublicKeyOrZswapState,
    contractState,
    time,
    parentBlockHash,
  );
  const localQueryContext = localState ? createLocalQueryContext(localState) : undefined;
  callContext.currentLocalQueryContext = localQueryContext;
  // The per-address maps below must alias *this* call context's cells, so a write through either
  // route is visible from the other. (They previously indexed a second, separately-constructed
  // call context, which held distinct `QueryContext` objects.)
  const zswapLocalState = callContext.currentZswapLocalState;
  assertDefined(zswapLocalState, `initial Zswap local state for contract '${contractAddress}'`);
  return {
    callContext,
    queryContexts: { [contractAddress]: callContext.currentQueryContext },
    gasCosts: { [contractAddress]: callContext.currentGasCost },
    zswapLocalStates: { [contractAddress]: zswapLocalState },
    localQueryContexts: localQueryContext === undefined ? {} : { [contractAddress]: localQueryContext },
    contractStates: {},
    costModel: costModel ?? ocrt.CostModel.initialCostModel(),
    callProofDataTrace: [],
    gasLimit,
    stateProvider: crossContract?.stateProvider,
    moduleProvider: crossContract?.moduleProvider,
    localStateProvider: crossContract?.localStateProvider,
    hostInterfaceProvider,
    activeContracts: new Set([contractAddress]),
    events: [],
  };
};

/**
 * @internal
 */
export const copyCircuitContext = (context: CircuitContext): CircuitContext => ({
  // `activeContracts` falls through the spread. Shared by reference on purpose — do not copy it.
  ...context,
  callContext: { ...context.callContext },
  queryContexts: { ...context.queryContexts },
  gasCosts: { ...context.gasCosts },
  zswapLocalStates: { ...context.zswapLocalStates },
  localQueryContexts: { ...context.localQueryContexts },
  contractStates: { ...context.contractStates },
  callProofDataTrace: [...context.callProofDataTrace],
  events: [...context.events],
});

/**
 * @internal
 */
export const finalizeCallProofData = (circuitContext: CircuitContext, proofData: ProofData): void => {
  const contractAddress = circuitContext.callContext.contractAddress;
  const initialQueryContext = circuitContext.callContext.initialQueryContext;
  const currentQueryContext = circuitContext.callContext.currentQueryContext;

  const zswapLocalState = circuitContext.callContext.currentZswapLocalState;

  assertDefined(initialQueryContext, `initial ledger context for contract '${contractAddress}'`);
  assertDefined(currentQueryContext, `current ledger context for contract '${contractAddress}'`);
  assertDefined(zswapLocalState, `Zswap local state for contract '${contractAddress}'`);

  circuitContext.callProofDataTrace.push({
    ...proofData,
    circuitId: circuitContext.callContext.circuitId,
    contractAddress,
    initialQueryContext,
    finalQueryContext: currentQueryContext,
    zswapLocalState,
  });
};

/**
 * @internal
 */
const coerceToChargedState = (contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState): ocrt.ChargedState => {
  let state;
  if (contractState instanceof ocrt.ChargedState) {
    state = contractState;
  } else if (contractState instanceof ocrt.ContractState) {
    state = contractState.data;
  } else if (contractState instanceof ocrt.StateValue) {
    state = new ocrt.ChargedState(contractState);
  } else {
    throw new CompactError(`'contractState' parameter ${contractState} has unexpected type`);
  }
  return state;
};

/**
 * @internal
 */
export const createInitialQueryContext = (
  contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState,
  contractAddress: ocrt.ContractAddress,
  time: number,
  parentBlockHash?: string,
  caller?: ocrt.PublicAddress,
): ocrt.QueryContext => {
  const initialQueryContext = new ocrt.QueryContext(coerceToChargedState(contractState), contractAddress);
  const balance = contractState instanceof ocrt.ContractState ? contractState.balance : new Map();
  initialQueryContext.block = {
    ...initialQueryContext.block,
    balance,
    ownAddress: contractAddress,
    secondsSinceEpoch: BigInt(time),
  };
  if (parentBlockHash) {
    initialQueryContext.block = {
      ...initialQueryContext.block,
      parentBlockHash,
    };
  }
  if (caller) {
    initialQueryContext.block = {
      ...initialQueryContext.block,
      caller,
    };
  }
  return initialQueryContext;
};

/**
 * @internal
 */
const isZswapLocalState = (value: any): value is ZswapLocalState => {
  return (
    typeof value === 'object' &&
    value !== null &&
    'coinPublicKey' in value &&
    typeof value.coinPublicKey === 'string' &&
    'currentIndex' in value &&
    'inputs' in value &&
    'outputs' in value
  );
};

/**
 * @internal
 */
const isEncodedZswapLocalState = (value: any): value is EncodedZswapLocalState => {
  return (
    typeof value === 'object' &&
    value !== null &&
    'coinPublicKey' in value &&
    typeof value.coinPublicKey === 'object' &&
    value.coinPublicKey !== null &&
    'bytes' in value.coinPublicKey &&
    'currentIndex' in value &&
    'inputs' in value &&
    'outputs' in value
  );
};

export const createCallContext = (
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  coinPublicKeyOrZswapState: ocrt.CoinPublicKey | EncodedCoinPublicKey | ZswapLocalState | EncodedZswapLocalState,
  contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState,
  maybeTime?: number,
  parentBlockHash?: string,
  caller?: ocrt.PublicAddress,
): CallContext => {
  const time = maybeTime ?? Math.floor(Date.now() / 1_000);
  const initialQueryContext = createInitialQueryContext(contractState, contractAddress, time, parentBlockHash, caller);

  let zswapLocalState: EncodedZswapLocalState;
  if (isZswapLocalState(coinPublicKeyOrZswapState)) {
    // Convert ZswapLocalState to EncodedZswapLocalState
    zswapLocalState = encodeZswapLocalState(coinPublicKeyOrZswapState);
  } else if (isEncodedZswapLocalState(coinPublicKeyOrZswapState)) {
    // Use EncodedZswapLocalState directly
    zswapLocalState = coinPublicKeyOrZswapState;
  } else {
    // It's a CoinPublicKey or EncodedCoinPublicKey, create empty state
    zswapLocalState = emptyZswapLocalState(coinPublicKeyOrZswapState);
  }

  return {
    circuitId,
    contractAddress,
    initialQueryContext: initialQueryContext,
    currentQueryContext: initialQueryContext,
    currentGasCost: emptyRunningCost(),
    currentZswapLocalState: zswapLocalState,
    currentLocalQueryContext: undefined,
    parentBlockHash,
    time,
  };
};

/**
 * @internal
 */
export const emptyRunningCost = (): ocrt.RunningCost => ({
  readTime: 0n,
  computeTime: 0n,
  bytesWritten: 0n,
  bytesDeleted: 0n,
});

/**
 * The results of the call to a Compact circuit
 */
export interface CircuitResults<R = any> {
  /**
   * The primary result, as returned from Compact
   */
  result: R;
  /**
   * The updated context after the circuit execution, that can be used to
   * inform further runs
   */
  context: CircuitContext;
  /**
   * The gas consumption of the circuit execution
   */
  gasCost: ocrt.RunningCost;
}

const addRunningCost = (a: ocrt.RunningCost, b: ocrt.RunningCost): ocrt.RunningCost => {
  return {
    readTime: a.readTime + b.readTime,
    computeTime: a.computeTime + b.computeTime,
    bytesWritten: a.bytesWritten + b.bytesWritten,
    bytesDeleted: a.bytesDeleted + b.bytesDeleted,
  };
};

/**
 * Runs a program (query) against the current ledger state in the given circuit context. Records the transcript in the
 * given partial proof data.
 *
 * @param circuitContext The context for the currently executing circuit.
 * @param partialProofData The partial proof data to insert the query results into.
 * @param program The query to run.
 */
export const queryLedgerState = (
  circuitContext: CircuitContext,
  partialProofData: PartialProofData,
  program: ocrt.Op<null>[],
): ocrt.AlignedValue | undefined => {
  try {
    const res = circuitContext.callContext.currentQueryContext.query(program, circuitContext.costModel, circuitContext.gasLimit);
    circuitContext.callContext.currentQueryContext = res.context;
    circuitContext.callContext.currentGasCost = addRunningCost(circuitContext.callContext.currentGasCost, res.gasCost);

    // The generated ledger read-accessors (`contract.ledger(state).field`) also run read queries through this function,
    // but with a minimal synthetic context that has no `queryContexts`/`gasCosts` maps and no `callContext.contractAddress`.
    // Only thread the per-address cells when we are in a real circuit context.
    const liveAddress = circuitContext.callContext.contractAddress;
    if (liveAddress !== undefined && circuitContext.queryContexts !== undefined) {
      circuitContext.queryContexts[liveAddress] = res.context;
      const current_gas = circuitContext.gasCosts[liveAddress] ?? emptyRunningCost();
      circuitContext.gasCosts[liveAddress] = addRunningCost(current_gas, res.gasCost);

      // Accumulate `log` events on the single global list, tagged with the contract that
      // emitted them (`read` events instead fill the popeq results in the public transcript
      // below). Gated by the same real-context check: the synthetic read-accessor context
      // emits no logs and has neither an address nor an `events` list.
      for (const ev of res.events) {
        if (ev.tag === 'log') {
          circuitContext.events.push({ ...ev.content, address: liveAddress });
        }
      }
    }

    const reads = res.events.filter((e) => e.tag === 'read');
    let i = 0;
    partialProofData.publicTranscript = partialProofData.publicTranscript.concat(
      program.map((op) =>
        typeof op === 'object' && 'popeq' in op
          ? { popeq: { ...op.popeq, result: reads[i++].content } }
          : op,
      ) as ocrt.Op<ocrt.AlignedValue>[],
    );
    if (res.events.length === 1 && res.events[0].tag === 'read') {
      return res.events[0].content;
    }
    return undefined;
  } catch (err) {
    if (err instanceof Error) {
      throw new CompactError(err.toString());
    }
    throw err;
  }
};

/**
 * Runs a read-only query against the current mid-call ledger state without recording it.
 * A local function's ledger read is served from this snapshot: appending it to the public
 * transcript would make it an on-chain-replayed observation, so the query runs in gather
 * mode and is recorded nowhere — tier 1 replays only the local ops (which already embed
 * what the read produced), and tier 2 re-executes the call against the basis block.
 *
 * @param circuitContext The context for the currently executing circuit.
 * @param program The read-only query to run.
 */
export const snapshotLedgerState = (
  circuitContext: CircuitContext,
  program: ocrt.Op<null>[],
): ocrt.AlignedValue | undefined => {
  try {
    const res = circuitContext.callContext.currentQueryContext.query(program, circuitContext.costModel, circuitContext.gasLimit);
    if (res.events.length === 1 && res.events[0].tag === 'read') {
      return res.events[0].content;
    }
    return undefined;
  } catch (err) {
    if (err instanceof Error) {
      throw new CompactError(err.toString());
    }
    throw err;
  }
};
