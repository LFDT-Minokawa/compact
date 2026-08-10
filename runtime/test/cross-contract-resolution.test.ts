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

// How `crossContractCall` classifies everything that can go wrong before a callee is entered.
//
// `module-resolution.test.ts` covers the failure payloads as values — what they carry, how they
// read. This covers the code that decides which one to raise, which is only reachable by making the
// call. It is the one place in this suite that does.
//
// Nothing here needs a conformant module or a deployed key: every case below fails before the
// module is in hand. The cases past that point are `test-center`'s, against generated modules.

import { describe, expect, test } from 'vitest';
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  CircuitContext,
  ContractModuleProvider,
  ContractStateProvider,
  InterfaceDescriptor,
  ModuleResolutionError,
  ModuleThunk,
  PartialProofData,
  createCircuitContext,
  crossContractCall,
} from '../src/index.js';

const COIN_PUBLIC_KEY = '0'.repeat(64);
const PARENT_BLOCK_HASH = '0'.repeat(64);
const CIRCUIT_ID = 'add';

/** A contract type declaring one impure circuit, as the caller's `declaredInterfaces` would hold. */
const DECLARATION: InterfaceDescriptor = {
  [CIRCUIT_ID]: { pure: false, argumentTypes: [{ tag: 'Field' }], resultType: { tag: 'Field' } },
};

const emptyProofData = (): PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
});

/** A chain holding one contract, deployed at `address`, with `add` as an operation. */
const stateProviderFor = (address: ocrt.ContractAddress): ContractStateProvider => {
  const state = new ocrt.ContractState();
  state.setOperation(CIRCUIT_ID, new ocrt.ContractOperation());
  return { getContractState: async (_blockHash, queried) => (queried === address ? state : undefined) };
};

/**
 * Make the call and return the resolution failure it raised. Fails the test if it raised something
 * else, or nothing: a case that stops failing has to be noticed rather than pass.
 */
const failureFrom = async (options: {
  moduleProvider?: ContractModuleProvider;
  declaration?: InterfaceDescriptor;
}): Promise<ModuleResolutionError['failure']> => {
  const calleeAddress = ocrt.sampleContractAddress();
  const context: CircuitContext = createCircuitContext(
    'caller',
    ocrt.sampleContractAddress(),
    COIN_PUBLIC_KEY,
    new ocrt.ContractState(),
    0,
    stateProviderFor(calleeAddress),
    undefined,
    undefined,
    0,
    PARENT_BLOCK_HASH,
    true,
    options.moduleProvider,
  );
  try {
    await crossContractCall({
      context,
      interfaceName: 'Inner',
      declaration: options.declaration ?? DECLARATION,
      calleeCircuitId: CIRCUIT_ID,
      calleeAddress,
      partialProofData: emptyProofData(),
      args: [1n],
    });
  } catch (error) {
    if (ModuleResolutionError.is(error)) {
      return error.failure;
    }
    throw new Error(`expected a ModuleResolutionError, got ${String(error)}`);
  }
  throw new Error('expected the call to reject');
};

/** A provider whose thunk rejects with `rejection`. */
const rejectingProvider = (rejection: unknown): ContractModuleProvider => ({
  resolve: () => () => Promise.reject(rejection),
});

describe('crossContractCall failure classification', () => {
  test('no module provider on the context', async () => {
    expect((await failureFrom({})).kind).toEqual('ModuleProviderAbsent');
  });

  test('the contract type declares the called circuit pure', async () => {
    const failure = await failureFrom({
      moduleProvider: rejectingProvider(new Error('never reached')),
      declaration: { [CIRCUIT_ID]: { pure: true, argumentTypes: [], resultType: { tag: 'Field' } } },
    });
    // Ahead of everything else: a pure circuit has no verifier key and is never a deployed operation,
    // so there is nothing to resolve rather than something that fails to resolve.
    expect(failure.kind).toEqual('PureInterfaceCircuit');
  });

  test('the provider has no binding for the address', async () => {
    const failure = await failureFrom({ moduleProvider: { resolve: () => undefined } });
    expect(failure.kind).toEqual('UnsupportedImplementation');
  });

  test('the provider throws', async () => {
    const cause = new Error('table not loaded');
    const failure = await failureFrom({
      moduleProvider: {
        resolve: () => {
          throw cause;
        },
      },
    });
    if (failure.kind !== 'ProviderThrew') {
      throw new Error(`expected ProviderThrew, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(cause);
  });

  test('the provider returns something that is not a thunk', async () => {
    // A provider is application code and may be untyped at the boundary. Returning the module itself
    // rather than a thunk for it is the easy mistake, and it is the provider's defect, not a load
    // failure.
    const notAThunk = { Contract: class {} } as unknown as ModuleThunk;
    const failure = await failureFrom({ moduleProvider: { resolve: () => notAThunk } });
    if (failure.kind !== 'ProviderThrew') {
      throw new Error(`expected ProviderThrew, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(notAThunk);
  });

  test('the thunk rejects', async () => {
    const cause = new Error('chunk 42 failed');
    const failure = await failureFrom({ moduleProvider: rejectingProvider(cause) });
    if (failure.kind !== 'ModuleLoadRejected') {
      throw new Error(`expected ModuleLoadRejected, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(cause);
  });

  test('a wrapped rejection is passed through whole, not unwrapped or inspected', async () => {
    const wrapped = new Error('outer', { cause: new Error('inner', { cause: new Error('ECONNRESET') }) });
    const failure = await failureFrom({ moduleProvider: rejectingProvider(wrapped) });
    if (failure.kind !== 'ModuleLoadRejected') {
      throw new Error(`expected ModuleLoadRejected, got ${failure.kind}`);
    }
    expect(failure.cause).toBe(wrapped);
  });

  test('a rejection that is not an Error is carried too', async () => {
    const failure = await failureFrom({ moduleProvider: rejectingProvider('offline') });
    if (failure.kind !== 'ModuleLoadRejected') {
      throw new Error(`expected ModuleLoadRejected, got ${failure.kind}`);
    }
    expect(failure.cause).toEqual('offline');
  });

  test('every failure names the call it could not bind', async () => {
    const calleeAddress = ocrt.sampleContractAddress();
    const callerAddress = ocrt.sampleContractAddress();
    const context: CircuitContext = createCircuitContext(
      'caller',
      callerAddress,
      COIN_PUBLIC_KEY,
      new ocrt.ContractState(),
      0,
      stateProviderFor(calleeAddress),
      undefined,
      undefined,
      0,
      PARENT_BLOCK_HASH,
      true,
      { resolve: () => undefined },
    );
    const error = await crossContractCall({
      context,
      interfaceName: 'Inner',
      declaration: DECLARATION,
      calleeCircuitId: CIRCUIT_ID,
      calleeAddress,
      partialProofData: emptyProofData(),
      args: [1n],
    }).then(
      () => undefined,
      (e: unknown) => e,
    );
    if (!ModuleResolutionError.is(error)) {
      throw new Error(`expected a ModuleResolutionError, got ${String(error)}`);
    }
    expect(error.context).toEqual({ calleeAddress, calleeCircuitId: CIRCUIT_ID, interfaceName: 'Inner', callerAddress });
  });
});
