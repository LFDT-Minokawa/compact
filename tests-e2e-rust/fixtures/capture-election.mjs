// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// SPDX-License-Identifier: Apache-2.0
//
// F2.2/2 of the M3.5 plan: multi-step TS reference state capture for
// election.compact. Mirrors F1.2 (zerocash) structure.
//
// election.compact has a source-level constructor
// `constructor(authority_init: Bytes<32>) { authority = authority_init; }`,
// so we seed `authority` to `public_key(FIXED_SK)` and unblock the
// owner-driven asserts `public_key(sk) == authority.read()` in
// set_topic / advance / add_voter.
//
// vote$commit + vote$reveal additionally need a real MerklePath rooted
// in the on-chain MerkleTree. We use the same trick as
// capture-zerocash.mjs: extract the on-chain BoundedMerkleTree out of
// the ChargedState, ask it for `pathForLeaf(idx, leafHash(leaf))`, and
// decode the resulting AlignedValue into the witness's
// `MerkleTreePath<10, Bytes<32>>` shape. Driver-side index counters
// track where each insertion lands.
//
// The voter we register is `AUTHORITY` itself (which equals
// `public_key(FIXED_SK)`). That way `vote$commit` derives the same pk
// from `private$secret_key()`, and `context$eligible_voters$path_of`
// can return a path whose leaf matches.
//
// Usage:
//   compactc --skip-zk examples/election.compact /tmp/election-ts-driver/
//   echo '{"type":"module"}' > /tmp/election-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/election-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-election.mjs \
//     > tests-e2e-rust/fixtures/election-ts-state.json

import { Contract } from '/tmp/election-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';
import { leafHash, valueToBigInt } from '@midnight-ntwrk/onchain-runtime-v3';

// ------------ Fixed deterministic witness payloads -----------------
const FIXED_SK = new Uint8Array(32).fill(7); // private$secret_key

// Decode the StateBoundedMerkleTree.pathForLeaf AlignedValue into the
// witness's MerkleTreePath shape. See capture-zerocash.mjs for the
// detailed layout — same pattern, just at depth 10 here.
function decodeMerklePath(av, depth) {
  const v = av.value;
  const path = [];
  for (let i = 0; i < depth; i++) {
    const fieldBig = valueToBigInt([v[1 + 2 * i]]);
    const gl = v[2 + 2 * i];
    const goesLeft = gl.length > 0 && gl[0] !== 0;
    path.push({ sibling: { field: fieldBig }, goes_left: goesLeft });
  }
  return { leaf: new Uint8Array(v[0]), path };
}

// Driver-side mirrors of the two MerkleTrees on-chain. Each one keeps
// a `hex(leaf) → index` map updated alongside the corresponding
// `insert(leaf)` call on the source contract; the witness consults
// the right map (eligible_voters vs committed_votes) and then asks
// the actual on-chain tree (extracted out of the ChargedState) for
// `pathForLeaf(idx, leafHash(leaf))`.
const eligibleIndex = new Map();
let eligibleNext = 0n;
const committedIndex = new Map();
let committedNext = 0n;

const sharedState = { rawStateValue: null };

// Pulled out of the ChargedState; election's ledger layout puts the
// two MerkleTree ADTs at root indices 5 (committed_votes) and 6
// (eligible_voters). Each is an array `[BoundedMerkleTree, counter]`.
function committedVotesTree(stateValue) {
  return stateValue.asArray()[5].asArray()[0].asBoundedMerkleTree().rehash();
}
function eligibleVotersTree(stateValue) {
  return stateValue.asArray()[6].asArray()[0].asBoundedMerkleTree().rehash();
}

// Capture the paths actually returned to the witnesses, so the Rust
// test can replay them byte-identically without a Rust-side mirror.
let capturedEligiblePath = null;
let capturedCommittedPath = null;

// Tracks the private-state machine the contract assumes between
// circuits. After a successful `vote$commit`, the next call to
// `private$state()` must return PrivateState.committed; otherwise
// `vote$reveal` will see `initial` and bail with "illegal state for
// revealing". The driver toggles this via `private$state$advance`,
// which the contract calls at the tail of each circuit that
// transitions the private state.
let privateStateFsm = 0; // PrivateState.initial
function bumpPrivateState() {
  // initial -> committed -> revealed; values matter to the
  // CompactTypeEnum encoding.
  if (privateStateFsm < 2) privateStateFsm += 1;
}

const witnesses = {
  'private$secret_key': (ctx) => [ctx.privateState, new Uint8Array(FIXED_SK)],
  'private$state': (ctx) => [ctx.privateState, privateStateFsm],
  'private$state$advance': (ctx) => {
    bumpPrivateState();
    return [ctx.privateState, []];
  },
  'private$vote$record': (ctx, _ballot) => [ctx.privateState, []],
  'private$vote': (ctx) => [ctx.privateState, 0], // PermissibleVotes.yes
  'context$eligible_voters$path_of': (ctx, pk) => {
    // add_voter's first assertion is `!path_of(pk).is_some`, before
    // the voter is inserted. Honour that by returning is_some=false
    // until the mirror records the insertion.
    const hex = Buffer.from(pk).toString('hex');
    const idx = eligibleIndex.get(hex);
    if (idx === undefined) {
      // Stub path — is_some=false, so the witness type is satisfied
      // but the assertion takes the `false` branch.
      const stub = Array.from({ length: 10 }, () => ({
        sibling: { field: 0n },
        goes_left: false,
      }));
      return [
        ctx.privateState,
        { is_some: false, value: { leaf: new Uint8Array(pk), path: stub } },
      ];
    }
    const tree = eligibleVotersTree(sharedState.rawStateValue);
    const leafAv = leafHash({
      value: [pk],
      alignment: [{ tag: 'atom', value: { tag: 'bytes', length: 32 } }],
    });
    const pathAv = tree.pathForLeaf(idx, leafAv);
    const decoded = decodeMerklePath(pathAv, 10);
    decoded.leaf = new Uint8Array(pk);
    capturedEligiblePath = decoded;
    return [ctx.privateState, { is_some: true, value: decoded }];
  },
  'context$committed_votes$path_of': (ctx, cm) => {
    const hex = Buffer.from(cm).toString('hex');
    const idx = committedIndex.get(hex);
    if (idx === undefined) {
      const stub = Array.from({ length: 10 }, () => ({
        sibling: { field: 0n },
        goes_left: false,
      }));
      return [
        ctx.privateState,
        { is_some: false, value: { leaf: new Uint8Array(cm), path: stub } },
      ];
    }
    const tree = committedVotesTree(sharedState.rawStateValue);
    const leafAv = leafHash({
      value: [cm],
      alignment: [{ tag: 'atom', value: { tag: 'bytes', length: 32 } }],
    });
    const pathAv = tree.pathForLeaf(idx, leafAv);
    const decoded = decodeMerklePath(pathAv, 10);
    decoded.leaf = new Uint8Array(cm);
    capturedCommittedPath = decoded;
    return [ctx.privateState, { is_some: true, value: decoded }];
  },
};

const contract = new Contract(witnesses);
const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

const AUTHORITY = contract._public_key_0(new Uint8Array(FIXED_SK));

// VOTER_PK = AUTHORITY: vote$commit derives pk via `public_key(sk)`,
// which equals AUTHORITY for our FIXED_SK. So the only voter we can
// register (and have vote$commit succeed for) is AUTHORITY itself.
const VOTER_PK = new Uint8Array(AUTHORITY);

// ---- Step 1: initialState -----------------------------------------
const initResult = contract.initialState(constructorCtx, AUTHORITY);
const afterInitContractState = initResult.currentContractState;
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString(
  'hex',
);

function rewrapEnvelope(prev, newChargedState) {
  const next = new cr.ContractState();
  next.data = newChargedState;
  for (const opKey of prev.operations()) {
    next.setOperation(opKey, prev.operation(opKey));
  }
  next.maintenanceAuthority = prev.maintenanceAuthority;
  next.balance = prev.balance;
  return next;
}

function chargedStateFromCtx(ctx) {
  return new cr.ChargedState(ctx.currentQueryContext.state.state);
}

function freshCtx() {
  return {
    ctx: cr.createCircuitContext(
      cr.dummyContractAddress(),
      emptyCpk,
      afterInitContractState.data,
      initResult.currentPrivateState,
    ),
    envelope: afterInitContractState,
  };
}

const fixture = {
  afterInit: { stateHex: afterInitHex },
};

// runChain: applies a sequence of (label, runner) steps starting from
// a fresh post-init context. After each step we refresh
// `sharedState.rawStateValue` so any later witness call sees the
// freshest ChargedState. Also resets the driver mirrors so each chain
// is independent. Captured paths are scoped per chain too.
function runChain(recordLabel, steps, registerInserts = () => {}) {
  // Per-chain mirror reset — each chain is rebuilt from a fresh
  // post-init context so all derived state restarts from scratch.
  eligibleIndex.clear();
  eligibleNext = 0n;
  committedIndex.clear();
  committedNext = 0n;
  capturedEligiblePath = null;
  capturedCommittedPath = null;
  privateStateFsm = 0;

  let { ctx, envelope } = freshCtx();
  // Re-export so witnesses see the per-chain freshly-reset state.
  sharedState.rawStateValue = ctx.currentQueryContext.state.state;
  try {
    for (let i = 0; i < steps.length; i++) {
      const [stepLabel, runner] = steps[i];
      const out = runner(ctx);
      ctx = out.context;
      sharedState.rawStateValue = ctx.currentQueryContext.state.state;
      envelope = rewrapEnvelope(envelope, chargedStateFromCtx(ctx));
      // Post-step bookkeeping: now that this step has actually
      // performed its insertion (and the on-chain tree has the leaf),
      // mirror the index so any later witness call can find it.
      registerInserts(stepLabel);
    }
    const hex = Buffer.from(envelope.serialize()).toString('hex');
    fixture[recordLabel] = { stateHex: hex };
  } catch (e) {
    fixture[recordLabel] = { error: String((e && e.message) || e) };
  }
}

// Helper that registers the insertion mirror records for a given step
// label. Centralised so the chains below stay readable.
function insertRegistrar(stepLabel) {
  if (stepLabel === 'add_voter') {
    eligibleIndex.set(Buffer.from(VOTER_PK).toString('hex'), eligibleNext++);
  }
  if (stepLabel === 'vote_commit') {
    // vote$commit inserts `commit_with_sk(ballot_repr(ballot), sk)` =
    // persistentHash<Vector<2, Bytes<32>>>([pad32("yes"), FIXED_SK]).
    // Compute it eagerly so the *next* path_of can find it.
    const vec2 = new cr.CompactTypeVector(2, new cr.CompactTypeBytes(32));
    const yesPad = new Uint8Array(32);
    yesPad.set([121, 101, 115]); // "yes"
    const cm = cr.persistentHash(vec2, [yesPad, new Uint8Array(FIXED_SK)]);
    committedIndex.set(Buffer.from(cm).toString('hex'), committedNext++);
  }
}

// init → set_topic("hello")
runChain(
  'afterSetTopic',
  [['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')]],
  insertRegistrar,
);

// init → set_topic("hello") → advance
runChain(
  'afterAdvance',
  [
    ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
    ['advance', (ctx) => contract.circuits.advance(ctx)],
  ],
  insertRegistrar,
);

// init → add_voter(AUTHORITY)
runChain(
  'afterAddVoter',
  [['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)]],
  insertRegistrar,
);

// init → set_topic → add_voter → advance → vote$commit(yes)
runChain(
  'afterVoteCommit',
  [
    ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
    ['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)],
    ['advance', (ctx) => contract.circuits.advance(ctx)],
    ['vote_commit', (ctx) => contract.circuits['vote$commit'](ctx, 0)],
  ],
  insertRegistrar,
);
if (capturedEligiblePath) {
  fixture.votePathEligible = serialisePath(capturedEligiblePath);
}

// init → set_topic → add_voter → advance → vote$commit → advance → vote$reveal
runChain(
  'afterVoteReveal',
  [
    ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
    ['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)],
    ['advance', (ctx) => contract.circuits.advance(ctx)],
    ['vote_commit', (ctx) => contract.circuits['vote$commit'](ctx, 0)],
    ['advance', (ctx) => contract.circuits.advance(ctx)],
    ['vote_reveal', (ctx) => contract.circuits['vote$reveal'](ctx)],
  ],
  insertRegistrar,
);
if (capturedCommittedPath) {
  fixture.votePathCommitted = serialisePath(capturedCommittedPath);
}

// Encode one captured MerklePath into the JSON shape the Rust
// fixture loader expects: { leafHex, path: [{ siblingHex, goesLeft }, … ] }
// with siblings as big-endian 32-byte hex strings.
function serialisePath(p) {
  const path = p.path.map((e) => {
    let n = e.sibling.field;
    const buf = new Uint8Array(32);
    for (let i = 31; i >= 0; i--) {
      buf[i] = Number(n & 0xffn);
      n >>= 8n;
    }
    return {
      siblingHex: Buffer.from(buf).toString('hex'),
      goesLeft: e.goes_left,
    };
  });
  return {
    leafHex: Buffer.from(p.leaf).toString('hex'),
    path,
  };
}

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
