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
// To make spend succeed, we use a real MerklePath harness:
//   - private$zk_public_key returns persistentHash(FIXED_SK) (same as
//     derive_zk_public_key(FIXED_SK)) so mint and spend insert/look up
//     the same commitment.
//   - context$path_of pulls the on-chain BoundedMerkleTree directly out
//     of the ChargedState and computes pathForLeaf(idx, leafHash(cm))
//     using a small driver-side mirror that remembers which index each
//     commitment was inserted at.
//   - The decoded MerklePath bytes for the spend's old_commitment are
//     also emitted to the JSON fixture under `pathOfBytes` so the Rust
//     test can replay the same path byte-identically.
//
// Usage:
//   compactc --skip-zk examples/zerocash.compact /tmp/zc-ts/
//   echo '{"type":"module"}' > /tmp/zc-ts/contract/package.json
//   ln -sfn $PWD/node_modules /tmp/zc-ts/contract/node_modules
//   node tests-e2e-rust/fixtures/capture-zerocash.mjs \
//     > tests-e2e-rust/fixtures/zerocash-ts-state.json

import { Contract, ledger } from '/tmp/zc-ts/contract/index.js';
import * as cr from '@midnight-ntwrk/compact-runtime';
import { leafHash, persistentHash, valueToBigInt } from '@midnight-ntwrk/onchain-runtime-v3';

// ------------ Fixed deterministic witness payloads -----------------
const FIXED_SK = new Uint8Array(32).fill(1);
const FIXED_NONCE = new Uint8Array(32).fill(3);
const FIXED_OPENING = new Uint8Array(32).fill(4);
const FIXED_CIPHERTEXT = new Uint8Array([10, 11, 12]);

// Derive the public key as `persistentHash<Bytes<32>>(FIXED_SK)`.
// zerocash.compact's `commitment_from_coin_info` and the in-circuit
// `derive_zk_public_key(source_sk)` both feed this exact value into
// the commitment hash, so making `private$zk_public_key` return it
// keeps mint and spend coherent: they hash the same commitment.
function derivedPk() {
  return persistentHash(
    [{ tag: 'atom', value: { tag: 'bytes', length: 32 } }],
    [FIXED_SK],
  )[0];
}
const FIXED_PK = derivedPk();

function fixedCoinInfo() {
  return {
    nonce: { bytes: new Uint8Array(FIXED_NONCE) },
    opening: { bytes: new Uint8Array(FIXED_OPENING) },
  };
}

// Decode the AlignedValue returned by StateBoundedMerkleTree.pathForLeaf
// into the witness's MerkleTreePath shape. AlignedValue layout for a
// depth-N path is:
//   value[0]                    = Uint8Array(32)   leaf bytes
//   value[1 + 2*i] (i=0..N-1)   = field-bytes      sibling.field
//   value[2 + 2*i] (i=0..N-1)   = Uint8Array(1)    goes_left (0|1)
// The field bytes are big-endian and may be variable-length (the value
// is in normal form — no trailing zeros), so we use valueToBigInt to
// decode them correctly.
function decodeMerklePath(av, depth) {
  const v = av.value;
  const path = [];
  for (let i = 0; i < depth; i++) {
    const fieldBig = valueToBigInt([v[1 + 2 * i]]);
    const gl = v[2 + 2 * i];
    const goesLeft = gl.length > 0 && gl[0] !== 0;
    path.push({ sibling: { field: fieldBig }, goes_left: goesLeft });
  }
  return { leaf: { bytes: new Uint8Array(v[0]) }, path };
}

// Driver-side mirror: hex(commitment) → insertion index. Each
// `commitments.insert(cm)` call in the source contract increments
// `nextIdx`; the witness uses the recorded index to ask the on-chain
// tree for the *exact* path that satisfies checkRoot.
const cmIndex = new Map();
let nextIdx = 0n;

// Shared mutable holder so witnesses can pull the latest raw state
// value (the closure outer ChargedState) into the path lookup.
const sharedState = { rawStateValue: null };

// Captured to drop into the JSON fixture so the Rust test can replay
// the path byte-identically without re-implementing the harness.
let capturedSpendPath = null;

const witnesses = {
  'private$zk_secret_key': (ctx) => [
    ctx.privateState,
    { bytes: new Uint8Array(FIXED_SK) },
  ],
  'private$zk_public_key': (ctx) => [
    ctx.privateState,
    { bytes: new Uint8Array(FIXED_PK) },
  ],
  'private$add_coin': (ctx, _coin) => [ctx.privateState, []],
  'private$remove_coin': (ctx, _coin) => [ctx.privateState, []],
  'context$new_coin_info': (ctx) => [ctx.privateState, fixedCoinInfo()],
  'context$path_of': (ctx, cm) => {
    // Pull the on-chain BoundedMerkleTree out of the ChargedState.
    // commitments lives at ledger-array index 1 (array of
    // [BoundedMerkleTree, counter, rootMap]); we want position 0.
    const stateValue = sharedState.rawStateValue;
    if (!stateValue) {
      const stub = Array.from({ length: 32 }, () => ({
        sibling: { field: 0n },
        goes_left: false,
      }));
      return [ctx.privateState, { leaf: cm, path: stub }];
    }
    const tree = stateValue
      .asArray()[1]
      .asArray()[0]
      .asBoundedMerkleTree()
      .rehash();
    const cmHex = Buffer.from(cm.bytes).toString('hex');
    const idx = cmIndex.get(cmHex);
    if (idx === undefined) {
      // Commitment not in our mirror — return stub; spend will fail
      // and the multi-step driver captures the error.
      const stub = Array.from({ length: 32 }, () => ({
        sibling: { field: 0n },
        goes_left: false,
      }));
      return [ctx.privateState, { leaf: cm, path: stub }];
    }
    const cmAv = leafHash({
      value: [cm.bytes],
      alignment: [{ tag: 'atom', value: { tag: 'bytes', length: 32 } }],
    });
    const pathAv = tree.pathForLeaf(idx, cmAv);
    const decoded = decodeMerklePath(pathAv, 32);
    // The witness type is MerkleTreePath<32, commitment>, so the
    // leaf is the *unhashed* commitment struct.
    decoded.leaf = { bytes: new Uint8Array(cm.bytes) };
    capturedSpendPath = decoded;
    return [ctx.privateState, decoded];
  },
  'context$encrypt': (ctx, _pk, _coin) => [
    ctx.privateState,
    new Uint8Array(FIXED_CIPHERTEXT),
  ],
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
const afterInitHex = Buffer.from(afterInitContractState.serialize()).toString(
  'hex',
);

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

const fixture = {
  afterInit: { stateHex: afterInitHex },
};

// ---- Predict the cm that mint will insert, so the witness can
// produce a real path during spend. --------------------------------
const vecType = new cr.CompactTypeVector(4, new cr.CompactTypeBytes(32));
const DOMAIN = new Uint8Array([
  108, 97, 114, 101, 115, 58, 122, 101, 114, 111, 99, 97, 115, 104, 58, 99, 111,
  109, 109, 105, 116, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
]);
const mintCm = persistentHash(
  vecType.alignment(),
  vecType.toValue([DOMAIN, FIXED_NONCE, FIXED_OPENING, FIXED_PK]),
)[0];
cmIndex.set(Buffer.from(mintCm).toString('hex'), nextIdx++);

// ---- Step 2: zerocash_mint ----------------------------------------
let afterMintContractState = null;
try {
  const mintOut = contract.circuits.zerocash_mint(circuitCtx);
  circuitCtx = mintOut.context;
  afterMintContractState = rewrapEnvelope(
    afterInitContractState,
    chargedStateFromCtx(circuitCtx),
  );
  const afterMintHex = Buffer.from(afterMintContractState.serialize()).toString(
    'hex',
  );
  fixture.afterMint = { stateHex: afterMintHex };
} catch (e) {
  fixture.afterMint = { error: String((e && e.message) || e) };
}

// ---- Step 3: spend ------------------------------------------------
if (afterMintContractState) {
  try {
    sharedState.rawStateValue = circuitCtx.currentQueryContext.state.state;
    const destPk = {
      zk: { bytes: new Uint8Array(32).fill(5) },
      encryption: new Uint8Array(32).fill(6),
    };
    const inputCoin = fixedCoinInfo();
    const spendOut = contract.circuits.spend(circuitCtx, destPk, inputCoin);
    circuitCtx = spendOut.context;
    const afterSpendContractState = rewrapEnvelope(
      afterMintContractState,
      chargedStateFromCtx(circuitCtx),
    );
    const afterSpendHex = Buffer.from(
      afterSpendContractState.serialize(),
    ).toString('hex');
    fixture.afterSpend = { stateHex: afterSpendHex };
    if (capturedSpendPath) {
      // Serialise the captured MerklePath into a compact JSON
      // structure the Rust test can read directly:
      //   leafHex                  — 32-byte commitment.bytes
      //   path: [{ siblingHex, goesLeft }, ...]   (32 entries)
      // We dump siblings as big-endian 32-byte hex so the Rust side
      // can rebuild Field elements without bigint plumbing.
      const path = capturedSpendPath.path.map((e) => {
        let n = e.sibling.field;
        const buf = new Uint8Array(32);
        for (let i = 31; i >= 0; i--) {
          buf[i] = Number(n & 0xffn);
          n >>= 8n;
        }
        return {
          siblingHex: Buffer.from(buf).toString('hex'),
          goesLeft: e.goes_left,
        };
      });
      fixture.spendPath = {
        leafHex: Buffer.from(capturedSpendPath.leaf.bytes).toString('hex'),
        path,
      };
    }
  } catch (e) {
    fixture.afterSpend = { error: String((e && e.message) || e) };
  }
}

process.stdout.write(JSON.stringify(fixture, null, 2) + '\n');
