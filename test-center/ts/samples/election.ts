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

// A commit-reveal election: the authority runs it from its wallet, each voter's ballot waits in
// their own capsule between the commit and the reveal, and the Merkle paths are found off chain in
// the public trees.

const KEYS = 'midnight:capsule/keys@1.0.0';

class Party {
  readonly account = new Account();
  readonly wallet: Record<string, runtime.HostInterface>;
  constructor(readonly secret: Uint8Array) {
    this.wallet = { [KEYS]: { secretKey: () => this.secret } };
  }
  get publicKey(): Uint8Array {
    return contractCode.pureCircuits.public_key(this.secret);
  }
}

const call = (chain: TestChain, address: any, p: Party, circuitId: string, args: unknown[] = []) =>
  chain.call({ module: contractCode, address, circuitId, args, account: p.account, hostInterfaces: p.wallet });

const ledger = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);
// a capsule the account has never written is at the declaration defaults
const record = (p: Party, address: any) => contractCode.localState(p.account.entryLocalState(contractCode, address)!);

test('setup, commit, reveal: each ballot waits in its voter\'s capsule', async () => {
  const chain = new TestChain();
  const authority = new Party(new Uint8Array(32).fill(1));
  const bob = new Party(new Uint8Array(32).fill(2));
  const carol = new Party(new Uint8Array(32).fill(3));
  const dave = new Party(new Uint8Array(32).fill(4));
  const { address } = await chain.deploy({ module: contractCode, args: [authority.publicKey] });

  // setup, by the authority only
  await expect(call(chain, address, bob, 'set_topic', ['tea or coffee'])).rejects.toThrow(/without authorization/);
  await call(chain, address, authority, 'set_topic', ['tea or coffee']);
  await call(chain, address, authority, 'add_voter', [bob.publicKey]);
  await call(chain, address, authority, 'add_voter', [carol.publicKey]);
  // the duplicate is caught off chain, by searching the public tree from the authority's capsule
  await expect(call(chain, address, authority, 'add_voter', [bob.publicKey])).rejects.toThrow(/add a voter twice/);
  await call(chain, address, authority, 'advance');
  expect(ledger(chain, address).state).toEqual(contractCode.PublicState.commit);

  // commit
  await call(chain, address, bob, 'vote$commit', [contractCode.PermissibleVotes.yes]);
  await call(chain, address, carol, 'vote$commit', [contractCode.PermissibleVotes.no]);
  await expect(call(chain, address, dave, 'vote$commit', [contractCode.PermissibleVotes.yes])).rejects.toThrow(/without authorization/);
  await expect(call(chain, address, bob, 'vote$commit', [contractCode.PermissibleVotes.no])).rejects.toThrow(/In illegal state for committing/);
  expect(record(bob, address).voter_state).toEqual(contractCode.PrivateState.committed);
  expect(record(bob, address).my_vote).toEqual({ is_some: true, value: contractCode.PermissibleVotes.yes });
  expect(ledger(chain, address).tally_yes).toEqual(0n);

  // reveal
  await expect(call(chain, address, bob, 'vote$reveal')).rejects.toThrow(/In illegal state for revealing/);
  await call(chain, address, authority, 'advance');
  await call(chain, address, bob, 'vote$reveal');
  await call(chain, address, carol, 'vote$reveal');
  await expect(call(chain, address, bob, 'vote$reveal')).rejects.toThrow(/In illegal state for revealing/);
  expect(ledger(chain, address).tally_yes).toEqual(1n);
  expect(ledger(chain, address).tally_no).toEqual(1n);
  expect(record(bob, address).voter_state).toEqual(contractCode.PrivateState.revealed);
  expect(record(carol, address).my_vote).toEqual({ is_some: true, value: contractCode.PermissibleVotes.no });
  // the authority's capsule holds no ballot
  expect(record(authority, address).voter_state).toEqual(contractCode.PrivateState.initial);
  expect(record(authority, address).my_vote.is_some).toEqual(false);
});
