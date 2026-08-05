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

// Events thread up across a cross-contract call: the entry contract (Outer) emits
// one event and then cross-calls Inner, which emits another. The single result
// context should hold both, in emission order, each tagged with the address of the
// contract that emitted it — the integration point between the CCC threading model
// (`copyCircuitContext` / `restoreCircuitContext`) and the events list.

const deployPair = async (chain: TestChain) => {
  const inner = await chain.deploy({ module: innerCode, args: [], initialPrivateState: 0 });
  const outer = await chain.deploy({
    module: outerCode,
    args: [inner.encodedAddress],
    initialPrivateState: 0,
  });
  return { inner, outer };
};

describe('events thread across a cross-contract call', () => {
  test("a callee's event surfaces in the caller's result, after the caller's own, address-tagged", async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const n = new Uint8Array(32).fill(0x42);

    const { context } = (await chain.call({
      module: outerCode,
      address: outer.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'outerEmit',
      args: [n],
    })) as { result: bigint; context: any };

    // Two events on the single global list: the root's emit, then the callee's.
    expect(context.events.length).toEqual(2);

    // Emission order is preserved across the call boundary: the root contract emits
    // before it cross-calls, so its event comes first.
    expect(context.events[0].address).toEqual(outer.address);
    expect(context.events[1].address).toEqual(inner.address);
    expect(context.events[0].address).not.toEqual(context.events[1].address);

    // Each entry is a well-formed, decoded event record.
    for (const ev of context.events) {
      expect(ev.version).toEqual(1);
      expect(ev.eventType).toEqual('shielded-spend');
      expect(ev.data).toBeDefined();
    }
  });

  test('a standalone call to the callee emits exactly its own single event', async () => {
    const chain = new TestChain();
    const { inner } = await deployPair(chain);
    const n = new Uint8Array(32).fill(0x07);

    const { context } = (await chain.call({
      module: innerCode,
      address: inner.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'innerEmit',
      args: [n],
    })) as { result: bigint; context: any };

    expect(context.events.length).toEqual(1);
    expect(context.events[0].address).toEqual(inner.address);
    expect(context.events[0].eventType).toEqual('shielded-spend');
  });
});
