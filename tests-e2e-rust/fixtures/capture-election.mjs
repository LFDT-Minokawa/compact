// SPDX-License-Identifier: Apache-2.0
//
// F2.2 of the M3.5 plan: multi-step TS reference state capture for
// election.compact. Mirrors F1.2 (zerocash) structure.
//
// election.compact has no source-level constructor, so initial_state()
// seeds `authority` to `Bytes<32>::default()` = all zeros. The
// owner-driven circuits (set_topic / advance / add_voter) all assert
// `public_key(sk) == authority.read()`, which means the witness-side
// secret_key must hash (via persistent_hash with the "lares:election:pk:"
// domain separator) to all-zero bytes. That is hash-resistant, so
// every owner-driven step is expected to fail unless we can synthesize
// a preimage — which we cannot.
//
// We still drive the chain: any successful step is captured as
// `stateHex`; any failure is captured as `error`. The Rust test gates
// each step on the presence of `stateHex` (panics with the captured
// error if absent), giving us a clear diagnostic if upstream behavior
// ever changes.
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

// ---- Step 1: initialState -----------------------------------------
const initResult = contract.initialState(constructorCtx);
const afterInitContractState = initResult.currentContractState;
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');

let circuitCtx = cr.createCircuitContext(
  cr.dummyContractAddress(),
  emptyCpk,
  afterInitContractState.data,
  initResult.currentPrivateState,
);

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

const fixture = {
  afterInit: { stateHex: afterInitHex },
};

let lastContractState = afterInitContractState;

function tryStep(label, runner) {
  try {
    const out = runner(circuitCtx);
    circuitCtx = out.context;
    const nextState = rewrapEnvelope(lastContractState, chargedStateFromCtx(circuitCtx));
    const hex = Buffer.from(nextState.serialize()).toString('hex');
    lastContractState = nextState;
    fixture[label] = { stateHex: hex };
    return true;
  } catch (e) {
    fixture[label] = { error: String((e && e.message) || e) };
    return false;
  }
}

// ---- Step 2: set_topic("hello") -----------------------------------
tryStep('afterSetTopic', (ctx) => contract.circuits.set_topic(ctx, 'hello'));

// ---- Step 3: advance() --------------------------------------------
tryStep('afterAdvance', (ctx) => contract.circuits.advance(ctx));

// ---- Step 4: add_voter(pk) ----------------------------------------
const VOTER_PK = new Uint8Array(32).fill(0x11);
tryStep('afterAddVoter', (ctx) => contract.circuits.add_voter(ctx, VOTER_PK));

// ---- Step 5: vote$commit(yes) -------------------------------------
tryStep('afterVoteCommit', (ctx) => contract.circuits['vote$commit'](ctx, 0));

// ---- Step 6: vote$reveal() ----------------------------------------
tryStep('afterVoteReveal', (ctx) => contract.circuits['vote$reveal'](ctx));

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
