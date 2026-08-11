// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// Shielded coin operations across a cross-contract call tree (LFDT-Minokawa/compact#658).
//
// A contract that is sent a shielded coin only takes custody of it if it claims the receive in
// the same transaction, so a callee must be able to run `receiveShielded` — which means having a
// Zswap local state of its own. These tests pin the state's shape: one per contract, keyed by
// address like `queryContexts` and `gasCosts`, threaded across a call so a callee's coins survive
// its return, and mirrored onto `callProofDataTrace` so transaction assembly can attribute every
// input and output to the contract that made it.

import { describe, expect, test } from 'vitest';
import * as compactRuntime from '../src/index.js';
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';

const COIN_PUBLIC_KEY = '0'.repeat(64);

const sampleCoinInfo = (value: bigint) =>
  ocrt.encodeShieldedCoinInfo({
    type: ocrt.sampleRawTokenType(),
    nonce: '2ab78b2272ec3489da60e6af54a87bfa53a7fa727602a040df782ebae7f5ab59',
    value,
  });

const contractRecipient = (address: ocrt.ContractAddress) => ({
  is_left: false,
  left: { bytes: new Uint8Array(32) },
  right: { bytes: ocrt.encodeContractAddress(address) },
});

const makeContext = (address: ocrt.ContractAddress) =>
  compactRuntime.createCircuitContext({
    circuitId: 'test',
    contractAddress: address,
    coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
    contractState: new ocrt.ContractState(),
    privateState: undefined,
  });

describe('per-contract Zswap local state', () => {
  test('createCircuitContext keys the entry contract into zswapLocalStates', () => {
    const address = ocrt.sampleContractAddress();
    const context = makeContext(address);

    expect(Object.keys(context.zswapLocalStates)).toEqual([address]);
    // The map cell and the live call context must be the same object, or a write through one
    // route would be invisible from the other.
    expect(context.zswapLocalStates[address]).toBe(context.callContext.currentZswapLocalState);
  });

  test('createZswapOutput writes through to the per-address map', () => {
    const address = ocrt.sampleContractAddress();
    const context = makeContext(address);

    compactRuntime.createZswapOutput(context, sampleCoinInfo(100n), contractRecipient(address));

    expect(context.zswapLocalStates[address]).toBe(context.callContext.currentZswapLocalState);
    expect(context.zswapLocalStates[address]!.outputs.length).toBe(1);
    expect(context.zswapLocalStates[address]!.currentIndex).toBe(1n);
  });

  test('createZswapInput writes through to the per-address map', () => {
    const address = ocrt.sampleContractAddress();
    const context = makeContext(address);

    compactRuntime.createZswapInput(context, {
      ...sampleCoinInfo(100n),
      mt_index: 0n,
    });

    expect(context.zswapLocalStates[address]).toBe(context.callContext.currentZswapLocalState);
    expect(context.zswapLocalStates[address]!.inputs.length).toBe(1);
  });

  test('copyCircuitContext copies the map without aliasing it', () => {
    const address = ocrt.sampleContractAddress();
    const context = makeContext(address);
    const copy = compactRuntime.copyCircuitContext(context);

    expect(copy.zswapLocalStates).not.toBe(context.zswapLocalStates);
    expect(copy.zswapLocalStates[address]).toBe(context.zswapLocalStates[address]);

    // A coin created on the copy must not leak back into the original's map.
    compactRuntime.createZswapOutput(copy, sampleCoinInfo(100n), contractRecipient(address));
    expect(copy.zswapLocalStates[address]!.outputs.length).toBe(1);
    expect(context.zswapLocalStates[address]!.outputs.length).toBe(0);
  });

  test('finalizeCallProofData records the state on the trace entry', () => {
    const address = ocrt.sampleContractAddress();
    const context = makeContext(address);
    compactRuntime.createZswapOutput(context, sampleCoinInfo(100n), contractRecipient(address));

    compactRuntime.finalizeCallProofData(context, {
      input: { value: [], alignment: [] },
      output: { value: [], alignment: [] },
      publicTranscript: [],
      privateTranscriptOutputs: [],
    });

    expect(context.callProofDataTrace.length).toBe(1);
    const entry = context.callProofDataTrace[0]!;
    expect(entry.contractAddress).toBe(address);
    // Transaction assembly reads the coins off this entry, so it has to carry the state the call
    // actually finished with rather than the one it started from.
    expect(entry.zswapLocalState.outputs.length).toBe(1);
    expect(entry.zswapLocalState).toBe(context.callContext.currentZswapLocalState);
  });
});

describe('ownPublicKey', () => {
  test('is readable by the entry contract', () => {
    const context = makeContext(ocrt.sampleContractAddress());
    expect(compactRuntime.ownPublicKey(context).bytes).toEqual(ocrt.encodeCoinPublicKey(COIN_PUBLIC_KEY));
  });

  test('reads the submitter key from whichever contract is executing', () => {
    // All three Zswap natives — ownPublicKey, createZswapInput, createZswapOutput — are declared
    // `witness` in midnight-natives.ss, but none of them touch persistent private state, so the
    // CoIP-2 rule that keeps user-declared witnesses out of callees does not reach them. A callee
    // gets its own state seeded with the submitter's coin public key, which is what lets it pay
    // the submitter back (change, refunds, swap proceeds).
    //
    // Gating the read would not have bought confidentiality either: a coin public key is an
    // ordinary circuit parameter type — `sendShielded` and `mintShieldedToken` both take
    // `Either<ZswapCoinPublicKey, ContractAddress>` — so a caller can simply pass the value in.
    const callee = makeContext(ocrt.sampleContractAddress());
    expect(compactRuntime.ownPublicKey(callee).bytes).toEqual(ocrt.encodeCoinPublicKey(COIN_PUBLIC_KEY));
  });

  test('is refused only when there is no Zswap local state at all', () => {
    const context = makeContext(ocrt.sampleContractAddress());
    context.callContext.currentZswapLocalState = undefined;

    expect(() => compactRuntime.ownPublicKey(context)).toThrow(compactRuntime.CompactError);
  });
});
