// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// The module a call resolves to has to be the code deployed at that address. Both sides of every
// comparison here are the harness's: this suite compiles with `skip-zk`, so `TestChain.deploy`
// installs the keys and computes the fingerprints over the same bytes.

/** Invoke a circuit on an Outer contract as a call transaction. */
const callOuter = (
  chain: TestChain,
  address: any,
  circuitId: string,
  ...args: readonly unknown[]
): Promise<{ result: any; context: any }> =>
  chain.call({
    module: outerCode,
    address,
    witnesses: {},
    privateState: 0,
    circuitId,
    args,
  }) as unknown as Promise<{ result: any; context: any }>;

/** The deployed verifier key for one operation, or `undefined` if the operation carries none. */
const deployedKey = (chain: TestChain, address: any, circuitId: string): Uint8Array | undefined =>
  chain.getContractStateOrThrow(address).operation(circuitId)?.verifierKey;

/** The same digest with its first character changed: still well-formed, certainly not deployed. */
const perturb = (hash: string): string => (hash.startsWith('0') ? '1' : '0') + hash.slice(1);

/** Run `call` and return the error it rejected with, asserting that it rejected at all. */
const rejection = async (call: Promise<unknown>): Promise<any> => {
  const error = await call.then(
    () => undefined,
    (e: unknown) => e,
  );
  if (!runtime.ModuleResolutionError.is(error)) {
    throw new Error(`expected a ModuleResolutionError, got ${String(error)}`);
  }
  return error;
};

describe('cross-contract key agreement', () => {
  test('a call binds when the resolved module is the one deployed at the address', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    const key = deployedKey(chain, inner.address, 'add');
    if (key === undefined) {
      throw new Error('the harness installed no verifier key on Inner.add');
    }
    expect(inner.module.expectedVk['add']).toEqual(runtime.verifierKeyHashOf(key));

    const { result } = await callOuter(chain, outer.address, 'add', 7n);
    expect(result).toEqual(7n);
  });

  test('two deployments of one contract are interchangeable', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [innerA.encodedAddress],
      initialPrivateState: 0,
    });

    // The harness keys by compiled contract, as a chain does, so identical code deployed twice has
    // identical keys — and B's module really is a correct implementation of what is at A's address.
    expect(innerB.module.expectedVk).toEqual(innerA.module.expectedVk);
    chain.overrideModule(innerA.address, innerB.module);

    const { result } = await callOuter(chain, outer.address, 'add', 7n);
    expect(result).toEqual(7n);
  });

  test('a module for different code is rejected', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    // Outer also has `add(Field): Field`, so it clears conformance and only the keys can tell it
    // apart from the Inner deployed at that address.
    expect(outer.module.expectedVk['add']).not.toEqual(inner.module.expectedVk['add']);
    chain.overrideModule(inner.address, outer.module);

    const error = await rejection(callOuter(chain, outer.address, 'add', 7n));
    expect(error.context.calleeAddress).toEqual(inner.address);
    if (error.failure.kind !== 'ImplementationMismatch') {
      throw new Error(`expected ImplementationMismatch, got ${error.failure.kind}`);
    }
    expect(error.failure.circuitId).toEqual('add');
    expect(error.failure.expected).toEqual(outer.module.expectedVk['add']);
    expect(error.failure.actual).toEqual(inner.module.expectedVk['add']);
  });

  test('a disagreement on a circuit other than the called one is caught', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const caller = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });
    // An Outer stands in as the callee, since the overlap rule needs a callee carrying more than one
    // operation and Inner has exactly one.
    const callee = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });
    await callOuter(chain, caller.address, 'setInner', callee.encodedAddress);

    // `add` still agrees, so the call gets past the mandatory comparison and into the overlap.
    const expectedVk = { ...callee.module.expectedVk, setInner: perturb(callee.module.expectedVk['setInner']) };
    chain.overrideModule(callee.address, { ...callee.module, expectedVk });

    const error = await rejection(callOuter(chain, caller.address, 'add', 7n));
    if (error.failure.kind !== 'ImplementationMismatch') {
      throw new Error(`expected ImplementationMismatch, got ${error.failure.kind}`);
    }
    expect(error.context.calleeCircuitId).toEqual('add');
    expect(error.failure.circuitId).toEqual('setInner');
    expect(error.failure.actual).toEqual(callee.module.expectedVk['setInner']);
  });

  test('a module recording no fingerprint at all is rejected', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    // The shape a module compiled with `skip-zk` has. There is a key on chain and nothing to
    // compare it against, so the module cannot be shown to be the deployed code.
    chain.overrideModule(inner.address, { ...inner.module, expectedVk: {} });

    const error = await rejection(callOuter(chain, outer.address, 'add', 7n));
    if (error.failure.kind !== 'ImplementationMismatch') {
      throw new Error(`expected ImplementationMismatch, got ${error.failure.kind}`);
    }
    expect(error.failure.expected).toBeUndefined();
    expect(error.failure.actual).toEqual(inner.module.expectedVk['add']);
  });

  test('a recorded fingerprint that is not a digest is its own failure', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    // Not a mismatch: there was nothing comparable to disagree with.
    chain.overrideModule(inner.address, {
      ...inner.module,
      expectedVk: { ...inner.module.expectedVk, add: 'not-a-digest' },
    });

    const error = await rejection(callOuter(chain, outer.address, 'add', 7n));
    if (error.failure.kind !== 'MalformedVerifierKeyHash') {
      throw new Error(`expected MalformedVerifierKeyHash, got ${error.failure.kind}`);
    }
    expect(error.failure.circuitId).toEqual('add');
    expect(error.failure.recorded).toEqual('not-a-digest');
  });

  test('an operation deployed without a verifier key is rejected', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    chain.getContractStateOrThrow(inner.address).setOperation('add', new runtime.ContractOperation());
    expect(deployedKey(chain, inner.address, 'add')?.length ?? 0).toEqual(0);

    const error = await rejection(callOuter(chain, outer.address, 'add', 7n));
    expect(error.failure.kind).toEqual('OperationAbsent');
    expect(error.context.calleeCircuitId).toEqual('add');
  });
});
