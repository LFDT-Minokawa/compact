// SPDX-License-Identifier: Apache-2.0
//
// F2.2/2 of the M3.5 plan: multi-step TS reference state capture for
// election.compact. Mirrors F1.2 (zerocash) structure.
//
// election.compact now exposes a source-level constructor
// `constructor(authority_init: Bytes<32>) { authority = authority_init; }`
// so we can seed `authority` to `public_key(FIXED_SK)` and unblock
// the owner-driven asserts `public_key(sk) == authority.read()` in
// set_topic / advance / add_voter.
//
// We still drive the chain robustly: any successful step is captured
// as `stateHex`; any failure is captured as `error`. The Rust test
// gates each step on the presence of `stateHex` (panics with the
// captured error if absent). vote$commit / vote$reveal additionally
// need a MerklePath rooted in the on-chain tree, which we don't
// synthesize here — those steps remain expected-error.
//
// Usage:
//   compactc --skip-zk examples/election.compact /tmp/election-ts-driver/
//   echo '{"type":"module"}' > /tmp/election-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/election-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-election.mjs \
//     > tests-e2e-rust/fixtures/election-ts-state.json

import { Contract } from '/tmp/election-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// ------------ Fixed deterministic witness payloads -----------------
const FIXED_SK = new Uint8Array(32).fill(7); // private$secret_key

// Build a MerkleTreePath of depth 10 with all siblings = 0 and
// goes_left = false. The leaf is whatever the caller asks for. This
// is enough to satisfy the *type* of the witness; it will not
// generally satisfy `eligible_voters.checkRoot(...)` etc.
function stubMerklePath(leaf) {
  const path = [];
  for (let i = 0; i < 10; i++) {
    path.push({ sibling: { field: 0n }, goes_left: false });
  }
  return { leaf: new Uint8Array(leaf), path };
}

const witnesses = {
  'private$secret_key': (ctx) => [ctx.privateState, new Uint8Array(FIXED_SK)],
  'private$state': (ctx) => [ctx.privateState, 0], // PrivateState.initial
  'private$state$advance': (ctx) => [ctx.privateState, []],
  'private$vote$record': (ctx, _ballot) => [ctx.privateState, []],
  'private$vote': (ctx) => [ctx.privateState, 0], // PermissibleVotes.yes
  'context$eligible_voters$path_of': (ctx, pk) => [
    ctx.privateState,
    { is_some: false, value: stubMerklePath(pk) },
  ],
  'context$committed_votes$path_of': (ctx, cm) => [
    ctx.privateState,
    { is_some: false, value: stubMerklePath(cm) },
  ],
};

const contract = new Contract(witnesses);

const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

// Compute authority = public_key(FIXED_SK) via the Contract's private
// helper. This matches the Rust side, which hardcodes the same bytes
// as AUTHORITY (computed via persistent_hash with domain separator
// "lares:election:pk:"). Keep these two in sync.
const AUTHORITY = contract._public_key_0(new Uint8Array(FIXED_SK));

// ---- Step 1: initialState -----------------------------------------
const initResult = contract.initialState(constructorCtx, AUTHORITY);
const afterInitContractState = initResult.currentContractState;
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');

// Rewrap helper: carry over operations + authority + balance from a
// prior ContractState envelope onto a freshly produced ChargedState.
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

// Build a fresh circuit context anchored at the post-init contract
// state. Each "independent" sub-chain calls this to get its own
// starting ctx + prior-envelope; that way each labelled step's
// captured stateHex matches what the Rust test produces when it
// runs the same prefix from initial_state().
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
// a fresh post-init context. Each step's captured stateHex is the
// post-step ContractState bytes, ready to byte-compare against Rust.
// `recordLabel` is the slot we write into the top-level fixture; this
// is the final step. Earlier steps are run but not exported.
function runChain(recordLabel, steps) {
  let { ctx, envelope } = freshCtx();
  try {
    for (let i = 0; i < steps.length; i++) {
      const [_stepLabel, runner] = steps[i];
      const out = runner(ctx);
      ctx = out.context;
      envelope = rewrapEnvelope(envelope, chargedStateFromCtx(ctx));
    }
    const hex = Buffer.from(envelope.serialize()).toString('hex');
    fixture[recordLabel] = { stateHex: hex };
  } catch (e) {
    fixture[recordLabel] = { error: String((e && e.message) || e) };
  }
}

const VOTER_PK = new Uint8Array(32).fill(0x11);

// init → set_topic("hello")
runChain('afterSetTopic', [
  ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
]);

// init → set_topic("hello") → advance (advance requires topic.is_some)
runChain('afterAdvance', [
  ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
  ['advance', (ctx) => contract.circuits.advance(ctx)],
]);

// init → add_voter(pk) — must run before any state advance.
runChain('afterAddVoter', [
  ['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)],
]);

// vote$commit / vote$reveal both need a real MerklePath rooted in the
// on-chain tree. We don't synthesize one here; expect an assertion
// error capturing the diagnostic.
runChain('afterVoteCommit', [
  ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
  ['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)],
  ['advance', (ctx) => contract.circuits.advance(ctx)],
  ['vote_commit', (ctx) => contract.circuits['vote$commit'](ctx, 0)],
]);

runChain('afterVoteReveal', [
  ['set_topic', (ctx) => contract.circuits.set_topic(ctx, 'hello')],
  ['add_voter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK)],
  ['advance', (ctx) => contract.circuits.advance(ctx)],
  ['vote_commit', (ctx) => contract.circuits['vote$commit'](ctx, 0)],
  ['advance', (ctx) => contract.circuits.advance(ctx)],
  ['vote_reveal', (ctx) => contract.circuits['vote$reveal'](ctx)],
]);

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
