// SPDX-License-Identifier: Apache-2.0
//
// F2.1 of the M3.5 plan: capture TS reference state for election.compact's
// initial_state(). election has no source-level constructor (implicit) and
// declares 7 witnesses; for capturing initial_state none are invoked, so we
// supply trivial stubs.
//
// Usage:
//   compactc --skip-zk examples/election.compact /tmp/election-ts-driver/
//   echo '{"type":"module"}' > /tmp/election-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/election-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-election.mjs \
//     > tests-e2e-rust/fixtures/election-ts-state.json

import { Contract } from '/tmp/election-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

const witnesses = {
  'private$secret_key':              (ctx)            => [ctx.privateState, new Uint8Array(32)],
  'private$state':                   (ctx)            => [ctx.privateState, 0],
  'private$state$advance':           (ctx)            => [ctx.privateState, []],
  'private$vote$record':             (ctx, _ballot)   => [ctx.privateState, []],
  'private$vote':                    (ctx)            => [ctx.privateState, 0],
  'context$eligible_voters$path_of': (ctx, _pk)       => [ctx.privateState, { is_some: false, value: { leaf: new Uint8Array(32), path: [] } }],
  'context$committed_votes$path_of': (ctx, _cm)       => [ctx.privateState, { is_some: false, value: { leaf: new Uint8Array(32), path: [] } }],
};

const contract = new Contract(witnesses);

const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

const initResult = contract.initialState(constructorCtx);
const afterInitContractState = initResult.currentContractState;

const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');

const fixture = {
  afterInit: { stateHex: afterInitHex },
};

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
