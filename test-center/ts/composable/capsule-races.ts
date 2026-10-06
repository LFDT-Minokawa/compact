// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// A callee's capsule where one landed transaction at a time is not the whole story: transactions in
// flight on one capsule, first touches racing, a capsule two calls deep, a callee's coin
// operations, a container pin and a checkpoint split in a callee's record, a failure the
// application catches, a wallet whose answers change, and a callee circuit with nothing to prove.

const TALLY = 'vendor:capsule/tally@1.0.0';
const ZSWAP = 'midnight:capsule/zswap@1.0.0';

// The transacting party's answer to the Capsule pair's callee; the harness wallet serves the coin
// operations beneath it.
const WALLET = { [TALLY]: { weight: () => 3n } };

const rejection = async (promise: Promise<unknown>): Promise<unknown> => {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  throw new Error('expected the call to reject');
};

const resolutionError = async (promise: Promise<unknown>): Promise<runtime.ModuleResolutionError> => {
  const error = await rejection(promise);
  if (runtime.ModuleResolutionError.is(error)) {
    return error;
  }
  throw error;
};

// The local side of landing a rehearsed transaction: the account folds its records.
const land = (chain: TestChain, account: Account, result: runtime.CircuitResults<unknown>): void =>
  account.commit(result, (address) => chain.moduleFor(address));

const recordOf = (result: runtime.CircuitResults<unknown>, address: string): runtime.CallProofData => {
  const records = result.context.callProofDataTrace.filter((record) => record.contractAddress === address);
  expect(records).toHaveLength(1);
  return records[0];
};

// The Capsule pair's `visit` begins with a public operation, therefore its entries at offset 0 are
// the prologue's.
const prologueOf = (record: runtime.CallProofData) => record.localTranscript!.filter((entry) => entry.offset === 0);

const deployPair = async (chain: TestChain) => {
  const inner = await chain.deploy({ module: innerCode, args: [] });
  const outer = await chain.deploy({ module: outerCode, args: [inner.encodedAddress] });
  return { inner, outer };
};

const visitOnce = (outer: { address: string }, account: Account) => ({
  module: outerCode,
  address: outer.address,
  circuitId: 'visitOnce',
  args: [],
  account,
  hostInterfaces: WALLET,
});

const innerBooks = (account: Account, inner: { address: string }) => innerCode.localState(account.localState(inner.address)!);
const visitors = (chain: TestChain, inner: { address: string }): bigint =>
  innerCode.ledger(chain.getContractStateOrThrow(inner.address).data).visitors;

const deployVault = async (chain: TestChain) => {
  const vault = await chain.deploy({ module: vaultCode, args: [] });
  // `Vault` and `Recall` are two contract types for the one vault.
  const relay = await chain.deploy({ module: relayCode, args: [vault.encodedAddress, vault.encodedAddress] });
  const entry = await chain.deploy({ module: entryCode, args: [relay.encodedAddress] });
  return { vault, relay, entry };
};

const relayCall = (relay: { address: string }, circuitId: string, args: readonly unknown[], account: Account) => ({
  module: relayCode,
  address: relay.address,
  circuitId,
  args,
  account,
});

const vaultBooks = (account: Account, vault: { address: string }) => vaultCode.localState(account.localState(vault.address)!);
const deposits = (chain: TestChain, vault: { address: string }): bigint =>
  vaultCode.ledger(chain.getContractStateOrThrow(vault.address).data).deposits;

const note = (byte: number): Uint8Array => new Uint8Array(32).fill(byte);

describe('transactions in flight on one callee capsule', () => {
  test('the later of two rehearsed against the same capsule fails tier 1 once the earlier lands, and folds rehearsed again', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();
    await chain.call(visitOnce(outer, account));
    expect(innerBooks(account, inner).visits).toEqual(3n);

    const a = await chain.rehearse(visitOnce(outer, account));
    const b = await chain.rehearse(visitOnce(outer, account));
    expect(a.result).toEqual(6n);
    expect(b.result).toEqual(6n);

    land(chain, account, a);
    // b's callee record pins its read of `visits` at 6, but on the capsule a left its increment
    // reaches 9.
    expect(() => land(chain, account, b)).toThrow(/record 0 for \w+ diverged: ReplayFailed at entry 2: mismatch between expected/);
    expect(innerBooks(account, inner).visits).toEqual(6n);
    expect(account.records.get(inner.address)).toHaveLength(2);

    const b2 = await chain.rehearse(visitOnce(outer, account));
    expect(b2.result).toEqual(9n);
    land(chain, account, b2);
    expect(innerBooks(account, inner).visits).toEqual(9n);
    expect(account.refold(innerCode, inner.address).toString()).toEqual(account.localState(inner.address)!.toString());
  });

  test('a transaction whose later record on a capsule diverges lands none of its records there', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();
    await chain.call(visitOnce(outer, account));
    const before = account.localState(inner.address)!.toString();

    // The Capsule pair's second visit in a call observes what its first does, so it replays whenever
    // the first does; the callee records of two calls rehearsed on one capsule, spliced into one
    // trace, stand in for a transaction whose later record alone diverges.
    const a = await chain.rehearse(visitOnce(outer, account));
    const b = await chain.rehearse(visitOnce(outer, account));
    const spliced = {
      ...a,
      context: { ...a.context, callProofDataTrace: [recordOf(a, inner.address), recordOf(b, inner.address)] },
    };
    expect(() => land(chain, account, spliced)).toThrow(/record 1 for \w+ diverged: ReplayFailed at entry 2: mismatch between expected/);
    expect(account.localState(inner.address)!.toString()).toEqual(before);
    expect(account.records.get(inner.address)).toHaveLength(1);
  });

  test('two first touches each run the prologue; the later diverges on the guard, and rehearsed again records only the guard read', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();

    const a = await chain.rehearse(visitOnce(outer, account));
    const b = await chain.rehearse(visitOnce(outer, account));
    // The guard read, `joined = true`, and the guard write.
    expect(prologueOf(recordOf(a, inner.address))).toHaveLength(3);
    expect(prologueOf(recordOf(b, inner.address))).toHaveLength(3);

    land(chain, account, a);
    expect(() => land(chain, account, b)).toThrow(/record 0 for \w+ diverged: ReplayFailed at entry 0: mismatch between expected/);

    const b2 = await chain.rehearse(visitOnce(outer, account));
    expect(prologueOf(recordOf(b2, inner.address))).toHaveLength(1);
    land(chain, account, b2);
    expect(innerBooks(account, inner).visits).toEqual(6n);
    expect(account.refold(innerCode, inner.address).toString()).toEqual(account.localState(inner.address)!.toString());
  });
});

describe('a capsule two calls deep', () => {
  test("the vault's record sits flat in the trace with its own local transcript, each caller's record pins its callee's return, and the account folds it", async () => {
    const chain = new TestChain();
    const { vault, relay, entry } = await deployVault(chain);
    const alice = new Account();

    const r = await chain.call({ module: entryCode, address: entry.address, circuitId: 'stash', args: [note(1)], account: alice });
    expect(r.result).toEqual(1n);
    const [vaultRecord, relayRecord, entryRecord] = r.context.callProofDataTrace;
    expect([vaultRecord, relayRecord, entryRecord].map((record) => record.contractAddress)).toEqual([
      vault.address,
      relay.address,
      entry.address,
    ]);
    // The prologue's guard read, `joinedAt` and guard write, then the insert and the size read.
    expect(vaultRecord.localTranscript).toHaveLength(5);
    expect(relayRecord.localTranscript).toBeUndefined();
    expect(entryRecord.localTranscript).toBeUndefined();
    expect(vaultRecord.calleeReturns).toBeUndefined();
    expect(relayRecord.calleeReturns).toEqual([
      { contractAddress: vault.address, circuitId: 'stash', input: vaultRecord.input, output: vaultRecord.output },
    ]);
    expect(entryRecord.calleeReturns).toEqual([
      { contractAddress: relay.address, circuitId: 'stash', input: relayRecord.input, output: relayRecord.output },
    ]);
    // the note travels as each callee's input, so the two pins carry the same arguments
    expect(relayRecord.calleeReturns![0].input).toEqual(entryRecord.calleeReturns![0].input);
    expect(Object.keys(runtime.localStates(r.context))).toEqual([vault.address]);
    expect(alice.lookupCount(vault.address)).toEqual(1);
    expect(vaultBooks(alice, vault).notes.member(note(1))).toEqual(true);
    expect(vaultBooks(alice, vault).joinedAt).toEqual({ is_some: true, value: 0n });
    expect(alice.refold(vaultCode, vault.address).toString()).toEqual(runtime.localStates(r.context)[vault.address].toString());

    // Another participant's first touch, two calls deep too, reads the vault's ledger as of that call.
    const bob = new Account();
    await chain.call({ module: entryCode, address: entry.address, circuitId: 'stash', args: [note(2)], account: bob });
    expect(vaultBooks(bob, vault).joinedAt).toEqual({ is_some: true, value: 1n });
    expect(vaultBooks(bob, vault).notes.member(note(1))).toEqual(false);
  });
});

describe("a callee's coin operations", () => {
  const PARTY = 'a1'.repeat(32);

  test("run against the callee's own Zswap local state, answered by the wallet the root's context carries", async () => {
    const chain = new TestChain();
    const { vault, relay } = await deployVault(chain);
    const account = new Account();
    expect(vaultCode.hostInterfaces).toEqual({ [ZSWAP]: ['ownPublicKey', 'createZswapOutput'] });

    const r = await chain.call({ ...relayCall(relay, 'mint', [5n], account), coinPublicKey: PARTY });
    const coin = r.result as { value: bigint };
    expect(coin.value).toEqual(5n);
    const [vaultRecord, relayRecord] = r.context.callProofDataTrace;
    // `ownPublicKey()`, then `createZswapOutput` inside `mintShieldedToken`, each beside its question:
    // the second's arguments are the coin and the recipient, its answer nothing.
    expect(vaultRecord.hostOutputs!.map(({ interfaceId, name }) => [interfaceId, name])).toEqual([
      [ZSWAP, 'ownPublicKey'],
      [ZSWAP, 'createZswapOutput'],
    ]);
    expect(vaultRecord.hostOutputs![0].args).toEqual({ value: [], alignment: [] });
    expect(vaultRecord.hostOutputs![1].result).toEqual({ value: [], alignment: [] });
    expect(relayRecord.hostOutputs).toBeUndefined();
    const party = r.context.zswapLocalStates[relay.address].coinPublicKey;
    expect(party.bytes).toEqual(runtime.encodeCoinPublicKey(PARTY));
    expect(vaultRecord.hostOutputs![1].args.value).toContainEqual(party.bytes);
    const vaultZswap = r.context.zswapLocalStates[vault.address];
    expect(vaultZswap.outputs).toHaveLength(1);
    expect(vaultZswap.outputs[0].coinInfo).toEqual(coin);
    expect(vaultZswap.outputs[0].recipient.is_left).toEqual(true);
    expect(vaultZswap.outputs[0].recipient.left).toEqual(party);
    expect(r.context.zswapLocalStates[relay.address].outputs).toHaveLength(0);
    // The nonce was drawn from the capsule's books.
    expect(vaultBooks(account, vault).minted).toEqual(1n);
  });

  test('a wallet without them fails the callee at resolution, before anything is committed', async () => {
    const chain = new TestChain();
    const { vault, relay } = await deployVault(chain);
    const account = new Account();

    const error = await resolutionError(
      chain.call({ ...relayCall(relay, 'mint', [5n], account), hostInterfaceProvider: { resolve: () => undefined } }),
    );
    expect(error.failure).toEqual({
      kind: 'HostInterfaceAbsent',
      interfaceId: ZSWAP,
      resolved: false,
      missing: ['ownPublicKey', 'createZswapOutput'],
    });
    expect(account.lookupCount(vault.address)).toEqual(0);
    expect(deposits(chain, vault)).toEqual(0n);
  });
});

describe("a container pin in a callee's record", () => {
  test('iteration in the vault leaves an observe entry, which folds, and which fails tier 1 on a capsule holding another note', async () => {
    const chain = new TestChain();
    const { vault, relay } = await deployVault(chain);
    const account = new Account();
    await chain.call(relayCall(relay, 'stash', [note(1)], account));
    const first = await chain.call(relayCall(relay, 'audit', [], account));
    expect(first.result).toEqual(1n);
    expect(recordOf(first, vault.address).localTranscript!.filter((entry) => entry.tag === 'observe')).toHaveLength(1);

    const stash = await chain.rehearse(relayCall(relay, 'stash', [note(2)], account));
    const audit = await chain.rehearse(relayCall(relay, 'audit', [], account));
    land(chain, account, stash);
    expect(() => land(chain, account, audit)).toThrow(/record 0 for \w+ diverged: ObservationMismatch at entry 1, the container at \[1\]/);

    const again = await chain.rehearse(relayCall(relay, 'audit', [], account));
    expect(again.result).toEqual(2n);
    land(chain, account, again);
    expect(vaultBooks(account, vault).copies.size()).toEqual(2n);
    expect(account.refold(vaultCode, vault.address).toString()).toEqual(account.localState(vault.address)!.toString());
  });
});

describe('a checkpoint in a callee', () => {
  const isCheckpoint = (op: unknown): boolean => op === 'ckpt' || (typeof op === 'object' && op !== null && 'ckpt' in op);

  test("splits the callee's record at its own call's checkpoint: a partial fold keeps the prologue and the write before it", async () => {
    const chain = new TestChain();
    const { vault, relay } = await deployVault(chain);
    const account = new Account();

    const r = await chain.rehearse(relayCall(relay, 'stage', [5n], account));
    const record = recordOf(r, vault.address);
    const c = record.publicTranscript.findIndex(isCheckpoint);
    expect(c).toBeGreaterThan(0);
    expect(record.localTranscript!.filter((entry) => entry.offset > c)).toHaveLength(1);

    const prior = vaultCode.initialLocalState();
    const partial = vaultCode.localState(foldedState(foldCall(prior, record, { tag: 'partial', guaranteedLength: c })));
    expect(partial.staged).toEqual(5n);
    expect(partial.joinedAt.is_some).toEqual(true);
    const whole = foldedState(foldCall(prior, record));
    expect(vaultCode.localState(whole).staged).toEqual(10n);
    expect(whole.toString()).toEqual(runtime.localStates(r.context)[vault.address].toString());
  });
});

describe('carrying on after a classified failure', () => {
  test('a wallet that cannot answer the callee: caught, and the call made again with one that can is the first touch it would have been', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();

    const error = await resolutionError(chain.call({ ...visitOnce(outer, account), hostInterfaces: {} }));
    expect(error.failure.kind).toEqual('HostInterfaceAbsent');

    const r = await chain.call(visitOnce(outer, account));
    expect(r.result).toEqual(3n);
    expect(account.lookupCount(inner.address)).toEqual(1);
    expect(prologueOf(recordOf(r, inner.address))).toHaveLength(3);
    expect(visitors(chain, inner)).toEqual(1n);
  });

  test('a capsule store that throws: classified with its cause, and once it answers the next call runs against the capsule as last folded', async () => {
    const cause = new Error('capsule store locked');
    class LockableAccount extends Account {
      locked = false;
      async getLocalState(address: string) {
        if (this.locked) {
          throw cause;
        }
        return super.getLocalState(address);
      }
    }
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new LockableAccount();
    await chain.call(visitOnce(outer, account));

    account.locked = true;
    const error = await resolutionError(chain.call(visitOnce(outer, account)));
    if (error.failure.kind !== 'LocalStateProviderThrew') {
      throw new Error(`expected LocalStateProviderThrew, got ${error.failure.kind}`);
    }
    expect(error.failure.cause).toBe(cause);
    expect(visitors(chain, inner)).toEqual(1n);
    expect(innerBooks(account, inner).visits).toEqual(3n);

    account.locked = false;
    const r = await chain.call(visitOnce(outer, account));
    expect(r.result).toEqual(6n);
    expect(prologueOf(recordOf(r, inner.address))).toHaveLength(1);
    expect(visitors(chain, inner)).toEqual(2n);
  });
});

describe('the call-time backstop', () => {
  // A wallet whose answer for the tally interface runs out after `answers` resolutions.
  const fickle = (answers: number): runtime.HostInterfaceProvider => {
    let left = answers;
    return { resolve: (id) => (id === TALLY && left-- > 0 ? WALLET[TALLY] : undefined) };
  };
  const UNRESOLVED = `the host interface provider resolves no '${TALLY}', of which weight is required`;

  test('at a root, the entry check takes the only answer, therefore the lookup at the call fails', async () => {
    const [contract, context] = await startContract(innerCode);
    await expect(contract.circuits.visit({ ...context, hostInterfaceProvider: fickle(1) })).rejects.toThrow(
      `cannot call host function weight of ${TALLY}: ${UNRESOLVED}`,
    );
  });

  test("at a callee, an answer that runs out after resolution fails at the callee's entry check or at the call, past the commit point, so not as a resolution failure", async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();

    // Resolution takes the only answer; the callee's entry check asks again.
    const atEntry = await rejection(chain.call({ ...visitOnce(outer, account), hostInterfaceProvider: fickle(1) }));
    expect(runtime.ModuleResolutionError.is(atEntry)).toEqual(false);
    expect((atEntry as Error).message).toContain(`visit: ${UNRESOLVED}`);

    // Resolution and the entry check take both answers; the call asks a third time.
    const atCall = await rejection(chain.call({ ...visitOnce(outer, account), hostInterfaceProvider: fickle(2) }));
    expect(runtime.ModuleResolutionError.is(atCall)).toEqual(false);
    expect((atCall as Error).message).toContain(`cannot call host function weight of ${TALLY}: ${UNRESOLVED}`);

    expect(visitors(chain, inner)).toEqual(0n);
    expect(account.localState(inner.address)).toBeUndefined();
  });
});

describe('a callee circuit with only local effects', () => {
  test('has nothing to prove, therefore a caller cannot bind a call to it: conformance refuses it as not provable', async () => {
    const chain = new TestChain();
    const { vault, relay } = await deployVault(chain);
    const account = new Account();
    expect(vaultCode.circuitSignatures.remember.provable).toEqual(false);

    const error = await resolutionError(chain.call(relayCall(relay, 'remember', [note(1)], account)));
    expect(error.failure).toEqual({ kind: 'NonconformantImplementation', circuitId: 'remember', check: 'Provability' });
    expect(error.message).toContain(
      "through contract type 'Recall' could not be bound to an implementation: the resolved module does not implement the contract type: circuit 'remember' is declared impure but is not among the module's provable circuits.",
    );
    expect(account.lookupCount(vault.address)).toEqual(0);
    expect(account.localState(vault.address)).toBeUndefined();
  });
});
