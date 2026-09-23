// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
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

import { describe, expect, test } from 'vitest';
import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import {
  CircuitContext,
  createCircuitContext,
  foldLocalTranscript,
  PartialProofData,
  queryLocalState,
} from '../src/index.js';

const COIN_PUBLIC_KEY = '0'.repeat(64);

// FAB atoms are little-endian and minimal-length, so zero is the empty byte string.
const minBytes = (n: bigint): Uint8Array => {
  const bytes: number[] = [];
  for (let v = n; v > 0n; v >>= 8n) bytes.push(Number(v & 0xffn));
  return new Uint8Array(bytes);
};
const atom = (n: bigint, length: number): ocrt.AlignedValue => ({
  value: [minBytes(n)],
  alignment: [{ tag: 'atom', value: { tag: 'bytes', length } }],
});
const u8 = (n: number) => atom(BigInt(n), 1);
const u64 = (n: number) => atom(BigInt(n), 8);
const key = (av: ocrt.AlignedValue): ocrt.Key => ({ tag: 'value', value: av });
const toBigint = (av: ocrt.AlignedValue): bigint => {
  let v = 0n;
  const b = av.value[0];
  for (let i = b.length - 1; i >= 0; i--) v = (v << 8n) | BigInt(b[i]);
  return v;
};

// the local layout of `local credits: Counter;`: Array[Cell(u64 0)]
const initialLocalState = (): ocrt.StateValue => {
  let sv = ocrt.StateValue.newArray();
  sv = sv.arrayPush(ocrt.StateValue.newCell(u64(0)));
  return sv;
};

// `Counter.increment(n)` and `Counter.read` at path [0], as `midnight-ledger.ss` expands them
const increment = (n: number): ocrt.Op<null>[] => [
  { idx: { cached: false, pushPath: true, path: [key(u8(0))] } },
  { addi: { immediate: n } },
  { ins: { cached: true, n: 1 } },
];
const readCounter: ocrt.Op<null>[] = [
  { dup: { n: 0 } },
  { idx: { cached: false, pushPath: false, path: [key(u8(0))] } },
  { popeq: { cached: true, result: null } },
];

const emptyProofData = (): PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
});

const context = (): CircuitContext =>
  createCircuitContext({
    circuitId: 'test',
    contractAddress: ocrt.dummyContractAddress(),
    coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
    contractState: new ocrt.ContractState(),
    privateState: undefined,
    localState: initialLocalState(),
  });

describe('queryLocalState', () => {
  test('runs ops against local state and returns reads', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    const read = queryLocalState(ctx, pd, readCounter);
    expect(read).toBeDefined();
    expect(toBigint(read!)).toBe(5n);
  });

  test('records offset-tagged batches with popeq results filled, touching neither public transcript nor private inputs', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    // a public op lands between the two local batches
    pd.publicTranscript.push('noop' as unknown as ocrt.Op<ocrt.AlignedValue>);
    const read = queryLocalState(ctx, pd, readCounter);
    expect(pd.localTranscript).toHaveLength(2);
    expect(pd.localTranscript![0].offset).toBe(0);
    expect(pd.localTranscript![1].offset).toBe(1);
    const popeq = pd.localTranscript![1].ops.find((op) => typeof op === 'object' && 'popeq' in op);
    expect(popeq).toBeDefined();
    expect((popeq as { popeq: { result: ocrt.AlignedValue } }).popeq.result).toEqual(read);
    expect(pd.publicTranscript).toHaveLength(1);
    expect(pd.privateTranscriptOutputs).toHaveLength(0);
  });

  test('throws when no local state was supplied', () => {
    const ctx = createCircuitContext({
      circuitId: 'test',
      contractAddress: ocrt.dummyContractAddress(),
      coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
      contractState: new ocrt.ContractState(),
      privateState: undefined,
    });
    expect(() => queryLocalState(ctx, emptyProofData(), increment(1))).toThrow(/local state/);
  });
});

describe('foldLocalTranscript', () => {
  const rehearse = () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    pd.publicTranscript.push('noop' as unknown as ocrt.Op<ocrt.AlignedValue>, 'ckpt' as unknown as ocrt.Op<ocrt.AlignedValue>);
    queryLocalState(ctx, pd, increment(7)); // fallible side: offset 2
    return pd.localTranscript!;
  };
  const counterOf = (sv: ocrt.StateValue): bigint => toBigint(sv.asArray()![0].asCell());

  test('success applies every batch', () => {
    const folded = foldLocalTranscript(initialLocalState(), rehearse(), { tag: 'success' });
    expect(counterOf(folded)).toBe(12n);
  });

  test('partial success truncates at the checkpoint split', () => {
    // rehearse() records ['noop', 'ckpt'], so the landed guaranteed transcript has length 1
    const folded = foldLocalTranscript(initialLocalState(), rehearse(), { tag: 'partial', guaranteedLength: 1 });
    expect(counterOf(folded)).toBe(5n);
  });

  test('an op recorded just before the checkpoint is guaranteed', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    pd.publicTranscript.push('noop' as unknown as ocrt.Op<ocrt.AlignedValue>);
    queryLocalState(ctx, pd, increment(2)); // offset 1 === guaranteedLength: before the ckpt
    pd.publicTranscript.push('ckpt' as unknown as ocrt.Op<ocrt.AlignedValue>);
    queryLocalState(ctx, pd, increment(7)); // offset 2: after the ckpt, rolled back
    const folded = foldLocalTranscript(initialLocalState(), pd.localTranscript!, { tag: 'partial', guaranteedLength: 1 });
    expect(counterOf(folded)).toBe(7n);
  });

  test('a mismatch on an observed read reports divergence', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    queryLocalState(ctx, pd, readCounter); // pins the observed value 5
    // a prior state the rehearsal never saw: the counter already holds 1
    let mutated = ocrt.StateValue.newArray();
    mutated = mutated.arrayPush(ocrt.StateValue.newCell(u64(1)));
    expect(() => foldLocalTranscript(mutated, pd.localTranscript!, { tag: 'success' })).toThrow(/re-executed/);
  });

  test('blind ops replay on any prior state', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    let mutated = ocrt.StateValue.newArray();
    mutated = mutated.arrayPush(ocrt.StateValue.newCell(u64(1)));
    const folded = foldLocalTranscript(mutated, pd.localTranscript!, { tag: 'success' });
    expect(counterOf(folded)).toBe(6n);
  });
});
