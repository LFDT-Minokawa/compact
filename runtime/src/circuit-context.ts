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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';
import { emptyZswapLocalState, EncodedCoinPublicKey, EncodedZswapLocalState } from './zswap.js';
import { PartialProofData, ProofData } from './proof-data.js';
import { CompactError } from './error.js';

/**
 * The external information accessible from within a Compact circuit call
 */
export interface CircuitContext<PS = any> {
  /**
   * The current private state for the contract.
   */
  currentPrivateState: PS;
  /**
   * The current Zswap local state. Tracks inputs and outputs produced during circuit execution.
   */
  currentZswapLocalState: EncodedZswapLocalState;
  /**
   * The current on-chain context the transaction is evolving.
   */
  currentQueryContext: ocrt.QueryContext;
  /**
   * The cost model to use for the execution.
   */
  costModel: ocrt.CostModel;
  /**
   * The gas limit for this circuit.
   */
  gasLimit?: ocrt.RunningCost;
}

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
 * Creates a new circuit context.
 *
 * @param contractAddress The address of the contract being executed.
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 * @param contractState The initial ledger state of the contract.
 * @param privateState The initial private state of the contract.
 * @param gasLimit The upper bound on gas costs for this contract. If no gas limit is supplied, no gas limit will be
 *                 enforced for the execution.
 * @param costModel The cost model to use for this contract. Only use for debugging or testing purposes. Normally circuits
 *                  should execute with the standard Midnight cost model.
 * @param time Optional parameter indicating the time in seconds since the last Unix epoch. Parameter used mainly for testing.
 *
 * @typeparam PS The type of the private state of the contract.
 */
export const createCircuitContext = <PS>(
  contractAddress: ocrt.ContractAddress,
  coinPublicKey: ocrt.CoinPublicKey | EncodedCoinPublicKey,
  contractState: ocrt.ContractState | ocrt.StateValue | ocrt.ChargedState,
  privateState: PS,
  gasLimit?: ocrt.RunningCost,
  costModel?: ocrt.CostModel,
  time?: number,
): CircuitContext<PS> => {
  const initialQueryContext = new ocrt.QueryContext(coerceToChargedState(contractState), contractAddress);
  initialQueryContext.block = {
    ...initialQueryContext.block,
    secondsSinceEpoch: BigInt(time ?? Math.floor(Date.now() / 1_000)),
  };
  return {
    currentPrivateState: privateState,
    currentZswapLocalState: emptyZswapLocalState(coinPublicKey),
    currentQueryContext: initialQueryContext,
    costModel: costModel ?? ocrt.CostModel.initialCostModel(),
    gasLimit,
  };
};

/**
 * Function for creating an initial running cost of zero.
 *
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
   * The data required to prove this circuit run
   */
  proofData: ProofData;
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
    const res = circuitContext.currentQueryContext.query(program, circuitContext.costModel, circuitContext.gasLimit);
    circuitContext.currentQueryContext = res.context;
    // @ts-expect-error: We use a hidden variable to track running cost so we can move it to `CircuitResults` at the end
    circuitContext['gasCost'] = res.gasCost;
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
