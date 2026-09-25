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

// `kernel.caller()` through the runtime's own call path: the parent is set when a
// callee is entered (and re-set when a cached callee is re-entered), a root call
// and a constructor see `none`. The PR's inline tests set `block.caller` by hand;
// these do not touch it.

const ZERO32 = new Uint8Array(32);

const none = () => ({
  is_some: false,
  value: { is_left: false, left: { bytes: ZERO32 }, right: { bytes: ZERO32 } },
});

const calledByContract = (encodedAddress: { bytes: Uint8Array }) => ({
  is_some: true,
  value: { is_left: true, left: { bytes: encodedAddress.bytes }, right: { bytes: ZERO32 } },
});

const call = (
  chain: TestChain,
  module: any,
  address: any,
  circuitId: string,
): Promise<{ result: any; context: any }> =>
  chain.call({
    module,
    address,
    witnesses: {},
    privateState: 0,
    circuitId,
    args: [],
  }) as unknown as Promise<{ result: any; context: any }>;

const deployAll = async () => {
  const chain = new TestChain();
  const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
  const middle = await chain.deploy({
    module: middleCode,
    args: [inner.encodedAddress],
    initialPrivateState: 0,
  });
  const outer = await chain.deploy({
    module: outerCode,
    args: [inner.encodedAddress, middle.encodedAddress],
    initialPrivateState: 0,
  });
  return { chain, inner, middle, outer };
};

describe('kernel.caller() through the runtime call path', () => {
  test('a root call sees none', async () => {
    const { chain, inner, outer } = await deployAll();
    expect((await call(chain, innerCode, inner.address, 'whoCalled')).result).toEqual(none());
    expect((await call(chain, outerCode, outer.address, 'direct')).result).toEqual(none());
  });

  test('a constructor sees none', async () => {
    const { chain, inner } = await deployAll();
    const ledger = innerCode.ledger(chain.getContractStateOrThrow(inner.address).data);
    expect(ledger.deployer).toEqual(none());
  });

  test('a callee sees left(parent)', async () => {
    const { chain, outer } = await deployAll();
    const { result } = await call(chain, outerCode, outer.address, 'viaInner');
    expect(result).toEqual(calledByContract(outer.encodedAddress));
  });

  test('a callee sees its immediate parent, not the root', async () => {
    const { chain, middle, outer } = await deployAll();
    const { result } = await call(chain, outerCode, outer.address, 'viaMiddle');
    expect(result).toEqual(calledByContract(middle.encodedAddress));
  });

  test('the same callee entered from two parents in one transaction sees each in turn', async () => {
    const { chain, middle, outer } = await deployAll();
    const { result } = await call(chain, outerCode, outer.address, 'both');
    expect(result).toEqual([calledByContract(outer.encodedAddress), calledByContract(middle.encodedAddress)]);
  });

  test('a callee does not inherit a caller set on the root', async () => {
    // The root's own context is the only one a DApp could set today, and it must not leak
    // into callees. Their caller is the parent contract, whatever the root's is.
    const { chain, inner, outer } = await deployAll();
    const { result, context } = await call(chain, outerCode, outer.address, 'viaInner');
    expect(result).toEqual(calledByContract(outer.encodedAddress));
    expect(context.queryContexts[outer.address].block.caller).toBeUndefined();
    const innerCaller = context.queryContexts[inner.address].block.caller;
    expect(innerCaller.tag).toEqual('contract');
    expect(runtime.encodeContractAddress(innerCaller.address)).toEqual(outer.encodedAddress.bytes);
  });
});
