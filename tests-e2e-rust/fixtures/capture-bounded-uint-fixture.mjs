// SPDX-License-Identifier: Apache-2.0
//
// Iter 8 of codegen-rust polish: capture TS reference state for
// bounded_uint_fixture.compact's initial_state(). The fixture has no
// source-level constructor and no source witnesses; the frontend
// synthesises an empty implicit one.
//
// Usage:
//   compactc --skip-zk examples/bounded_uint_fixture.compact \
//     /tmp/bounded-uint-ts-driver/
//   echo '{"type":"module"}' > /tmp/bounded-uint-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" \
//     /tmp/bounded-uint-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-bounded-uint-fixture.mjs \
//     > tests-e2e-rust/fixtures/bounded-uint-fixture-ts-state.json

import { Contract } from '/tmp/bounded-uint-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

const witnesses = {};
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
