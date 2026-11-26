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

import { beforeEach, describe, expect, test, vi } from 'vitest';
import * as compactRuntime from '../src/index.js';

// These tests use placeholder proofs, so the inner-proof check is stubbed out. Real proofs are
// checked only by Midnight's separate end-to-end test repository for now; tests here with real
// proofs are to follow.
const checkInnerProof = vi.hoisted(() => vi.fn());
vi.mock('@midnightntwrk/zkir-v3', () => ({ checkInnerProof }));
beforeEach(() => {
  checkInnerProof.mockReset();
});

const emptyProofData = (): compactRuntime.PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
  innerProofs: [],
});

const VK = '0x01ff';
const field = (x: bigint): compactRuntime.Value => compactRuntime.CompactTypeField.toValue(x);
const ENCODING = Array.from({ length: compactRuntime.ACCUMULATOR_PUBLIC_INPUTS }, (_, i) => BigInt(i + 1));

describe('prepareVerification', () => {
  test('records each inner proof, in order', async () => {
    const proofData = emptyProofData();
    const p = new Uint8Array([1, 2, 3]);
    const q = new Uint8Array([4, 5]);
    await compactRuntime.prepareVerification(proofData, VK, [field(1n)], p);
    await compactRuntime.prepareVerification(proofData, VK, [field(2n), field(3n)], q);
    expect(proofData.innerProofs).toEqual([p, q]);
  });

  test('records a copy of the proof', async () => {
    const proofData = emptyProofData();
    const p = new Uint8Array([1, 2, 3]);
    await compactRuntime.prepareVerification(proofData, VK, [field(1n)], p);
    p[0] = 9;
    // a Buffer's slice() would share its memory
    const b = Buffer.from([4, 5, 6]);
    await compactRuntime.prepareVerification(proofData, VK, [field(1n)], b);
    b[0] = 9;
    expect(proofData.innerProofs).toEqual([new Uint8Array([1, 2, 3]), new Uint8Array([4, 5, 6])]);
  });

  test('rejects a proof that is not a Uint8Array', async () => {
    await expect(compactRuntime.prepareVerification(emptyProofData(), VK, [], 'proof' as unknown as Uint8Array)).rejects.toThrow(
      compactRuntime.CompactError,
    );
  });
});

describe('the call-time check', () => {
  test('receives the key, the instance the public inputs encode, and the proof', async () => {
    const p = new Uint8Array([1, 2, 3]);
    await compactRuntime.prepareVerification(emptyProofData(), VK, [field(2n), field(3n)], p);
    const carried = compactRuntime.Accumulator.fromPublicInputs(ENCODING);
    await compactRuntime.prepareVerification(emptyProofData(), VK, [field(1n), carried], p);
    // the key may arrive as a Buffer, a Uint8Array subclass
    expect(checkInnerProof.mock.calls.map(([vk, ...rest]) => [new Uint8Array(vk), ...rest])).toEqual([
      [new Uint8Array([1, 255]), [2n, 3n], p],
      [new Uint8Array([1, 255]), [1n, ...ENCODING], p],
    ]);
  });

  test('is skipped when a computed accumulator is among the public inputs', async () => {
    const proofData = emptyProofData();
    const a = await compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([1]));
    checkInnerProof.mockClear();
    const p = new Uint8Array([2]);
    await compactRuntime.prepareVerification(proofData, VK, [field(1n), a], p);
    expect(checkInnerProof).not.toHaveBeenCalled();
    expect(proofData.innerProofs).toEqual([new Uint8Array([1]), p]);
  });

  test('wraps a refusal in a CompactError and records nothing', async () => {
    checkInnerProof.mockImplementation(() => {
      throw new Error('inner proof does not hold');
    });
    const proofData = emptyProofData();
    const call = compactRuntime.prepareVerification(proofData, VK, [field(1n)], new Uint8Array([1]));
    await expect(call).rejects.toThrow(compactRuntime.CompactError);
    await expect(call).rejects.toThrow('the public inputs are wrong, the key is for another circuit, or the proof is false');
    expect(proofData.innerProofs).toEqual([]);
  });
});

describe('accumulate and verifyAccumulator', () => {
  test('accept the accumulators prepareVerification returns', async () => {
    const proofData = emptyProofData();
    const a = await compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([1]));
    const b = await compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([2]));
    const c = await compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([3]));
    expect(compactRuntime.verifyAccumulator(compactRuntime.accumulate(compactRuntime.accumulate(a, b), c))).toEqual([]);
  });

  test('reject anything else', async () => {
    const a = await compactRuntime.prepareVerification(emptyProofData(), VK, [], new Uint8Array([1]));
    const forged = { publicInputs: undefined } as unknown as compactRuntime.Accumulator;
    expect(() => compactRuntime.accumulate(a, forged)).toThrow(compactRuntime.CompactError);
    expect(() => compactRuntime.verifyAccumulator(forged)).toThrow(compactRuntime.CompactError);
  });
});

describe('carried accumulators', () => {
  test('prepareVerification accepts one among the public inputs and records the proof', async () => {
    const proofData = emptyProofData();
    const p = new Uint8Array([1]);
    const carried = compactRuntime.Accumulator.fromPublicInputs(ENCODING);
    compactRuntime.verifyAccumulator(await compactRuntime.prepareVerification(proofData, VK, [field(1n), carried], p));
    expect(proofData.innerProofs).toEqual([p]);
  });

  test('fromPublicInputs keeps the encoding and rejects a wrong one', () => {
    expect(compactRuntime.Accumulator.fromPublicInputs(ENCODING).publicInputs).toEqual(ENCODING);
    expect(() => compactRuntime.Accumulator.fromPublicInputs(ENCODING.slice(1))).toThrow(compactRuntime.CompactError);
    expect(() => compactRuntime.Accumulator.fromPublicInputs([...ENCODING.slice(1), -1n])).toThrow(compactRuntime.CompactError);
    expect(() => compactRuntime.Accumulator.fromPublicInputs([...ENCODING.slice(1), compactRuntime.MAX_FIELD + 1n])).toThrow(
      compactRuntime.CompactError,
    );
  });

  test('CompactTypeAccumulator round-trips a supplied accumulator', () => {
    const rt = compactRuntime.CompactTypeAccumulator;
    expect(rt.alignment()).toHaveLength(compactRuntime.ACCUMULATOR_PUBLIC_INPUTS);
    const value = rt.toValue(compactRuntime.Accumulator.fromPublicInputs(ENCODING));
    expect(rt.fromValue(value).publicInputs).toEqual(ENCODING);
    expect(value).toHaveLength(0);
  });

  test('CompactTypeAccumulator has no value for a computed accumulator', async () => {
    const a = await compactRuntime.prepareVerification(emptyProofData(), VK, [], new Uint8Array([1]));
    expect(() => compactRuntime.CompactTypeAccumulator.toValue(a)).toThrow(compactRuntime.CompactError);
  });
});
