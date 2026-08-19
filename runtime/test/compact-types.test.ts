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

// Conformance tests for the `CompactType` protocol.
//
// The tuple and struct descriptors emitted by print-typescript.ss hand one
// shared array to every element's `fromValue` in turn and do no offset
// arithmetic, therefore a descriptor that does not consume exactly its own
// prefix or that rejects trailing atoms cannot be nested in a compound
// type. This file enforces the prefix consumption contract.
//
// Descriptors are discovered from the module rather than listed here, therefore
// exporting one without adding a sample fails the coverage test below.

import { describe, expect, test } from 'vitest';
import * as runtime from '../src/index.js';

/** An atom appended past the end of a value, to check chaining tolerance. */
const junk = (): Uint8Array => new Uint8Array([9]);

const IDENTITY: runtime.Secp256k1Point = runtime.secp256k1MulGenerator(0n);
const G: runtime.Secp256k1Point = runtime.secp256k1MulGenerator(1n);

/** Structural test for the `CompactType` interface on an instance. */
function isDescriptor(value: unknown): boolean {
  if (typeof value !== 'object' || value === null) return false;
  const v = value as Record<string, unknown>;
  return typeof v.alignment === 'function' && typeof v.toValue === 'function' && typeof v.fromValue === 'function';
}

/** Structural test for a class whose instances are `CompactType`s. */
function isDescriptorClass(value: unknown): boolean {
  if (typeof value !== 'function') return false;
  const proto = (value as { prototype?: Record<string, unknown> }).prototype;
  if (proto == null) return false;
  return (
    typeof proto.alignment === 'function' &&
    typeof proto.toValue === 'function' &&
    typeof proto.fromValue === 'function'
  );
}

/**
 * Every descriptor a module exports, singleton or class. Read from the module itself, so a new descriptor cannot
 * be silently omitted from this suite. Takes the namespace as a parameter so the coverage tests can inject a synthetic
 * one and prove the guard bites.
 */
export function discoverDescriptors(namespace: Record<string, unknown>): ReadonlySet<string> {
  return new Set(
    Object.entries(namespace)
      .filter(([, value]) => isDescriptor(value) || isDescriptorClass(value))
      .map(([name]) => name),
  );
}

const exportedNamespace = runtime as unknown as Record<string, unknown>;

/**
 * A descriptor paired with a value of its TypeScript representation. One table holds descriptors of different Compact types,
 * so the type parameter is erased here, but it is checked at construction in {@link sample}.
 */
interface Case {
  readonly label: string;
  readonly descriptor: runtime.CompactType<unknown>;
  readonly value: unknown;
}

function sample<A>(label: string, descriptor: runtime.CompactType<A>, value: A): Case {
  return { label, descriptor: descriptor as runtime.CompactType<unknown>, value };
}

/**
 * Conformance samples, keyed by exported descriptor name. `Vector` at n >= 2 and `MerkleTreePath` with a curve-point
 * leaf chain internally, therefore those are the variants worth constructing. The first entry for each name is the
 * canonical sample, used for the pairwise chaining tests.
 */
const REGISTRY: Readonly<Record<string, readonly Case[]>> = {
  CompactTypeField: [
    sample('Field', runtime.CompactTypeField, 12345678901234567890n),
    sample('Field (zero)', runtime.CompactTypeField, 0n),
    sample('Field (max)', runtime.CompactTypeField, runtime.MAX_FIELD),
  ],
  CompactTypeBoolean: [
    sample('Boolean (true)', runtime.CompactTypeBoolean, true),
    sample('Boolean (false)', runtime.CompactTypeBoolean, false),
  ],
  CompactTypeBytes: [
    sample('Bytes[4]', new runtime.CompactTypeBytes(4), new Uint8Array([1, 2, 3, 4])),
    // toValue trims trailing zeros but fromValue pads them back, so this round trips through a shorter atom.
    sample('Bytes[4] (trailing zeros)', new runtime.CompactTypeBytes(4), new Uint8Array([1, 2, 0, 0])),
    sample('Bytes[32]', new runtime.CompactTypeBytes(32), new Uint8Array(32).fill(7)),
  ],
  CompactTypeUnsignedInteger: [
    sample('Uint[<=255]', new runtime.CompactTypeUnsignedInteger(255n, 1), 200n),
    sample('Uint[<=255] (zero)', new runtime.CompactTypeUnsignedInteger(255n, 1), 0n),
    sample(
      'Uint[<=2^64-1]',
      new runtime.CompactTypeUnsignedInteger(18446744073709551615n, 8),
      18446744073709551615n,
    ),
  ],
  CompactTypeEnum: [sample('Enum[<=7]', new runtime.CompactTypeEnum(7, 1), 5), sample('Enum[<=7] (zero)', new runtime.CompactTypeEnum(7, 1), 0)],
  CompactTypeVector: [
    sample('Vector<3, Field>', new runtime.CompactTypeVector(3, runtime.CompactTypeField), [1n, 2n, 3n]),
    // A Vector of one element passes even when its element does not consume, so n >= 2 is the case that matters.
    sample('Vector<2, Secp256k1Point>', new runtime.CompactTypeVector(2, runtime.CompactTypeSecp256k1Point), [G, IDENTITY]),
    sample('Vector<2, Secp256k1Scalar>', new runtime.CompactTypeVector(2, runtime.CompactTypeSecp256k1Scalar), [1n, 2n]),
  ],
  CompactTypeJubjubPoint: [sample('JubjubPoint', runtime.CompactTypeJubjubPoint, { x: 11n, y: 22n })],
  CompactTypeSecp256k1Base: [
    sample('Secp256k1Base', runtime.CompactTypeSecp256k1Base, G.x),
    sample('Secp256k1Base (zero)', runtime.CompactTypeSecp256k1Base, 0n),
    sample('Secp256k1Base (max)', runtime.CompactTypeSecp256k1Base, runtime.MAX_SECP256K1_BASE),
  ],
  CompactTypeSecp256k1Scalar: [
    sample('Secp256k1Scalar', runtime.CompactTypeSecp256k1Scalar, 987654321n),
    sample('Secp256k1Scalar (zero)', runtime.CompactTypeSecp256k1Scalar, 0n),
    sample('Secp256k1Scalar (max)', runtime.CompactTypeSecp256k1Scalar, runtime.MAX_SECP256K1_SCALAR),
  ],
  CompactTypeSecp256k1Point: [
    sample('Secp256k1Point', runtime.CompactTypeSecp256k1Point, G),
    sample('Secp256k1Point (identity)', runtime.CompactTypeSecp256k1Point, IDENTITY),
    // The ZKIR representation subtracts one from each coordinate, so this encodes to five zero-length atoms. The atom
    // count is invariant, but the widths are not.
    sample('Secp256k1Point (all-empty atoms)', runtime.CompactTypeSecp256k1Point, {
      x: 1n,
      y: 1n,
      identity: false,
    }),
  ],
  CompactTypeMerkleTreeDigest: [sample('MerkleTreeDigest', runtime.CompactTypeMerkleTreeDigest, { field: 99n })],
  CompactTypeMerkleTreePathEntry: [
    sample('MerkleTreePathEntry', runtime.CompactTypeMerkleTreePathEntry, {
      sibling: { field: 7n },
      goes_left: true,
    }),
  ],
  CompactTypeMerkleTreePath: [
    sample('MerkleTreePath<2, Field>', new runtime.CompactTypeMerkleTreePath(2, runtime.CompactTypeField), {
      leaf: 7n,
      path: [
        { sibling: { field: 1n }, goes_left: true },
        { sibling: { field: 2n }, goes_left: false },
      ],
    }),
    // The leaf is decoded before the path, so a bare curve point still has to chain here.
    // Reached from `MerkleTree<n, Secp256k1Point>.findPathForLeaf`.
    sample(
      'MerkleTreePath<2, Secp256k1Point>',
      new runtime.CompactTypeMerkleTreePath(2, runtime.CompactTypeSecp256k1Point),
      {
        leaf: G,
        path: [
          { sibling: { field: 1n }, goes_left: true },
          { sibling: { field: 2n }, goes_left: false },
        ],
      },
    ),
  ],
  CompactTypeOpaqueString: [
    sample('Opaque<"string">', runtime.CompactTypeOpaqueString, 'hello'),
    sample('Opaque<"string"> (empty)', runtime.CompactTypeOpaqueString, ''),
  ],
  CompactTypeOpaqueUint8Array: [
    sample('Opaque<"Uint8Array">', runtime.CompactTypeOpaqueUint8Array, new Uint8Array([7, 8, 9])),
  ],
};

describe('conformance coverage', () => {
  test('every exported CompactType has a sample', () => {
    const missing = [...discoverDescriptors(exportedNamespace)].filter((name) => !(name in REGISTRY)).sort();
    expect(
      missing,
      `${missing.join(', ')} exported from src/index.ts but absent from REGISTRY in this file.\n` +
        'Add an entry keyed by that name, holding a representative value of the type.\n' +
        'The protocol tests below are generated from it, so a descriptor with no\n' +
        'sample is a descriptor with no conformance coverage.',
    ).toStrictEqual([]);
  });

  test('the registry has no samples for descriptors that no longer exist', () => {
    const exported = discoverDescriptors(exportedNamespace);
    const stale = Object.keys(REGISTRY)
      .filter((name) => !exported.has(name))
      .sort();
    expect(
      stale,
      `${stale.join(', ')} present in REGISTRY but no longer exported from src/index.ts.\n` +
        'Remove the entry, or restore the export if it was dropped by accident.',
    ).toStrictEqual([]);
  });

  test('discovery notices a descriptor that has been added', () => {
    // Discovery could silently stop recognizing descriptors, and then the two tests above would pass vacuously,
    // so make it say so here.
    const augmented: Record<string, unknown> = {
      ...exportedNamespace,
      CompactTypeSomeNewCurvePoint: {
        alignment: () => [],
        toValue: () => [],
        fromValue: () => undefined,
      },
    };
    const missing = [...discoverDescriptors(augmented)].filter((name) => !(name in REGISTRY));
    expect(missing).toStrictEqual(['CompactTypeSomeNewCurvePoint']);
  });

  test('discovery finds every descriptor, as instances or as classes', () => {
    expect(discoverDescriptors(exportedNamespace).size).toBe(Object.keys(REGISTRY).length);
  });
});

const cases: readonly Case[] = Object.values(REGISTRY).flat();

describe('CompactType protocol', () => {
  describe.each(cases)('$label', (c: Case) => {
    test('alignment declares as many atoms as toValue produces', () => {
      expect(c.descriptor.toValue(c.value).length).toBe(c.descriptor.alignment().length);
    });

    test('fromValue consumes exactly its own atoms', () => {
      const value = c.descriptor.toValue(c.value);
      const before = value.length;
      c.descriptor.fromValue(value);
      expect(before - value.length).toBe(c.descriptor.alignment().length);
      expect(value).toHaveLength(0);
    });

    test('fromValue ignores superfluous trailing atoms', () => {
      const value = c.descriptor.toValue(c.value).concat([junk(), junk()]);
      expect(() => c.descriptor.fromValue(value)).not.toThrow();
      expect(value).toHaveLength(2);
    });

    test('fromValue decodes identically with or without trailing atoms', () => {
      const plain = c.descriptor.fromValue(c.descriptor.toValue(c.value));
      const padded = c.descriptor.fromValue(c.descriptor.toValue(c.value).concat([junk()]));
      expect(padded).toStrictEqual(plain);
    });

    test('fromValue fails loudly on truncated input', () => {
      const truncated = c.descriptor.toValue(c.value).slice(0, -1);
      expect(() => c.descriptor.fromValue(truncated)).toThrow(runtime.CompactError);
    });

    test('round trips', () => {
      expect(c.descriptor.fromValue(c.descriptor.toValue(c.value))).toStrictEqual(c.value);
    });
  });
});

// Enumerating Compact types would only sample the property, so assert it directly: any two descriptors, adjacent, must chain.
// A descriptor that decodes correctly only as the last member of a compound fails as the first half of every pair.
const canonical: readonly Case[] = Object.values(REGISTRY).map((variants) => variants[0]!);

describe('any two descriptors chain', () => {
  const pairs = canonical.flatMap((first) => canonical.map((second) => ({ first, second })));

  test.each(pairs)('$first.label then $second.label', ({ first, second }) => {
    const encoded = first.descriptor.toValue(first.value).concat(second.descriptor.toValue(second.value));
    expect(encoded.length).toBe(first.descriptor.alignment().length + second.descriptor.alignment().length);
    // Decode off one array in order, exactly as the generated code does.
    const decodedFirst = first.descriptor.fromValue(encoded);
    const decodedSecond = second.descriptor.fromValue(encoded);
    // A non-consuming fromValue returns the first element twice, so assert element-wise rather than merely that nothing threw.
    expect(decodedFirst).toStrictEqual(first.value);
    expect(decodedSecond).toStrictEqual(second.value);
    expect(encoded).toHaveLength(0);
  });
});

describe('input validation', () => {
  test('Opaque<"Uint8Array"> throws rather than returning undefined', () => {
    expect(() => runtime.CompactTypeOpaqueUint8Array.fromValue([])).toThrow(runtime.CompactError);
  });

  test('Opaque<"string"> throws rather than returning the empty string', () => {
    // TextDecoder.prototype.decode(undefined) is specified to return "".
    expect(() => runtime.CompactTypeOpaqueString.fromValue([])).toThrow(runtime.CompactError);
  });

  test('Enum reports an out-of-range value as an Enum failure', () => {
    expect(() => new runtime.CompactTypeEnum(3, 1).fromValue([new Uint8Array([9])])).toThrow(/expected Enum\[<=3\]/);
  });

  test('Enum rejects an out-of-range value on encode', () => {
    expect(() => new runtime.CompactTypeEnum(3, 1).toValue(9)).toThrow(/expected Enum\[<=3\]/);
  });

  test('UnsignedInteger rejects an out-of-range value on encode', () => {
    const u = new runtime.CompactTypeUnsignedInteger(255n, 1);
    expect(() => u.toValue(256n)).toThrow(/expected UnsignedInteger\[<=255\]/);
    expect(() => u.toValue(-1n)).toThrow(/expected UnsignedInteger\[<=255\]/);
  });

  test('Bytes rejects an over-long value on encode', () => {
    expect(() => new runtime.CompactTypeBytes(4).toValue(new Uint8Array([1, 2, 3, 4, 5]))).toThrow(
      /expected Bytes\[4\]/,
    );
  });

  test('Bytes.fromValue does not alias the atom it decoded', () => {
    const b = new runtime.CompactTypeBytes(4);
    const encoded = b.toValue(new Uint8Array([1, 2, 3, 4]));
    const decoded = b.fromValue(encoded.slice());
    decoded[0] = 255;
    expect(b.fromValue(encoded)[0]).toBe(1);
  });

  test('Secp256k1Point rejects an identity flag that is neither 0 nor 1', () => {
    const encoded = runtime.CompactTypeSecp256k1Point.toValue(G);
    encoded[4] = new Uint8Array([2]);
    expect(() => runtime.CompactTypeSecp256k1Point.fromValue(encoded)).toThrow(/expected Secp256k1Point/);
  });

  test('Secp256k1Base rejects an out-of-range value on encode', () => {
    expect(() => runtime.CompactTypeSecp256k1Base.toValue(runtime.SECP256K1_BASE_MODULUS)).toThrow(
      /expected Secp256k1Base/,
    );
  });

  test('Secp256k1Scalar rejects an out-of-range value on encode', () => {
    expect(() => runtime.CompactTypeSecp256k1Scalar.toValue(runtime.SECP256K1_SCALAR_MODULUS)).toThrow(
      /expected Secp256k1Scalar/,
    );
  });
});
