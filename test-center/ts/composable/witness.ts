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

describe('Witnesses can return contract values', () => {
  test('pickViaWitness returns the contract value the witness chose', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });

    const witnesses = {
      chooseInner: ({ privateState }: any): [any, any] => [privateState, inner.encodedAddress],
      inspectInner: ({ privateState }: any, _i: any): [any, any] => [privateState, 0n],
    };

    const outer = await chain.deploy({
      module: outerCode,
      args: [],
      initialPrivateState: 0,
      witnesses,
    });

    const { result } = (await chain.call({
      module: outerCode,
      address: outer.address,
      witnesses,
      privateState: 0,
      circuitId: 'pickViaWitness',
      args: [],
    })) as { result: any };
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });
});

describe('Witnesses can accept contract values', () => {
  test('inspectViaWitness passes a contract value into the witness', async () => {
    const chain = new TestChain();
    const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });

    let received: Uint8Array | undefined;
    const witnesses = {
      chooseInner: ({ privateState }: any): [any, any] => [privateState, inner.encodedAddress],
      inspectInner: ({ privateState }: any, i: any): [any, any] => {
        received = i.bytes;
        // Derive a Field from the contract value so we can assert on it.
        return [privateState, BigInt(i.bytes[0])];
      },
    };

    const outer = await chain.deploy({
      module: outerCode,
      args: [],
      initialPrivateState: 0,
      witnesses,
    });

    const expectedFirst = BigInt(inner.encodedAddress.bytes[0]);
    const { result } = (await chain.call({
      module: outerCode,
      address: outer.address,
      witnesses,
      privateState: 0,
      circuitId: 'inspectViaWitness',
      args: [inner.encodedAddress],
    })) as { result: any };

    expect(received !== undefined).toEqual(true);
    expect(bytesEqual(received as Uint8Array, inner.encodedAddress.bytes)).toEqual(true);
    expect(result).toEqual(expectedFirst);
  });
});
