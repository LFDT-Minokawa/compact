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

// TODO: Enable when contract re-entrancy is supported
// Skipped: direct self-recursion (`foo` -> `self.foo`) re-enters a contract that is
// already executing, which the re-entrancy guard (on by default) now rejects. Kept
// as documentation of the previous threaded-state behaviour.
test.skip('self-recursion terminates and threads ledger state: foo(1) === 2', async () => {
  const chain = new TestChain();
  const self = await chain.deploy({ module: contractCode, args: [], initialPrivateState: 0 });

  // Wire `self` to its own address (one call transaction).
  await chain.call({
    module: contractCode,
    address: self.address,
    witnesses: {},
    privateState: 0,
    circuitId: 'set',
    args: [self.encodedAddress],
  });

  // foo(1): outer turn writes b=false then self-calls; the inner turn must see
  // b=false (base case) and return 1 + 1.
  const { result } = await chain.call({
    module: contractCode,
    address: self.address,
    witnesses: {},
    privateState: 0,
    circuitId: 'foo',
    args: [1n],
  });

  expect(result).toEqual(2n);

  const ledger = contractCode.ledger(chain.getContractStateOrThrow(self.address).data);
  expect(ledger.b).toEqual(false);
});

test('self-recursion (foo -> self.foo) is rejected by the re-entrancy guard', async () => {
  const chain = new TestChain();
  const self = await chain.deploy({ module: contractCode, args: [], initialPrivateState: 0 });

  // Point `self` at its own address; `set` performs no cross-contract call.
  await chain.call({
    module: contractCode,
    address: self.address,
    witnesses: {},
    privateState: 0,
    circuitId: 'set',
    args: [self.encodedAddress],
  });

  // foo's first turn (b === true) calls back into the same contract while it is
  // still executing, so the guard refuses to re-enter it and the call rejects.
  await expect(
    chain.call({
      module: contractCode,
      address: self.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'foo',
      args: [1n],
    }),
    // The message names the re-entered contract: `self` calling back into itself.
  ).rejects.toThrow(`Contract re-entrancy detected: '${self.address}'`);
});
