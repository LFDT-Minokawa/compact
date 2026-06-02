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

// Prod-18 — honourable-mention sweep: capture TS reference state for
// nested_map_fixture.compact's initial_state(). Mirrors upstream
// test1010: a single ledger field of type
// Map<Field, Map<Field, Uint<64>>> whose implicit initial value is an
// empty outer Map. Validates that nested Map<K, Map<K2, V>> seeds to
// the same bytes on both sides of the codegen.
//
// Usage:
//   compactc --skip-zk examples/nested_map_fixture.compact \
//     /tmp/nested-map-fixture-driver/
//   echo '{"type":"module"}' > /tmp/nested-map-fixture-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" /tmp/nested-map-fixture-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-nested-map-fixture.mjs \
//     > tests-e2e-rust/fixtures/nested-map-fixture-ts-state.json

import { Contract } from '/tmp/nested-map-fixture-driver/contract/index.js';
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
