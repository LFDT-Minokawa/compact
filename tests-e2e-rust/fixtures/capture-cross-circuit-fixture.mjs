// SPDX-License-Identifier: Apache-2.0
//
// E5 of the M3.5 plan: capture TS reference state for
// cross_circuit_fixture.compact's initial_state(). The fixture has no
// source-level constructor and no source witnesses; the frontend
// synthesises an empty implicit one. The contract exports two impure
// circuits where `reset_and_set` calls `reset()` — this exercises the
// body walker's new `impure-exported` classification on the Rust side.
//
// Usage:
//   compactc --skip-zk examples/cross_circuit_fixture.compact /tmp/cross-circuit-ts-driver/
//   echo '{"type":"module"}' > /tmp/cross-circuit-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/cross-circuit-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-cross-circuit-fixture.mjs \
//     > tests-e2e-rust/fixtures/cross-circuit-fixture-ts-state.json

import { Contract } from '/tmp/cross-circuit-ts-driver/contract/index.js';
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
