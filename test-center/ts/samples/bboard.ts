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

// The bulletin board identifies the poster by the capsule secret, therefore only the wallet that
// posted can take the post down.

const KEYS = 'midnight:capsule/keys@1.0.0';
const wallet = (secret: Uint8Array) => ({ [KEYS]: { secretKey: () => secret } });
const ALICE = new Uint8Array(32).fill(1);
const BOB = new Uint8Array(32).fill(2);

const call = (chain: TestChain, address: any, secret: Uint8Array, circuitId: string, args: unknown[] = []) =>
  chain.call({ module: contractCode, address, circuitId, args, hostInterfaces: wallet(secret) });

const board = (chain: TestChain, address: any) => contractCode.ledger(chain.getContractStateOrThrow(address).data);

test('only the poster takes a post down', async () => {
  const chain = new TestChain();
  const { address } = await chain.deploy({ module: contractCode, args: [] });
  expect(contractCode.hostInterfaces).toEqual({ [KEYS]: ['secretKey'] });

  await call(chain, address, ALICE, 'post', ['hello']);
  expect(board(chain, address).state).toEqual(contractCode.STATE.occupied);
  expect(board(chain, address).message).toEqual({ is_some: true, value: 'hello' });

  await expect(call(chain, address, BOB, 'take_down')).rejects.toThrow(/not the current poster/);
  await expect(call(chain, address, BOB, 'post', ['mine now'])).rejects.toThrow(/occupied board/);

  const taken = await call(chain, address, ALICE, 'take_down');
  expect(taken.result).toEqual('hello');
  expect(board(chain, address).state).toEqual(contractCode.STATE.vacant);
  expect(board(chain, address).message).toEqual({ is_some: false, value: '' });
  expect(board(chain, address).instance).toEqual(2n);

  // the next instance is a new board: Bob posts, and Alice's old key no longer matters
  await call(chain, address, BOB, 'post', ['second']);
  await expect(call(chain, address, ALICE, 'take_down')).rejects.toThrow(/not the current poster/);
  expect((await call(chain, address, BOB, 'take_down')).result).toEqual('second');
});
