// SPDX-License-Identifier: Apache-2.0
//
// M1 of the M3 plan: capture the TS-side reference state for
// tiny.compact so the Rust byte-parity test (M2) has something to
// assert against.
//
// Driver sequence:
//   1. Build a Contract with a deterministic `private$secret_key`
//      witness returning a 32-byte constant (all 0x07).
//   2. Call `initialState(ctx, 42n)` to drive tiny.compact's
//      constructor, producing an initial ContractState.
//   3. Serialize the resulting ContractState with `.serialize()`
//      (the canonical byte serializer used by counter's fixture).
//   4. Print a JSON object with the hex bytes + the post-state
//      ledger view (just the exported `value` field, as a string
//      because Field decodes to a bigint in TS).
//
// Usage:
//   # First compile tiny.compact to TS:
//   #   compactc --skip-zk examples/tiny.compact /tmp/tiny-ts-driver/
//   # Then run:
//   node tests-e2e-rust/fixtures/capture-tiny.mjs \
//     > tests-e2e-rust/fixtures/tiny-ts-state.json

// NOTE: the generated contract module uses ESM `import` syntax. Node
// only treats files with .mjs or a parent package.json marking
// `"type": "module"` as ESM. Before running this driver, write a
// minimal package.json into the generated contract dir:
//
//   echo '{"type":"module"}' > /tmp/tiny-ts-driver/contract/package.json
//
// (compactc could emit one itself; for now we do it out-of-band.)
import { Contract, ledger } from '/tmp/tiny-ts-driver/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// Deterministic witness: always returns a 32-byte constant secret.
// The constructor passes this through public_key() (a persistent
// hash), so the resulting `authority` field is deterministic too.
const witnesses = {
  private$secret_key: (ctx) => {
    const sk = new Uint8Array(32).fill(7);
    return [ctx.privateState, sk];
  },
};

const contract = new Contract(witnesses);

// Build a ConstructorContext with an empty Zswap local state. We
// pass an EncodedCoinPublicKey directly (32 zero bytes) so we don't
// need to deal with bech32 encoding of the string form.
const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

const result = contract.initialState(constructorCtx, 42n);

// Canonical byte encoding of the post-init ContractState.
const stateBytes = result.currentContractState.serialize();
const stateHex = Buffer.from(stateBytes).toString('hex');

// Decoded ledger view — tiny.compact exports the `value` field.
// `ledger()` expects a StateValue or ChargedState, so pass the
// ContractState's `data` (a ChargedState) rather than the wrapper.
const view = ledger(result.currentContractState.data);
const valueStr = view.value.toString();

const fixture = {
  stateHex,
  ledger: {
    value: valueStr,
  },
};

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
