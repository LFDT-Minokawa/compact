// SPDX-License-Identifier: Apache-2.0
//
// F7 of the M3.5 plan: capture TS reference state for witnesses_fixture.compact's
// initial_state(). The fixture declares three witnesses but only references
// fetch_field from its export circuit; the unused declarations are dropped by
// the frontend. We still provide a deterministic witness implementation so
// the TS driver loads, even though initial_state() doesn't invoke it.
//
// Usage:
//   compactc --skip-zk examples/witnesses_fixture.compact /tmp/witnesses-ts-driver/
//   echo '{"type":"module"}' > /tmp/witnesses-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/witnesses-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-witnesses-fixture.mjs \
//     > tests-e2e-rust/fixtures/witnesses-fixture-ts-state.json

import { Contract } from '/tmp/witnesses-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

const witnesses = {
  fetch_field: (ctx) => [ctx.privateState, 42n],
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
