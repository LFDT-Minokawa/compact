// SPDX-License-Identifier: Apache-2.0
//
// F6 of the M3.5 plan: capture TS reference state for aliases_fixture.compact's
// initial_state(). Two transparent type aliases (Uint<16>, Bytes<8>) plus one
// nominal alias (`export new type Tag = Bytes<8>;`) over ledger fields.
// No constructor, no witnesses.
//
// Usage:
//   compactc --skip-zk examples/aliases_fixture.compact /tmp/aliases-ts-driver/
//   echo '{"type":"module"}' > /tmp/aliases-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/aliases-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-aliases-fixture.mjs \
//     > tests-e2e-rust/fixtures/aliases-fixture-ts-state.json

import { Contract } from '/tmp/aliases-ts-driver/contract/index.js';
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
