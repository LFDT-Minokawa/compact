// SPDX-License-Identifier: Apache-2.0
//
// F1.2 of the M3.5 plan: multi-step TS reference state capture for
// zerocash.compact, mirroring the M2.1 tiny.compact pattern.
//
// Driver sequence:
//   1. initialState() — capture envelope (after_init)
//   2. zerocash_mint() — capture envelope (after_mint)
//   3. spend(dest_pk, input_coin) — capture envelope (after_spend)
//
// Deterministic witnesses are necessary because zerocash's circuits
// fold their results into the on-chain state via persistent_hash, so
// any non-determinism would diverge the bytes.
//
// Usage:
//   compactc --skip-zk examples/zerocash.compact /tmp/zc-ts/
//   echo '{"type":"module"}' > /tmp/zc-ts/contract/package.json
//   ln -sfn $PWD/node_modules /tmp/zc-ts/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-zerocash.mjs \
//     > tests-e2e-rust/fixtures/zerocash-ts-state.json

import { Contract, ledger } from '/tmp/zc-ts/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';

// ------------ Fixed deterministic witness payloads -----------------
const FIXED_SK = new Uint8Array(32).fill(1);           // private$zk_secret_key
const FIXED_PK = new Uint8Array(32).fill(2);           // private$zk_public_key
const FIXED_NONCE = new Uint8Array(32).fill(3);        // context$new_coin_info.nonce
const FIXED_OPENING = new Uint8Array(32).fill(4);      // context$new_coin_info.opening
const FIXED_CIPHERTEXT = new Uint8Array([10, 11, 12]); // context$encrypt result

function fixedCoinInfo() {
  return {
    nonce: { bytes: new Uint8Array(FIXED_NONCE) },
    opening: { bytes: new Uint8Array(FIXED_OPENING) },
  };
}

// Build a MerkleTreePath of depth 32 with all siblings = 0 and
// goes_left = false. The path's leaf is set by the caller — for the
// spend driver we set it to the commitment that was actually inserted
// by zerocash_mint, but the resulting root won't match commitments.checkRoot
// (the contract inserted at index 0; this stub doesn't claim a position).
// If spend cannot be driven, we capture just init + mint.
function makeMerklePathFor(leafCommitment) {
  const path = [];
  for (let i = 0; i < 32; i++) {
    path.push({
      sibling: { field: 0n },
      goes_left: false,
    });
  }
  return {
    leaf: { bytes: new Uint8Array(leafCommitment.bytes) },
    path,
  };
}

// ------------ Witnesses -------------------------------------------
let lastMintedCommitment = null; // captured by witnesses for path_of stub

const witnesses = {
  'private$zk_secret_key': (ctx) => [ctx.privateState, { bytes: new Uint8Array(FIXED_SK) }],
  'private$zk_public_key': (ctx) => [ctx.privateState, { bytes: new Uint8Array(FIXED_PK) }],
  'private$add_coin': (ctx, _coin) => [ctx.privateState, []],
  'private$remove_coin': (ctx, _coin) => [ctx.privateState, []],
  'context$new_coin_info': (ctx) => [ctx.privateState, fixedCoinInfo()],
  'context$path_of': (ctx, cm) => {
    // Provide a depth-32 path whose leaf is the requested commitment.
    return [ctx.privateState, makeMerklePathFor(cm)];
  },
  'context$encrypt': (ctx, _pk, _coin) => [ctx.privateState, new Uint8Array(FIXED_CIPHERTEXT)],
};

const contract = new Contract(witnesses);

const emptyCpk = { bytes: new Uint8Array(32) };
const constructorCtx = {
  initialPrivateState: null,
  initialZswapLocalState: cr.emptyZswapLocalState(emptyCpk),
};

// ---- Step 1: initialState -----------------------------------------
const initResult = contract.initialState(constructorCtx);
const afterInitContractState = initResult.currentContractState;
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString('hex');

// Build the running CircuitContext from the post-init ContractState,
// same shape as capture-tiny.mjs.
let circuitCtx = cr.createCircuitContext(
  cr.dummyContractAddress(),
  emptyCpk,
  afterInitContractState.data,
  initResult.currentPrivateState,
);

// Rewrap helper: carry over operations + authority + balance from a
// prior ContractState envelope.
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

const fixture = {
  afterInit: { stateHex: afterInitHex },
};

// ---- Step 2: zerocash_mint ----------------------------------------
let afterMintContractState = null;
try {
  const mintOut = contract.circuits.zerocash_mint(circuitCtx);
  circuitCtx = mintOut.context;
  afterMintContractState = rewrapEnvelope(
    afterInitContractState,
    chargedStateFromCtx(circuitCtx),
  );
  const afterMintHex = Buffer.from(afterMintContractState.serialize()).toString('hex');
  fixture.afterMint = { stateHex: afterMintHex };
} catch (e) {
  fixture.afterMint = { error: String(e && e.message || e) };
}

// ---- Step 3: spend ------------------------------------------------
// spend asserts that the path's root matches commitments.checkRoot.
// Our deterministic witness provides a stub path with all-zero siblings
// and goes_left=false. checkRoot succeeds only if the resulting root
// appears in the historic-merkle-tree's root set, which is normally
// only populated by genuine insertions. If this assert fails, capture
// only init+mint.
if (afterMintContractState) {
  try {
    // dest_public_key — deterministic
    const destPk = {
      zk: { bytes: new Uint8Array(32).fill(5) },
      encryption: new Uint8Array(32).fill(6),
    };
    // input_coin — deterministic; must be a coin whose commitment was
    // already inserted into the HMT (impossible without driving mint
    // with this exact coin first). Use fixedCoinInfo — same coin the
    // mint witness returned, so its commitment is in the tree.
    const inputCoin = fixedCoinInfo();
    const spendOut = contract.circuits.spend(circuitCtx, destPk, inputCoin);
    circuitCtx = spendOut.context;
    const afterSpendContractState = rewrapEnvelope(
      afterMintContractState,
      chargedStateFromCtx(circuitCtx),
    );
    const afterSpendHex = Buffer.from(afterSpendContractState.serialize()).toString('hex');
    fixture.afterSpend = { stateHex: afterSpendHex };
  } catch (e) {
    fixture.afterSpend = { error: String(e && e.message || e) };
  }
}

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
