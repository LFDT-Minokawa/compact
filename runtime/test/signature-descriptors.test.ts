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
import * as runtime from '../src/index.js';
import { SignatureType } from '../src/index.js';

const descriptorOf = runtime.descriptorOf;

/** A value encoded and decoded through one descriptor comes back equal. */
const roundTrips = (type: SignatureType, value: unknown): void => {
  const descriptor = descriptorOf(type);
  const encoded = descriptor.toValue(value);
  expect(encoded.length).toEqual(descriptor.alignment().length);
  expect(descriptor.fromValue([...encoded])).toEqual(value);
};

describe('descriptorOf: leaves', () => {
  test('a leaf tag resolves to the runtime descriptor of the same name', () => {
    const leaves: [SignatureType, runtime.CompactType<unknown>][] = [
      [{ tag: 'Boolean' }, runtime.CompactTypeBoolean],
      [{ tag: 'Field' }, runtime.CompactTypeField],
      [{ tag: 'JubjubScalar' }, runtime.CompactTypeJubjubScalar],
      [{ tag: 'JubjubPoint' }, runtime.CompactTypeJubjubPoint],
      [{ tag: 'Secp256k1Base' }, runtime.CompactTypeSecp256k1Base],
      [{ tag: 'Secp256k1Scalar' }, runtime.CompactTypeSecp256k1Scalar],
      [{ tag: 'Secp256k1Point' }, runtime.CompactTypeSecp256k1Point],
      [{ tag: 'Secp256r1Base' }, runtime.CompactTypeSecp256r1Base],
      [{ tag: 'Secp256r1Scalar' }, runtime.CompactTypeSecp256r1Scalar],
      [{ tag: 'Secp256r1Point' }, runtime.CompactTypeSecp256r1Point],
      [{ tag: 'Curve25519Base' }, runtime.CompactTypeCurve25519Base],
      [{ tag: 'Curve25519Scalar' }, runtime.CompactTypeCurve25519Scalar],
      [{ tag: 'Curve25519Point' }, runtime.CompactTypeCurve25519Point],
      [{ tag: 'Opaque', tsType: 'string' }, runtime.CompactTypeOpaqueString],
      [{ tag: 'Opaque', tsType: 'Uint8Array' }, runtime.CompactTypeOpaqueUint8Array],
    ];
    for (const [type, descriptor] of leaves) {
      expect(descriptorOf(type), type.tag).toBe(descriptor);
    }
  });

  test('an Opaque of a TypeScript type the compiler does not support is refused', () => {
    expect(() => descriptorOf({ tag: 'Opaque', tsType: 'Date' })).toThrow(/opaque type Date is not supported/);
  });

  test('Bytes carries its length', () => {
    const d = descriptorOf({ tag: 'Bytes', length: 5 }) as runtime.CompactTypeBytes;
    expect(d).toBeInstanceOf(runtime.CompactTypeBytes);
    expect(d.length).toEqual(5);
    roundTrips({ tag: 'Bytes', length: 5 }, new Uint8Array([1, 2, 3, 4, 5]));
  });
});

describe('descriptorOf: Uint widths', () => {
  // The compiler gives a Uint the bytes its maximum needs, and one when the maximum is zero:
  // `(max 1 (div (+ (integer-length n) 7) 8))` in print-typescript.ss.
  const widths: [string, number][] = [
    ['0', 1],
    ['1', 1],
    ['255', 1],
    ['256', 2],
    ['65535', 2],
    ['65536', 3],
    [(2n ** 64n - 1n).toString(), 8],
    [(2n ** 64n).toString(), 9],
    [(2n ** 128n - 1n).toString(), 16],
  ];
  for (const [maxval, length] of widths) {
    test(`Uint<..${maxval}> is ${length} byte(s)`, () => {
      const d = descriptorOf({ tag: 'Uint', maxval }) as runtime.CompactTypeUnsignedInteger;
      expect(d).toBeInstanceOf(runtime.CompactTypeUnsignedInteger);
      expect(d.maxValue).toEqual(BigInt(maxval));
      expect(d.length).toEqual(length);
      expect(d.alignment()).toEqual([{ tag: 'atom', value: { tag: 'bytes', length } }]);
    });
  }

  test('the maximum is exact past 2^53', () => {
    roundTrips({ tag: 'Uint', maxval: (2n ** 128n - 1n).toString() }, 2n ** 128n - 1n);
    expect(() => descriptorOf({ tag: 'Uint', maxval: '255' }).toValue(256n)).toThrow(/expected UnsignedInteger/);
  });
});

describe('descriptorOf: Enum', () => {
  test('the largest value is the element count less one, and the width follows it', () => {
    const three = descriptorOf({ tag: 'Enum', name: 'Color', elements: ['red', 'green', 'blue'] }) as runtime.CompactTypeEnum;
    expect(three).toBeInstanceOf(runtime.CompactTypeEnum);
    expect([three.maxValue, three.length]).toEqual([2, 1]);
    const one = descriptorOf({ tag: 'Enum', name: 'Unit', elements: ['only'] }) as runtime.CompactTypeEnum;
    expect([one.maxValue, one.length]).toEqual([0, 1]);
    const many = descriptorOf({
      tag: 'Enum',
      name: 'Big',
      elements: Array.from({ length: 257 }, (_, i) => `e${i}`),
    }) as runtime.CompactTypeEnum;
    expect([many.maxValue, many.length]).toEqual([256, 2]);
    roundTrips({ tag: 'Enum', name: 'Color', elements: ['red', 'green', 'blue'] }, 2);
  });
});

describe('descriptorOf: composites', () => {
  const inner: SignatureType = { tag: 'Struct', name: 'Inner', elements: [{ name: 'f', type: { tag: 'Field' } }] };
  const outer: SignatureType = {
    tag: 'Struct',
    name: 'Outer',
    elements: [
      { name: 'i', type: inner },
      { name: 'b', type: { tag: 'Boolean' } },
      { name: 'c', type: { tag: 'Enum', name: 'Color', elements: ['red', 'green', 'blue'] } },
      { name: 'v', type: { tag: 'Vector', length: 2, type: { tag: 'Uint', maxval: '255' } } },
    ],
  };

  test('a struct encodes its elements in declaration order and decodes them from one stream', () => {
    const d = descriptorOf(outer);
    expect(d).toBeInstanceOf(runtime.CompactTypeStruct);
    expect(d.alignment()).toEqual(
      [
        runtime.CompactTypeField.alignment(),
        runtime.CompactTypeBoolean.alignment(),
        new runtime.CompactTypeEnum(2, 1).alignment(),
        new runtime.CompactTypeVector(2, new runtime.CompactTypeUnsignedInteger(255n, 1)).alignment(),
      ].flat(),
    );
    roundTrips(outer, { i: { f: 7n }, b: true, c: 1, v: [3n, 4n] });
  });

  test('a tuple is positional', () => {
    const tuple: SignatureType = { tag: 'Tuple', types: [{ tag: 'Field' }, { tag: 'Boolean' }, inner] };
    expect(descriptorOf(tuple)).toBeInstanceOf(runtime.CompactTypeTuple);
    roundTrips(tuple, [1n, false, { f: 2n }]);
    expect(() => descriptorOf(tuple).toValue([1n, false])).toThrow(/expected 3-element tuple/);
  });

  test('a vector repeats its element type', () => {
    const d = descriptorOf({ tag: 'Vector', length: 3, type: inner });
    expect(d).toBeInstanceOf(runtime.CompactTypeVector);
    roundTrips({ tag: 'Vector', length: 3, type: inner }, [{ f: 1n }, { f: 2n }, { f: 3n }]);
  });

  test('the empty struct and the empty tuple encode to nothing', () => {
    expect(descriptorOf({ tag: 'Struct', name: 'Unit', elements: [] }).alignment()).toEqual([]);
    expect(descriptorOf({ tag: 'Tuple', types: [] }).toValue([])).toEqual([]);
    roundTrips({ tag: 'Tuple', types: [] }, []);
  });
});

describe('descriptorOf: aliases and contract references', () => {
  test('a nominal alias is the codec of the type it names', () => {
    const d = descriptorOf({ tag: 'Alias', name: 'Nominal', type: { tag: 'Bytes', length: 8 } });
    expect(d).toBeInstanceOf(runtime.CompactTypeBytes);
    expect(d.alignment()).toEqual(new runtime.CompactTypeBytes(8).alignment());
    roundTrips({ tag: 'Alias', name: 'Nominal', type: { tag: 'Bytes', length: 8 } }, new Uint8Array(8).fill(1));
  });

  test('a contract reference is its address', () => {
    const type: SignatureType = { tag: 'Contract', name: 'VoterRegistry', circuits: {} };
    expect(descriptorOf(type).alignment()).toEqual(new runtime.CompactTypeBytes(32).alignment());
    roundTrips(type, { bytes: new Uint8Array(32).fill(0xab) });
  });
});
