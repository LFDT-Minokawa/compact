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

// SPDX-License-Identifier: Apache-2.0
//
// F5 of the M3.5 plan: capture TS reference state for vector_fixture.compact's
// initial_state(). One Vector<3, Field> ledger field, no constructor, no witnesses.
//
// Usage:
//   compactc --skip-zk examples/vector_fixture.compact /tmp/vector-ts-driver/
//   echo '{"type":"module"}' > /tmp/vector-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/vector-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-vector-fixture.mjs \
//     > tests-e2e-rust/fixtures/vector-fixture-ts-state.json

import { Contract } from '/tmp/vector-ts-driver/contract/index.js';
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
