// SPDX-License-Identifier: Apache-2.0
//
// Iter 4 validation: capture TS reference state for
// for_range_fixture.compact's initial_state(). One Counter ledger field
// seeded to 10 via a literal-bounds for-range loop in the source-level
// constructor. The exported `ping` circuit is a no-op (.increment(0))
// so the contract has at least one exported entry point.
//
// Usage:
//   compactc --skip-zk examples/for_range_fixture.compact /tmp/for-range-fixture-driver/
//   echo '{"type":"module"}' > /tmp/for-range-fixture-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/for-range-fixture-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-for-range-fixture.mjs \
//     > tests-e2e-rust/fixtures/for-range-fixture-ts-state.json

import { Contract } from '/tmp/for-range-fixture-driver/contract/index.js';
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
