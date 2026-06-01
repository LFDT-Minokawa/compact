// SPDX-License-Identifier: Apache-2.0
//
// Iter 6 validation: capture TS reference state for
// fold_fixture.compact's initial_state(). One Counter ledger field
// seeded by iterating a literal Uint<16>[3] array in the constructor;
// the loop variable IS used in the body, so each iteration is a
// `c.increment(x)` with x cycling through 1, 2, 3 — and the final
// Counter value is 6. Mirrors Iter 5's for-iter capture but exercises
// the per-iteration loop-var substitution that Iter 6 unlocks in the
// Rust emitter.
//
// Usage:
//   compactc --skip-zk --rust examples/fold_fixture.compact /tmp/fold-fixture-driver/
//   echo '{"type":"module"}' > /tmp/fold-fixture-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/fold-fixture-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-fold-fixture.mjs \
//     > tests-e2e-rust/fixtures/fold-fixture-ts-state.json

import { Contract } from '/tmp/fold-fixture-driver/contract/index.js';
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
