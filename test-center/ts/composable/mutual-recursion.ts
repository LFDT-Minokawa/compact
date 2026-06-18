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

// Mutual recursion across contract boundaries.

const bytesEqual = (a: Uint8Array, b: Uint8Array): boolean => {
  if (a.length !== b.length) return false;
  for (let i = 0; i < a.length; i++) {
    if (a[i] !== b[i]) return false;
  }
  return true;
};

/** Read a contract's `called` Counter from the chain's persisted state. */
const aCalled = (chain: TestChain, address: any): bigint =>
  aCode.ledger(chain.getContractStateOrThrow(address).data).called;

const bCalled = (chain: TestChain, address: any): bigint =>
  bCode.ledger(chain.getContractStateOrThrow(address).data).called;

/**
 * Deploy A and B, then wire them to each other with two independent call
 * transactions. Returns the chain and the two deployed-contract handles.
 */
const buildWiredChain = async () => {
  const chain = new TestChain();

  const a = await chain.deploy({ module: aCode, args: [], initialPrivateState: 0 });
  const b = await chain.deploy({ module: bCode, args: [], initialPrivateState: 0 });

  // A.set(B): A.ledger.b := B's address. No cross-contract call; commits A only.
  await chain.call({
    module: aCode,
    address: a.address,
    witnesses: {},
    privateState: 0,
    circuitId: 'set',
    args: [b.encodedAddress],
  });

  // B.set(A): B.ledger.a := A's address. No cross-contract call; commits B only.
  await chain.call({
    module: bCode,
    address: b.address,
    witnesses: {},
    privateState: 0,
    circuitId: 'set',
    args: [a.encodedAddress],
  });

  return { chain, a, b };
};

describe('Mutually recursive contracts across independent transactions', () => {
  test('set transactions persist: the stored reference fields point at each other', async () => {
    const { chain, a, b } = await buildWiredChain();

    const aLedger = aCode.ledger(chain.getContractStateOrThrow(a.address).data);
    const bLedger = bCode.ledger(chain.getContractStateOrThrow(b.address).data);

    // Each `set` mutation was committed back to the chain.
    expect(bytesEqual(aLedger.b.bytes, b.encodedAddress.bytes)).toEqual(true);
    expect(bytesEqual(bLedger.a.bytes, a.encodedAddress.bytes)).toEqual(true);
  });

  test('A.isOdd descends through B.isEven and back; B is fetched from the provider', async () => {
    const { chain, a, b } = await buildWiredChain();

    const { result } = await chain.call({
      module: aCode,
      address: a.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'isOdd',
      args: [5n],
    });

    expect(result).toEqual(true); // 5 is odd

    // The isOdd transaction seeded `queryContexts` with the entry contract A only;
    // B's post-set state was pulled from the chain via the ContractStateProvider.
    // A, being the entry point, is resolved from the seed and never re-fetched.
    expect(chain.fetchCount(b.address)).toBeGreaterThan(0);
    expect(chain.fetchCount(a.address)).toEqual(0);
  });

  // The state-threading test
  test('re-entrant turns thread ledger state: per-contract counters accumulate', async () => {
    const { chain, a, b } = await buildWiredChain();

    const { result } = await chain.call({
      module: aCode,
      address: a.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'isOdd',
      args: [5n],
    });
    expect(result).toEqual(true);

    expect(aCalled(chain, a.address)).toEqual(3n);
    expect(bCalled(chain, b.address)).toEqual(3n);
  });

  test('an even argument returns false', async () => {
    const { chain, a } = await buildWiredChain();

    const { result } = await chain.call({
      module: aCode,
      address: a.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'isOdd',
      args: [4n],
    });

    expect(result).toEqual(false);
  });

  test('base case: A.isOdd(0) short-circuits without entering B', async () => {
    const { chain, a, b } = await buildWiredChain();

    const { result } = await chain.call({
      module: aCode,
      address: a.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'isOdd',
      args: [0n],
    });

    expect(result).toEqual(false);
    // x == 0 returns before the cross-contract call, so B is never fetched.
    expect(chain.fetchCount(b.address)).toEqual(0);
  });

  test('starting from B: B.isEven composes symmetrically', async () => {
    const { chain, a, b } = await buildWiredChain();

    const { result } = await chain.call({
      module: bCode,
      address: b.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'isEven',
      args: [6n],
    });

    expect(result).toEqual(true);
    expect(chain.fetchCount(a.address)).toBeGreaterThan(0);
    expect(chain.fetchCount(b.address)).toEqual(0);

    // Threading holds with B as the entry point and A resolved from the provider.
    expect(bCalled(chain, b.address)).toEqual(4n);
    expect(aCalled(chain, a.address)).toEqual(3n);
  });
});
