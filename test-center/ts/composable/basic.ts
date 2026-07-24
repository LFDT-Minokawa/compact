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

/** Read the `v` field of the Inner ledger from the chain's persisted state. */
const innerV = (chain: TestChain, address: any): bigint =>
  innerCode.ledger(chain.getContractStateOrThrow(address).data).v;

const bytesEqual = (a: Uint8Array, b: Uint8Array): boolean => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};

/** Invoke a circuit on the Outer contract as a call transaction. */
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

describe('Outer.add forwards to Inner.add', () => {
  test('single call: result equals Inner.v after the call', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    const { result } = await callOuter(chain, outer.address, 'add', 7n);
    expect(result).toEqual(7n);
    expect(innerV(chain, inner.address)).toEqual(7n);
  });

  test('chain of five Outer.add calls returns running totals', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    const adds = [3n, 5n, 7n, 11n, 13n];
    let running = 0n;
    for (const v of adds) {
      // Each add is its own transaction; Inner.v persists across them via the store.
      const { result } = await callOuter(chain, outer.address, 'add', v);
      running += v;
      expect(result).toEqual(running);
    }
    expect(innerV(chain, inner.address)).toEqual(adds.reduce((a, b) => a + b, 0n));
  });
});

describe('setInner swaps which Inner is current', () => {
  test('setInner returns the previously-stored inner address', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [innerA.encodedAddress],
      initialPrivateState: 0,
    });

    const { result } = await callOuter(chain, outer.address, 'setInner', innerB.encodedAddress);
    expect(bytesEqual(result.bytes, innerA.encodedAddress.bytes)).toEqual(true);
  });

  test('setInner directs subsequent Outer.add to the new inner', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [innerA.encodedAddress],
      initialPrivateState: 0,
    });

    // 1. add against A
    await callOuter(chain, outer.address, 'add', 3n);
    expect(innerV(chain, innerA.address)).toEqual(3n);
    // B has not been referenced yet — the provider has never been asked for it.
    expect(chain.fetchCount(innerB.address)).toEqual(0);

    // 2. swap to B
    await callOuter(chain, outer.address, 'setInner', innerB.encodedAddress);
    // A's committed state survives the swap.
    expect(innerV(chain, innerA.address)).toEqual(3n);

    // 3. add against B
    const { result } = await callOuter(chain, outer.address, 'add', 5n);
    expect(result).toEqual(5n);
    expect(innerV(chain, innerA.address)).toEqual(3n); // A unchanged
    expect(innerV(chain, innerB.address)).toEqual(5n);
  });

  test('setInner to the same inner is functionally a no-op', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    await callOuter(chain, outer.address, 'add', 3n);
    await callOuter(chain, outer.address, 'setInner', inner.encodedAddress);
    const { result } = await callOuter(chain, outer.address, 'add', 5n);
    expect(result).toEqual(8n);
    expect(innerV(chain, inner.address)).toEqual(8n);
  });

  test('rotating through three inners keeps each independent', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerC = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [innerA.encodedAddress],
      initialPrivateState: 0,
    });

    await callOuter(chain, outer.address, 'add', 1n); // A.v = 1
    await callOuter(chain, outer.address, 'setInner', innerB.encodedAddress);
    await callOuter(chain, outer.address, 'add', 2n); // B.v = 2
    await callOuter(chain, outer.address, 'setInner', innerC.encodedAddress);
    await callOuter(chain, outer.address, 'add', 3n); // C.v = 3
    await callOuter(chain, outer.address, 'setInner', innerA.encodedAddress);
    await callOuter(chain, outer.address, 'add', 10n); // A.v = 11

    expect(innerV(chain, innerA.address)).toEqual(11n);
    expect(innerV(chain, innerB.address)).toEqual(2n);
    expect(innerV(chain, innerC.address)).toEqual(3n);
  });

  test('outer.inner ledger field reflects the most recent setInner', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [innerA.encodedAddress],
      initialPrivateState: 0,
    });

    // Before the swap, Outer.inner = innerA.
    const outerLedger0 = outerCode.ledger(chain.getContractStateOrThrow(outer.address).data);
    expect(bytesEqual(outerLedger0.inner.bytes, innerA.encodedAddress.bytes)).toEqual(true);

    await callOuter(chain, outer.address, 'setInner', innerB.encodedAddress);
    const outerLedger1 = outerCode.ledger(chain.getContractStateOrThrow(outer.address).data);
    expect(bytesEqual(outerLedger1.inner.bytes, innerB.encodedAddress.bytes)).toEqual(true);
  });
});

describe('Multiple Outer instances stay isolated', () => {
  test('two Outers each wrapping their own Inner do not interfere', async () => {
    const chain = new TestChain();
    const inner1 = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const inner2 = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer1 = await chain.deploy({
      module: outerCode,
      args: [inner1.encodedAddress],
      initialPrivateState: 0,
    });
    const outer2 = await chain.deploy({
      module: outerCode,
      args: [inner2.encodedAddress],
      initialPrivateState: 0,
    });

    const r1 = await callOuter(chain, outer1.address, 'add', 4n);
    const r2 = await callOuter(chain, outer2.address, 'add', 9n);

    expect(innerV(chain, inner1.address)).toEqual(4n);
    expect(innerV(chain, inner2.address)).toEqual(9n);

    // Each transaction only ever referenced its own inner.
    expect(r1.context.queryContexts[inner2.address]).toBeUndefined();
    expect(r2.context.queryContexts[inner1.address]).toBeUndefined();
  });
});

describe('Contract values are first-class: const assignment', () => {
  test('echoStored threads the stored contract value through const bindings', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    const { result } = await callOuter(chain, outer.address, 'echoStored');
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('echoInner round-trips a contract value passed as a parameter', async () => {
    const chain = new TestChain();
    const stored = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const other = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [stored.encodedAddress],
      initialPrivateState: 0,
    });

    // The value returned is the argument, independent of the stored ledger field.
    const { result } = await callOuter(chain, outer.address, 'echoInner', other.encodedAddress);
    expect(bytesEqual(result.bytes, other.encodedAddress.bytes)).toEqual(true);
    expect(bytesEqual(result.bytes, stored.encodedAddress.bytes)).toEqual(false);
  });

  test('a const-bound contract value can be the receiver of a call', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({
      module: outerCode,
      args: [inner.encodedAddress],
      initialPrivateState: 0,
    });

    const { result } = await callOuter(chain, outer.address, 'addViaConst', 6n);
    expect(result).toEqual(6n);
    expect(innerV(chain, inner.address)).toEqual(6n);
  });
});
