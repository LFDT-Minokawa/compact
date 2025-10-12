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
import type { EncodedCoinPublicKey, EncodedZswapLocalState } from './zswap.js';
import { emptyZswapLocalStates } from './zswap.js';
import type { PartialProofData, ProofData } from './proof-data.js';
import { assertDefined, CompactError } from './error.js';

/**
 * The identifier for a contract. This is derived from the name of a contract in a Compact source file.
 */
export type ContractId = string;

/**
 * A circuit identifier. This is derived from the name of a circuit in a Compact source file.
 */
export type CircuitId = string;

/**
 * Contains data needed to create a proof for a single circuit call, whether the top-level circuit call or an intermediate
 * circuit call.
 */
export interface ProofDataFrame extends ProofData {
  /**
   * The ID of the contract for which this proof data is pertinent.
   */
  readonly contractId: ContractId;
  /**
   * The ID of the circuit for which this proof data is pertinent.
   */
  readonly circuitId: CircuitId;
  /**
   * The address of the contract defining the circuit for which this proof data is pertinent.
   */
  readonly contractAddress: ocrt.ContractAddress;
  /**
   * The ledger state of the contract before the circuit was called.
   */
  readonly initialQueryContext: ocrt.QueryContext;
  /**
   * The ledger state of the contract before the circuit returned.
   */
  readonly currentQueryContext: ocrt.QueryContext;
}

/**
 * Contains data needed to create a proof for a top-level circuit call. There is one proof data frame for every circuit that
 * is called and returns as a result of a top-level circuit call.
 */
export type ProofDataTrace = ProofDataFrame[];

/**
 * Information about the currently executing circuit in the current contract. This data changes each time a circuit is
 * entered or exited.
 *
 * @typeparam PS A type describing the private state of the currently executing contract.
 *
 * TODO: Make each property below 'readonly' when the runtime becomes immutable.
 */
export interface StackFrame<PS = any> {
  /**
   * The ID of the current contract.
   */
  contractId: ContractId;
  /**
   * The ID of the current circuit.
   */
  circuitId: CircuitId;
  /**
   * The address of the current contract.
   */
  contractAddress: ocrt.ContractAddress;
  /**
   * The initial ledger state of the current contract. Null only if the top-level circuit call is still initializing.
   */
  initialQueryContext: ocrt.QueryContext;
  /**
   * The current ledger state of the current contract. Null only if the top-level circuit call is still initializing.
   */
  currentQueryContext: ocrt.QueryContext;
  /**
   * The private state of the current contract. Null only if the top-level circuit call is still initializing.
   */
  currentPrivateState: PS;
  /**
   * The Zswap local state of the current contract. Null only if the top-level circuit call is still initializing.
   */
  currentZswapLocalState: EncodedZswapLocalState;
}

/**
 * The external information accessible from within a Compact circuit call.
 *
 * @typeparam PSS A type describing the aggregate private state of all contracts involved in the circuit call.
 */
export interface CircuitContext<PSS = any> extends StackFrame<PSS> {
  /**
   * The current private (witness) states for all contracts involved in the circuit call.
   */
  privateStates: Record<ocrt.ContractAddress, PSS>;
  /**
   * The current Zswap local states for all contracts involved in the circuit call. Tracks Zswap inputs and outputs produced
   * during circuit execution.
   */
  zswapLocalStates: Record<ocrt.ContractAddress, EncodedZswapLocalState>;
  /**
   * The current public (ledger) states for all contracts involved in the circuit call.
   */
  ledgerStates: Record<ocrt.ContractAddress, ocrt.QueryContext>;
  /**
   * The current proof data trace for all circuits called and returned up until this point.
   */
  proofDataTrace: ProofDataTrace;
  /**
   * The index of the next contract call to occur, starting at 0. This is used when the contract call is claimed in the
   * kernel.
   */
  sequenceNumber: bigint;
}

/**
 * Makes a record of ledger contexts from ledger states, where each ledger state can be represented as either a {@link ocrt.ContractState}
 * or {@link ocrt.StateValue}.
 *
 * @param contractStates The contract states from which to construct ledger contexts.
 * @param time Optional parameter indicating the time in seconds since the last Unix epoch. Parameter used mainly for testing.
 */
const createQueryContexts = (
  contractStates: Record<ocrt.ContractAddress, ocrt.ContractState | ocrt.StateValue>,
  time?: number,
): Record<ocrt.ContractAddress, ocrt.QueryContext> =>
  Object.fromEntries(
    Object.entries(contractStates).map(([address, contractState]) => {
      const initialQueryContext = new ocrt.QueryContext(
        contractState instanceof ocrt.ContractState ? contractState.data : contractState,
        address,
      );
      initialQueryContext.block = {
        ...initialQueryContext.block,
        secondsSinceEpoch: BigInt(time ?? Math.floor(Date.now() / 1_000)),
      };
      return [address, initialQueryContext];
    }),
  );

/**
 * Creates a new circuit context.
 *
 * @param contractId The ID of the contract being executed.
 * @param circuitId The ID of the top-level circuit being executed.
 * @param contractAddress The address defining the circuit being executed.
 * @param coinPublicKey The Zswap coin public key of the user executing the circuit.
 * @param contractStates The initial ledger states of all contracts potentially involved in the circuit call.
 * @param privateStates The initial private states of all contracts potentially involved in the circuit call.
 * @param time Optional parameter indicating the time in seconds since the last Unix epoch. Parameter used mainly for testing.
 *
 * @typeparam PSS A type describing the aggregate private state of all contracts involved in the circuit call.
 */
export const createCircuitContext = <PSS = any>(
  contractId: ContractId,
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  coinPublicKey: ocrt.CoinPublicKey | EncodedCoinPublicKey,
  contractStates: Record<ocrt.ContractAddress, ocrt.ContractState | ocrt.StateValue>,
  privateStates: Record<ocrt.ContractAddress, PSS>,
  time?: number,
): CircuitContext<PSS> => {
  const circuitContext = {
    contractId,
    circuitId,
    contractAddress,
    initialQueryContext: null,
    currentQueryContext: null,
    currentPrivateState: null,
    currentZswapLocalState: null,
    zswapLocalStates: emptyZswapLocalStates(coinPublicKey, Object.keys(contractStates)),
    privateStates,
    ledgerStates: createQueryContexts(contractStates, time),
    proofDataTrace: [],
    sequenceNumber: 0n,
  } as unknown as CircuitContext<PSS>;
  freshStackFrame(circuitContext, contractId, circuitId, contractAddress);
  return circuitContext;
};

/**
 * Returns a circuit context in which the public and private state heaps have been copied. This function is used to
 * preserve the immutability contract the between the input and output circuit contexts of a circuit.
 *
 * @param context The circuit context to copy.
 */
export const copyCircuitContext = (context: CircuitContext): CircuitContext => ({
  ...context,
  zswapLocalStates: { ...context.zswapLocalStates },
  privateStates: { ...context.privateStates },
  ledgerStates: { ...context.ledgerStates },
  proofDataTrace: [...context.proofDataTrace],
});

/**
 * Copies and returns the stack frame data for the currently executing circuit. The result is typically passed to
 * {@link restoreStackFrame} after a call to a different contract returns.
 *
 * @param circuitContext The context for the currently executing circuit.
 */
export const copyStackFrame = ({
  contractId,
  circuitId,
  contractAddress,
  initialQueryContext,
  currentQueryContext,
  currentPrivateState,
  currentZswapLocalState,
}: CircuitContext): StackFrame => ({
  contractId,
  circuitId,
  contractAddress,
  initialQueryContext,
  currentQueryContext,
  currentPrivateState,
  currentZswapLocalState,
});

/**
 * Called by the circuit caller. Sets the contract address and circuit ID in the circuit context. Be sure to store the current query context,
 * the current private state, the current circuit, and the current contract address in temporary variables before calling this function.
 *
 * @param circuitContext The context for the currently executing circuit.
 * @param contractId The ID of the contract containing the circuit to be called.
 * @param contractAddress The ledger address of the contract to be called.
 * @param circuitId The ID of the circuit in the contract to be called.
 */
export const freshStackFrame = (
  circuitContext: CircuitContext,
  contractId: ContractId,
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
): void => {
  const initialQueryContext = readQueryContext(circuitContext, contractAddress);
  circuitContext.contractId = contractId;
  circuitContext.circuitId = circuitId;
  circuitContext.contractAddress = contractAddress;
  circuitContext.initialQueryContext = initialQueryContext;
  circuitContext.currentQueryContext = initialQueryContext;
  circuitContext.currentPrivateState = readPrivateState(circuitContext, contractAddress);
  circuitContext.currentZswapLocalState = readZswapLocalState(circuitContext, contractAddress);
};

/**
 * Called by the circuit caller. Restores all context variables stored in temporary variables after {@link copyStackFrame}.
 *
 * @param circuitContext The context for the current circuit.
 * @param stackFrame The stack frame data to be inserted into the given circuit context.
 */
export const restoreStackFrame = (
  circuitContext: CircuitContext,
  {
    contractId,
    circuitId,
    contractAddress,
    initialQueryContext,
    currentQueryContext,
    currentPrivateState,
    currentZswapLocalState,
  }: StackFrame,
): void => {
  circuitContext.contractId = contractId;
  circuitContext.circuitId = circuitId;
  circuitContext.contractAddress = contractAddress;
  circuitContext.initialQueryContext = initialQueryContext;
  circuitContext.currentQueryContext = currentQueryContext;
  circuitContext.currentPrivateState = currentPrivateState;
  circuitContext.currentZswapLocalState = currentZswapLocalState;
};

/**
 * Called by the circuit caller. Transfers the public and private data heaps from the result of a circuit call to the
 * caller context. Necessary because each impure circuit call makes a copy of the input context. Therefore, the changes
 * in the heap from the callee circuit are not automatically reflected in the caller circuit context.
 *
 * @param callerContext The context for the circuit caller.
 * @param calleeContext The context resulting from calling the callee.
 * @param callerStackFrame The stack frame data to be inserted into the given circuit context.
 */
export const restoreCircuitContext = (
  callerContext: CircuitContext,
  calleeContext: CircuitContext,
  callerStackFrame: StackFrame,
) => {
  restoreStackFrame(callerContext, callerStackFrame);
  callerContext.privateStates = calleeContext.privateStates;
  callerContext.ledgerStates = calleeContext.ledgerStates;
  callerContext.zswapLocalStates = calleeContext.zswapLocalStates;
  callerContext.proofDataTrace = calleeContext.proofDataTrace;
};

/**
 * Saves the ledger state of the currently executing contract to the ledger state record in the circuit context. Moves
 * the current ledger state in the stack frame into the ledger state record.
 *
 * @param circuitContext The context for the current circuit.
 */
export const saveCurrentQueryContext = ({
  currentQueryContext,
  contractId,
  contractAddress,
  ledgerStates,
}: CircuitContext): void => {
  assertDefined(currentQueryContext, `ledger context for contract '${contractId}' with address '${contractAddress}'`);
  ledgerStates[contractAddress] = currentQueryContext;
};

/**
 * Reads a ledger state from the ledger state record in the given context.
 *
 * @param circuitContext The current circuit context.
 * @param contractAddress The address of the contract having the ledger state to be read.
 */
export const readQueryContext = ({ ledgerStates }: CircuitContext, contractAddress: ocrt.ContractAddress): ocrt.QueryContext => {
  const ledgerState = ledgerStates[contractAddress];
  assertDefined(ledgerState, `ledger context for contract with address '${contractAddress}'`);
  return ledgerState;
};

/**
 * Saves the private state of the currently executing contract to the private state record in the circuit context. Moves
 * the current private state in the stack frame into the private state record.
 *
 * @param circuitContext The context for the current circuit.
 */
export const saveCurrentPrivateState = ({ privateStates, contractAddress, currentPrivateState }: CircuitContext): void => {
  privateStates[contractAddress] = currentPrivateState;
};

/**
 * Reads a private state from the private state record in the given context.
 *
 * @param circuitContext The current circuit context.
 * @param contractAddress The address of the contract having the private state to be read.
 */
export const readPrivateState = ({ privateStates }: CircuitContext, contractAddress: ocrt.ContractAddress): any => {
  return privateStates[contractAddress];
};

/**
 * Saves the Zswap local state of the currently executing contract to the Zswap local state record in the circuit context. Moves
 * the current Zswap local state in the stack frame into the Zswap local state record.
 *
 * @param circuitContext The context for the current circuit.
 */
export const saveCurrentZswapLocalState = ({
  zswapLocalStates,
  contractId,
  contractAddress,
  currentZswapLocalState,
}: CircuitContext): void => {
  assertDefined(currentZswapLocalState, `Zswap local state for contract '${contractId}' with address '${contractAddress}'`);
  zswapLocalStates[contractAddress] = currentZswapLocalState;
};

/**
 * Reads a Zswap local state from the Zswap local state record in the given context.
 *
 * @param circuitContext The current circuit context.
 * @param contractAddress The address of the contract having the Zswap local state to be read.
 */
export const readZswapLocalState = (
  { zswapLocalStates }: CircuitContext,
  contractAddress: ocrt.ContractAddress,
): EncodedZswapLocalState => {
  const zswapLocalState = zswapLocalStates[contractAddress];
  assertDefined(zswapLocalState, `Zswap local state for contract with address '${contractAddress}'`);
  return zswapLocalState;
};

/**
 * Called before a circuit is exited by the circuit that will be exited. Stores the ledger, private, and Zswap local states
 * in the current stack frame into their respective records.
 *
 * @param circuitContext The context for the circuit being exited. The "current" states in the stack frame have been
 *                       updated according to the circuit logic.
 * @param proofData The proof data produced during the execution of the circuit being exited.
 */
export const finalizeCircuitContext = (circuitContext: CircuitContext, proofData: ProofData): void => {
  assertDefined(
    circuitContext.initialQueryContext,
    `initial ledger context for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  assertDefined(
    circuitContext.currentQueryContext,
    `current ledger context for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  saveCurrentQueryContext(circuitContext);
  saveCurrentPrivateState(circuitContext);
  saveCurrentZswapLocalState(circuitContext);
  circuitContext.proofDataTrace.push({
    ...proofData,
    contractId: circuitContext.contractId,
    circuitId: circuitContext.circuitId,
    contractAddress: circuitContext.contractAddress,
    initialQueryContext: circuitContext.initialQueryContext,
    currentQueryContext: circuitContext.currentQueryContext,
  });
};

/**
 * The results of the call to a Compact circuit.
 *
 * @typeParam PSS A type describing the aggregate private state of all contracts involved in the circuit call.
 * @typeParam R The return type of the circuit.
 */
export interface CircuitResults<PSS = any, R = any> {
  /**
   * The primary result, as returned from Compact.
   */
  readonly result: R;
  /**
   * The updated context after the circuit execution.
   */
  readonly context: CircuitContext<PSS>;
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
  assertDefined(
    circuitContext.currentQueryContext,
    `query context for contract '${circuitContext.contractId}' with address '${circuitContext.contractAddress}'`,
  );
  try {
    const res = circuitContext.currentQueryContext.query(program, ocrt.CostModel.dummyCostModel());
    circuitContext.currentQueryContext = res.context;
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
