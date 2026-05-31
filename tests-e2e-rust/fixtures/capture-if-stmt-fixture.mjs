// SPDX-License-Identifier: Apache-2.0
//
// F8 of the M3.5 plan: capture TS reference state for if_stmt_fixture.compact's
// initial_state(). One Boolean ledger field plus an exported pure circuit
// `classify(b: Boolean): Boolean` whose body exercises E6's statement-position
// if-then-else emission. No constructor, no witnesses.
//
// Usage:
//   compactc --skip-zk examples/if_stmt_fixture.compact /tmp/if-stmt-ts-driver/
//   echo '{"type":"module"}' > /tmp/if-stmt-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/if-stmt-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-if-stmt-fixture.mjs \
//     > tests-e2e-rust/fixtures/if-stmt-fixture-ts-state.json

import { Contract } from '/tmp/if-stmt-ts-driver/contract/index.js';
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
