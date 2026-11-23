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

test('NumberedSet: insert numbers keys with the counter and advances it, raiseTo applies on the ledger', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  expect((await c.circuits.nonce(ctx)).result).toEqual(0n);
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(0n);
  expect((await c.circuits.isMember(ctx, 7n)).result).toEqual(false);

  // Two calls: each is numbered with the counter as it stood, and the insert itself moves the counter.
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect(hasPopeq(ctx)).toEqual(false);
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(0n);
  expect((await c.circuits.seenAt(ctx, 7n)).result).toEqual(0n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(1n);
  ctx = (await c.circuits.call(ctx, 9n)).context;
  expect((await c.circuits.nonceOf(ctx, 9n)).result).toEqual(1n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(2n);
  expect((await c.circuits.isMember(ctx, 9n)).result).toEqual(true);

  // A response raises last seen and clears the key.
  ctx = (await c.circuits.respond(ctx, 7n, 50n)).context;
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(50n);
  expect((await c.circuits.isMember(ctx, 7n)).result).toEqual(false);

  // A later call snapshots the raised value, and its insert moves the counter past it.
  ctx = (await c.circuits.call(ctx, 11n)).context;
  expect((await c.circuits.seenAt(ctx, 11n)).result).toEqual(50n);
  expect((await c.circuits.nonceOf(ctx, 11n)).result).toEqual(2n);
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(51n);

  // raiseTo is a max: a lower height leaves it alone, a higher one moves it.
  ctx = (await c.circuits.respond(ctx, 9n, 40n)).context;
  expect(hasPopeq(ctx)).toEqual(true); // the member assert reads; raiseTo does not
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(51n);
  ctx = (await c.circuits.respond(ctx, 11n, 60n)).context;
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(60n);

  // The TypeScript ledger accessor sees the same state: the counter and the numbers.
  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L.nonces.read()).toEqual(3n);
  expect(L.seen.read()).toEqual(60n);
  expect(L.nonces.member(11n)).toEqual(false);
  expect(L.nonces.member(9n)).toEqual(false);
  ctx = (await c.circuits.call(ctx, 21n)).context;
  ctx = (await c.circuits.call(ctx, 22n)).context;
  const L2 = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L2.nonces.read()).toEqual(5n);
  expect(L2.nonces.lookup(21n)).toEqual(3n);
  expect(L2.nonces.lookup(22n)).toEqual(4n);
  expect(L2.seen.lookup(21n)).toEqual(60n);
  expect(L2.seen.lookup(22n)).toEqual(61n);
  expect(L2.seen.read()).toEqual(62n);
  ctx = (await c.circuits.respond(ctx, 21n, 0n)).context;
  ctx = (await c.circuits.respond(ctx, 22n, 0n)).context;

  // Inserting a key already in the set leaves its number alone and does not
  // advance the counter.
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(5n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(6n);
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(5n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(6n);
  // Removing and inserting it again renumbers it and advances the counter.
  ctx = (await c.circuits.respond(ctx, 7n, 0n)).context;
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect((await c.circuits.nonceOf(ctx, 7n)).result).toEqual(6n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(7n);

  // Looking up a key that was never inserted fails.
  await expect(c.circuits.nonceOf(ctx, 12345n)).rejects.toThrow();

  // reset clears both halves.
  ctx = (await c.circuits.reset(ctx)).context;
  expect((await c.circuits.nonce(ctx)).result).toEqual(0n);
  expect((await c.circuits.lastSeen(ctx)).result).toEqual(0n);
  expect((await c.circuits.isMember(ctx, 7n)).result).toEqual(false);
});

test('NumberedSet: size, isEmpty and the TypeScript iterator', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const ledgerOf = (ctx: any) => contractCode.ledger(ctx.callContext.currentQueryContext.state);
  const numbers = (field: any) => new Map([...field]);

  expect((await c.circuits.pending(ctx)).result).toEqual(0n);
  expect((await c.circuits.idle(ctx)).result).toEqual(true);
  expect(ledgerOf(ctx).nonces.size()).toEqual(0n);
  expect(ledgerOf(ctx).nonces.isEmpty()).toEqual(true);
  expect([...ledgerOf(ctx).nonces]).toEqual([]);

  for (const k of [7n, 9n, 11n]) ctx = (await c.circuits.call(ctx, k)).context;
  expect((await c.circuits.pending(ctx)).result).toEqual(3n);
  expect((await c.circuits.idle(ctx)).result).toEqual(false);
  expect(ledgerOf(ctx).nonces.size()).toEqual(3n);
  expect(ledgerOf(ctx).nonces.isEmpty()).toEqual(false);
  expect(numbers(ledgerOf(ctx).nonces)).toEqual(new Map([[7n, 0n], [9n, 1n], [11n, 2n]]));

  // Removing a key drops it from the iterator; inserting a present key
  // neither adds an entry nor changes its number nor advances the counter.
  ctx = (await c.circuits.respond(ctx, 9n, 0n)).context;
  ctx = (await c.circuits.call(ctx, 7n)).context;
  expect(ledgerOf(ctx).nonces.size()).toEqual(2n);
  expect(numbers(ledgerOf(ctx).nonces)).toEqual(new Map([[7n, 0n], [11n, 2n]]));

  // isEmpty is about the keys, not the counter.
  ctx = (await c.circuits.respond(ctx, 7n, 0n)).context;
  ctx = (await c.circuits.respond(ctx, 11n, 0n)).context;
  expect(ledgerOf(ctx).nonces.read()).toEqual(3n);
  expect((await c.circuits.idle(ctx)).result).toEqual(true);
  expect(ledgerOf(ctx).nonces.isEmpty()).toEqual(true);

  // Non-integer keys come back as their TypeScript representation.
  const a = new Uint8Array(32).fill(1), b = new Uint8Array(32).fill(2);
  ctx = (await c.circuits.name(ctx, a)).context;
  ctx = (await c.circuits.name(ctx, b)).context;
  const named = [...ledgerOf(ctx).named].sort((x, y) => Number(x[1] - y[1]));
  expect(named).toEqual([[a, 0n], [b, 1n]]);
});

// The ledger re-runs a transaction's public transcript against the state it
// finds when the transaction lands, and fails it if any value read with popeq
// has changed. replay(base, proved) does the same: it applies the transcript
// that was proved in `proved` to the state left by `base`.
const replayOnto = (base: any, proved: any) => {
  const at = base.callContext.currentQueryContext;
  const gas = { readTime: 10n ** 15n, computeTime: 10n ** 15n, bytesWritten: 10n ** 12n, bytesDeleted: 10n ** 12n } as any;
  return new runtime.QueryContext(at.state, at.address).runTranscript(
    {
      gas,
      effects: proved.callContext.currentQueryContext.effects,
      program: proved.callProofDataTrace.at(-1).publicTranscript,
    },
    runtime.CostModel.initialCostModel(),
  );
};

test('NumberedSet: inserts proved against the same state both land', async () => {
  const [c1, s1] = await startContract(contractCode, {}, 0);
  const [c2, s2] = await startContract(contractCode, {}, 0);
  const a = (await c1.circuits.call(s1, 7n)).context; // proved with the counter at 0
  const b = (await c2.circuits.call(s2, 9n)).context; // also proved with the counter at 0
  const L = contractCode.ledger(replayOnto(a, b).state.state); // b lands after a
  expect(L.nonces.read()).toEqual(2n);
  expect(L.nonces.lookup(7n)).toEqual(0n);
  expect(L.nonces.lookup(9n)).toEqual(1n);

  // Control: a read of the counter proved against the old state is rejected.
  const [c3, s3] = await startContract(contractCode, {}, 0);
  const v = (await c3.circuits.nonce(s3)).context;
  expect(() => replayOnto(a, v)).toThrow();
  expect(() => replayOnto(s3, v)).not.toThrow();
});

test('NumberedSet: raiseTo proved against the same state commutes', async () => {
  const setUp = async () => {
    let [c, ctx] = await startContract(contractCode, {}, 0);
    ctx = (await c.circuits.call(ctx, 1n)).context;
    ctx = (await c.circuits.call(ctx, 2n)).context;
    return [c, ctx] as const;
  };
  const [c1, s1] = await setUp();
  const [c2, s2] = await setUp();
  const r50 = (await c1.circuits.respond(s1, 1n, 50n)).context;
  const r40 = (await c2.circuits.respond(s2, 2n, 40n)).context;
  expect(contractCode.ledger(replayOnto(r50, r40).state.state).seen.read()).toEqual(50n);
  expect(contractCode.ledger(replayOnto(r40, r50).state.state).seen.read()).toEqual(50n);
});

test('NumberedSet: reads of the keys conflict with concurrent inserts', async () => {
  const [c1, s1] = await startContract(contractCode, {}, 0);
  const [c2, s2] = await startContract(contractCode, {}, 0);
  const landed = (await c1.circuits.call(s1, 7n)).context;
  // size and isEmpty proved before a new key was inserted are rejected.
  const size = (await c2.circuits.pending(s2)).context;
  const empty = (await c2.circuits.idle(s2)).context;
  expect(() => replayOnto(landed, size)).toThrow();
  expect(() => replayOnto(landed, empty)).toThrow();
  // A lookup proved with 7 -> 0 survives someone inserting 7 again first,
  // since that leaves its number alone, but not a remove and re-insert.
  const [c3, s3] = await startContract(contractCode, {}, 0);
  const base = (await c3.circuits.call(s3, 7n)).context;
  const read = (await c1.circuits.nonceOf(landed, 7n)).context;
  const reinserted = (await c3.circuits.call(base, 7n)).context; // counter still at 1, 7 -> 0
  expect(() => replayOnto(reinserted, read)).not.toThrow();
  const removed = (await c3.circuits.respond(reinserted, 7n, 0n)).context;
  const renumbered = (await c3.circuits.call(removed, 7n)).context; // 7 -> 1
  expect(() => replayOnto(renumbered, read)).toThrow();
});

test('NumberedSet: concurrent inserts of the same key keep the first number and advance the counter once', async () => {
  const [c1, s1] = await startContract(contractCode, {}, 0);
  const [c2, s2] = await startContract(contractCode, {}, 0);
  let base1 = (await c1.circuits.call(s1, 1n)).context; // counter at 1
  let base2 = (await c2.circuits.call(s2, 1n)).context;
  const first = (await c1.circuits.call(base1, 5n)).context; // 5 -> 1, counter at 2
  const second = (await c2.circuits.call(base2, 5n)).context; // proved with 5 absent
  const L = contractCode.ledger(replayOnto(first, second).state.state);
  expect(L.nonces.lookup(5n)).toEqual(1n); // the second insert found 5 present
  expect(L.nonces.read()).toEqual(2n); // and so did not advance the counter
  expect(L.nonces.size()).toEqual(2n);
});

test('NumberedSet: the TypeScript accessor offers read() and lessThan()', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  for (const k of [1n, 2n, 3n]) ctx = (await c.circuits.call(ctx, k)).context;
  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L.nonces.read()).toEqual(3n);
  expect(L.nonces.lessThan(4n)).toEqual(true);
  expect(L.nonces.lessThan(3n)).toEqual(false);
  expect(L.plain).toEqual(0n); // a Counter is still a plain getter
});

test('NumberedSet: decrement and lowerTo land after a concurrent insert', async () => {
  const setUp = async () => {
    let [c, ctx] = await startContract(contractCode, {}, 0);
    for (const k of [1n, 2n, 3n]) ctx = (await c.circuits.call(ctx, k)).context; // counter at 3
    return [c, ctx] as const;
  };
  const [c1, s1] = await setUp();
  const [c2, s2] = await setUp();
  const inserted = (await c1.circuits.call(s1, 4n)).context; // 4 -> 3, counter at 4
  const lowered = (await c2.circuits.rewind(s2, 2n)).context; // proved with counter at 3
  expect(contractCode.ledger(replayOnto(inserted, lowered).state.state).nonces.read()).toEqual(2n);
  const [c3, s3] = await setUp();
  const undone = (await c3.circuits.undo(s3)).context; // proved with counter at 3
  expect(contractCode.ledger(replayOnto(inserted, undone).state.state).nonces.read()).toEqual(3n);
});

test('Counter: raiseTo and lowerTo do not conflict with concurrent updates', async () => {
  const [c1, s1] = await startContract(contractCode, {}, 0);
  const [c2, s2] = await startContract(contractCode, {}, 0);
  const [c3, s3] = await startContract(contractCode, {}, 0);
  const bumped = (await c1.circuits.plainBump(s1)).context; // counter 0 -> 10 lands first
  const raised = (await c2.circuits.plainRaise(s2, 7n)).context; // proved with counter at 0
  const lowered = (await c3.circuits.plainLower(s3, 4n)).context; // proved with counter at 0
  expect(contractCode.ledger(replayOnto(bumped, raised).state.state).plain).toEqual(10n);
  expect(contractCode.ledger(replayOnto(bumped, lowered).state.state).plain).toEqual(4n);
  const r = (await c2.circuits.plainRaise(bumped, 15n)).context;
  expect(contractCode.ledger(r.callContext.currentQueryContext.state).plain).toEqual(15n);
});

test('NumberedSet: insertCoin numbers received coins in arrival order', async () => {
  const random32 = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32)));
  const sampleCoin = (value: bigint) => ({ nonce: random32(), color: random32(), value });
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const coins = [sampleCoin(100n), sampleCoin(250n)];
  for (const coin of coins) ctx = (await c.circuits.deposit(ctx, coin)).context;

  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L.deposits.read()).toEqual(2n);
  expect(L.deposits.size()).toEqual(2n);
  // Each entry is the coin, qualified with its Merkle tree index, and its number.
  const entries = [...L.deposits].sort((x, y) => Number(x[1] - y[1]));
  expect(entries.map(([q, n]) => [q.nonce, q.color, q.value, n])).toEqual(
    coins.map((coin, i) => [new Uint8Array(coin.nonce), new Uint8Array(coin.color), coin.value, BigInt(i)]),
  );
  for (const [q, n] of entries) {
    expect(L.deposits.member(q)).toEqual(true);
    expect((await c.circuits.depositNumber(ctx, q)).result).toEqual(n);
  }

  // A coin the transaction has not received cannot be inserted.
  await expect(c.circuits.depositUnreceived(ctx, sampleCoin(5n))).rejects.toThrow(/Coin commitment not found/);
});

test('NumberedSet: lessThan in a circuit, and raiseTo and lowerTo at their boundaries', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const counter = async () => (await c.circuits.nonce(ctx)).result;
  for (const k of [1n, 2n, 3n]) ctx = (await c.circuits.call(ctx, k)).context; // counter at 3
  expect((await c.circuits.nonceBelow(ctx, 4n)).result).toEqual(true);
  expect((await c.circuits.nonceBelow(ctx, 3n)).result).toEqual(false);
  expect((await c.circuits.nonceBelow(ctx, 2n)).result).toEqual(false);
  ctx = (await c.circuits.advance(ctx, 3n)).context; // raising to the value
  expect(await counter()).toEqual(3n);
  ctx = (await c.circuits.advance(ctx, 2n)).context; // raising below the value
  expect(await counter()).toEqual(3n);
  ctx = (await c.circuits.rewind(ctx, 3n)).context; // lowering to the value
  expect(await counter()).toEqual(3n);
  ctx = (await c.circuits.rewind(ctx, 5n)).context; // lowering above the value
  expect(await counter()).toEqual(3n);
  ctx = (await c.circuits.advance(ctx, 8n)).context;
  expect(await counter()).toEqual(8n);
  ctx = (await c.circuits.rewind(ctx, 6n)).context;
  expect(await counter()).toEqual(6n);
});

test('Counter: raiseTo and lowerTo at their boundaries', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const value = () => contractCode.ledger(ctx.callContext.currentQueryContext.state).plain;
  ctx = (await c.circuits.plainBump(ctx)).context; // 10
  for (const [op, t, expected] of [
    ['plainRaise', 10n, 10n], ['plainRaise', 4n, 10n], ['plainLower', 10n, 10n],
    ['plainLower', 12n, 10n], ['plainRaise', 15n, 15n], ['plainLower', 7n, 7n],
  ] as const) {
    ctx = (await c.circuits[op](ctx, t)).context;
    expect(value()).toEqual(expected);
  }
});

test('NumberedSet: decrement and lowerTo can repeat numbers', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const num = async (k: bigint) => (await c.circuits.nonceOf(ctx, k)).result;
  ctx = (await c.circuits.call(ctx, 1n)).context; // 1 -> 0, counter at 1
  ctx = (await c.circuits.undo(ctx)).context; // counter back to 0
  ctx = (await c.circuits.call(ctx, 2n)).context; // 2 -> 0
  expect(await num(1n)).toEqual(await num(2n));
  ctx = (await c.circuits.advance(ctx, 5n)).context;
  ctx = (await c.circuits.call(ctx, 3n)).context; // 3 -> 5, counter at 6
  ctx = (await c.circuits.rewind(ctx, 0n)).context;
  ctx = (await c.circuits.call(ctx, 4n)).context; // 4 -> 0
  expect(await num(4n)).toEqual(0n);
  expect(await num(3n)).toEqual(5n); // earlier numbers do not move
});

test('NumberedSet: increment skips numbers', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  ctx = (await c.circuits.call(ctx, 1n)).context; // 1 -> 0, counter at 1
  ctx = (await c.circuits.skip(ctx, 4n)).context; // counter at 5
  ctx = (await c.circuits.call(ctx, 2n)).context; // 2 -> 5, counter at 6
  expect((await c.circuits.nonceOf(ctx, 1n)).result).toEqual(0n);
  expect((await c.circuits.nonceOf(ctx, 2n)).result).toEqual(5n);
  expect((await c.circuits.nonce(ctx)).result).toEqual(6n);
  // An increment proved against the same state as an insert lands after it.
  const [c2, s2] = await startContract(contractCode, {}, 0);
  const [c3, s3] = await startContract(contractCode, {}, 0);
  const inserted = (await c2.circuits.call(s2, 1n)).context; // counter at 1
  const skipped = (await c3.circuits.skip(s3, 4n)).context; // proved with the counter at 0
  expect(contractCode.ledger(replayOnto(inserted, skipped).state.state).nonces.read()).toEqual(5n);
});

test('NumberedSet: inserting a present coin leaves it and the counter unchanged', async () => {
  const random32 = () => Buffer.from(crypto.getRandomValues(new Uint8Array(32)));
  let [c, ctx] = await startContract(contractCode, {}, 0);
  ctx = (await c.circuits.depositTwice(ctx, { nonce: random32(), color: random32(), value: 7n })).context;
  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  expect(L.deposits.size()).toEqual(1n);
  expect(L.deposits.read()).toEqual(1n);
  expect([...L.deposits].map(([, n]) => n)).toEqual([0n]);
});

test('NumberedSet: nested in a Map', async () => {
  let [c, ctx] = await startContract(contractCode, {}, 0);
  const r = async (f: string, ...a: bigint[]) => (await c.circuits[f](ctx, ...a)).result;
  for (const [g, k] of [[1n, 10n], [1n, 11n], [2n, 10n], [1n, 10n]]) ctx = (await c.circuits.join(ctx, g, k)).context;
  // Each group numbers its own elements; re-joining keeps the number.
  expect([await r('groupNumber', 1n, 10n), await r('groupNumber', 1n, 11n), await r('groupNumber', 2n, 10n)])
    .toEqual([0n, 1n, 0n]);
  expect([await r('groupCounter', 1n), await r('groupCounter', 2n)]).toEqual([2n, 1n]);
  ctx = (await c.circuits.groupRaise(ctx, 2n, 9n)).context;
  ctx = (await c.circuits.leave(ctx, 1n, 11n)).context;
  expect([await r('groupCounter', 2n), await r('groupSize', 1n)]).toEqual([9n, 1n]);
  // The nested TypeScript accessor has the same shape as a top-level one.
  const L = contractCode.ledger(ctx.callContext.currentQueryContext.state);
  const g1 = L.groups.lookup(1n);
  expect(g1.read()).toEqual(2n);
  expect(g1.lessThan(3n)).toEqual(true);
  expect(g1.lessThan(2n)).toEqual(false);
  expect(g1.size()).toEqual(1n);
  expect(new Map([...g1])).toEqual(new Map([[10n, 0n]]));
  expect(new Map([...L.groups.lookup(2n)])).toEqual(new Map([[10n, 0n]]));
});
