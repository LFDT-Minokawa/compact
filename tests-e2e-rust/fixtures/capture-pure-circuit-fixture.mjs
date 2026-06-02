// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Iter-9: capture TS reference state for pure_circuit_fixture.compact's
// initial_state(). One Boolean ledger field plus two exported pure
// circuits (`and_b`, `which_u32`) and one impure `ping`. The pure
// circuits are tested directly in Rust (no TS-side runtime path to
// mirror) — only the initial-state byte layout needs a TS reference.
//
// Usage:
//   compactc --skip-zk examples/pure_circuit_fixture.compact /tmp/pure-circuit-ts-driver/
//   echo '{"type":"module"}' > /tmp/pure-circuit-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/pure-circuit-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-pure-circuit-fixture.mjs \
//     > tests-e2e-rust/fixtures/pure-circuit-fixture-ts-state.json

import { Contract } from '/tmp/pure-circuit-ts-driver/contract/index.js';
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
