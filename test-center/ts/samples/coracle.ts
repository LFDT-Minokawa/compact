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

// A game of coracle between two wallets: each player's board and nonce live in their own capsule,
// the ledger holds only commitments, and the loser's capsule is what proves the hit.

const KEYS = 'midnight:capsule/keys@1.0.0';
const NATIVE = new Uint8Array(32);
const DEPOSIT_VALUE = 100000n;

class Player {
  readonly account = new Account();
  readonly wallet: Record<string, runtime.HostInterface>;
  constructor(readonly secret: Uint8Array) {
    this.wallet = { [KEYS]: { secretKey: () => this.secret } };
  }
}

const coin = (tag: number, value: bigint) => ({ nonce: new Uint8Array(32).fill(tag), color: NATIVE, value });

const call = (chain: TestChain, address: any, p: Player, circuitId: string, args: unknown[] = []) =>
  chain.call({ module: contractCode, address, circuitId, args, account: p.account, hostInterfaces: p.wallet });

const ledger = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);
const board = (p: Player, address: any) => contractCode.localState(p.account.localState(address)!).board;

test('a full game: boards stay private, the hit is proved from the loser\'s capsule, the winner withdraws', async () => {
  const chain = new TestChain();
  const { address } = await chain.deploy({ module: contractCode, args: [] });
  const red = new Player(new Uint8Array(32).fill(1));
  const blue = new Player(new Uint8Array(32).fill(2));

  // red hides at 1, blue at 2; each wagers 50 and deposits the required stake
  const r1 = await call(chain, address, red, 'start', [1n, coin(3, 50n), coin(4, DEPOSIT_VALUE)]);
  expect(r1.result).toEqual(contractCode.Player.red);
  const r2 = await call(chain, address, blue, 'start', [2n, coin(5, 50n), coin(6, DEPOSIT_VALUE)]);
  expect(r2.result).toEqual(contractCode.Player.blue);
  expect(ledger(chain, address).pot.value).toEqual(100n);

  // the boards are in the capsules, committed on the ledger
  expect(board(red, address).contents).toEqual({ position: 1n });
  expect(board(blue, address).contents).toEqual({ position: 2n });
  expect(board(red, address).nonce).not.toEqual(board(blue, address).nonce);
  expect(ledger(chain, address).red_board.value).not.toEqual(ledger(chain, address).blue_board.value);

  // blue misses, red hits
  await call(chain, address, blue, 'guess', [5n]);
  expect(ledger(chain, address).last_guess).toEqual({ is_some: true, value: 5n });
  await call(chain, address, red, 'guess', [2n]);

  // blue's own capsule says blue is dead: no more guesses, only concession
  await expect(call(chain, address, blue, 'guess', [1n])).rejects.toThrow(/Blue player is not alive/);
  await expect(call(chain, address, red, 'concede')).rejects.toThrow(/Not Red's turn/);
  const conceded = await call(chain, address, blue, 'concede');
  expect((conceded.result as any).value).toEqual(DEPOSIT_VALUE);

  // red takes the pot and the deposit back; blue has nothing to withdraw
  const won = await call(chain, address, red, 'withdraw');
  expect((won.result as any).wager.value).toEqual(100n);
  expect((won.result as any).deposit.value).toEqual(DEPOSIT_VALUE);
  await expect(call(chain, address, blue, 'withdraw')).rejects.toThrow(/Blue hasn't won/);

  // a bystander is not a player
  const lurker = new Player(new Uint8Array(32).fill(9));
  await expect(call(chain, address, lurker, 'guess', [1n])).rejects.toThrow(/Not a player/);
});
