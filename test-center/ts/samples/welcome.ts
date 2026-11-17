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

// An organizer is whoever holds a capsule secret behind one of the organizer keys; a participant's
// check-in is public, and the identity they used stays in their own capsule.

const KEYS = 'midnight:capsule/keys@1.0.0';
const ORGANIZER = new Uint8Array(32).fill(1);
const VISITOR = new Uint8Array(32).fill(2);

class Participant {
  readonly account = new Account();
  readonly wallet: Record<string, runtime.HostInterface>;
  constructor(readonly secret: Uint8Array) {
    this.wallet = { [KEYS]: { secretKey: () => this.secret } };
  }
}

const call = (chain: TestChain, address: any, p: Participant, circuitId: string, args: unknown[]) =>
  chain.call({ module: contractCode, address, circuitId, args, account: p.account, hostInterfaces: p.wallet });

// a capsule the account has never written is at the declaration defaults
const books = (p: Participant, address: any) => contractCode.localState(p.account.entryLocalState(contractCode, address)!);
const ledger = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);

// the constructor's eligibility list is a fixed-size vector of optional names
const roster = (...names: string[]) =>
  Array.from({ length: 5000 }, (_, i) => (i < names.length ? { is_some: true, value: names[i] } : { is_some: false, value: '' }));

test('organizers manage the list; a visitor checks in and keeps the identity they used', async () => {
  const chain = new TestChain();
  const { address } = await chain.deploy({ module: contractCode, args: [ORGANIZER, roster('p1')] });
  const organizer = new Participant(ORGANIZER);
  const visitor = new Participant(VISITOR);

  await call(chain, address, organizer, 'add_participant', ['p2']);
  await expect(call(chain, address, visitor, 'add_participant', ['p3'])).rejects.toThrow(/Not an organizer/);
  expect(ledger(chain, address).eligible_participants.member('p2')).toEqual(true);
  expect(ledger(chain, address).eligible_participants.member('p3')).toEqual(false);

  await expect(call(chain, address, visitor, 'check_in', ['p3'])).rejects.toThrow(/Not eligible participant/);
  await call(chain, address, visitor, 'check_in', ['p2']);
  expect(ledger(chain, address).checked_in_participants.member('p2')).toEqual(true);
  expect(books(visitor, address).checked_in_as).toEqual({ is_some: true, value: 'p2' });
  // the organizer's capsule knows nothing of the visitor's check-in
  expect(books(organizer, address).checked_in_as).toEqual({ is_some: false, value: '' });

  // a second organizer, added by the first, can manage the list from their own wallet
  const deputy = new Participant(new Uint8Array(32).fill(3));
  await call(chain, address, organizer, 'add_organizer', [contractCode.pureCircuits.public_key(deputy.secret)]);
  await call(chain, address, deputy, 'add_participant', ['p4']);
  expect(ledger(chain, address).eligible_participants.member('p4')).toEqual(true);
});
