// SPDX-License-Identifier: Apache-2.0
//
// F3 of the M3.5 plan: capture TS reference state for map_fixture.compact's
// initial_state(). The fixture has no source-level constructor and no source
// witnesses; the frontend synthesises an empty implicit one. We drive the
// TS-emitted Contract.initialState() with an empty witnesses object and
// capture the serialized ContractState bytes.
//
// Usage:
//   compactc --skip-zk examples/map_fixture.compact /tmp/map-fixture-ts-driver/
//   echo '{"type":"module"}' > /tmp/map-fixture-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/map-fixture-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-map-fixture.mjs \
//     > tests-e2e-rust/fixtures/map-fixture-ts-state.json

import { Contract } from '/tmp/map-fixture-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// map_fixture has no witnesses; pass an empty object.
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
