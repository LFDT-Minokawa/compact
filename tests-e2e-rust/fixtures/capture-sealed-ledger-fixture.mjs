// SPDX-License-Identifier: Apache-2.0
//
// Prod-5a: capture TS reference state for sealed_ledger_fixture.compact.
//
// The fixture has a 1-line constructor that writes the sealed `admin`
// field (admin = 42) and exports a single circuit `ping()` that writes
// the regular `flag` field. We capture two stages:
//   - afterInit: ContractState after initialState() — proves the
//     sealed-field initializer reaches the same StateValue layout as
//     a regular ledger field.
//   - afterPing: ContractState after ping() — proves a non-sealed
//     field next to a sealed one is still writable end-to-end.
//
// Usage:
//   compactc --skip-zk examples/sealed_ledger_fixture.compact \
//     /tmp/sealed-ledger-ts-driver/
//   echo '{"type":"module"}' > /tmp/sealed-ledger-ts-driver/contract/package.json
//   ln -sfn "$PWD/node_modules" \
//     /tmp/sealed-ledger-ts-driver/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-sealed-ledger-fixture.mjs \
//     > tests-e2e-rust/fixtures/sealed-ledger-fixture-ts-state.json

import { Contract } from '/tmp/sealed-ledger-ts-driver/contract/index.js';
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

// ---- Step 2: ping() -------------------------------------------------------
const pingOut = contract.circuits.ping(circuitCtx);
circuitCtx = pingOut.context;
const afterPingContractState = rewrapEnvelope(
  afterInitContractState,
  chargedStateFromCtx(circuitCtx),
);
const afterPingHex = Buffer.from(afterPingContractState.serialize()).toString('hex');

const fixture = {
  afterInit: { stateHex: afterInitHex },
  afterPing: { stateHex: afterPingHex },
};

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
