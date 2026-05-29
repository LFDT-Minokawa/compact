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

describe('Contract values stored in Map<Field, Inner>', () => {
  test('register then read the stored contract value back out', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [inner],
    );

    const { context: c1 } = await outer.circuits.register(
      ctxt0,
      1n,
      inner.encodedAddress,
    );
    expect((await outer.circuits.isRegistered(c1, 1n)).result).toEqual(true);

    const { result } = await outer.circuits.getRegistered(c1, 1n);
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('distinct keys map to distinct contract values', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [innerA, innerB],
    );

    let ctxt = (
      await outer.circuits.register(ctxt0, 1n, innerA.encodedAddress)
    ).context;
    ctxt = (await outer.circuits.register(ctxt, 2n, innerB.encodedAddress))
      .context;

    const a = (await outer.circuits.getRegistered(ctxt, 1n)).result;
    const b = (await outer.circuits.getRegistered(ctxt, 2n)).result;
    expect(bytesEqual(a.bytes, innerA.encodedAddress.bytes)).toEqual(true);
    expect(bytesEqual(b.bytes, innerB.encodedAddress.bytes)).toEqual(true);
  });

  test('absent key is reported as not a member', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [inner],
    );

    const { context: c1 } = await outer.circuits.register(
      ctxt0,
      1n,
      inner.encodedAddress,
    );
    expect((await outer.circuits.isRegistered(c1, 99n)).result).toEqual(false);
  });
});

describe('Contract values stored in List<Inner>', () => {
  test('enqueue then peek returns the contract value at the head', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [inner],
    );

    const { context: c1 } = await outer.circuits.enqueue(
      ctxt0,
      inner.encodedAddress,
    );
    const { result } = await outer.circuits.peek(c1);
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });

  test('most-recently pushed contract value is at the head', async () => {
    const innerA = await deployDependency({ module: innerCode, args: [] });
    const innerB = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [innerA, innerB],
    );

    let ctxt = (await outer.circuits.enqueue(ctxt0, innerA.encodedAddress))
      .context;
    ctxt = (await outer.circuits.enqueue(ctxt, innerB.encodedAddress)).context;

    const { result } = await outer.circuits.peek(ctxt);
    expect(bytesEqual(result.bytes, innerB.encodedAddress.bytes)).toEqual(true);
  });
});

describe('Contract values stored in MerkleTree<2, Inner>', () => {
  test('a contract value can be inserted as a leaf and the tree fills', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      { module: outerCode, witnesses: {}, initialPrivateState: 0, args: [] },
      [inner],
    );

    // A depth-2 tree holds 4 leaves.
    expect((await outer.circuits.treeFull(ctxt0)).result).toEqual(false);

    let ctxt = ctxt0;
    for (let i = 0; i < 4; i++) {
      ctxt = (await outer.circuits.store(ctxt, inner.encodedAddress)).context;
    }
    expect((await outer.circuits.treeFull(ctxt)).result).toEqual(true);
  });
});
