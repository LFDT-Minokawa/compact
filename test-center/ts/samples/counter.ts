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

// The public round counter beside each account's private count of its own calls.

const increment = (chain: TestChain, address: any, account: Account) =>
  chain.call({ module: contractCode, address, circuitId: 'increment', args: [], account });

const count = (account: Account, address: any): bigint => contractCode.localState(account.localState(address)!).count;

test('each account counts its own calls; the chain counts them all', async () => {
  const chain = new TestChain();
  const { address } = await chain.deploy({ module: contractCode, args: [] });
  const alice = new Account();
  const bob = new Account();

  await increment(chain, address, alice);
  await increment(chain, address, alice);
  await increment(chain, address, bob);

  expect(contractCode.ledger(chain.getContractStateOrThrow(address).data).round).toEqual(3n);
  expect(count(alice, address)).toEqual(2n);
  expect(count(bob, address)).toEqual(1n);
});
