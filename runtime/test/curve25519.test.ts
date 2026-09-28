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

// Curve25519 is exposed to Compact as Curve25519Base, Curve25519Scalar and
// Curve25519Point, so the runtime functions tested here use those names.

import { describe, expect, test } from 'vitest';
import * as runtime from '../src/index.js';

// The Curve25519 generator and the group identity. Unlike secp256k1 and
// secp256r1, the identity is an ordinary affine point, (0, 1).
const G: runtime.Curve25519Point = {
  x: 15112221349535400772501151409588531511454012693041857206046113283949847762202n,
  y: 46316835694926478169428394003475163141307993866256225615783033603165251855960n,
};
const IDENTITY: runtime.Curve25519Point = { x: 0n, y: 1n };

// On an Edwards curve the negation of (x, y) is (-x, y).
const negate = (p: runtime.Curve25519Point): runtime.Curve25519Point => ({
  x: runtime.curve25519BaseNeg(p.x),
  y: p.y,
});

describe('curve25519 group operations', () => {
  test('mulGenerator matches the generator and the identity', () => {
    expect(runtime.curve25519MulGenerator(1n)).toEqual(G);
    expect(runtime.curve25519MulGenerator(0n)).toEqual(IDENTITY);
  });

  test('add, mul and mulGenerator agree on doubling', () => {
    const twoG = runtime.curve25519MulGenerator(2n);
    expect(runtime.curve25519Add(G, G)).toEqual(twoG);
    expect(runtime.curve25519Mul(G, 2n)).toEqual(twoG);
  });

  test('the identity is an additive unit and a zero scalar annihilates', () => {
    expect(runtime.curve25519Add(G, IDENTITY)).toEqual(G);
    expect(runtime.curve25519Add(IDENTITY, G)).toEqual(G);
    expect(runtime.curve25519Mul(G, 0n)).toEqual(IDENTITY);
  });

  test('a scalar of one leaves a point unchanged', () => {
    const P = runtime.curve25519MulGenerator(7n);
    expect(runtime.curve25519Mul(P, 1n)).toEqual(P);
  });

  test('a point and its negation add to the identity', () => {
    expect(runtime.curve25519Add(G, negate(G))).toEqual(IDENTITY);
  });

  test('scalar multiplication is additive in the scalar', () => {
    const fiveG = runtime.curve25519MulGenerator(5n);
    const threeG = runtime.curve25519MulGenerator(3n);
    expect(runtime.curve25519Add(runtime.curve25519MulGenerator(2n), threeG)).toEqual(fiveG);
    expect(runtime.curve25519Mul(G, 5n)).toEqual(fiveG);
  });

  test('the largest valid scalar gives the negated generator', () => {
    const L = runtime.CURVE25519_SCALAR_MODULUS;
    expect(runtime.curve25519MulGenerator(L - 1n)).toEqual(negate(G));
    expect(runtime.curve25519Mul(G, L - 1n)).toEqual(negate(G));
  });

  test('the largest valid scalar plus one generator reaches the identity', () => {
    const L = runtime.CURVE25519_SCALAR_MODULUS;
    expect(runtime.curve25519Add(runtime.curve25519MulGenerator(L - 1n), G)).toEqual(IDENTITY);
  });

  test('mul and mulGenerator agree at boundary scalars', () => {
    const L = runtime.CURVE25519_SCALAR_MODULUS;
    for (const s of [0n, 1n, 2n, L - 2n, L - 1n]) {
      expect(runtime.curve25519Mul(G, s)).toEqual(runtime.curve25519MulGenerator(s));
    }
  });

  test('rejects a scalar outside [0, l)', () => {
    // The group order itself is out of range, so it cannot be used to reach
    // the identity.
    const L = runtime.CURVE25519_SCALAR_MODULUS;
    expect(() => runtime.curve25519MulGenerator(L)).toThrow();
    expect(() => runtime.curve25519MulGenerator(-1n)).toThrow();
    expect(() => runtime.curve25519Mul(G, L)).toThrow();
    expect(() => runtime.curve25519Mul(G, -1n)).toThrow();
  });
});

describe('curve25519 point validation', () => {
  const P = runtime.CURVE25519_BASE_MODULUS;

  test('accepts the generator and computed points', () => {
    expect(runtime.isValidCurve25519Point(G)).toBe(true);
    expect(runtime.isValidCurve25519Point(runtime.curve25519MulGenerator(7n))).toBe(true);
    expect(runtime.isValidCurve25519Point(negate(G))).toBe(true);
  });

  test('the identity is accepted, it lies on the curve', () => {
    expect(runtime.isValidCurve25519Point(IDENTITY)).toBe(true);
    expect(runtime.curve25519Add(IDENTITY, IDENTITY)).toEqual(IDENTITY);
    expect(runtime.curve25519Mul(IDENTITY, 5n)).toEqual(IDENTITY);
  });

  test('rejects a point that is not on the curve', () => {
    // (1, 1) does not satisfy the curve equation.
    expect(runtime.isValidCurve25519Point({ x: 1n, y: 1n })).toBe(false);
    expect(runtime.isValidCurve25519Point({ x: G.x, y: G.y + 1n })).toBe(false);
  });

  test('rejects (0, 0), which is the identity only on the secp curves', () => {
    expect(runtime.isValidCurve25519Point({ x: 0n, y: 0n })).toBe(false);
  });

  test('rejects a point from another curve', () => {
    const alien = runtime.secp256k1MulGenerator(1n);
    expect(runtime.isValidCurve25519Point({ x: alien.x % P, y: alien.y % P })).toBe(false);
  });

  test('rejects a coordinate that is not reduced', () => {
    expect(runtime.isValidCurve25519Point({ x: P, y: G.y })).toBe(false);
    expect(runtime.isValidCurve25519Point({ x: G.x, y: P + G.y })).toBe(false);
    // (p, 1) reduces to the identity, but is still not a valid encoding of it.
    expect(runtime.isValidCurve25519Point({ x: P, y: 1n })).toBe(false);
  });

  test('rejects a value that is not a point object', () => {
    expect(runtime.isValidCurve25519Point(null)).toBe(false);
    expect(runtime.isValidCurve25519Point(undefined)).toBe(false);
    expect(runtime.isValidCurve25519Point(5n)).toBe(false);
    expect(runtime.isValidCurve25519Point({ x: G.x })).toBe(false);
  });

  test('rejects coordinates that are not bigints', () => {
    expect(runtime.isValidCurve25519Point({ x: 0, y: 1 })).toBe(false);
    expect(runtime.isValidCurve25519Point({ x: G.x.toString(), y: G.y })).toBe(false);
  });

  test('rejects a negative coordinate', () => {
    expect(runtime.isValidCurve25519Point({ x: -G.x, y: G.y })).toBe(false);
    expect(runtime.isValidCurve25519Point({ x: G.x, y: -1n })).toBe(false);
  });

  test('accepts a small-order point, only the curve equation is checked', () => {
    // (0, -1) lies on the curve and has order 2, so it is outside the
    // prime-order subgroup generated by G.
    const order2 = { x: 0n, y: P - 1n };
    expect(runtime.isValidCurve25519Point(order2)).toBe(true);
    expect(runtime.curve25519Add(order2, order2)).toEqual(IDENTITY);
    expect(runtime.curve25519Mul(order2, 2n)).toEqual(IDENTITY);
    expect(runtime.curve25519Add(runtime.curve25519Add(G, order2), order2)).toEqual(G);
  });
});

describe('curve25519 point coordinates', () => {
  test('pointX and pointY extract the affine coordinates', () => {
    expect(runtime.curve25519PointX(G)).toEqual(G.x);
    expect(runtime.curve25519PointY(G)).toEqual(G.y);
  });

  test('the identity has coordinates (0, 1)', () => {
    expect(runtime.curve25519PointX(IDENTITY)).toEqual(0n);
    expect(runtime.curve25519PointY(IDENTITY)).toEqual(1n);
  });
});

describe('curve25519 scalar field operations', () => {
  const L = runtime.CURVE25519_SCALAR_MODULUS;
  const a = 123456789n;
  const b = L - 7n;

  test('add reduces modulo the scalar modulus', () => {
    expect(runtime.curve25519ScalarAdd(a, b)).toEqual((a + b) % L);
    expect(runtime.curve25519ScalarAdd(a, L - a)).toEqual(0n);
    expect(runtime.curve25519ScalarAdd(0n, 0n)).toEqual(0n);
    expect(runtime.curve25519ScalarAdd(L - 1n, 1n)).toEqual(0n);
    expect(runtime.curve25519ScalarAdd(L - 1n, L - 1n)).toEqual(L - 2n);
  });

  test('neg is the additive inverse', () => {
    expect(runtime.curve25519ScalarAdd(a, runtime.curve25519ScalarNeg(a))).toEqual(0n);
    expect(runtime.curve25519ScalarNeg(0n)).toEqual(0n);
    expect(runtime.curve25519ScalarNeg(1n)).toEqual(L - 1n);
    expect(runtime.curve25519ScalarNeg(runtime.curve25519ScalarNeg(a))).toEqual(a);
  });

  test('sub wraps around the scalar modulus', () => {
    expect(runtime.curve25519ScalarSub(b, a)).toEqual(b - a);
    expect(runtime.curve25519ScalarSub(a, b)).toEqual(runtime.curve25519ScalarNeg(b - a));
    expect(runtime.curve25519ScalarSub(a, a)).toEqual(0n);
    expect(runtime.curve25519ScalarSub(0n, 1n)).toEqual(L - 1n);
    expect(runtime.curve25519ScalarSub(0n, L - 1n)).toEqual(1n);
  });

  test('mul reduces modulo the scalar modulus', () => {
    expect(runtime.curve25519ScalarMul(a, b)).toEqual((a * b) % L);
    expect(runtime.curve25519ScalarMul(a, 0n)).toEqual(0n);
    expect(runtime.curve25519ScalarMul(a, 1n)).toEqual(a);
    expect(runtime.curve25519ScalarMul(L - 1n, L - 1n)).toEqual(1n);
  });

  test('inv is the multiplicative inverse', () => {
    expect(runtime.curve25519ScalarMul(a, runtime.curve25519ScalarInv(a))).toEqual(1n);
    expect(runtime.curve25519ScalarInv(1n)).toEqual(1n);
    expect(runtime.curve25519ScalarInv(L - 1n)).toEqual(L - 1n);
  });

  test('zero has no multiplicative inverse', () => {
    expect(() => runtime.curve25519ScalarInv(0n)).toThrow(runtime.CompactError);
  });

  test('uses the scalar modulus, not the base modulus', () => {
    const P = runtime.CURVE25519_BASE_MODULUS;
    expect(runtime.curve25519ScalarAdd(L - 1n, 1n)).not.toEqual(runtime.curve25519BaseAdd(L - 1n, 1n));
    expect(runtime.curve25519ScalarNeg(1n)).not.toEqual(P - 1n);
  });
});

describe('curve25519 base field operations', () => {
  const P = runtime.CURVE25519_BASE_MODULUS;
  const a = 987654321n;
  const b = P - 11n;

  test('add reduces modulo the base modulus', () => {
    expect(runtime.curve25519BaseAdd(a, b)).toEqual((a + b) % P);
    expect(runtime.curve25519BaseAdd(a, P - a)).toEqual(0n);
    expect(runtime.curve25519BaseAdd(0n, 0n)).toEqual(0n);
    expect(runtime.curve25519BaseAdd(P - 1n, 1n)).toEqual(0n);
    expect(runtime.curve25519BaseAdd(P - 1n, P - 1n)).toEqual(P - 2n);
  });

  test('neg is the additive inverse', () => {
    expect(runtime.curve25519BaseAdd(a, runtime.curve25519BaseNeg(a))).toEqual(0n);
    expect(runtime.curve25519BaseNeg(0n)).toEqual(0n);
    expect(runtime.curve25519BaseNeg(1n)).toEqual(P - 1n);
    expect(runtime.curve25519BaseNeg(runtime.curve25519BaseNeg(a))).toEqual(a);
  });

  test('sub wraps around the base modulus', () => {
    expect(runtime.curve25519BaseSub(b, a)).toEqual(b - a);
    expect(runtime.curve25519BaseSub(a, b)).toEqual(runtime.curve25519BaseNeg(b - a));
    expect(runtime.curve25519BaseSub(a, a)).toEqual(0n);
    expect(runtime.curve25519BaseSub(0n, 1n)).toEqual(P - 1n);
    expect(runtime.curve25519BaseSub(0n, P - 1n)).toEqual(1n);
  });

  test('mul reduces modulo the base modulus', () => {
    expect(runtime.curve25519BaseMul(a, b)).toEqual((a * b) % P);
    expect(runtime.curve25519BaseMul(a, 0n)).toEqual(0n);
    expect(runtime.curve25519BaseMul(a, 1n)).toEqual(a);
    expect(runtime.curve25519BaseMul(P - 1n, P - 1n)).toEqual(1n);
  });

  test('inv is the multiplicative inverse', () => {
    expect(runtime.curve25519BaseMul(a, runtime.curve25519BaseInv(a))).toEqual(1n);
    expect(runtime.curve25519BaseInv(1n)).toEqual(1n);
    expect(runtime.curve25519BaseInv(P - 1n)).toEqual(P - 1n);
  });

  test('zero has no multiplicative inverse', () => {
    expect(() => runtime.curve25519BaseInv(0n)).toThrow(runtime.CompactError);
  });

  test('the generator satisfies the curve equation', () => {
    // In twisted Edwards form, Curve25519 is -x^2 + y^2 = 1 + d*x^2*y^2 with d = -121665/121666.
    const d = runtime.curve25519BaseMul(runtime.curve25519BaseNeg(121665n), runtime.curve25519BaseInv(121666n));
    const x2 = runtime.curve25519BaseMul(G.x, G.x);
    const y2 = runtime.curve25519BaseMul(G.y, G.y);
    const lhs = runtime.curve25519BaseSub(y2, x2);
    const rhs = runtime.curve25519BaseAdd(1n, runtime.curve25519BaseMul(d, runtime.curve25519BaseMul(x2, y2)));
    expect(lhs).toEqual(rhs);
  });
});

describe('curve25519 serialization', () => {
  const L = runtime.CURVE25519_SCALAR_MODULUS;
  const P = runtime.CURVE25519_BASE_MODULUS;
  const Scalar = runtime.CompactTypeCurve25519Scalar;
  const Base = runtime.CompactTypeCurve25519Base;
  const Point = runtime.CompactTypeCurve25519Point;

  test('the encoding subtracts one, so zero wraps to the largest value', () => {
    expect(Scalar.toValue(1n).every((atom) => atom.length === 0)).toBe(true);
    expect(Base.toValue(1n).every((atom) => atom.length === 0)).toBe(true);
    expect(Scalar.fromValue(Scalar.toValue(0n))).toEqual(0n);
    expect(Base.fromValue(Base.toValue(0n))).toEqual(0n);
  });

  test('a scalar round trips across the 2^204 limb split', () => {
    for (const s of [(1n << 204n) - 1n, 1n << 204n, (1n << 204n) + 1n, (1n << 204n) + 2n, L - 1n]) {
      expect(Scalar.fromValue(Scalar.toValue(s))).toEqual(s);
    }
  });

  test('a base value round trips across the 2^192 limb split', () => {
    for (const x of [(1n << 192n) - 1n, 1n << 192n, (1n << 192n) + 1n, (1n << 192n) + 2n, P - 1n]) {
      expect(Base.fromValue(Base.toValue(x))).toEqual(x);
    }
  });

  test('rejects a value outside the field on encode', () => {
    expect(() => Scalar.toValue(L)).toThrow(/expected Curve25519Scalar/);
    expect(() => Scalar.toValue(-1n)).toThrow(/expected Curve25519Scalar/);
    expect(() => Base.toValue(P)).toThrow(/expected Curve25519Base/);
    expect(() => Base.toValue(-1n)).toThrow(/expected Curve25519Base/);
  });

  test('rejects an overflowing low limb on decode', () => {
    // 26 bytes of ones is 2^208 - 1, past the 204 bits the low limb may hold.
    expect(() => Scalar.fromValue([new Uint8Array(26).fill(0xff), new Uint8Array(0)])).toThrow(runtime.CompactError);
    // 24 bytes cannot overflow 192 bits, so the base limb needs a longer atom.
    expect(() => Base.fromValue([new Uint8Array(25).fill(0xff), new Uint8Array(0)])).toThrow(runtime.CompactError);
  });

  test('rejects a reconstructed value outside the field on decode', () => {
    // The high limb is all ones, so the value is above the modulus.
    const tooBig = [new Uint8Array(0), new Uint8Array(7).fill(0xff)];
    expect(() => Scalar.fromValue(tooBig)).toThrow(runtime.CompactError);
    expect(() => Base.fromValue([new Uint8Array(0), new Uint8Array(8).fill(0xff)])).toThrow(runtime.CompactError);
  });

  test('the identity point round trips as (0, 1)', () => {
    expect(Point.fromValue(Point.toValue(IDENTITY))).toEqual(IDENTITY);
  });
});
