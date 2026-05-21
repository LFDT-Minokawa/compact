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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v3';
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
    costModel: costModel ?? ocrt.CostModel.initialCostModel(),
    callProofDataTrace: [],
    gasLimit,
    stateProvider,
  };
};

/**
 * @internal
 */
export const copyCircuitContext = (context: CircuitContext): CircuitContext => ({
  ...context,
  callContext: { ...context.callContext },
  queryContexts: { ...context.queryContexts },
  gasCosts: { ...context.gasCosts },
  callProofDataTrace: [...context.callProofDataTrace],
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

  circuitContext.queryContexts[contractAddress] = currentQueryContext;
  circuitContext.gasCosts[contractAddress] = circuitContext.callContext.currentGasCost;

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
): ocrt.AlignedValue | ocrt.GatherResult[] => {
  try {
    const res = circuitContext.callContext.currentQueryContext.query(program, circuitContext.costModel, circuitContext.gasLimit);
    circuitContext.callContext.currentQueryContext = res.context;
    circuitContext.callContext.currentGasCost = addRunningCost(circuitContext.callContext.currentGasCost, res.gasCost);
    const reads = res.events.filter((e) => e.tag === 'read');
    let i = 0;
    partialProofData.publicTranscript = partialProofData.publicTranscript.concat(
      program.map((op) =>
        typeof op === 'object' && 'popeq' in op
          ? {
              popeq: {
                ...op.popeq,
                result: reads[i++].content,
              },
            }
          : op,
      ) as ocrt.Op<ocrt.AlignedValue>[],
    );
    if (res.events.length === 1) {
      const event = res.events[0];
      if (event.tag === 'read') {
        return event.content;
      }
    }
    return res.events;
  } catch (err) {
    if (err instanceof Error) {
      throw new CompactError(err.toString());
    }
    throw err;
  }
};
