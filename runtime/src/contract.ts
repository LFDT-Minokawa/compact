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
 * The called circuit's fingerprint is mandatory and must match. Every other circuit present on both
 * sides must agree too — one circuit's key is too weak a check, because two versions of a contract
 * agree on every circuit they didn't change, while requiring the module's whole set to be deployed
 * is too strong, since removing an entry point would make the callee unusable for every other
 * circuit.
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

  // Nothing on the chain to fingerprint: either the address holds a contract with no such
  // entry point, or its operation was deployed without a key. Either way is an error.
  const deployed = deployedHash(calleeCircuitId);
  if (deployed === undefined) {
    failResolution(resolutionContext, { kind: 'OperationAbsent' });
  }

  const recorded = calleeModule.expectedVk?.[calleeCircuitId];
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
 * Asks the provider for the callee's module and loads it.
 *
 * Everything a provider can do wrong is classified here, so that an
 * application sees one vocabulary of failures.
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
    // Retain the full deployed state. The cached query context keeps only ledger data, not the
    // operations' verifier keys, so stashing it here is what lets {@link checkImplementation} run on
    // every call — including a later call to a *different* circuit of this same callee.
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
  callerCoinPublicKey: EncodedCoinPublicKey,
): void => {
  context.callContext.circuitId = circuitId;
  context.callContext.contractAddress = contractAddress;
  context.callContext.initialQueryContext = queryContext;
  context.callContext.currentQueryContext = queryContext;
  context.callContext.currentGasCost = currentGasCost;
  // Undefined because sub-calls do not support witnesses, so a callee has no private state.
  context.callContext.currentPrivateState = undefined;
  // Shielded coin operations, by contrast, *are* supported in a callee, and the ledger relies on
  // them: an output addressed to a contract is only credited if that contract claims the receive
  // in the same transaction, which for a callee means running `receiveShielded` here. Each
  // contract keeps its own state — created on first entry, reused on a later sequential call to
  // the same address — sharing only the submitter's coin public key, since one wallet pays for
  // the whole transaction.
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
  callerCircuitContext.zswapLocalStates = calleeCircuitContext.zswapLocalStates;
  callerCircuitContext.contractStates = calleeCircuitContext.contractStates;
  callerCircuitContext.callProofDataTrace = calleeCircuitContext.callProofDataTrace;
  // Take the callee's accumulated event list (callee-emitted events tagged with the callee's
  // address are appended in order). Only runs on a successful return, so a reverted sub-call's
  // events are dropped with its discarded context.
  callerCircuitContext.events = calleeCircuitContext.events;
  // Re-point the caller's `currentQueryContext` at the threaded state for its own
  // contract (advanced if the sub-call re-entered the caller). Same for the Zswap local state.
  const callerAddress = callerCircuitContext.callContext.contractAddress;
  callerCircuitContext.callContext.currentQueryContext = callerCircuitContext.queryContexts[callerAddress];
  callerCircuitContext.callContext.currentZswapLocalState = callerCircuitContext.zswapLocalStates[callerAddress];
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
 * The call site's side of a cross-contract call, as emitted by `compactc`.
 */
export type CrossContractCallOptions = {
  /** The caller's circuit context. Mutated in place for the duration of the sub-call. */
  readonly context: CircuitContext;
  /** The caller's local name for the contract type. Names the declaration, for diagnostics. */
  readonly interfaceName: string;
  /** The caller's `declaredInterfaces[interfaceName]`. Also where the callee's declared purity is. */
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
 * Calls a circuit defined in another contract from the currently executing contract and returns the
 * result.
 *
 * Everything before the `try` establishes that the call can be made at all. Everything inside it
 * binds the call to an implementation and runs it.
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

    // 7. Check conformance before checking keys. A non-conformant module is a mistake in the application, and a key
    //    mismatch is the code and the chain having drifted. Checking in this order keeps one from
    //    being diagnosed as the other.
    checkModuleConformance(declaration, calleeModule, resolutionContext);

    // 5 and 8. The operation exists and carries a key, and its fingerprint agrees.
    checkImplementation(deployedState, calleeModule, calleeCircuitId, resolutionContext);

    // 9. Construct the callee and proceed as before.
    const provableCircuit = new calleeModule.Contract(forbiddenCalleeWitnesses(calleeAddress)).provableCircuits[calleeCircuitId];
    assertDefined(provableCircuit, `'${calleeCircuitId}' for callee '${calleeAddress}'`);
    const calleeGasCosts = resolveGasCost(circuitContext, calleeAddress);
    const callerCallContext = copyCallContext(circuitContext.callContext);
    // The callee inherits only the submitter's coin public key; everything else about its Zswap
    // local state is its own.
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
    if (circuitContext.reentrancyGuard === true) {
      circuitContext.activeContracts?.delete(calleeAddress);
    }
  }
};
