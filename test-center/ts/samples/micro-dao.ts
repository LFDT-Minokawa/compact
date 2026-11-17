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

// Two proposals through the DAO: the voter's books are keyed by round in their own capsule, so the
// second proposal needs nothing reset, and the DApp reads the voter's phase through `localState`.

const KEYS = 'midnight:capsule/keys@1.0.0';
const NATIVE = new Uint8Array(32);
const COSTS = { seed_dust: 2n, buy_in_dust: 2n };
// every wallet here pays from the same (harness) coin public key, which is also the beneficiary
const BENEFICIARY = { bytes: new Uint8Array(32) };

class Member {
  readonly account = new Account();
  readonly wallet: Record<string, runtime.HostInterface>;
  constructor(readonly secret: Uint8Array) {
    this.wallet = { [KEYS]: { secretKey: () => this.secret } };
  }
}

const coin = (tag: number, value: bigint) => ({ nonce: new Uint8Array(32).fill(tag), color: NATIVE, value });

const call = (chain: TestChain, address: any, m: Member, circuitId: string, args: unknown[] = []) =>
  chain.call({ module: contractCode, address, circuitId, args, account: m.account, hostInterfaces: m.wallet });

const ledger = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);
// the voter's phase is derived from the books and the public round, so the accessor needs both; a
// capsule the account has never written is at the declaration defaults
const books = (chain: TestChain, m: Member, address: any) =>
  contractCode.localState(m.account.entryLocalState(contractCode, address)!, chain.getContractStateOrThrow(address).data);

test('two proposals: commit, reveal, cash out, and vote again without resetting anything', async () => {
  const chain = new TestChain();
  const organizer = new Member(new Uint8Array(32).fill(1));
  const voter = new Member(new Uint8Array(32).fill(2));
  const { address } = await chain.deploy({ module: contractCode, args: [organizer.secret, COSTS] });

  // round 0
  await call(chain, address, organizer, 'set_topic', ['budget', BENEFICIARY, coin(1, COSTS.seed_dust)]);
  expect(ledger(chain, address).state).toEqual(contractCode.LedgerState.commit);
  const token = (await call(chain, address, voter, 'buy_in', [coin(2, COSTS.buy_in_dust), 1n])).result as any;
  expect(token.value).toEqual(1n);

  await expect(call(chain, address, voter, 'vote_reveal')).rejects.toThrow(/In illegal state for revealing/);
  await call(chain, address, voter, 'vote_commit', [true, token]);
  expect(books(chain, voter, address).voter_state()).toEqual(contractCode.VoterState.committed);
  expect(books(chain, voter, address).ballots.lookup(0n)).toEqual(true);
  await expect(call(chain, address, voter, 'vote_commit', [true, token])).rejects.toThrow(/In illegal state for committing/);

  await expect(call(chain, address, voter, 'advance')).rejects.toThrow(/without authorization/);
  await call(chain, address, organizer, 'advance');
  expect(ledger(chain, address).state).toEqual(contractCode.LedgerState.reveal);
  await call(chain, address, voter, 'vote_reveal');
  expect(ledger(chain, address).yes).toEqual(1n);
  expect(books(chain, voter, address).voter_state()).toEqual(contractCode.VoterState.revealed);
  await expect(call(chain, address, voter, 'vote_reveal')).rejects.toThrow(/In illegal state for revealing/);

  await call(chain, address, organizer, 'advance');
  expect(ledger(chain, address).state).toEqual(contractCode.LedgerState.final);
  // the vote carried, so the organizer cannot skip past the payout
  await expect(call(chain, address, organizer, 'advance')).rejects.toThrow(/cash out is expected/);
  await call(chain, address, voter, 'cash_out');
  expect(ledger(chain, address).state).toEqual(contractCode.LedgerState.setup);
  expect(ledger(chain, address).round).toEqual(1n);

  // round 1: the same voter starts fresh, with round 0 still on the books
  expect(books(chain, voter, address).voter_state()).toEqual(contractCode.VoterState.initial);
  await call(chain, address, organizer, 'set_topic', ['holiday', BENEFICIARY, coin(3, COSTS.seed_dust)]);
  const token2 = (await call(chain, address, voter, 'buy_in', [coin(4, COSTS.buy_in_dust), 1n])).result as any;
  await call(chain, address, voter, 'vote_commit', [false, token2]);
  expect(books(chain, voter, address).voter_state()).toEqual(contractCode.VoterState.committed);
  expect(books(chain, voter, address).ballots.lookup(1n)).toEqual(false);
  expect(books(chain, voter, address).revealed_rounds.member(0n)).toEqual(true);
  expect(books(chain, voter, address).revealed_rounds.member(1n)).toEqual(false);
  // the organizer's capsule holds no ballots at all
  expect(books(chain, organizer, address).ballots.isEmpty()).toEqual(true);
});
