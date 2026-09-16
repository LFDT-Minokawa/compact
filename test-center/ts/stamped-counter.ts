// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

const hasPopeq = (ctx: any) =>
  JSON.stringify(ctx.callProofDataTrace.at(-1)?.publicTranscript).includes('popeq');

test('StampedCounter: stamp copies the counter, increment and raiseTo apply on the ledger', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  expect((await c.circuits.nonce(ctx)).result).toEqual(0n);
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(0n);
  expect((await c.circuits.isStamped(ctx, 7n)).result).toEqual(false);

  // Two calls: each is stamped with the counter as it stood, then the counter moves.
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect(hasPopeq(ctx)).toEqual(false);
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(0n);
  expect((await c.circuits.seenAt(ctx, 7n)).result).toEqual(0n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(1n);
  ctx = (await c.circuits.call(ctx, 9n)).context;
  expect((await c.circuits.nonceOf(ctx, 9n)).result).toEqual(1n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(2n);
  expect((await c.circuits.isStamped(ctx, 9n)).result).toEqual(true);

  // A response raises last seen and clears the key.
  ctx = (await c.circuits.respond(ctx, 7n, 50n)).context;
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(50n);
  expect((await c.circuits.isStamped(ctx, 7n)).result).toEqual(false);

  // A later call snapshots the raised value.
  ctx = (await c.circuits.call(ctx, 11n)).context;
  expect((await c.circuits.seenAt(ctx, 11n)).result).toEqual(50n);
  expect((await c.circuits.nonceOf(ctx, 11n)).result).toEqual(2n);

  // raiseTo is a max: a lower height leaves it alone, a higher one moves it.
  ctx = (await c.circuits.respond(ctx, 9n, 40n)).context;
  expect(hasPopeq(ctx)).toEqual(true); // the member assert reads; raiseTo does not
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(50n);
  ctx = (await c.circuits.respond(ctx, 11n, 60n)).context;
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(60n);

  // The TypeScript ledger accessor sees the same state: the counter and the stamps.
  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L.nonces.value()).toEqual(3n);
  expect(L.seen.value()).toEqual(60n);
  expect(L.nonces.member(11n)).toEqual(false);
  expect(L.nonces.member(9n)).toEqual(false);
  ctx = (await c.circuits.call(ctx, 21n)).context;
  ctx = (await c.circuits.call(ctx, 22n)).context;
  const L2 = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L2.nonces.value()).toEqual(5n);
  expect(L2.nonces.lookup(21n)).toEqual(3n);
  expect(L2.nonces.lookup(22n)).toEqual(4n);
  expect(L2.seen.lookup(22n)).toEqual(60n);
  ctx = (await c.circuits.respond(ctx, 21n, 0n)).context;
  ctx = (await c.circuits.respond(ctx, 22n, 0n)).context;

  // Re-stamping a key overwrites its stamp.
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(5n);
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(6n);

  // Looking up a key that was never stamped fails.
  await expect(c.circuits.nonceOf(ctx, 12345n)).rejects.toThrow();

  // reset clears both halves.
  ctx = (await c.circuits.reset(ctx)).context;
  expect((await c.circuits.nonce(ctx)).result).toEqual(0n);
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(0n);
  expect((await c.circuits.isStamped(ctx, 7n)).result).toEqual(false);
});
