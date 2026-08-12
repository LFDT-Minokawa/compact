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
import {
  CircuitId,
  CallContext,
  CircuitContext,
  createInitialQueryContext,
  emptyRunningCost,
  queryLedgerState,
  CommunicationCommitmentData,
} from './circuit-context.js';
import { assertDefined } from './error.js';
import { checkConformance } from './conformance.js';
import { InterfaceDescriptor } from './interface-descriptor.js';
import { ModuleResolutionContext, ModuleResolutionError, ModuleResolutionFailure } from './module-resolution.js';
import { ContractModuleProvider, ModuleThunk } from './providers.js';
import { Module } from './module.js';
import { VerifierKeyHash, isVerifierKeyHash, verifierKeyHashOf } from './verifier-key-hash.js';
import { emptyZswapLocalState, EncodedCoinPublicKey } from './zswap.js';
import { assertIsContractAddress, fromHex } from './utils.js';
import { CompactError } from './error.js';
import { PartialProofData } from './proof-data.js';
import { CompactTypeBytes, CompactTypeField, CompactTypeUnsignedInteger } from './compact-types.js';
import { alignedConcat } from './built-ins.js';

/**
 * Raises a resolution failure. Annotated `never` so that a call to it narrows at the use site.
 *
 * @internal
 */
const failResolution: (context: ModuleResolutionContext, failure: ModuleResolutionFailure) => never = (
  context,
  failure,
) => {
  throw new ModuleResolutionError(context, failure);
};

/**
 * Checks that the module resolved for `calleeAddress` is the code deployed there, by
 * comparing verifier key fingerprints.
 *
 * The called circuit must match, and so must every other circuit the two sides share: two versions
 * of a contract agree on whatever they didn't change.
 *
 * @internal
 */
const checkImplementation = (
  deployedState: ocrt.ContractState,
  calleeModule: Module,
  calleeCircuitId: CircuitId,
  resolutionContext: ModuleResolutionContext,
): void => {
  const deployedHash = (circuitId: CircuitId): VerifierKeyHash | undefined => {
    const key = deployedState.operation(circuitId)?.verifierKey;
    return key === undefined || key.length === 0 ? undefined : verifierKeyHashOf(key);
  };
  const recordedHash = (circuitId: CircuitId, recorded: string): VerifierKeyHash => {
    if (!isVerifierKeyHash(recorded)) {
      failResolution(resolutionContext, {
        kind: 'MalformedVerifierKeyHash',
        circuitId,
        recorded,
      });
    }
    return recorded;
  };

  // No key on the chain: no such entry point, or an operation deployed without one.
  const deployed = deployedHash(calleeCircuitId);
  if (deployed === undefined) {
    failResolution(resolutionContext, { kind: 'OperationAbsent' });
  }

  // Own properties only: `toString` and `constructor` are legal circuit names, so a bare index
  // would find `Object.prototype`'s and report a function as a malformed fingerprint.
  const expectedVk = calleeModule.expectedVk;
  const recorded = expectedVk !== undefined && Object.hasOwn(expectedVk, calleeCircuitId) ? expectedVk[calleeCircuitId] : undefined;
  if (recorded === undefined) {
    failResolution(resolutionContext, {
      kind: 'ImplementationMismatch',
      circuitId: calleeCircuitId,
      actual: deployed,
    });
  }
  const expected = recordedHash(calleeCircuitId, recorded);
  if (expected !== deployed) {
    failResolution(resolutionContext, {
      kind: 'ImplementationMismatch',
      circuitId: calleeCircuitId,
      expected,
      actual: deployed,
    });
  }

  for (const circuitId of Object.keys(calleeModule.expectedVk)) {
    if (circuitId === calleeCircuitId) {
      continue;
    }
    const otherDeployed = deployedHash(circuitId);
    // Absent on the chain side means the circuit is not in the overlap, not that it disagrees.
    if (otherDeployed === undefined) {
      continue;
    }
    const otherExpected = recordedHash(circuitId, calleeModule.expectedVk[circuitId]);
    if (otherExpected !== otherDeployed) {
      failResolution(resolutionContext, {
        kind: 'ImplementationMismatch',
        circuitId,
        expected: otherExpected,
        actual: otherDeployed,
      });
    }
  }
};

/**
 * Checks the resolved module against the contract type the caller declared.
 *
 * @internal
 */
const checkModuleConformance = (
  declaration: InterfaceDescriptor,
  calleeModule: Module,
  resolutionContext: ModuleResolutionContext,
): void => {
  const conformance = checkConformance(declaration, calleeModule.circuitSignatures);
  switch (conformance.outcome) {
    case 'Conformant':
      return;
    case 'Violation':
      failResolution(resolutionContext, {
        kind: 'NonconformantImplementation',
        circuitId: conformance.circuitId,
        check: conformance.check,
        argumentIndex: conformance.argumentIndex,
      });
      break;
    case 'Unreadable':
      failResolution(resolutionContext, {
        kind: 'UnreadableModule',
        circuitId: conformance.circuitId,
        unreadableTag: conformance.unreadableTag,
        argumentIndex: conformance.argumentIndex,
      });
      break;
    default: {
      const exhaustive: never = conformance;
      throw new CompactError(`unhandled conformance outcome ${JSON.stringify(exhaustive)}`);
    }
  }
};

/**
 * Asks the provider for the callee's module and loads it, turning every provider fault into a
 * {@link ModuleResolutionFailure}.
 *
 * @internal
 */
const resolveModule = async (
  provider: ContractModuleProvider,
  calleeAddress: ocrt.ContractAddress,
  resolutionContext: ModuleResolutionContext,
): Promise<Module> => {
  let thunk: ModuleThunk | undefined;
  try {
    thunk = provider.resolve(calleeAddress);
  } catch (cause) {
    failResolution(resolutionContext, { kind: 'ProviderThrew', cause });
  }
  if (thunk === undefined) {
    failResolution(resolutionContext, { kind: 'UnsupportedImplementation' });
  }
  if (typeof thunk !== 'function') {
    failResolution(resolutionContext, { kind: 'ProviderThrew', cause: thunk });
  }
  try {
    return await thunk();
  } catch (cause) {
    failResolution(resolutionContext, { kind: 'ModuleLoadRejected', cause });
  }
};

/**
 * @internal
 */
const resolveQueryContext = async (
  context: CircuitContext,
  callee: ocrt.ContractAddress,
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
    // The cached query context drops the verifier keys, so keep the whole state for
    // {@link checkImplementation}.
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
  return queryContext;
};

/**
 * Gets a contract's accumulated gas cost from the circuit context. {@link resolveQueryContext}
 * always leaves a cost behind, so a miss is a bug.
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
  callerCoinPublicKey: EncodedCoinPublicKey,
): void => {
  context.callContext.circuitId = circuitId;
  context.callContext.contractAddress = contractAddress;
  context.callContext.initialQueryContext = queryContext;
  context.callContext.currentQueryContext = queryContext;
  context.callContext.currentGasCost = currentGasCost;
  // Undefined because sub-calls do not support witnesses, so a callee has no private state.
  context.callContext.currentPrivateState = undefined;
  // A callee *can* do coin operations — an output addressed to a contract is credited only if that
  // contract claims it in the same transaction — so each gets its own state, created on first entry
  // and reused on a later sequential call to the same address.
  context.callContext.currentZswapLocalState = context.zswapLocalStates[contractAddress] ??=
    emptyZswapLocalState(callerCoinPublicKey);
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
 * Restores the caller's circuit context after a cross-contract sub-call returns. Contexts are copied
 * on invocation to keep the JS interfaces immutable, so the per-address maps the callee advanced are
 * copied back explicitly and the caller's `callContext` is reset to its pre-call snapshot.
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
  callerCircuitContext.zswapLocalStates = calleeCircuitContext.zswapLocalStates;
  callerCircuitContext.contractStates = calleeCircuitContext.contractStates;
  callerCircuitContext.callProofDataTrace = calleeCircuitContext.callProofDataTrace;
  // Only reached on a successful return, so a reverted sub-call's events go with its discarded
  // context.
  callerCircuitContext.events = calleeCircuitContext.events;
  // The caller's own cells are deliberately not re-pointed from the maps. The guard refuses
  // re-entry, so nothing advanced them during the sub-call, and reading the map back would rewind
  // any write that reached the live cell first.
};

const Bytes32Descriptor = new CompactTypeBytes(32);

const contractAddressToValue = (address: ocrt.ContractAddress): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(ocrt.encodeContractAddress(address)),
  alignment: Bytes32Descriptor.alignment(),
});

const circuitIdToValue = (circuitId: CircuitId): ocrt.AlignedValue => ({
  value: Bytes32Descriptor.toValue(fromHex(ocrt.entryPointHash(circuitId))),
  alignment: Bytes32Descriptor.alignment(),
});

/**
 * Converts a hex-encoded `Fr` from `ocrt.communicationCommitment{,Randomness}` into the
 * `AlignedValue` that midnight-ledger's `AlignedValue::from(fr)` produces: one field atom holding
 * the LE bytes with trailing zeros stripped (`transient-crypto/src/fab.rs`).
 *
 * The wasm hex is SCALE compact-integer encoded, which for a full-width `Fr` is one marker byte
 * then the LE bytes. Drop the `slice(1)` when the API hands back plain bytes.
 */
const frHexToAlignedValue = (frHex: string): ocrt.AlignedValue => {
  const allBytes = fromHex(frHex);
  if (allBytes.length < 1) {
    throw new CompactError('empty Fr hex encoding');
  }
  const leBytes = allBytes.slice(1);
  // `ValueAtom::normalize` strips trailing zero bytes.
  let end = leBytes.length;
  while (end > 0 && leBytes[end - 1] === 0) end -= 1;
  return {
    value: [leBytes.slice(0, end)],
    alignment: CompactTypeField.alignment(),
  };
};

const KernelStateFieldIndexDescriptor = new CompactTypeUnsignedInteger(255n, 1);

/**
 * Hand-written equivalent of what `compactc` emits for `Kernel.claimContractCall`. Keep the two in
 * sync.
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
 * Rejects a call to a callee already on the call stack; otherwise marks it active until the
 * `finally` in {@link crossContractCall} pops it.
 *
 * @internal
 */
const assertNoReentrancy = (circuitContext: CircuitContext, calleeAddress: ocrt.ContractAddress): void => {
  assertDefined(circuitContext.activeContracts, 'active-contract set for the re-entrancy guard');
  if (circuitContext.activeContracts.has(calleeAddress)) {
    throw new CompactError(
      `Contract re-entrancy detected: '${calleeAddress}' is already executing on the call stack; ` +
        `re-entrant cross-contract calls are not yet supported`,
    );
  }
  circuitContext.activeContracts.add(calleeAddress);
};

/**
 * Witnesses for constructing a callee. A callee can never run one, but the generated `Contract`
 * constructor validates a function-valued field for every witness the callee *declares*, so `{}`
 * throws. This proxy satisfies those checks for any name and throws only if a witness is invoked.
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
 * The call site's side of a cross-contract call, as emitted by `compactc`.
 */
export type CrossContractCallOptions = {
  /** The caller's circuit context. Mutated in place for the duration of the sub-call. */
  readonly context: CircuitContext;
  /** The caller's local name for the contract type, used in diagnostics. */
  readonly interfaceName: string;
  /** The caller's `declaredInterfaces[interfaceName]`. */
  readonly declaration: InterfaceDescriptor;
  /** String identifier of the circuit being called.*/
  readonly calleeCircuitId: CircuitId;
  /** On-chain address of contract being called.*/
  readonly calleeAddress: ocrt.ContractAddress;
  /** The proof data created when the caller's circuit was initialized. */
  readonly partialProofData: PartialProofData;
  /** Arguments to the circuit being called.*/
  readonly args: readonly any[];
};

/**
 * Calls a circuit on another contract and returns its result.
 *
 * @internal
 */
export const crossContractCall = async ({
  context: circuitContext,
  interfaceName,
  declaration,
  calleeCircuitId,
  calleeAddress,
  partialProofData: callerProofData,
  args,
}: CrossContractCallOptions): Promise<any> => {
  const resolutionContext: ModuleResolutionContext = {
    calleeAddress,
    calleeCircuitId,
    interfaceName,
    callerAddress: circuitContext.callContext.contractAddress,
  };

  // 1. A circuit the contract type declares `pure` has no verifier key and is never a deployed
  //    operation, so there is nothing to call into.
  const declared = Object.hasOwn(declaration, calleeCircuitId)
    ? declaration[calleeCircuitId]
    : undefined;
  assertDefined(declared, `declaration of circuit '${calleeCircuitId}' on contract type '${interfaceName}'`);
  if (declared.pure) {
    failResolution(resolutionContext, { kind: 'PureInterfaceCircuit' });
  }

  // 2. Address checks, then the provider itself.
  assertIsContractAddress(calleeAddress);
  assertNotDefaultContractAddress(calleeAddress);
  const moduleProvider = circuitContext.moduleProvider;
  if (moduleProvider === undefined) {
    failResolution(resolutionContext, { kind: 'ModuleProviderAbsent' });
  }

  // 3. Re-entrancy guard. Must stay last before the `try`; the `finally` is its removal.
  assertNoReentrancy(circuitContext, calleeAddress);
  try {
    // 4. Deployed state at the pinned parent block, memoized by address.
    const calleeQueryContext = await resolveQueryContext(circuitContext, calleeAddress);
    const deployedState = circuitContext.contractStates?.[calleeAddress];
    assertDefined(deployedState, `deployed contract state for callee '${calleeAddress}'`);

    // 6. The module, from the provider.
    const calleeModule = await resolveModule(moduleProvider, calleeAddress, resolutionContext);

    // 7. Conformance before keys: a non-conformant module is an application mistake, a key mismatch
    //    is the code and the chain having drifted.
    checkModuleConformance(declaration, calleeModule, resolutionContext);

    // 5 and 8. The operation exists and carries a key, and its fingerprint agrees.
    checkImplementation(deployedState, calleeModule, calleeCircuitId, resolutionContext);

    // 9. Construct the callee and run it.
    const provableCircuit = new calleeModule.Contract(forbiddenCalleeWitnesses(calleeAddress)).provableCircuits[calleeCircuitId];
    assertDefined(provableCircuit, `'${calleeCircuitId}' for callee '${calleeAddress}'`);
    const calleeGasCosts = resolveGasCost(circuitContext, calleeAddress);
    const callerCallContext = copyCallContext(circuitContext.callContext);
    const callerZswapLocalState = callerCallContext.currentZswapLocalState;
    assertDefined(callerZswapLocalState, `Zswap local state for calling contract '${callerCallContext.contractAddress}'`);
    setupCallContext(
      circuitContext,
      calleeCircuitId,
      calleeAddress,
      calleeQueryContext,
      calleeGasCosts,
      callerZswapLocalState.coinPublicKey,
    );
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
    circuitContext.activeContracts?.delete(calleeAddress);
  }
};
