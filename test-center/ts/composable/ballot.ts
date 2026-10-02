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

// The direction document's worked example, end to end: two participants sign up through the
// ballot, which enrolls each in a registry it knows only by address, then vote; each contract's
// books live in the participant's own capsule, and every capsule folds back from its records.

const KEYS = 'midnight:capsule/keys@1.0.0';
const AGE = 'identus:verification/age@1.2.0';
const ISSUER = new Uint8Array(32).fill(0xaa);
const SIGNATURE = new Uint8Array(64).fill(1);

/** One participant: a wallet (the host functions answer from it) and an account (the capsules). */
class Participant {
  readonly account = new Account();
  constructor(
    readonly secret: Uint8Array,
    readonly birth: bigint = 0n,
    readonly issuer: Uint8Array = ISSUER,
  ) {}
}

// The host interfaces are process-wide, so they answer for whoever is transacting. Registered
// per test rather than at load, since other tests in this file pin what an unregistered
// interface does.
let transacting: Participant | undefined;
const wallet = (): Participant => {
  if (transacting === undefined) throw new Error('no participant is transacting');
  return transacting;
};
const installWallet = (): void => {
  runtime.registerHostInterface(KEYS, { secretKey: () => wallet().secret });
  runtime.registerHostInterface(AGE, {
    ageCredential: () => ({ date: wallet().birth, issuer: wallet().issuer, signature: SIGNATURE }),
  });
};

const deployBoth = async (chain: TestChain) => {
  const registry = await chain.deploy({ module: registryCode, args: [], initialPrivateState: 0 });
  const ballot = await chain.deploy({ module: ballotCode, args: [registry.encodedAddress, ISSUER], initialPrivateState: 0 });
  return { registry, ballot };
};

const as = async <T>(participant: Participant, run: () => Promise<T>): Promise<T> => {
  transacting = participant;
  try {
    return await run();
  } finally {
    transacting = undefined;
  }
};

// The block time every transaction here is built at, and the public time bound a signup proves
// its credential against.
const NOW = BigInt(Math.floor(Date.now() / 1_000));

const signup = (chain: TestChain, ballot: any, p: Participant) =>
  as(p, () =>
    chain.call({
      module: ballotCode,
      address: ballot.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'signup',
      args: [NOW],
      time: Number(NOW),
      account: p.account,
    }));

const vote = (chain: TestChain, ballot: any, p: Participant, choice: boolean) =>
  as(p, () =>
    chain.call({
      module: ballotCode,
      address: ballot.address,
      witnesses: {},
      privateState: 0,
      circuitId: 'vote',
      args: [choice],
      time: Number(NOW),
      account: p.account,
    }));

const ballotLedger = (chain: TestChain, ballot: any) => ballotCode.ledger(chain.getContractStateOrThrow(ballot.address).data);
const registryLedger = (chain: TestChain, registry: any) => registryCode.ledger(chain.getContractStateOrThrow(registry.address).data);
const ballotBooks = (p: Participant, ballot: any) => ballotCode.localState(p.account.localState(ballot.address)!);
const registryBooks = (p: Participant, registry: any) => registryCode.localState(p.account.localState(registry.address)!);

describe('the registry and the ballot', () => {
  test('both modules declare their host requirements, and the registry has none', () => {
    installWallet();
    expect(ballotCode.hostInterfaces).toEqual({ [AGE]: ['ageCredential'], [KEYS]: ['secretKey'] });
    expect(registryCode.hostInterfaces).toEqual({});
    expect(runtime.missingHostFunctions(ballotCode.hostInterfaces)).toEqual([]);
  });

  test('two participants enroll and vote, each from their own capsules, and every capsule folds back from its records', async () => {
    installWallet();
    const chain = new TestChain();
    const { registry, ballot } = await deployBoth(chain);
    const alice = new Participant(new Uint8Array(32).fill(1));
    const bob = new Participant(new Uint8Array(32).fill(2));

    // Alice signs up: her ballot capsule is first touched (the local constructor runs), and so is
    // her registry capsule, inside the same transaction, as the callee.
    const s1 = await signup(chain, ballot, alice);
    const [enrollRecord, signupRecord] = s1.context.callProofDataTrace;
    expect(enrollRecord.contractAddress).toEqual(registry.address);
    expect(enrollRecord.circuitId).toEqual('enroll');
    // the registry's books: `remember`'s insert, and nothing of the ballot's
    expect(enrollRecord.localTranscript).toHaveLength(1);
    expect(enrollRecord.hostOutputs).toBeUndefined();
    expect(signupRecord.contractAddress).toEqual(ballot.address);
    // the credential and the key, in call order; the prologue and `myCommitment = some(c)`
    expect(signupRecord.hostOutputs).toHaveLength(2);
    expect(signupRecord.localTranscript).toHaveLength(4);
    expect(signupRecord.calleeReturns).toEqual([enrollRecord.output]);
    expect(Object.keys(runtime.localStates(s1.context)).sort()).toEqual([ballot.address, registry.address].sort());
    // folded into her capsules
    expect(ballotBooks(alice, ballot).credits).toEqual(1n);
    expect(ballotBooks(alice, ballot).myCommitment.is_some).toEqual(true);
    expect(registryBooks(alice, registry).myEnrollments.size()).toEqual(1n);
    // and the public tree has one leaf
    expect(registryLedger(chain, registry).members.firstFree()).toEqual(1n);

    // Bob signs up: the shared tree grows, his books hold only his enrollment, hers are untouched.
    await signup(chain, ballot, bob);
    expect(registryLedger(chain, registry).members.firstFree()).toEqual(2n);
    expect(registryBooks(bob, registry).myEnrollments.size()).toEqual(1n);
    expect(registryBooks(alice, registry).myEnrollments.size()).toEqual(1n);
    const aliceCommitment = ballotBooks(alice, ballot).myCommitment.value;
    const bobCommitment = ballotBooks(bob, ballot).myCommitment.value;
    expect(registryBooks(alice, registry).myEnrollments.member(aliceCommitment)).toEqual(true);
    expect(registryBooks(alice, registry).myEnrollments.member(bobCommitment)).toEqual(false);
    expect(registryBooks(bob, registry).myEnrollments.member(bobCommitment)).toEqual(true);

    // Alice votes: her registry capsule proves her membership against the two-leaf tree.
    const v1 = await vote(chain, ballot, alice, true);
    const proveRecord = v1.context.callProofDataTrace[0];
    expect(proveRecord.circuitId).toEqual('proveMembership');
    // `myEnrollments.member(c)` is the one local op; the tree scan is an unrecorded snapshot read
    expect(proveRecord.localTranscript).toHaveLength(1);
    expect(ballotLedger(chain, ballot).votesFor).toEqual(1n);
    expect(ballotLedger(chain, ballot).nullifiers.size()).toEqual(1n);
    expect(ballotBooks(alice, ballot).credits).toEqual(0n);

    // A second vote fails on her private budget, before anything public, and folds nothing.
    const recordsBefore = alice.account.records.get(ballot.address)!.length;
    await expect(vote(chain, ballot, alice, false)).rejects.toThrow(/no votes left/);
    expect(alice.account.records.get(ballot.address)).toHaveLength(recordsBefore);
    expect(ballotBooks(alice, ballot).credits).toEqual(0n);
    expect(ballotLedger(chain, ballot).votesFor).toEqual(1n);
    expect(ballotLedger(chain, ballot).votesAgainst).toEqual(0n);

    // Bob votes the other way.
    const v2 = await vote(chain, ballot, bob, false);
    expect(ballotLedger(chain, ballot).votesAgainst).toEqual(1n);
    expect(ballotLedger(chain, ballot).nullifiers.size()).toEqual(2n);
    expect(ballotBooks(bob, ballot).credits).toEqual(0n);

    // The books are per account: Bob's registry capsule knows nothing of Alice's enrollment,
    // although the public tree holds it.
    await expect(
      as(bob, () =>
        chain.call({
          module: registryCode,
          address: registry.address,
          witnesses: {},
          privateState: 0,
          circuitId: 'proveMembership',
          args: [aliceCommitment],
          account: bob.account,
        })),
    ).rejects.toThrow(/not enrolled here/);

    // Recovery: each capsule refolded from the declaration defaults over its records is the state
    // the incremental folds reached, which is the state the last transaction touching it rehearsed.
    for (const [p, last] of [[alice, v1], [bob, v2]] as const) {
      for (const [code, deployed] of [[ballotCode, ballot], [registryCode, registry]] as const) {
        const refolded = p.account.refold(code, deployed.address);
        expect(refolded.toString()).toEqual(p.account.localState(deployed.address)!.toString());
        expect(refolded.toString()).toEqual(runtime.localStates(last.context)[deployed.address].toString());
      }
    }
    expect(alice.account.records.get(ballot.address)).toHaveLength(2);
    expect(alice.account.records.get(registry.address)).toHaveLength(2);
  });

  test('the credential is checked in-circuit, and a participant who never signed up cannot vote', async () => {
    installWallet();
    const chain = new TestChain();
    const { registry, ballot } = await deployBoth(chain);

    const underage = new Participant(new Uint8Array(32).fill(3), NOW);
    await expect(signup(chain, ballot, underage)).rejects.toThrow(/under age/);

    const impostor = new Participant(new Uint8Array(32).fill(4), 0n, new Uint8Array(32).fill(0xbb));
    await expect(signup(chain, ballot, impostor)).rejects.toThrow(/unrecognized issuer/);

    // The prologue grants the credit and `spendCredit` takes it; `commitmentOf` then fails, and a
    // failed call folds nothing, so the account still has no capsule for the ballot.
    const lurker = new Participant(new Uint8Array(32).fill(5));
    await expect(vote(chain, ballot, lurker, true)).rejects.toThrow(/not signed up/);
    expect(lurker.account.localState(ballot.address)).toBeUndefined();
    expect(lurker.account.localState(registry.address)).toBeUndefined();
    expect(registryLedger(chain, registry).members.firstFree()).toEqual(0n);
  });
});
