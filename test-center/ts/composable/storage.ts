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

describe('Contract values stored in Map<Field, Inner>', () => {
  test('register then read the stored contract value back out', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    await callOuter(chain, outer.address, 'register', 1n, inner.encodedAddress);
    expect((await callOuter(chain, outer.address, 'isRegistered', 1n)).result).toEqual(true);

    const { result } = await callOuter(chain, outer.address, 'getRegistered', 1n);
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('distinct keys map to distinct contract values', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    await callOuter(chain, outer.address, 'register', 1n, innerA.encodedAddress);
    await callOuter(chain, outer.address, 'register', 2n, innerB.encodedAddress);

    const a = (await callOuter(chain, outer.address, 'getRegistered', 1n)).result;
    const b = (await callOuter(chain, outer.address, 'getRegistered', 2n)).result;
    expect(bytesEqual(a.bytes, innerA.encodedAddress.bytes)).toEqual(true);
    expect(bytesEqual(b.bytes, innerB.encodedAddress.bytes)).toEqual(true);
  });

  test('absent key is reported as not a member', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    await callOuter(chain, outer.address, 'register', 1n, inner.encodedAddress);
    expect((await callOuter(chain, outer.address, 'isRegistered', 99n)).result).toEqual(false);
  });
});

describe('Contract values stored in List<Inner>', () => {
  test('enqueue then peek returns the contract value at the head', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    await callOuter(chain, outer.address, 'enqueue', inner.encodedAddress);
    const { result } = await callOuter(chain, outer.address, 'peek');
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('most-recently pushed contract value is at the head', async () => {
    const chain = new TestChain();
    const innerA = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const innerB = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    await callOuter(chain, outer.address, 'enqueue', innerA.encodedAddress);
    await callOuter(chain, outer.address, 'enqueue', innerB.encodedAddress);

    const { result } = await callOuter(chain, outer.address, 'peek');
    expect(bytesEqual(result.bytes, innerB.encodedAddress.bytes)).toEqual(true);
  });
});

describe('Contract values stored in MerkleTree<2, Inner>', () => {
  test('a contract value can be inserted as a leaf and the tree fills', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
    const outer = await chain.deploy({ module: outerCode, args: [], initialPrivateState: 0 });

    // A depth-2 tree holds 4 leaves.
    expect((await callOuter(chain, outer.address, 'treeFull')).result).toEqual(false);

    for (let i = 0; i < 4; i++) {
      await callOuter(chain, outer.address, 'store', inner.encodedAddress);
    }
    expect((await callOuter(chain, outer.address, 'treeFull')).result).toEqual(true);
  });
});
