// SPDX-License-Identifier: Apache-2.0
//
// F1.1 of the M3.5 plan: capture TS reference state for zerocash.compact's
// initial_state(). zerocash has no source-level constructor and no source
// witnesses — the frontend synthesises an empty implicit one. We drive the
// TS-emitted Contract.initialState() with an empty witnesses object and
// capture the serialized ContractState bytes.
//
// Usage:
//   compactc --skip-zk examples/zerocash.compact /tmp/zerocash-ts-driver/
//   echo '{"type":"module"}' > /tmp/zerocash-ts-driver/contract/package.json
//   node tests-e2e-rust/fixtures/capture-zerocash.mjs \
//     > tests-e2e-rust/fixtures/zerocash-ts-state.json

import { Contract } from '/tmp/zerocash-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// zerocash has 7 witnesses; for capturing initial_state none of them are
// invoked (the constructor is empty), so we supply trivial stubs.
const noop = (ctx) => [ctx.privateState, undefined];
const witnesses = {
  'private$zk_secret_key': (ctx) => [ctx.privateState, { bytes: new Uint8Array(32) }],
  'private$remove_coin': (ctx, _coin) => [ctx.privateState, []],
  'private$zk_public_key': (ctx) => [ctx.privateState, { bytes: new Uint8Array(32) }],
  'private$add_coin': (ctx, _coin) => [ctx.privateState, []],
  'context$path_of': (ctx, _cm) => [ctx.privateState, null],
  'context$new_coin_info': (ctx) => [ctx.privateState, null],
  'context$encrypt': (ctx, _pk, _coin) => [ctx.privateState, new Uint8Array(0)],
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
