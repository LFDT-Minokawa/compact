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
import { ContractStateProvider } from './providers.js';

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
   * Data included by the parent call only if this was a sub-call
   */
  commCommData?: CommunicationCommitmentData;
}

export interface CallContext<PS = any> {
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
   * The current private state for the contract.
   */
  currentPrivateState: PS | undefined;
  /**
   * The current Zswap local state. Tracks inputs and outputs produced during circuit execution.
   */
  currentZswapLocalState: EncodedZswapLocalState | undefined;
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
export interface CircuitContext<PS = any> {
  /**
   * The context for the current call.
   */
  callContext: CallContext<PS>;
  /**
   * The current query context of every contract in the call tree.
   */
  queryContexts: Record<ocrt.ContractAddress, ocrt.QueryContext>;
  /**
   * The current gas costs for every contract in the call tree.
   */
  gasCosts: Record<ocrt.ContractAddress, ocrt.RunningCost>;
  /**
   * The deployed {@link ocrt.ContractState} of every cross-contract callee resolved during the
   * execution, keyed by address. Populated by {@link crossContractCall} (via the state provider)
   * the first time a callee is reached. Retained — unlike the cached query context, which keeps only
   * ledger data — so the implementation-binding guard can read a callee's deployed verifier key for
   * *any* of its circuits on *every* call, including later calls to a different circuit of an
   * already-resolved callee. The entry contract is not recorded here; only fetched callees are.
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
   * When `true`, {@link crossContractCall} refuses to enter a contract that is
   * already executing on the current call stack — i.e. a re-entrant cross-contract
   * call (`A -> A`, or `A -> B -> A`) — and throws instead. On by default (the
   * upstream ledger can mis-apply transcripts on re-entry). Pass `false` to
   * {@link createCircuitContext} to opt out, e.g. for tests that deliberately
   * exercise recursion.
   */
  reentrancyGuard?: boolean;
  /**
   * The set of contract addresses currently executing on the cross-contract call
   * stack: the entry contract plus every callee whose call has not yet returned.
   * Maintained by {@link crossContractCall} and shared by reference across the call
   * tree (via {@link copyCircuitContext}). Only consulted when {@link reentrancyGuard}
   * is set.
   */
  activeContracts?: Set<ocrt.ContractAddress>;
  /**
   * Events emitted by the on-chain VM during circuit execution from `log` operations,
   * each tagged with the address of the emitting contract. A single global list shared
   * across the whole call tree (threaded like {@link callProofDataTrace}); a per-contract
   * view is a filter over the `address` tag. Surfaced via `CircuitResults.context.events`.
   */
  events: LogEvent[];
}

/**
 * Entry point for constructing the {@link CircuitContext} to pass as an argument to a circuit. Always use this
 * function to set up the initial circuit context.
 *
 * @param circuitId The name of the circuit being executed.
 * @param contractAddress The address of the contract defining the circuit being executed.
 * @param coinPublicKeyOrZswapState The initial Zswap local state information - used for tracking shielded coin transfers.
 * @param contractState The initial ledger state to execute the contract again - most often a snapshot fetched from the chain.
 * @param privateState The initial witness / private state to execute the contract again - most often a snapshot fetched
 *                     from local storage.
 * @param stateProvider The provider to use to dynamically fetch on-chain contract state. This is only used to execute
 *                      cross-contract calls, and is not needed if the circuit being executed does not perform any
 *                      cross-contract calls.
 * @param gasLimit The maximum gas this contract should consume.
 * @param costModel The model capturing how much ledger operations cost.
 * @param time The current time. Used to execute the block time related kernel operations.
 * @param parentBlockHash The hash of the block the transaction is being built on. Also passed to {@link ContractStateProvider}
 *                        to fetch the correct contract states when executing cross-contract calls.
 * @param reentrancyGuard When `true`, cross-contract calls that re-enter a contract already executing on the call
 *                        stack (`A -> A`, or `A -> B -> A`) throw instead of running. On by default; pass `false`
 *                        to opt out.
 */
export const createCircuitContext = <PS>(
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  coinPublicKeyOrZswapState: ocrt.CoinPublicKey | EncodedCoinPublicKey | ZswapLocalState | EncodedZswapLocalState,
  contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState,
  privateState: PS,
  stateProvider?: ContractStateProvider,
  gasLimit?: ocrt.RunningCost,
  costModel?: ocrt.CostModel,
  time?: number,
  parentBlockHash?: string,
  reentrancyGuard?: boolean,
): CircuitContext<PS> => {
  const callContext = createCallContext(
    circuitId,
    contractAddress,
    coinPublicKeyOrZswapState,
    contractState,
    privateState,
    time,
    parentBlockHash,
  );
  return {
    callContext: createCallContext(
      circuitId,
      contractAddress,
      coinPublicKeyOrZswapState,
      contractState,
      privateState,
      time,
      parentBlockHash,
    ),
    queryContexts: { [contractAddress]: callContext.currentQueryContext },
    gasCosts: { [contractAddress]: callContext.currentGasCost },
    contractStates: {},
    costModel: costModel ?? ocrt.CostModel.initialCostModel(),
    callProofDataTrace: [],
    gasLimit,
    stateProvider,
    reentrancyGuard: reentrancyGuard ?? true,
    activeContracts: new Set([contractAddress]),
    events: [],
  };
};

/**
 * @internal
 */
export const copyCircuitContext = (context: CircuitContext): CircuitContext => ({
  // `reentrancyGuard` and `activeContracts` fall through the spread: the guard
  // flag is copied by value and the active-contract set is intentionally shared
  // *by reference* across the whole call tree so `crossContractCall` sees one
  // coherent call stack. Do not deep-copy `activeContracts` here.
  ...context,
  callContext: { ...context.callContext },
  queryContexts: { ...context.queryContexts },
  gasCosts: { ...context.gasCosts },
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

  assertDefined(initialQueryContext, `initial ledger context for contract '${contractAddress}'`);
  assertDefined(currentQueryContext, `current ledger context for contract '${contractAddress}'`);

  circuitContext.callProofDataTrace.push({
    ...proofData,
    circuitId: circuitContext.callContext.circuitId,
    contractAddress,
    initialQueryContext,
    finalQueryContext: currentQueryContext,
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

export const createCallContext = <PS>(
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  coinPublicKeyOrZswapState: ocrt.CoinPublicKey | EncodedCoinPublicKey | ZswapLocalState | EncodedZswapLocalState,
  contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState,
  privateState: PS,
  maybeTime?: number,
  parentBlockHash?: string,
  caller?: ocrt.PublicAddress,
): CallContext<PS> => {
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
    currentPrivateState: privateState,
    currentZswapLocalState: zswapLocalState,
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
export interface CircuitResults<PS = any, R = any> {
  /**
   * The primary result, as returned from Compact
   */
  result: R;
  /**
   * The updated context after the circuit execution, that can be used to
   * inform further runs
   */
  context: CircuitContext<PS>;
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
