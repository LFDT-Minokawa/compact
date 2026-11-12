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

import { describe, expect, test } from 'vitest';
import * as compactRuntime from '../src/index.js';

const emptyProofData = (): compactRuntime.PartialProofData => ({
  input: { value: [], alignment: [] },
  publicTranscript: [],
  privateTranscriptOutputs: [],
  innerProofs: [],
});

const VK = '0x00';

describe('prepareVerification', () => {
  test('records each inner proof, in order', () => {
    const proofData = emptyProofData();
    const p = new Uint8Array([1, 2, 3]);
    const q = new Uint8Array([4, 5]);
    compactRuntime.prepareVerification(proofData, VK, [1n], p);
    compactRuntime.prepareVerification(proofData, VK, [2n, 3n], q);
    expect(proofData.innerProofs).toEqual([p, q]);
  });

  test('rejects a proof that is not a Uint8Array', () => {
    expect(() =>
      compactRuntime.prepareVerification(emptyProofData(), VK, [], 'proof' as unknown as Uint8Array),
    ).toThrow(compactRuntime.CompactError);
  });
});

describe('accumulate and verifyAccumulator', () => {
  test('accept the accumulators prepareVerification returns', () => {
    const proofData = emptyProofData();
    const a = compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([1]));
    const b = compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([2]));
    const c = compactRuntime.prepareVerification(proofData, VK, [], new Uint8Array([3]));
    expect(compactRuntime.verifyAccumulator(compactRuntime.accumulate(compactRuntime.accumulate(a, b), c))).toEqual([]);
  });

  test('reject anything else', () => {
    const a = compactRuntime.prepareVerification(emptyProofData(), VK, [], new Uint8Array([1]));
    const forged = { publicInputs: undefined } as unknown as compactRuntime.Accumulator;
    expect(() => compactRuntime.accumulate(a, forged)).toThrow(compactRuntime.CompactError);
    expect(() => compactRuntime.verifyAccumulator(forged)).toThrow(compactRuntime.CompactError);
  });
});

const ENCODING = Array.from({ length: compactRuntime.ACCUMULATOR_PUBLIC_INPUTS }, (_, i) => BigInt(i + 1));

describe('carried accumulators', () => {
  test('prepareVerification accepts one among the public inputs and records the proof', () => {
    const proofData = emptyProofData();
    const p = new Uint8Array([1]);
    const carried = compactRuntime.Accumulator.fromPublicInputs(ENCODING);
    compactRuntime.verifyAccumulator(compactRuntime.prepareVerification(proofData, VK, [1n, carried], p));
    expect(proofData.innerProofs).toEqual([p]);
  });

  test('fromPublicInputs keeps the encoding and rejects a wrong one', () => {
    expect(compactRuntime.Accumulator.fromPublicInputs(ENCODING).publicInputs).toEqual(ENCODING);
    expect(() => compactRuntime.Accumulator.fromPublicInputs(ENCODING.slice(1))).toThrow(compactRuntime.CompactError);
    expect(() => compactRuntime.Accumulator.fromPublicInputs([...ENCODING.slice(1), -1n])).toThrow(compactRuntime.CompactError);
    expect(() =>
      compactRuntime.Accumulator.fromPublicInputs([...ENCODING.slice(1), compactRuntime.MAX_FIELD + 1n]),
    ).toThrow(compactRuntime.CompactError);
  });

  test('CompactTypeAccumulator round-trips a supplied accumulator', () => {
    const rt = compactRuntime.CompactTypeAccumulator;
    expect(rt.alignment()).toHaveLength(compactRuntime.ACCUMULATOR_PUBLIC_INPUTS);
    const value = rt.toValue(compactRuntime.Accumulator.fromPublicInputs(ENCODING));
    expect(rt.fromValue(value).publicInputs).toEqual(ENCODING);
    expect(value).toHaveLength(0);
  });

  test('CompactTypeAccumulator has no value for a computed accumulator', () => {
    const a = compactRuntime.prepareVerification(emptyProofData(), VK, [], new Uint8Array([1]));
    expect(() => compactRuntime.CompactTypeAccumulator.toValue(a)).toThrow(compactRuntime.CompactError);
  });
});
