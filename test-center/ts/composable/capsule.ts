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

// A cross-contract callee's capsule, end to end: the gate on its host interface, where its local
// state comes from, its prologue at first touch inside the caller's transaction, one record per
// capsule, the pinned return, and the fold reproducing what the account's calls rehearsed.

const TALLY = 'vendor:capsule/tally@1.0.0';

const deployPair = async (chain: TestChain) => {
  const inner = await chain.deploy({ module: innerCode, args: [] });
  const outer = await chain.deploy({ module: outerCode, args: [inner.encodedAddress] });
  return { inner, outer };
};

// The transacting party's wallet answers the callee's host interface; the harness's own serves the
// coin operations beneath it.
const WALLET = { [TALLY]: { weight: () => 3n } };

const call = (chain: TestChain, outer: any, circuitId: string, account?: Account, hostInterfaces: Record<string, any> = WALLET) =>
  chain.call({
    module: outerCode,
    address: outer.address,
    circuitId,
    args: [],
    account,
    hostInterfaces,
  });

const resolutionFailure = async (promise: Promise<unknown>) => {
  try {
    await promise;
  } catch (error) {
    if (runtime.ModuleResolutionError.is(error)) {
      return error.failure;
    }
    throw error;
  }
  throw new Error('expected the call to reject');
};

const innerBooks = (account: Account, inner: any) => innerCode.localState(account.localState(inner.address)!);
const visitors = (chain: TestChain, inner: any): bigint => innerCode.ledger(chain.getContractStateOrThrow(inner.address).data).visitors;

describe('a cross-contract callee with local state and a host function', () => {
  test('the module declares what it requires', () => {
    expect(innerCode.hostInterfaces).toEqual({ [TALLY]: ['weight'] });
    expect(outerCode.hostInterfaces).toEqual({});
  });

  test('the gate: an interface the wallet does not answer fails resolution before anything is committed or looked up', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();

    // A wallet that does not know the interface at all, then one whose implementation is incomplete.
    const unresolved = await resolutionFailure(call(chain, outer, 'visitOnce', account, {}));
    expect(unresolved).toEqual({ kind: 'HostInterfaceAbsent', interfaceId: TALLY, resolved: false, missing: ['weight'] });
    const incomplete = await resolutionFailure(call(chain, outer, 'visitOnce', account, { [TALLY]: {} }));
    expect(incomplete).toEqual({ kind: 'HostInterfaceAbsent', interfaceId: TALLY, resolved: true, missing: ['weight'] });

    expect(visitors(chain, inner)).toEqual(0n);
    expect(account.lookupCount(inner.address)).toEqual(0);
    expect(account.localState(inner.address)).toBeUndefined();
  });

  test('without an account, a callee that keeps local state cannot be resolved', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);

    const failure = await resolutionFailure(call(chain, outer, 'visitOnce'));
    expect(failure.kind).toEqual('LocalStateProviderAbsent');
    expect(visitors(chain, inner)).toEqual(0n);
  });

  test('first touch installs the defaults and runs the prologue; later calls run against the folded capsule', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const account = new Account();

    // Transaction 1: the callee's capsule does not exist yet.
    const r1 = await call(chain, outer, 'visitOnce', account);
    expect(r1.result).toEqual(3n);
    expect(account.lookupCount(inner.address)).toEqual(1);
    // Two records, flat, the callee's first: its own local transcript (the prologue's guard read,
    // `joined = true` and guard write, then the increment and the read) and its host output live
    // there and nowhere else.
    const [calleeRecord, callerRecord] = r1.context.callProofDataTrace;
    expect(calleeRecord.contractAddress).toEqual(inner.address);
    expect(calleeRecord.circuitId).toEqual('visit');
    expect(calleeRecord.localTranscript).toHaveLength(5);
    expect(calleeRecord.hostOutputs).toHaveLength(1);
    expect(calleeRecord.calleeReturns).toBeUndefined();
    expect(callerRecord.contractAddress).toEqual(outer.address);
    expect(callerRecord.localTranscript).toBeUndefined();
    expect(callerRecord.hostOutputs).toBeUndefined();
    // The caller's record pins the value the chain binds it to, the callee's output, beside the call
    // it answers.
    expect(callerRecord.calleeReturns).toEqual([
      { contractAddress: inner.address, circuitId: 'visit', input: calleeRecord.input, output: calleeRecord.output },
    ]);
    // Only the callee has a capsule in this call tree.
    expect(Object.keys(runtime.localStates(r1.context))).toEqual([inner.address]);
    // The account folded the callee's record.
    expect(innerBooks(account, inner).visits).toEqual(3n);
    expect(innerBooks(account, inner).joined).toEqual(true);
    expect(visitors(chain, inner)).toEqual(1n);

    // Transaction 2: two sequential calls; the provider is asked once, the second call sees the
    // first's writes, and the prologue does not run again (the guard read alone).
    const r2 = await call(chain, outer, 'visitTwice', account);
    expect(r2.result).toEqual(9n);
    expect(account.lookupCount(inner.address)).toEqual(2);
    const calleeRecords = r2.context.callProofDataTrace.filter((record) => record.contractAddress === inner.address);
    expect(calleeRecords).toHaveLength(2);
    expect(calleeRecords[0].localTranscript).toHaveLength(3);
    expect(calleeRecords[1].localTranscript).toHaveLength(3);
    expect(r2.context.callProofDataTrace.at(-1)!.calleeReturns!.length).toEqual(2);
    expect(innerBooks(account, inner).visits).toEqual(9n);
    expect(outerCode.ledger(chain.getContractStateOrThrow(outer.address).data).lastCount).toEqual(9n);

    // Recovery: every record of the capsule folded from the declaration defaults reaches the same
    // state as the incremental folds, which is the state the last transaction rehearsed.
    const refolded = account.refold(innerCode, inner.address);
    expect(refolded.toString()).toEqual(account.localState(inner.address)!.toString());
    expect(refolded.toString()).toEqual(runtime.localStates(r2.context)[inner.address].toString());
  });

  test('capsules are per account: another participant starts from the defaults and gets its own prologue', async () => {
    const chain = new TestChain();
    const { inner, outer } = await deployPair(chain);
    const alice = new Account();
    const bob = new Account();

    await call(chain, outer, 'visitTwice', alice);
    expect(innerBooks(alice, inner).visits).toEqual(6n);

    // Bob's first touch is a call that only reads: the prologue still runs as the callee's
    // prologue, so he is joined at the end of it.
    const r = await call(chain, outer, 'checkJoined', bob);
    expect(r.result).toEqual(true);
    expect(innerBooks(bob, inner).visits).toEqual(0n);
    expect(innerBooks(bob, inner).joined).toEqual(true);
    expect(innerBooks(alice, inner).visits).toEqual(6n);
    // The public side is shared.
    expect(visitors(chain, inner)).toEqual(3n);
  });
});
