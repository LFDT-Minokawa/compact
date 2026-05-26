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
import {
  CircuitId,
  CallContext,
  CircuitContext,
  CircuitResults,
  copyCallContext,
  createInitialQueryContext,
  emptyRunningCost,
  CommunicationCommitmentData,
} from './circuit-context.js';
import { ConstructorContext, ConstructorResult } from './constructor-context.js';
import { assertDefined } from './error.js';
import { assertIsContractAddress, fromHex, toHex } from './utils.js';
import { CompactError } from './error.js';
import { PartialProofData } from './proof-data.js';
import { CompactTypeField, Bytes32Descriptor } from './compact-types.js';

/**
 * The type of a provable circuit. A provable circuit is a function that accepts a circuit context and an arbitrary list of
 * parameters and returns a result and additional data used to construct a transaction.
 */
export type ProvableCircuit = (context: CircuitContext, ...args: any[]) => Promise<CircuitResults>;

export type ProvableCircuits = Record<CircuitId, ProvableCircuit>;

export interface Contract {
  provableCircuits: ProvableCircuits;
}

export type ContractCtor = new (witnesses: Record<string, never>) => Contract;

const resolveQueryContext = async (context: CircuitContext, callee: ocrt.ContractAddress): Promise<ocrt.QueryContext> => {
  if (callee in context.queryContexts) {
    return context.queryContexts[callee];
  }
  assertDefined(context.stateProvider, `state provider for call to '${callee}'`);
  assertDefined(context.callContext.parentBlockHash, `parent block hash to fetch state for callee '${callee}'`);
  const contractState = await context.stateProvider.getContractState(context.callContext.parentBlockHash, callee);
  assertDefined(contractState, `contract state for callee '${callee}'`);
  const initialQueryContext = createInitialQueryContext(
    contractState,
    callee,
    context.callContext.time,
    context.callContext.parentBlockHash,
    { tag: 'contract', address: context.callContext.contractAddress },
  );
  context.queryContexts[callee] = initialQueryContext;
  context.gasCosts[callee] = emptyRunningCost();
  return initialQueryContext;
};

const resolveGasCosts = (context: CircuitContext, callee: ocrt.ContractAddress): ocrt.RunningCost => {
  if (callee in context.gasCosts) {
    return context.gasCosts[callee];
  }
  throw new CompactError(`Gas costs for contract '${callee}' not found`);
};

export const setupCallContext = (
  context: CircuitContext,
  circuitId: CircuitId,
  contractAddress: ocrt.ContractAddress,
  queryContext: ocrt.QueryContext,
  currentGasCost: ocrt.RunningCost,
): void => {
  context.callContext.circuitId = circuitId;
  context.callContext.contractAddress = contractAddress;
  context.callContext.initialQueryContext = queryContext;
  context.callContext.currentQueryContext = queryContext;
  context.callContext.currentGasCost = currentGasCost;
  // Undefined because these two should only be called for sub-calls, which do not support witnesses
  context.callContext.currentPrivateState = undefined;
  context.callContext.currentZswapLocalState = undefined;
};

export const restoreCallContext = (
  callerContext: CircuitContext,
  {
    circuitId,
    contractAddress,
    initialQueryContext,
    currentQueryContext,
    currentGasCost,
    currentPrivateState,
    currentZswapLocalState,
    parentBlockHash,
    time,
  }: CallContext,
): void => {
  callerContext.callContext.circuitId = circuitId;
  callerContext.callContext.contractAddress = contractAddress;
  callerContext.callContext.initialQueryContext = initialQueryContext;
  callerContext.callContext.currentQueryContext = currentQueryContext;
  callerContext.callContext.currentGasCost = currentGasCost;
  callerContext.callContext.currentPrivateState = currentPrivateState;
  callerContext.callContext.currentZswapLocalState = currentZswapLocalState;
  callerContext.callContext.parentBlockHash = parentBlockHash;
  callerContext.callContext.time = time;
};

export const restoreCircuitContext = (
  callerCircuitContext: CircuitContext,
  callerCallContext: CallContext,
  calleeCircuitContext: CircuitContext,
): void => {
  restoreCallContext(callerCircuitContext, callerCallContext);
  callerCircuitContext.queryContexts = calleeCircuitContext.queryContexts;
  callerCircuitContext.gasCosts = calleeCircuitContext.gasCosts;
  callerCircuitContext.callProofDataTrace = calleeCircuitContext.callProofDataTrace;
};

/**
 * Convert a hex-encoded `Fr` (as produced by `ocrt.communicationCommitment` or
 * `ocrt.communicationCommitmentRandomness` — both go through
 * `to_value_hex_ser(&Fr)` in `onchain-runtime-wasm/src/primitives.rs`) into an
 * `AlignedValue` matching midnight-ledger's `AlignedValue::from(fr)`:
 *
 *   alignment = [{ tag: 'atom', value: { tag: 'field' } }]
 *   value     = [ValueAtom(fr.as_le_bytes()).normalize()]
 *
 * where `normalize()` strips trailing zeros from the LE byte vector
 * (see `transient-crypto/src/fab.rs:201` and `base-crypto/src/fab/conversions.rs`
 * for the `From<Fr> for ValueAtom` and `From<DynAligned> for AlignedValue` impls
 * we're mirroring).
 *
 * The hex from `to_value_hex_ser(&fr)` is in SCALE compact-integer form (see
 * `serialize/src/util.rs::ScaleBigInt`).  For uniformly-random Fr — which both
 * the rand and the `transient_commit` output approximately are — the encoding
 * is `[marker_byte, ...fr.as_le_bytes()]`: 33 bytes total, marker is one byte.
 * Strip that marker and then normalize.
 *
 * When the wasm API stops SCALE-encoding these and just hands back plain bytes, drop the `slice(1)`.
 */
const frHexToAlignedValue = (frHex: string): ocrt.AlignedValue => {
  const allBytes = fromHex(frHex);
  if (allBytes.length < 1) {
    throw new CompactError('empty Fr hex encoding');
  }
  // Drop the SCALE marker.  The Fr's LE bytes follow.
  const leBytes = allBytes.slice(1);
  // `ValueAtom::normalize` strips trailing zero bytes; in LE that's the
  // high-order zeros of the integer representation.
  let end = leBytes.length;
  while (end > 0 && leBytes[end - 1] === 0) end -= 1;
  return {
    value: [leBytes.slice(0, end)],
    alignment: CompactTypeField.alignment(),
  };
};

export function assertNotDefaultContractAddress(address: ocrt.ContractAddress): void {
  if (address === ocrt.dummyContractAddress()) {
    throw new CompactError(`Cannot perform cross-contract call to default contract address`);
  }
}

const uint8ArrayToAlignedValue = (x: Uint8Array): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(x),
  alignment: Bytes32Descriptor.alignment(),
});

/**
 * Calls a circuit defined in another contract from the currently executing contract and returns the result.
 *
 * @param circuitContext The circuitContext of the currently executing circuit.
 * @param calleeContractCtor The 'Contract' class constructor defined in the callee module.
 * @param calleeCircuitId The ID of the circuit to be called in the contract to be called.
 * @param calleeAddress The address of the contract to be called.
 * @param callerProofData The proof data instance created when the caller circuit was initialized.
 * @param args The arguments to the circuit to be called.
 *
 * @internal
 */
export const crossContractCall = async (
  circuitContext: CircuitContext,
  calleeContractCtor: ContractCtor,
  calleeCircuitId: CircuitId,
  calleeAddress: ocrt.ContractAddress,
  callerProofData: PartialProofData,
  ...args: any[]
): Promise<[any, bigint, Uint8Array]> => {
  assertIsContractAddress(calleeAddress);
  assertNotDefaultContractAddress(calleeAddress);
  const provableCircuit = new calleeContractCtor({}).provableCircuits[calleeCircuitId];
  assertDefined(provableCircuit, `'${calleeCircuitId}' for callee '${calleeAddress}'`);
  const calleeQueryContext = await resolveQueryContext(circuitContext, calleeAddress);
  const calleeGasCosts = resolveGasCosts(circuitContext, calleeAddress);
  const callerCallContext = copyCallContext(circuitContext.callContext);
  setupCallContext(circuitContext, calleeCircuitId, calleeAddress, calleeQueryContext, calleeGasCosts);
  const circuitResult = await provableCircuit(circuitContext, ...args);
  restoreCircuitContext(circuitContext, callerCallContext, circuitResult.context);

  const calleeCallProofData = circuitContext.callProofDataTrace[circuitContext.callProofDataTrace.length - 1];

  // Cc-rand: generated once so the ZKIR private_input gate and the
  // compiled transientCommit() see the same value. Returned as bigint
  // to feed straight into transientCommit's opening.
  const commCommRandHex = ocrt.communicationCommitmentRandomness();
  const commCommRandAligned = frHexToAlignedValue(commCommRandHex);
  const commCommRandBigInt = ocrt.valueToBigInt(commCommRandAligned.value);

  // Entry-point: IR-typed Bytes<32>, which is a bare Uint8Array in TS.
  // The AlignedValue form is only for the transcript push.
  const entryPointBytes = fromHex(ocrt.entryPointHash(calleeCircuitId));
  const entryPointAligned = uint8ArrayToAlignedValue(entryPointBytes);

  // Private-transcript pushes (output, cc-rand, entry-point) in the
  // order the ZKIR private_input gates consume them.
  callerProofData.privateTranscriptOutputs.push(calleeCallProofData.output);
  callerProofData.privateTranscriptOutputs.push(commCommRandAligned);
  callerProofData.privateTranscriptOutputs.push(entryPointAligned);

  return [circuitResult.result, commCommRandBigInt, entryPointBytes];
};

/**
 * Inverse of {@link frHexToAlignedValue}: bigint Fr → hex SCALE form.
 * Compiled transientCommit() yields a bigint but
 * {@link CommunicationCommitmentData} stores hex (downstream transaction
 * construction reads it).
 *
 * Cc-rand and comm-comm are uniformly-distributed, so always SCALE
 * Mode 3: marker `((n-4) << 2) | 0b11` then `n` LE bytes.
 */
const bigIntToFrHex = (x: bigint): ocrt.CommunicationCommitment => {
  const valueBytes = ocrt.bigIntToValue(x)[0];
  const n = valueBytes.length;
  if (n < 4) {
    throw new CompactError(`bigIntToFrHex expects a cryptographic-size Fr (>= 4 LE bytes), got ${n} bytes for ${x}`);
  }
  const result = new Uint8Array(1 + n);
  result[0] = ((n - 4) << 2) | 0b11;
  result.set(valueBytes, 1);
  return toHex(result);
};

/**
 * Stamp comm-comm metadata on the top of `callProofDataTrace`. The
 * compiled cross-contract-call body calls this right after the
 * synthesized transientCommit() — it replaces the inline stamping
 * that used to live in {@link crossContractCall}.
 *
 * Targeting the trace top is safe by construction: the desugar emits
 * this call inside the same `let*` block that just did the dispatch,
 * with only pure operations between, so nothing else can push a new
 * proof-data entry first.
 *
 * Args are bigints (Field-typed values projected by compiled code);
 * converted to hex for {@link CommunicationCommitmentData}.
 *
 * @internal
 */
export const recordCalleeCommComm = (circuitContext: CircuitContext, commComm: bigint, commCommRand: bigint): void => {
  const top = circuitContext.callProofDataTrace[circuitContext.callProofDataTrace.length - 1];
  top.commCommData = {
    commComm: bigIntToFrHex(commComm),
    commCommRand: bigIntToFrHex(commCommRand),
  };
};
