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

// Iter 10: capture TS reference state for module_fixture.compact.
//
// The fixture declares `inner_count: Counter` and `bump_inner()` inside
// `module M { ... }`, then re-exports both via `import M; export {
// inner_count, bump_inner }`. The constructor only touches the
// top-level `outer_flag: Boolean` field. We capture two stages:
//   - afterInit:     ContractState after initialState() — proves the
//                    module's `inner_count` field lands at the same
//                    flat slot index as a top-level field (the module
//                    boundary is invisible at this layer).
//   - afterBumpInner: ContractState after bump_inner() — proves a
//                    circuit defined inside the module is emitted as a
//                    flat method on `Contract` and mutates the shared
//                    ledger correctly.
//
// Usage:
//   compactc --skip-zk examples/module_fixture.compact \
//     /tmp/module-fixture-ts-driver/
//   echo '{"type":"module"}' > /tmp/module-fixture-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" \
//     /tmp/module-fixture-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-module-fixture.mjs \
//     > tests-e2e-rust/fixtures/module-fixture-ts-state.json

import { Contract } from '/tmp/module-fixture-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

const witnesses = {};
const contract = new Contract(witnesses);

const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

// ---- Step 1: initialState -------------------------------------------------
const initResult = contract.initialState(constructorCtx);
const afterInitContractState = initResult.currentContractState;
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');

// Build the running CircuitContext from the post-init ContractState.
let circuitCtx = cr.createCircuitContext(
  cr.dummyContractAddress(),
  emptyCpk,
  afterInitContractState.data,
  initResult.currentPrivateState,
);

function rewrapEnvelope(prev, newChargedState) {
  const next = new cr.ContractState();
  next.data = newChargedState;
  for (const opKey of prev.operations()) {
    next.setOperation(opKey, prev.operation(opKey));
  }
  next.maintenanceAuthority = prev.maintenanceAuthority;
  next.balance = prev.balance;
  return next;
}

function chargedStateFromCtx(ctx) {
  return new cr.ChargedState(ctx.currentQueryContext.state.state);
}

// ---- Step 2: bump_inner() -------------------------------------------------
const bumpOut = contract.circuits.bump_inner(circuitCtx);
circuitCtx = bumpOut.context;
const afterBumpInnerContractState = rewrapEnvelope(
  afterInitContractState,
  chargedStateFromCtx(circuitCtx),
);
const afterBumpInnerHex = Buffer.from(afterBumpInnerContractState.serialize()).toString('hex');

const fixture = {
  afterInit: { stateHex: afterInitHex },
  afterBumpInner: { stateHex: afterBumpInnerHex },
};

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
