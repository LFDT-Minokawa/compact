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
    const inner = await deployDependency({ module: innerCode, args: [] });
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {
          chooseInner: ({ privateState }: any) => [
            privateState,
            inner.encodedAddress,
          ],
          inspectInner: ({ privateState }: any, _i: any) => [privateState, 0n],
        },
        initialPrivateState: 0,
        args: [],
      },
      [inner],
    );

    const { result } = await outer.circuits.pickViaWitness(ctxt0);
    expect(bytesEqual(result.bytes, inner.encodedAddress.bytes)).toEqual(true);
  });
});

describe('Witnesses can accept contract values', () => {
  test('inspectViaWitness passes a contract value into the witness', async () => {
    const inner = await deployDependency({ module: innerCode, args: [] });
    let received: Uint8Array | undefined;
    const [outer, ctxt0] = await startContractGroup(
      {
        module: outerCode,
        witnesses: {
          chooseInner: ({ privateState }: any) => [
            privateState,
            inner.encodedAddress,
          ],
          inspectInner: ({ privateState }: any, i: any) => {
            received = i.bytes;
            // Derive a Field from the contract value so we can assert on it.
            return [privateState, BigInt(i.bytes[0])];
          },
        },
        initialPrivateState: 0,
        args: [],
      },
      [inner],
    );

    const expectedFirst = BigInt(inner.encodedAddress.bytes[0]);
    const { result } = await outer.circuits.inspectViaWitness(
      ctxt0,
      inner.encodedAddress,
    );

    expect(received !== undefined).toEqual(true);
    expect(
      bytesEqual(received as Uint8Array, inner.encodedAddress.bytes),
    ).toEqual(true);
    expect(result).toEqual(expectedFirst);
  });
});
