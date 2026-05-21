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
  createInitialQueryContext,
  emptyRunningCost,
  queryLedgerState,
  CommunicationCommitmentData,
} from './circuit-context.js';
import { assertDefined } from './error.js';
import { assertIsContractAddress, fromHex } from './utils.js';
import { CompactError } from './error.js';
import { PartialProofData } from './proof-data.js';
import { CompactTypeField, CompactTypeUnsignedInteger, Bytes32Descriptor } from './compact-types.js';
import { alignedConcat } from './built-ins.js';

/**
 * @internal
 */
type ProvableCircuit = (context: CircuitContext, ...args: any[]) => Promise<CircuitResults>;

/**
 * @internal
 */
type ProvableCircuits = Record<CircuitId, ProvableCircuit>;

/**
 * @internal
 */
type Contract = {
  provableCircuits: ProvableCircuits;
};

/**
 * @internal
 */
type ContractCtor = new (witnesses: Record<string, never>) => Contract;

/**
 * @internal
 */
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

/**
 * Gets the accumulated gas cost of a contract from the 'persistent' section of the circuit context.
 * Because {@link resolveQueryContext} either throws an error or populates `context.gasCosts` with
 * `emptyRunningCost`, throws an error if gas cost is not found.
 *
 * @internal
 */
const resolveGasCost = (context: CircuitContext, callee: ocrt.ContractAddress): ocrt.RunningCost => {
  if (callee in context.gasCosts) {
    return context.gasCosts[callee];
  }
  throw new CompactError(`Bug found: gas cost for contract '${callee}' not found`);
};

/**
 * @internal
 */
const copyCallContext = ({
  circuitId,
  contractAddress,
  initialQueryContext,
  currentQueryContext,
  currentGasCost,
  currentPrivateState,
  currentZswapLocalState,
  parentBlockHash,
  time,
}: CallContext): CallContext => ({
  circuitId,
  contractAddress,
  initialQueryContext,
  currentQueryContext,
  currentGasCost,
  currentPrivateState,
  currentZswapLocalState,
  parentBlockHash,
  time,
});

/**
 * Sets the call context up for the callee circuit. Called just before the callee is invoked.
 *
 * @internal
 */
const setupCallContext = (
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

/**
 * Restores the call context to match the caller's context just before a cross-contract call occurred.
 *
 * @internal
 */
const restoreCallContext = (
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

/**
 * Restores the circuit context to match the caller's context just before a cross-contract call occurred.
 * Circuit contexts are copied when a function is invoked to keep the JS interfaces immutable. That means
 * we must copy the top level values like `queryContexts` explicitly from the callee.
 *
 * @internal
 */
const restoreCircuitContext = (
  callerCircuitContext: CircuitContext,
  callerCallContext: CallContext,
  calleeCircuitContext: CircuitContext,
): void => {
  restoreCallContext(callerCircuitContext, callerCallContext);
  callerCircuitContext.queryContexts = calleeCircuitContext.queryContexts;
  callerCircuitContext.gasCosts = calleeCircuitContext.gasCosts;
  callerCircuitContext.callProofDataTrace = calleeCircuitContext.callProofDataTrace;
};

const contractAddressToValue = (address: ocrt.ContractAddress): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(ocrt.encodeContractAddress(address)),
  alignment: Bytes32Descriptor.alignment(),
});

const circuitIdToValue = (circuitId: CircuitId): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(fromHex(ocrt.entryPointHash(circuitId))),
  alignment: Bytes32Descriptor.alignment(),
});

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

const KernelStateFieldIndexDescriptor = new CompactTypeUnsignedInteger(255n, 1);

/**
 * JavaScript code for a kernel call to 'claimContractCall'. This code must be
 * kept in sync with the JS code that a real Compact source program would
 * produce for 'Kernel.claimContractCall'.
 *
 * @internal
 */
const kernelClaimContractCall = (
  context: CircuitContext,
  callerPartialProofData: PartialProofData,
  calleeAddress: ocrt.ContractAddress,
  calleeCircuitId: CircuitId,
  commComm: ocrt.CommunicationCommitment,
) => {
  queryLedgerState(context, callerPartialProofData, [
    { swap: { n: 0 } },
    {
      idx: {
        cached: true,
        pushPath: true,
        path: [
          {
            tag: 'value',
            value: {
              value: KernelStateFieldIndexDescriptor.toValue(3n),
              alignment: KernelStateFieldIndexDescriptor.alignment(),
            },
          },
        ],
      },
    },
    { dup: { n: 0 } },
    'size',
    {
      push: {
        storage: false,
        value: ocrt.StateValue.newCell(
          alignedConcat(contractAddressToValue(calleeAddress), circuitIdToValue(calleeCircuitId), frHexToAlignedValue(commComm)),
        ).encode(),
      },
    },
    { concat: { cached: true, n: 160 } },
    { push: { storage: false, value: ocrt.StateValue.newNull().encode() } },
    { ins: { cached: true, n: 2 } },
    { swap: { n: 0 } },
  ]);
};

const createCommCommData = (input: ocrt.AlignedValue, output: ocrt.AlignedValue): CommunicationCommitmentData => {
  const commCommRand = ocrt.communicationCommitmentRandomness();
  return { commComm: ocrt.communicationCommitment(input, output, commCommRand), commCommRand };
};

const assertNotDefaultContractAddress = (address: ocrt.ContractAddress): void => {
  if (address === ocrt.dummyContractAddress()) {
    throw new CompactError(`Cannot perform cross-contract call to default contract address`);
  }
};

/**
 * Calls a circuit defined in another contract from the currently executing contract and returns the result.
 *
 * @param circuitContext The current circuit context.
 * @param calleeContractCtor The 'Contract' class constructor defined in the callee module
 * @param calleeCircuitId The name of the circuit to be called in the contract to be called.
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
): Promise<any> => {
  assertIsContractAddress(calleeAddress);
  assertNotDefaultContractAddress(calleeAddress);
  const provableCircuit = new calleeContractCtor({}).provableCircuits[calleeCircuitId];
  assertDefined(provableCircuit, `'${calleeCircuitId}' for callee '${calleeAddress}'`);
  const calleeQueryContext = await resolveQueryContext(circuitContext, calleeAddress);
  const calleeGasCosts = resolveGasCost(circuitContext, calleeAddress);
  const callerCallContext = copyCallContext(circuitContext.callContext);
  setupCallContext(circuitContext, calleeCircuitId, calleeAddress, calleeQueryContext, calleeGasCosts);
  const circuitResult = await provableCircuit(circuitContext, ...args);
  restoreCircuitContext(circuitContext, callerCallContext, circuitResult.context);

  const calleeCallProofData = circuitContext.callProofDataTrace[circuitContext.callProofDataTrace.length - 1];
  const commCommData = createCommCommData(calleeCallProofData.input, calleeCallProofData.output);
  calleeCallProofData.commCommData = commCommData;
  callerProofData.privateTranscriptOutputs.push(calleeCallProofData.output);
  callerProofData.privateTranscriptOutputs.push(frHexToAlignedValue(commCommData.commCommRand));
  callerProofData.privateTranscriptOutputs.push(circuitIdToValue(calleeCircuitId));
  kernelClaimContractCall(circuitContext, callerProofData, calleeAddress, calleeCircuitId, commCommData.commComm);

  return circuitResult.result;
};
