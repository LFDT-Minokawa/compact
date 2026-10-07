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
  copyCircuitContext,
  createCircuitContext,
  foldLocalState,
  LocalFoldOutcome,
  LocalFoldResult,
  LocalRecord,
  LocalTranscriptEntry,
  PartialProofData,
  pinLocalContainer,
  queryLocalState,
  stateValueDigest,
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
    localState: initialLocalState(),
  });

// a record of the given local transcript, whose other fields the fold does not read
const recordOf = (
  localTranscript: readonly LocalTranscriptEntry[],
  contractAddress: ocrt.ContractAddress = ocrt.dummyContractAddress(),
): LocalRecord => ({
  contractAddress,
  circuitId: 'test',
  input: { value: [], alignment: [] },
  basis: {
    callContext: new ocrt.QueryContext(new ocrt.ChargedState(ocrt.StateValue.newNull()), contractAddress).block,
    stateDigest: stateValueDigest(ocrt.StateValue.newNull()),
  },
  localTranscript,
  hostOutputs: [],
  calleeReturns: [],
  privateTranscriptOutputs: [],
});

const success: LocalFoldOutcome = { tag: 'success' };

// one record folded on its own
const foldOne = (
  prior: ocrt.StateValue,
  localTranscript: readonly LocalTranscriptEntry[],
  outcome: LocalFoldOutcome = success,
): LocalFoldResult => foldLocalState(prior, [{ record: recordOf(localTranscript), outcome }]);

// the state a fold reached; a divergence fails the test with what diverged
const foldedState = (result: LocalFoldResult): ocrt.StateValue => {
  if (result.tag === 'diverged') {
    throw new Error(`step ${result.stepIndex} diverged: ${JSON.stringify(result.divergence)}`);
  }
  return result.state;
};

// the local layout of `local credits: Counter;` holding n
const counterState = (n: number): ocrt.StateValue => ocrt.StateValue.newArray().arrayPush(ocrt.StateValue.newCell(u64(n)));
const counterOf = (sv: ocrt.StateValue): bigint => toBigint(sv.asArray()![0].asCell());

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
    const entry = pd.localTranscript![1];
    expect(entry.offset).toBe(1);
    expect(entry.tag).toBe('ops');
    const popeq = entry.tag === 'ops' ? entry.ops.find((op) => typeof op === 'object' && 'popeq' in op) : undefined;
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
    });
    expect(() => queryLocalState(ctx, emptyProofData(), increment(1))).toThrow(/local state/);
  });
});

describe('copyCircuitContext', () => {
  test("starts a call from the given context's current ledger state and leaves the given context alone", () => {
    const given = createCircuitContext({
      circuitId: 'test',
      contractAddress: ocrt.dummyContractAddress(),
      coinPublicKeyOrZswapState: COIN_PUBLIC_KEY,
      contractState: new ocrt.ContractState(),
    });
    const initial = given.callContext.initialQueryContext;
    // as an earlier call leaves it: the current state moved on from the initial one
    given.callContext.currentQueryContext = new ocrt.QueryContext(
      new ocrt.ChargedState(ocrt.StateValue.newArray().arrayPush(ocrt.StateValue.newNull())),
      ocrt.dummyContractAddress(),
    );
    const copy = copyCircuitContext(given);
    expect(copy.callContext.initialQueryContext).toBe(given.callContext.currentQueryContext);
    expect(given.callContext.initialQueryContext).toBe(initial);
  });
});

describe('stateValueDigest', () => {
  const b32 = (i: number): ocrt.AlignedValue => {
    const bytes = new Uint8Array(32);
    bytes[0] = i & 0xff;
    bytes[1] = (i >> 8) & 0xff;
    bytes[31] = 9;
    return { value: [bytes], alignment: [{ tag: 'atom', value: { tag: 'bytes', length: 32 } }] };
  };
  const mapOf = (entries: readonly (readonly [number, number])[]): ocrt.StateMap =>
    entries.reduce((map, [k, v]) => map.insert(b32(k), ocrt.StateValue.newCell(u64(v))), new ocrt.StateMap());
  const digestOf = (map: ocrt.StateMap): string => stateValueDigest(ocrt.StateValue.newMap(map));
  const range = (n: number): number[] => Array.from({ length: n }, (_, i) => i);
  const contents = range(200).map((i) => [i, i * 3] as const);

  test('depends on the contents alone, not on the history that built them', () => {
    const ascending = digestOf(mapOf(contents));
    expect(ascending).toMatch(/^[0-9a-f]{64}$/);
    expect(digestOf(mapOf([...contents].reverse()))).toBe(ascending);
    // an earlier value for key 7 overwritten, then 300 keys inserted and the last 100 removed again
    const overwritten = mapOf([[7, 99], ...range(300).map((i) => [i, i * 3] as const)]);
    const removed = range(100).reduce((map, i) => map.remove(b32(200 + i)), overwritten);
    expect(digestOf(removed)).toBe(ascending);
    // and an encode/decode round trip
    expect(stateValueDigest(ocrt.StateValue.decode(ocrt.StateValue.newMap(mapOf(contents)).encode()))).toBe(ascending);
  });

  test('tells apart one key, one value, one alignment, one entry more, and array order', () => {
    const base = digestOf(mapOf(contents));
    expect(digestOf(mapOf(contents.map(([k, v]) => [k === 199 ? 4321 : k, v] as const)))).not.toBe(base);
    expect(digestOf(mapOf(contents.map(([k, v]) => [k, k === 100 ? v + 1 : v] as const)))).not.toBe(base);
    expect(digestOf(mapOf([...contents, [200, 600]]))).not.toBe(base);
    // the same byte under two alignments
    expect(stateValueDigest(ocrt.StateValue.newCell(u8(1)))).not.toBe(stateValueDigest(ocrt.StateValue.newCell(u64(1))));
    const arrayOf = (...xs: number[]) =>
      xs.reduce((sv, x) => sv.arrayPush(ocrt.StateValue.newCell(u64(x))), ocrt.StateValue.newArray());
    expect(stateValueDigest(arrayOf(1, 2))).toBe(stateValueDigest(arrayOf(1, 2)));
    expect(stateValueDigest(arrayOf(1, 2))).not.toBe(stateValueDigest(arrayOf(2, 1)));
  });
});

describe('pinLocalContainer', () => {
  test('records the container as a digest, not a copy', () => {
    const ctx = context();
    const pd = emptyProofData();
    pinLocalContainer(ctx, pd, [0]);
    const pin = pd.localTranscript![0];
    expect(pin).toEqual({
      tag: 'observe',
      offset: 0,
      path: [0],
      digest: stateValueDigest(initialLocalState().asArray()![0]),
    });
  });

  test('a matching prior replays, a differing one is caught', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    pinLocalContainer(ctx, pd, [0]);
    const pin = pd.localTranscript![1];
    expect(pin.tag).toBe('observe');
    expect(pin.tag === 'observe' && pin.path).toEqual([0]);
    // matching prior: the same increment, then the pin replays
    expect(counterOf(foldedState(foldOne(initialLocalState(), pd.localTranscript!)))).toBe(5n);
    // differing prior: the increment replays blind, then the pin's value equality catches its result
    const mutated = counterState(1);
    const result = foldOne(mutated, pd.localTranscript!);
    expect(result).toMatchObject({
      tag: 'diverged',
      stepIndex: 0,
      divergence: { kind: 'ObservationMismatch', entryIndex: 1, path: [0] },
    });
    expect(result.tag === 'diverged' && result.prior).toBe(mutated);
  });
});

describe('foldLocalState', () => {
  const rehearse = () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    pd.publicTranscript.push('noop' as unknown as ocrt.Op<ocrt.AlignedValue>, 'ckpt' as unknown as ocrt.Op<ocrt.AlignedValue>);
    queryLocalState(ctx, pd, increment(7)); // fallible side: offset 2
    return pd.localTranscript!;
  };

  test('success applies every batch', () => {
    expect(counterOf(foldedState(foldOne(initialLocalState(), rehearse())))).toBe(12n);
  });

  test('partial success truncates at the checkpoint split', () => {
    // rehearse() records ['noop', 'ckpt'], so the landed guaranteed transcript has length 1
    const folded = foldedState(foldOne(initialLocalState(), rehearse(), { tag: 'partial', guaranteedLength: 1 }));
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
    const folded = foldedState(foldOne(initialLocalState(), pd.localTranscript!, { tag: 'partial', guaranteedLength: 1 }));
    expect(counterOf(folded)).toBe(7n);
  });

  test('a partial fold checks a container pin recorded before the checkpoint, and skips one recorded after it', () => {
    const ctx = context();
    const pd = emptyProofData();
    pd.publicTranscript.push('noop' as unknown as ocrt.Op<ocrt.AlignedValue>);
    pinLocalContainer(ctx, pd, [0]); // offset 1 === guaranteedLength: before the ckpt
    pd.publicTranscript.push('ckpt' as unknown as ocrt.Op<ocrt.AlignedValue>);
    pinLocalContainer(ctx, pd, [0]); // offset 2: after it
    queryLocalState(ctx, pd, increment(7));
    const [guaranteed, fallible, fallibleOp] = pd.localTranscript!;
    const partial = { tag: 'partial', guaranteedLength: 1 } as const;
    const differing = counterState(1);
    expect(foldOne(differing, [guaranteed, fallible, fallibleOp], partial)).toMatchObject({
      tag: 'diverged',
      divergence: { kind: 'ObservationMismatch', entryIndex: 0, path: [0] },
    });
    expect(counterOf(foldedState(foldOne(differing, [fallible, fallibleOp], partial)))).toBe(1n);
  });

  test('a container pin on a path the prior lacks diverges', () => {
    const ctx = context();
    const pd = emptyProofData();
    pinLocalContainer(ctx, pd, [0]);
    expect(foldOne(ocrt.StateValue.newArray(), pd.localTranscript!)).toMatchObject({
      tag: 'diverged',
      divergence: { kind: 'ObservationMismatch', entryIndex: 0, path: [0] },
    });
  });

  test('a mismatch on an observed read diverges, naming the entry and carrying the VM message', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    queryLocalState(ctx, pd, readCounter); // pins the observed value 5
    // a prior state the rehearsal never saw: the counter already holds 1
    const result = foldOne(counterState(1), pd.localTranscript!);
    expect(result).toMatchObject({ tag: 'diverged', stepIndex: 0, divergence: { kind: 'ReplayFailed', entryIndex: 1 } });
    const divergence = result.tag === 'diverged' ? result.divergence : undefined;
    expect(divergence?.kind === 'ReplayFailed' && divergence.message).toMatch(/mismatch between expected/);
  });

  test('blind ops replay on any prior state', () => {
    const ctx = context();
    const pd = emptyProofData();
    queryLocalState(ctx, pd, increment(5));
    expect(counterOf(foldedState(foldOne(counterState(1), pd.localTranscript!)))).toBe(6n);
  });

  test('no steps fold to the prior', () => {
    const prior = initialLocalState();
    const result = foldLocalState(prior, []);
    expect(result.tag === 'folded' && result.state).toBe(prior);
  });

  describe('over several steps', () => {
    // a call that adds 5 and reads the 5 it left, rehearsed on the initial state, then a call that
    // reads that 5 and adds 1, rehearsed on the state the first left
    const rehearseTwo = (): [LocalRecord, LocalRecord] => {
      const ctx = context();
      const first = emptyProofData();
      queryLocalState(ctx, first, increment(5));
      queryLocalState(ctx, first, readCounter);
      const second = emptyProofData();
      queryLocalState(ctx, second, readCounter);
      queryLocalState(ctx, second, increment(1));
      return [recordOf(first.localTranscript!), recordOf(second.localTranscript!)];
    };
    const steps = (...records: LocalRecord[]) => records.map((record) => ({ record, outcome: success }));

    test('each step replays against the state the steps before it reached', () => {
      const [first, second] = rehearseTwo();
      expect(counterOf(foldedState(foldLocalState(initialLocalState(), steps(first, second))))).toBe(6n);
      // the second on its own observed a 5 the initial state does not hold
      expect(foldLocalState(initialLocalState(), steps(second))).toMatchObject({
        tag: 'diverged',
        stepIndex: 0,
        divergence: { kind: 'ReplayFailed', entryIndex: 0 },
      });
    });

    test('a divergence names its step and carries the state the steps before it reached', () => {
      const [first, second] = rehearseTwo();
      // the first again reads 10 where it observed 5
      const result = foldLocalState(initialLocalState(), steps(first, first, second));
      expect(result).toMatchObject({ tag: 'diverged', stepIndex: 1, divergence: { kind: 'ReplayFailed', entryIndex: 1 } });
      expect(result.tag === 'diverged' && counterOf(result.prior)).toBe(5n);
    });

    test("a failed transaction's record folds nothing, not even a check", () => {
      const [first, second] = rehearseTwo();
      // the second would diverge on the initial state, but its transaction did not land
      const result = foldLocalState(initialLocalState(), [
        { record: second, outcome: { tag: 'failure' } },
        { record: first, outcome: success },
      ]);
      expect(counterOf(foldedState(result))).toBe(5n);
    });
  });

  describe('defects throw', () => {
    test('steps naming different contracts', () => {
      const record = recordOf([]);
      const other = recordOf([], ocrt.sampleContractAddress());
      expect(() =>
        foldLocalState(initialLocalState(), [
          { record, outcome: success },
          { record: other, outcome: success },
        ]),
      ).toThrow(/step 1 is a record of/);
    });

    test.each([-1, 1.5, NaN, Infinity])('a partial outcome with guaranteed length %s', (guaranteedLength) => {
      expect(() => foldOne(initialLocalState(), [], { tag: 'partial', guaranteedLength })).toThrow(
        /step 0: a partial outcome's guaranteed length is a transcript length/,
      );
    });

    test('an outcome of no known kind', () => {
      expect(() => foldOne(initialLocalState(), [], { tag: 'landed' } as unknown as LocalFoldOutcome)).toThrow(/not 'landed'/);
    });

    test('before any step folds, even one that would diverge first', () => {
      const ctx = context();
      const pd = emptyProofData();
      queryLocalState(ctx, pd, readCounter);
      const diverging = { record: recordOf(pd.localTranscript!), outcome: success };
      // the read observed 0, so step 0 diverges on a counter holding 1; step 1 is malformed
      expect(() =>
        foldLocalState(counterState(1), [diverging, { record: recordOf([]), outcome: { tag: 'partial', guaranteedLength: -1 } }]),
      ).toThrow(/step 1/);
    });
  });
});
