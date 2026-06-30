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
import { sha256 } from '@noble/hashes/sha2.js';
import { bytesToHex } from '@noble/hashes/utils.js';
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
import { assertDefined, assertUndefined } from './error.js';
import { assertIsContractAddress, fromHex } from './utils.js';
import { CompactError, ContractInterfaceMismatchError } from './error.js';
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
type PureCircuit = (...args: any[]) => any;

/**
 * @internal
 */
type PureCircuits = Record<CircuitId, PureCircuit>;

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
type Module = {
  Contract: ContractCtor;
  pureCircuits: PureCircuits;
  /**
   * Per-circuit verifier-key fingerprints (lowercase SHA-256 hex of the compiled `.verifier`),
   * emitted into the generated contract module by `compactc`. Keyed by external circuit name. Used
   * by the cross-contract implementation-binding guard to detect when the contract deployed at a
   * call target does not match the implementation this module was compiled against.
   */
  expectedVk: Record<string, string>;
};

/**
 * Asserts that the contract deployed at `calleeAddress` is the implementation `calleeModule` was
 * compiled against, by hashing the deployed verifier key for `calleeCircuitId` and comparing it to
 * the fingerprint the compiler recorded on the module (`expectedVk`). Both sides are the lowercase
 * SHA-256 hex of the same `.verifier` bytes — the compiler emits `sha256sum`(verifier file) and the
 * deployed `operation.verifierKey` is byte-identical to that file — so an honest match is exact and
 * a substituted contract is rejected here rather than at the proof server.
 *
 * @internal
 */
const assertImplementationMatches = (
  contractState: ocrt.ContractState,
  calleeModule: Module,
  calleeCircuitId: CircuitId,
  calleeAddress: ocrt.ContractAddress,
): void => {
  const operation = contractState.operation(calleeCircuitId);
  const deployedVerifierKey = operation?.verifierKey;
  // No deployed verifier key means the circuit carries no proof obligation at this address.
  if (deployedVerifierKey === undefined || deployedVerifierKey.length === 0) {
    return;
  }
  const expected = calleeModule.expectedVk?.[calleeCircuitId];
  assertDefined(expected, `verifier-key fingerprint for circuit '${calleeCircuitId}' on the callee module`);
  const actual = bytesToHex(sha256(deployedVerifierKey));
  if (actual !== expected) {
    throw new ContractInterfaceMismatchError(calleeAddress, calleeCircuitId, expected, actual);
  }
};

/**
 * @internal
 */
const resolveQueryContext = async (
  context: CircuitContext,
  callee: ocrt.ContractAddress,
  calleeModule: Module,
  calleeCircuitId: CircuitId,
): Promise<ocrt.QueryContext> => {
  const caller: ocrt.PublicAddress = { tag: 'contract', address: context.callContext.contractAddress };
  let queryContext: ocrt.QueryContext;
  if (callee in context.queryContexts) {
    const cached = context.queryContexts[callee];
    // Keep the callee's accumulated state/effects; only rewrite the caller.
    cached.block = { ...cached.block, caller };
    queryContext = cached;
  } else {
    assertDefined(context.stateProvider, `state provider for call to '${callee}'`);
    assertDefined(context.callContext.parentBlockHash, `parent block hash to fetch state for callee '${callee}'`);
    const contractState = await context.stateProvider.getContractState(context.callContext.parentBlockHash, callee);
    assertDefined(contractState, `contract state for callee '${callee}'`);
    // Retain the full deployed state. The cached query context keeps only ledger data, not the
    // operations' verifier keys, so stashing it here is what lets the implementation-binding guard
    // below run on every call — including a later call to a *different* circuit of this same callee.
    (context.contractStates ??= {})[callee] = contractState;
    queryContext = createInitialQueryContext(
      contractState,
      callee,
      context.callContext.time,
      context.callContext.parentBlockHash,
      caller,
    );
    context.queryContexts[callee] = queryContext;
    context.gasCosts[callee] = emptyRunningCost();
  }
  const deployedState = context.contractStates?.[callee];
  assertDefined(deployedState, `deployed contract state for callee '${callee}'`);
  assertImplementationMatches(deployedState, calleeModule, calleeCircuitId, callee);
  return queryContext;
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
 * Restores the caller's circuit context after a cross-contract sub-call returns.
 * Circuit contexts are copied when a function is invoked to keep the JS interfaces immutable, so we must
 * copy the top-level values (`queryContexts`, `gasCosts`, `contractStates`, `callProofDataTrace`,
 * `events`) explicitly from the callee. The caller's `callContext` is otherwise reset to its pre-call snapshot — except for its
 * `currentQueryContext`, which we re-point at the (possibly advanced) threaded state for the caller's
 * own contract. That matters when the sub-call re-entered the caller's contract (direct self-recursion,
 * or indirect A -> B -> A): the caller's remaining ops — notably the kernel `claimContractCall` emitted
 * by `crossContractCall` — must build on the re-entrant writes rather than the pre-call snapshot, which
 * would otherwise be written back over the deeper turns' writes on commit.
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
  callerCircuitContext.contractStates = calleeCircuitContext.contractStates;
  callerCircuitContext.callProofDataTrace = calleeCircuitContext.callProofDataTrace;
  // Take the callee's accumulated event list (callee-emitted events tagged with the callee's
  // address are appended in order). Only runs on a successful return, so a reverted sub-call's
  // events are dropped with its discarded context.
  callerCircuitContext.events = calleeCircuitContext.events;
  // Re-point the caller's `currentQueryContext` at the threaded state for its own
  // contract (advanced if the sub-call re-entered the caller).
  const callerAddress = callerCircuitContext.callContext.contractAddress;
  callerCircuitContext.callContext.currentQueryContext = callerCircuitContext.queryContexts[callerAddress];
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

const assertPurityMatches = (
  module: Module,
  calleeCircuitId: CircuitId,
  calleeAddress: ocrt.ContractAddress,
  calleeIsPure: boolean,
): void => {
  const pureCircuit = module.pureCircuits[calleeCircuitId];
  const errMsg = `pure circuit '${calleeCircuitId}' for callee '${calleeAddress}'`;
  if (calleeIsPure) {
    assertDefined(pureCircuit, errMsg);
  } else {
    assertUndefined(pureCircuit, errMsg);
  }
};

/**
 * Enforces the re-entrancy guard for a cross-contract call and records the callee as
 * active on the call stack. When {@link CircuitContext.reentrancyGuard} is set, throws
 * if `calleeAddress` is already executing (a re-entrant call such as `A -> A` or
 * `A -> B -> A`); otherwise it adds the callee to {@link CircuitContext.activeContracts}
 * so a deeper sub-call can detect re-entry. The matching removal happens once the call
 * returns — see the `finally` in {@link crossContractCall}.
 *
 * @internal
 */
const assertNoReentrancy = (circuitContext: CircuitContext, calleeAddress: ocrt.ContractAddress): void => {
  const guardReentrancy = circuitContext.reentrancyGuard === true;
  if (guardReentrancy) {
    assertDefined(circuitContext.activeContracts, 'active-contract set for the re-entrancy guard');
    if (circuitContext.activeContracts.has(calleeAddress)) {
      throw new CompactError(
        `Contract re-entrancy detected: '${calleeAddress}' is already executing on the call stack; ` +
          `re-entrant cross-contract calls are not yet supported`,
      );
    }
    circuitContext.activeContracts.add(calleeAddress);
  }
};

/**
 * Builds the `witnesses` argument for constructing a cross-contract callee. Witnesses are
 * only available to the entry (root) contract, so a callee can never execute one — but
 * the generated `Contract` constructor validates a function-valued field for every witness
 * the callee *declares*, so passing `{}` throws (with an opaque field-name message) even
 * when the called circuit needs no witness. This proxy passes those `typeof` checks for any
 * name, so construction succeeds and witness-free circuits run unchanged; if the callee
 * circuit actually invokes a witness, the stub throws a clear, self-describing error.
 *
 * @internal
 */
const forbiddenCalleeWitnesses = (calleeAddress: ocrt.ContractAddress): Record<string, never> =>
  new Proxy(
    {},
    {
      get: (_target, witnessName) => () => {
        throw new CompactError(
          `Cross-contract callee '${calleeAddress}' invoked witness '${String(witnessName)}'; ` +
            `calls to witnesses in non-root contracts are not yet supported`,
        );
      },
    },
  ) as Record<string, never>;

/**
 * Calls a circuit defined in another contract from the currently executing contract and returns the result.
 *
 * @param circuitContext The current circuit context.
 * @param calleeModule The callee module containing TS executables.
 * @param calleeCircuitId The name of the circuit to be called in the contract to be called.
 * @param calleeAddress The address of the contract to be called.
 * @param calleeIsPure A flag indicating whether the circuit being called is pure.
 * @param callerProofData The proof data instance created when the caller circuit was initialized.
 * @param args The arguments to the circuit to be called.
 *
 * @internal
 */
export const crossContractCall = async (
  circuitContext: CircuitContext,
  calleeModule: Module,
  calleeCircuitId: CircuitId,
  calleeAddress: ocrt.ContractAddress,
  calleeIsPure: boolean,
  callerProofData: PartialProofData,
  ...args: any[]
): Promise<any> => {
  assertIsContractAddress(calleeAddress);
  assertNotDefaultContractAddress(calleeAddress);
  assertPurityMatches(calleeModule, calleeCircuitId, calleeAddress, calleeIsPure);
  assertNoReentrancy(circuitContext, calleeAddress);
  try {
    const provableCircuit = new calleeModule.Contract(forbiddenCalleeWitnesses(calleeAddress)).provableCircuits[calleeCircuitId];
    assertDefined(provableCircuit, `'${calleeCircuitId}' for callee '${calleeAddress}'`);
    const calleeQueryContext = await resolveQueryContext(circuitContext, calleeAddress, calleeModule, calleeCircuitId);
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
  } finally {
    // Pop the callee off the active stack once its call returns (or throws), so a
    // later *sequential* call to the same contract is permitted.
    if (circuitContext.reentrancyGuard === true) {
      circuitContext.activeContracts?.delete(calleeAddress);
    }
  }
};
