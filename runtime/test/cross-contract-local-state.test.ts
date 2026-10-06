// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// A cross-contract callee's capsule: where its local state comes from, when the provider is
// asked, what the checks past key agreement reject, and what the two records carry. The callee is
// a hand-rolled module shaped like `compactc`'s output — one circuit incrementing a local
// `Counter` — so the test needs no compiled contract; the generated code's side is `test-center`'s.

import { describe, expect, test } from 'vitest';
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  CircuitContext,
  CircuitResults,
  CompactTypeField,
  ContractModuleProvider,
  ContractStateProvider,
  HostInterface,
  HostInterfaceProvider,
  HostInterfaceRequirements,
  InterfaceDescriptor,
  LocalStateProvider,
  Module,
  ModuleResolutionError,
  PartialProofData,
  copyCircuitContext,
  createCircuitContext,
  crossContractCall,
  finalizeCallProofData,
  localStates,
  queryLocalState,
  verifierKeyHashOf,
} from '../src/index.js';

const COIN_PUBLIC_KEY = '0'.repeat(64);
const PARENT_BLOCK_HASH = '0'.repeat(64);
const CIRCUIT_ID = 'add';

const DECLARATION: InterfaceDescriptor = {
  [CIRCUIT_ID]: { pure: false, argumentTypes: [{ tag: 'Field' }], resultType: { tag: 'Field' } },
};

// FAB atoms are little-endian and minimal-length, so zero is the empty byte string.
const minBytes = (n: bigint): Uint8Array => {
  const bytes: number[] = [];
  for (let v = n; v > 0n; v >>= 8n) bytes.push(Number(v & 0xffn));
  return new Uint8Array(bytes);
};
const atom = (n: bigint, length: number): ocrt.AlignedValue => ({
  value: [minBytes(n)],
  alignment: [{ tag: 'atom', value: { tag: 'bytes', length } }],
});
const u8 = (n: number) => atom(BigInt(n), 1);
const u64 = (n: bigint) => atom(n, 8);
const key = (av: ocrt.AlignedValue): ocrt.Key => ({ tag: 'value', value: av });
const toBigint = (av: ocrt.AlignedValue): bigint => {
  let v = 0n;
  const b = av.value[0];
  for (let i = b.length - 1; i >= 0; i--) v = (v << 8n) | BigInt(b[i]);
  return v;
};
const field = (n: bigint): ocrt.AlignedValue => ({ value: CompactTypeField.toValue(n), alignment: CompactTypeField.alignment() });

// the local layout of `local count: Counter;`, at a given count
const counterState = (count: bigint): ocrt.StateValue =>
  ocrt.StateValue.newArray().arrayPush(ocrt.StateValue.newCell(u64(count)));
const countOf = (state: ocrt.StateValue): bigint => toBigint(state.asArray()![0].asCell()!);

// `count.increment(n)` and `count.read()` at path [0], as `midnight-ledger.ss` expands them
const increment = (n: number): ocrt.Op<null>[] => [
  { idx: { cached: false, pushPath: true, path: [key(u8(0))] } },
  { addi: { immediate: n } },
  { ins: { cached: true, n: 1 } },
];
const readCounter: ocrt.Op<null>[] = [
  { dup: { n: 0 } },
  { idx: { cached: false, pushPath: false, path: [key(u8(0))] } },
  { popeq: { cached: true, result: null } },
];

// The public layout every generated contract starts from: the kernel at index 0, materialized by
// the VM, which `kernelClaimContractCall` navigates into after the callee returns.
const kernelOnlyState = (): ocrt.ContractState => {
  const state = new ocrt.ContractState();
  state.data = new ocrt.ChargedState(ocrt.StateValue.newArray().arrayPush(ocrt.StateValue.newNull()));
  return state;
};

// The smallest envelope `ContractOperation.verifierKey` accepts: a tag it knows and a SCALE
// length prefix covering the payload, which nothing on this path parses.
const verifierKey = (): Uint8Array => {
  const header = new TextEncoder().encode('midnight:verifier-key[v7]:');
  const payload = new Uint8Array(8).fill(7);
  return new Uint8Array([...header, payload.length << 2, ...payload]);
};
const VERIFIER_KEY = verifierKey();

const emptyProofData = (): PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
});

/**
 * `add(x)`: increments the local counter by `x` and returns the new count, recording as the
 * generated wrapper does — a copied context, its own proof data, a record finalized into the
 * trace. Without a local half it returns `x` and asserts it was given no local state.
 */
const addCircuit =
  (hasLocalState: boolean) =>
  async (context: CircuitContext, x: bigint): Promise<CircuitResults> => {
    const ctx = copyCircuitContext(context);
    const pd: PartialProofData = { ...emptyProofData(), input: field(x) };
    let result: bigint;
    if (hasLocalState) {
      queryLocalState(ctx, pd, increment(Number(x)));
      result = toBigint(queryLocalState(ctx, pd, readCounter)!);
    } else {
      expect(ctx.callContext.currentLocalQueryContext).toBeUndefined();
      result = x;
    }
    finalizeCallProofData(ctx, { ...pd, output: field(result) });
    return { result, context: ctx, gasCost: ctx.callContext.currentGasCost };
  };

/** A callee module that passes conformance and key agreement, with the given capsule and host shape. */
const calleeModule = (options: { localState: boolean; hostInterfaces?: HostInterfaceRequirements }): Module => ({
  Contract: class {
    readonly provableCircuits = { [CIRCUIT_ID]: addCircuit(options.localState) };
  },
  pureCircuits: {},
  expectedVk: { [CIRCUIT_ID]: verifierKeyHashOf(VERIFIER_KEY) },
  circuitSignatures: {
    [CIRCUIT_ID]: { pure: false, provable: true, argumentTypes: [{ tag: 'Field' }], resultType: { tag: 'Field' } },
  },
  declaredInterfaces: {},
  ...(options.localState ? { initialLocalState: () => counterState(0n) } : {}),
  ...(options.hostInterfaces === undefined ? {} : { hostInterfaces: options.hostInterfaces }),
});

/** A chain holding the callee at `address`, its `add` operation carrying the module's key. */
const stateProviderFor = (address: ocrt.ContractAddress): ContractStateProvider => {
  const state = kernelOnlyState();
  const operation = new ocrt.ContractOperation();
  operation.verifierKey = VERIFIER_KEY;
  state.setOperation(CIRCUIT_ID, operation);
  return { getContractState: async (_blockHash, queried) => (queried === address ? state : undefined) };
};

const moduleProviderFor = (module: Module): ContractModuleProvider => ({ resolve: () => () => Promise.resolve(module) });

/** A provider serving one state, counting how often it is asked. */
const localStateProviderFor = (state: ocrt.StateValue | undefined): LocalStateProvider & { asked: number } => ({
  asked: 0,
  async getLocalState() {
    this.asked += 1;
    return state;
  },
});

type Harness = {
  context: CircuitContext;
  callerAddress: ocrt.ContractAddress;
  calleeAddress: ocrt.ContractAddress;
  callerProofData: PartialProofData;
  call: (x: bigint) => Promise<bigint>;
};

/** A provider serving exactly the given interfaces. */
const hostInterfaceProviderOf = (interfaces: Record<string, HostInterface>): HostInterfaceProvider => ({
  resolve: (id) => interfaces[id],
});

const harness = (options: {
  module: Module;
  localStateProvider?: LocalStateProvider;
  hostInterfaceProvider?: HostInterfaceProvider;
  callerLocalState?: ocrt.StateValue;
}): Harness => {
  const callerAddress = ocrt.sampleContractAddress();
  const calleeAddress = ocrt.sampleContractAddress();
  const context = createCircuitContext({
    circuitId: 'caller',
    contractAddress: callerAddress,
    coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
    contractState: kernelOnlyState(),
    localState: options.callerLocalState,
    time: 0,
    parentBlockHash: PARENT_BLOCK_HASH,
    hostInterfaceProvider: options.hostInterfaceProvider,
    crossContract: {
      stateProvider: stateProviderFor(calleeAddress),
      moduleProvider: moduleProviderFor(options.module),
      localStateProvider: options.localStateProvider,
    },
  });
  const callerProofData = emptyProofData();
  const call = (x: bigint): Promise<bigint> =>
    crossContractCall({
      context,
      interfaceName: 'Inner',
      declaration: DECLARATION,
      calleeCircuitId: CIRCUIT_ID,
      calleeAddress,
      partialProofData: callerProofData,
      args: [x],
    });
  return { context, callerAddress, calleeAddress, callerProofData, call };
};

const failureOf = async (promise: Promise<unknown>): Promise<ModuleResolutionError['failure']> => {
  try {
    await promise;
  } catch (error) {
    if (ModuleResolutionError.is(error)) {
      return error.failure;
    }
    throw new Error(`expected a ModuleResolutionError, got ${String(error)}`);
  }
  throw new Error('expected the call to reject');
};

/** Nothing of a rejected callee reaches the caller's context. */
const expectNothingCommitted = ({ context, calleeAddress }: Harness): void => {
  expect(context.queryContexts[calleeAddress]).toBeUndefined();
  expect(context.localQueryContexts[calleeAddress]).toBeUndefined();
  expect(context.gasCosts[calleeAddress]).toBeUndefined();
  expect(context.callProofDataTrace).toHaveLength(0);
};

describe('a callee with local state', () => {
  test('is first touched with its declaration defaults when the provider has no capsule', async () => {
    const provider = localStateProviderFor(undefined);
    const h = harness({ module: calleeModule({ localState: true }), localStateProvider: provider });

    expect(await h.call(5n)).toBe(5n);

    expect(provider.asked).toBe(1);
    expect(countOf(h.context.localQueryContexts[h.calleeAddress].state.state)).toBe(5n);
    expect(localStates(h.context)).toEqual({ [h.calleeAddress]: expect.anything() });
    expect(countOf(localStates(h.context)[h.calleeAddress])).toBe(5n);
  });

  test('runs against the capsule the provider holds', async () => {
    const provider = localStateProviderFor(counterState(37n));
    const h = harness({ module: calleeModule({ localState: true }), localStateProvider: provider });

    expect(await h.call(5n)).toBe(42n);
    expect(provider.asked).toBe(1);
  });

  test("a second sequential call in the transaction sees the first one's writes, and the provider is asked once", async () => {
    const provider = localStateProviderFor(counterState(10n));
    const h = harness({ module: calleeModule({ localState: true }), localStateProvider: provider });

    expect(await h.call(1n)).toBe(11n);
    expect(await h.call(2n)).toBe(13n);

    expect(provider.asked).toBe(1);
    expect(countOf(h.context.localQueryContexts[h.calleeAddress].state.state)).toBe(13n);
    // One record per call, each the callee's own, flat in the trace.
    expect(h.context.callProofDataTrace.map((record) => record.contractAddress)).toEqual([h.calleeAddress, h.calleeAddress]);
  });

  test('a root call leaves the context it was given without the capsules its callee used, so a second starts afresh', async () => {
    const provider = localStateProviderFor(counterState(10n));
    const h = harness({ module: calleeModule({ localState: true }), localStateProvider: provider });
    // a generated root wrapper runs on a copy of the context it is given
    const root = (x: bigint): Promise<bigint> =>
      crossContractCall({
        context: copyCircuitContext(h.context),
        interfaceName: 'Inner',
        declaration: DECLARATION,
        calleeCircuitId: CIRCUIT_ID,
        calleeAddress: h.calleeAddress,
        partialProofData: emptyProofData(),
        args: [x],
      });

    expect(await root(1n)).toBe(11n);
    expect(h.context.localQueryContexts[h.calleeAddress]).toBeUndefined();
    expect(await root(2n)).toBe(12n);
    expect(provider.asked).toBe(2);
  });

  test("leaves the caller's own local state alone", async () => {
    const h = harness({
      module: calleeModule({ localState: true }),
      localStateProvider: localStateProviderFor(undefined),
      callerLocalState: counterState(7n),
    });
    const callerCell = h.context.callContext.currentLocalQueryContext;

    await h.call(5n);

    expect(h.context.callContext.currentLocalQueryContext).toBe(callerCell);
    expect(countOf(h.context.localQueryContexts[h.callerAddress].state.state)).toBe(7n);
    expect(countOf(h.context.localQueryContexts[h.calleeAddress].state.state)).toBe(5n);
  });

  test("the two records: the callee's local transcript in its own, its return pinned in the caller's", async () => {
    const h = harness({ module: calleeModule({ localState: true }), localStateProvider: localStateProviderFor(undefined) });

    await h.call(5n);
    await h.call(6n);

    const [first, second] = h.context.callProofDataTrace;
    expect(first.contractAddress).toBe(h.calleeAddress);
    expect(first.localTranscript).toHaveLength(2);
    expect(second.localTranscript).toHaveLength(2);
    expect(first.calleeReturns).toBeUndefined();
    // The same values the caller's proof consumes, kept apart as this call's external results, each
    // beside the call it answers.
    expect(h.callerProofData.calleeReturns).toEqual([
      { contractAddress: h.calleeAddress, circuitId: CIRCUIT_ID, input: first.input, output: first.output },
      { contractAddress: h.calleeAddress, circuitId: CIRCUIT_ID, input: second.input, output: second.output },
    ]);
    expect(h.callerProofData.calleeReturns!.map(({ input }) => toBigint(input))).toEqual([5n, 6n]);
    expect(h.callerProofData.calleeReturns!.map(({ output }) => toBigint(output))).toEqual([5n, 11n]);
    expect(h.callerProofData.localTranscript).toBeUndefined();
  });

  test('cannot be resolved without a local state provider', async () => {
    const h = harness({ module: calleeModule({ localState: true }) });
    expect((await failureOf(h.call(5n))).kind).toBe('LocalStateProviderAbsent');
    expectNothingCommitted(h);
  });

  test('a provider that rejects is classified, and nothing is committed', async () => {
    const cause = new Error('store locked');
    const h = harness({
      module: calleeModule({ localState: true }),
      localStateProvider: { getLocalState: () => Promise.reject(cause) },
    });
    const failure = await failureOf(h.call(5n));
    if (failure.kind !== 'LocalStateProviderThrew') {
      throw new Error(`expected LocalStateProviderThrew, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(cause);
    expectNothingCommitted(h);
  });

  test('a provider that returns something other than a StateValue is classified too', async () => {
    const h = harness({
      module: calleeModule({ localState: true }),
      localStateProvider: { getLocalState: async () => 42 as unknown as ocrt.StateValue },
    });
    const failure = await failureOf(h.call(5n));
    if (failure.kind !== 'LocalStateProviderThrew') {
      throw new Error(`expected LocalStateProviderThrew, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(42);
    expectNothingCommitted(h);
  });
});

describe('a callee without local state', () => {
  test('runs with none, and the provider is never asked', async () => {
    const provider = localStateProviderFor(counterState(99n));
    const h = harness({ module: calleeModule({ localState: false }), localStateProvider: provider });

    expect(await h.call(5n)).toBe(5n);

    expect(provider.asked).toBe(0);
    expect(h.context.localQueryContexts[h.calleeAddress]).toBeUndefined();
    expect(h.context.callProofDataTrace[0].localTranscript).toBeUndefined();
  });

  test('needs no provider at all', async () => {
    const h = harness({ module: calleeModule({ localState: false }) });
    expect(await h.call(5n)).toBe(5n);
  });
});

describe('the host interface gate', () => {
  const requires = (hostInterfaces: HostInterfaceRequirements) => calleeModule({ localState: false, hostInterfaces });

  test('a callee declaring host functions cannot be resolved without a provider, and nothing is committed', async () => {
    const h = harness({ module: requires({ 'vendor:gate/any@1.0.0': ['f'] }) });
    expect((await failureOf(h.call(5n))).kind).toBe('HostInterfaceProviderAbsent');
    expectNothingCommitted(h);
  });

  test('an interface the provider does not resolve fails resolution, with nothing committed', async () => {
    const h = harness({
      module: requires({ 'vendor:gate/unresolved@1.0.0': ['f', 'g'] }),
      hostInterfaceProvider: hostInterfaceProviderOf({}),
    });
    const failure = await failureOf(h.call(5n));
    expect(failure).toEqual({
      kind: 'HostInterfaceAbsent',
      interfaceId: 'vendor:gate/unresolved@1.0.0',
      resolved: false,
      missing: ['f', 'g'],
    });
    expectNothingCommitted(h);
  });

  test('an incomplete implementation names the functions it lacks', async () => {
    const h = harness({
      module: requires({ 'vendor:gate/partial@1.0.0': ['f', 'g'] }),
      hostInterfaceProvider: hostInterfaceProviderOf({ 'vendor:gate/partial@1.0.0': { f: () => 1n } }),
    });
    expect(await failureOf(h.call(5n))).toEqual({
      kind: 'HostInterfaceAbsent',
      interfaceId: 'vendor:gate/partial@1.0.0',
      resolved: true,
      missing: ['g'],
    });
  });

  test('passes with a provider that serves the interface, and a module declaring none needs no provider', async () => {
    const module = requires({ 'vendor:gate/served@1.0.0': ['f'] });
    const served = harness({
      module,
      hostInterfaceProvider: hostInterfaceProviderOf({ 'vendor:gate/served@1.0.0': { f: () => 1n } }),
    });
    expect(await served.call(5n)).toBe(5n);

    const none = harness({ module: requires({}) });
    expect(await none.call(5n)).toBe(5n);
  });

  test('is checked before the capsule is looked up, so a provider is not consulted for a callee that cannot run', async () => {
    const provider = localStateProviderFor(undefined);
    const h = harness({
      module: calleeModule({ localState: true, hostInterfaces: { 'vendor:gate/first@1.0.0': ['f'] } }),
      localStateProvider: provider,
      hostInterfaceProvider: hostInterfaceProviderOf({}),
    });
    expect((await failureOf(h.call(5n))).kind).toBe('HostInterfaceAbsent');
    expect(provider.asked).toBe(0);
  });
});
