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

/** Invoke a circuit on the Liar contract as a call transaction. */
const callLiar = (
  chain: TestChain,
  address: any,
  circuitId: string,
  ...args: readonly unknown[]
): Promise<{ result: any; context: any }> =>
  chain.call({
    module: liarCode,
    address,
    witnesses: {},
    privateState: 0,
    circuitId,
    args,
  }) as unknown as Promise<{ result: any; context: any }>;

describe('cross-contract purity gate', () => {
  test('a callee circuit the interface mislabels as impure is rejected at runtime', async () => {
    const chain = new TestChain();
    // Honest.add does not mutate ledger state, so it is pure and present in Honest's `pureCircuits`.
    // Liar's interface independently declares `circuit add`, which compiles cleanly and lowers the cross-contract call
    // with calleeIsPure = false.
    const honest = await chain.deploy({ module: honestCode, args: [], initialPrivateState: 0 });
    const liar = await chain.deploy({
      module: liarCode,
      args: [honest.encodedAddress],
      initialPrivateState: 0,
    });

    // assertPurityMatches looks `add` up in Honest.pureCircuits, finds it, and throws — so the call transaction rejects
    // instead of executing.
    await expect(callLiar(chain, liar.address, 'callAdd', 5n)).rejects.toThrow(
      /Expected pure circuit 'add' for callee '.*' to be undefined/,
    );
  });
});
