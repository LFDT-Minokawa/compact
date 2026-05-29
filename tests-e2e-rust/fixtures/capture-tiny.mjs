// SPDX-License-Identifier: Apache-2.0
//
// M2.1 of the M3 plan: capture multi-step TS reference state for
// tiny.compact so the Rust byte-parity tests can assert at each step.
//
// Driver sequence:
//   1. Build a Contract with a deterministic `private$secret_key`
//      witness returning a 32-byte constant (all 0x07).
//   2. Call `initialState(ctx, 42n)` to drive tiny.compact's
//      constructor (post: state=1/set, value=42, authority=H([7;32])).
//   3. Call `circuits.clear(circuitCtx)` (post: state=0/unset, value=0).
//      Requires state==1 (true after init) AND apk==authority (true
//      because witness is deterministic).
//   4. Call `circuits.set(circuitCtx, 99n)` (post: state=1, value=99).
//      Requires state==0 (true after clear).
//   5. Call `circuits.get(circuitCtx)` — pure-ish read. Returns
//      Maybe<bigint>{is_some:true, value:99n}.
//
// For each step we capture:
//   - hex of `currentContractState.serialize()` AFTER applying the
//     mutation to the maintained ContractState envelope (so the
//     operations map / authority is included in the envelope).
//   - the decoded `ledger().value` as a decimal string.
// We also capture the get() result separately.
//
// Usage:
//   compactc --skip-zk examples/tiny.compact /tmp/tiny-ts-driver/
//   echo '{"type":"module"}' > /tmp/tiny-ts-driver/contract/package.json
//   node tests-e2e-rust/fixtures/capture-tiny.mjs \
//     > tests-e2e-rust/fixtures/tiny-ts-state.json

import { Contract, ledger } from '/tmp/tiny-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// Deterministic witness: always returns a 32-byte constant secret.
const witnesses = {
  private$secret_key: (ctx) => {
    const sk = new Uint8Array(32).fill(7);
    return [ctx.privateState, sk];
  },
};

const contract = new Contract(witnesses);

const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

// ---- Step 2: initialState -------------------------------------------------
const initResult = contract.initialState(constructorCtx, 42n);
const afterInitContractState = initResult.currentContractState; // ContractState

const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');
const afterInitValue = ledger(afterInitContractState.data).value.toString();

// Build the running CircuitContext from the post-init ContractState.
// This is exactly what an off-chain caller would do between circuit
// invocations: thread the latest ContractState into a new
// CircuitContext. We use the same deterministic witness, same private
// state, same empty zswap.
let circuitCtx = cr.createCircuitContext(
  cr.dummyContractAddress(),
  emptyCpk,
  afterInitContractState.data,
  initResult.currentPrivateState,
);

// Helper: wrap a CircuitContext's currentQueryContext.state back into
// a full ContractState envelope (operations + authority + balance)
// so we can serialize and compare byte-for-byte. We reuse the
// operations / authority / balance from the previous ContractState
// because circuits only mutate `data`.
function rewrapEnvelope(prev, newChargedState) {
  const next = new cr.ContractState();
  next.data = newChargedState;
  // Carry over operations entries from the prior envelope.
  for (const opKey of prev.operations()) {
    next.setOperation(opKey, prev.operation(opKey));
  }
  next.maintenanceAuthority = prev.maintenanceAuthority;
  next.balance = prev.balance;
  return next;
}

// In the TS runtime, `circuitCtx.currentQueryContext.state` is a
// QueryState whose `.state` is the underlying onchain StateValue.
function chargedStateFromCtx(ctx) {
  return new cr.ChargedState(ctx.currentQueryContext.state.state);
}

// ---- Step 3: clear --------------------------------------------------------
const clearOut = contract.circuits.clear(circuitCtx);
circuitCtx = clearOut.context;
const afterClearContractState = rewrapEnvelope(
  afterInitContractState,
  chargedStateFromCtx(circuitCtx),
);
const afterClearHex = Buffer.from(afterClearContractState.serialize()).toString('hex');
const afterClearValue = ledger(afterClearContractState.data).value.toString();

// ---- Step 4: set(99) ------------------------------------------------------
const setOut = contract.circuits.set(circuitCtx, 99n);
circuitCtx = setOut.context;
const afterSetContractState = rewrapEnvelope(
  afterClearContractState,
  chargedStateFromCtx(circuitCtx),
);
const afterSetHex = Buffer.from(afterSetContractState.serialize()).toString('hex');
const afterSetValue = ledger(afterSetContractState.data).value.toString();

// ---- Step 5: get() --------------------------------------------------------
const getOut = contract.circuits.get(circuitCtx);
circuitCtx = getOut.context;
const getResult = getOut.result; // { is_some, value }

const fixture = {
  // M2 (constructor-only) fixture shape kept at the top level for
  // backwards compatibility with the original tiny_init_byte_parity test.
  stateHex: afterInitHex,
  ledger: { value: afterInitValue },

  // M2.1 extension: per-step snapshots.
  afterInit: { stateHex: afterInitHex, ledger: { value: afterInitValue } },
  afterClear: { stateHex: afterClearHex, ledger: { value: afterClearValue } },
  afterSet99: { stateHex: afterSetHex, ledger: { value: afterSetValue } },
  getResult: {
    isSome: Boolean(getResult.is_some),
    value: getResult.value.toString(),
  },
};

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
