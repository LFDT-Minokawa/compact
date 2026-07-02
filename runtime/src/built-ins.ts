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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import {
  FIELD_MODULUS,
  JUBJUB_SCALAR_MODULUS,
  SECP256K1_BASE_MODULUS,
  SECP256K1_SCALAR_MODULUS,
} from './constants.js';
import {
  CompactType,
  CompactTypeJubjubPoint,
  JubjubPoint,
  JubjubSchnorrSignature,
  Secp256k1Point,
  toBinaryRepr,
} from './compact-types.js';
import { convertNumericToJubjubScalar } from './casts.js';
import { CompactError } from './error.js';

/**
 * Field addition
 * returns the result of adding x and y, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function addField(x: bigint, y: bigint): bigint {
  const t = x + y;
  // effectively mod(x + y, FIELD_MODULUS) for x and y in the assumed range
  // (x + y) % FIELD_MODULUS would also work but would likely be more expensive
  return t < FIELD_MODULUS ? t : t - FIELD_MODULUS;
}

/**
 * Field subtraction
 * returns the result of subtracting y from x, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function subField(x: bigint, y: bigint): bigint {
  // effectively mod(x - y, FIELD_MODULUS) for x and y in the assumed range
  // NB: JavaScript % implements remainder rather than modulus, so
  // (x - y) % FIELD_MODULUS would return an incorrect value for negative values of x - y.
  // also, any implementation involving % would likely be more expensive
  const t = x - y;
  return t >= 0 ? t : t + FIELD_MODULUS;
}

/**
 * Field multiplication
 * returns the result of multipying x and y, wrapping if necessary
 * x and y are assumed to be values in the range [0, FIELD_MODULUS)
 */
export function mulField(x: bigint, y: bigint): bigint {
  // effectively mod(x * y, FIELD_MODULUS) for x and y in the assumed range
  // (although JavaScript % implements remainder rather than modulo, remainder
  // and modulo coincide for nonnegative inputs)
  return (x * y) % FIELD_MODULUS;
}

/**
 * The Compact builtin `transientHash` function
 *
 * This function is a circuit-efficient compression function from arbitrary
 * data to field elements, which is not guaranteed to persist between upgrades.
 * It should not be used to derive state data, but can be used for consistency
 * checks.
 */
export function transientHash<A>(rtType: CompactType<A>, value: A): bigint {
  return ocrt.valueToBigInt(ocrt.transientHash(rtType.alignment(), rtType.toValue(value)));
}

/**
 * The Compact builtin `transientCommit` function
 *
 * This function is a circuit-efficient commitment function from arbitrary
 * values representable in Compact, and a field element commitment opening, to
 * field elements, which is not guaranteed to persist between
 * upgrades. It should not be used to derive state data, but can be used for
 * consistency checks.
 *
 * @throws If `opening` is out of range for field elements
 */
export function transientCommit<A>(rtType: CompactType<A>, value: A, opening: bigint): bigint {
  return ocrt.valueToBigInt(ocrt.transientCommit(rtType.alignment(), rtType.toValue(value), ocrt.bigIntToValue(opening)));
}

/**
 * The Compact builtin `persistentHash` function
 *
 * This function is a non-circuit-optimised hash function for mostly arbitrary
 * data. It is guaranteed to persist between upgrades, with the exception of
 * devnet. It *should* be used to derive state data, and not for consistency
 * checks where avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rtType` encodes a type containing Compact 'Opaque' types
 */
export function persistentHash<A>(rtType: CompactType<A>, value: A): Uint8Array {
  const wrapped = ocrt.persistentHash(rtType.alignment(), rtType.toValue(value))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `persistentCommit` function
 *
 * This function is a non-circuit-optimised commitment function from arbitrary
 * values representable in Compact, and a 256-bit bytestring opening, to a
 * 256-bit bytestring. It is guaranteed to persist between upgrades. It
 * *should* be used to derive state data, and not for consistency checks where
 * avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rtType` encodes a type containing Compact 'Opaque' types, or
 * `opening` is not 32 bytes long
 */
export function persistentCommit<A>(rtType: CompactType<A>, value: A, opening: Uint8Array): Uint8Array {
  if (opening.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  const wrapped = ocrt.persistentCommit(rtType.alignment(), rtType.toValue(value), [opening])[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `degradeToTransient` function
 *
 * This function "degrades" the output of a {@link persistentHash} or
 * {@link persistentCommit} to a field element, which can then be used in
 * {@link transientHash} or {@link transientCommit}.
 *
 * @throws If `x` is not 32 bytes long
 */
export function degradeToTransient(x: Uint8Array): bigint {
  if (x.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  return ocrt.valueToBigInt(ocrt.degradeToTransient([x]));
}

/**
 * The Compact builtin `upgradeFromTransient` function
 *
 * This function "upgrades" the output of a {@link transientHash} or
 * {@link transientCommit} to 256-bit byte string, which can then be used in
 * {@link persistentHash} or {@link persistentCommit}.
 *
 * @throws If `x` is not a valid field element
 */
export function upgradeFromTransient(x: bigint): Uint8Array {
  const wrapped = ocrt.upgradeFromTransient(ocrt.bigIntToValue(x))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `keccak256` function
 *
 * Hashes `value` using Keccak-256 and returns the 32-byte digest.
 *
 * @throws If `rtType` encodes a type containing Compact 'Opaque' types
 */
export function keccak256<A>(rtType: CompactType<A>, value: A): Uint8Array {
  return keccak_256(toBinaryRepr(rtType, value));
}

/**
 * The Compact builtin `jubjubPointX` function
 *
 * This function extracts the X-coordinate of a Compact `JubjubPoint`.
 */
export function jubjubPointX(pt: JubjubPoint): bigint {
  return pt.x;
}

/**
 * The Compact builtin `jubjubPointY` function
 *
 * This function extracts the Y-coordinate of a Compact `JubjubPoint`.
 */
export function jubjubPointY(pt: JubjubPoint): bigint {
  return pt.y;
}

/**
 * The Compact builtin `constructJubjubPoint` function
 *
 * This function constructs a Compact `JubjubPoint` from the X- and
 * Y-coordinates.  NOTE that it does not check that the coordinates represent a
 * valid point on the Jubjub curve.
 */
export function constructJubjubPoint(x: bigint, y: bigint): JubjubPoint {
  return { x, y };
}

/**
 * The Compact builtin `hashToCurve` function
 *
 * This function maps arbitrary values representable in Compact to elliptic
 * curve points in the proof system's embedded curve.
 *
 * Outputs are guaranteed to have unknown discrete logarithm with respect to
 * the group base, and any other output, but are not guaranteed to be unique (a
 * given input can be proven correct for multiple outputs).
 *
 * Inputs of different types may have the same output, if they have the same
 * field-aligned binary representation.
 */
export function hashToCurve<A>(rtType: CompactType<A>, x: A): JubjubPoint {
  return CompactTypeJubjubPoint.fromValue(ocrt.hashToCurve(rtType.alignment(), rtType.toValue(x)));
}

/**
 * The Compact builtin `ecAdd` function
 *
 * This function add two elliptic curve points (in multiplicative notation)
 */
export function ecAdd(a: JubjubPoint, b: JubjubPoint): JubjubPoint {
  return CompactTypeJubjubPoint.fromValue(ocrt.ecAdd(CompactTypeJubjubPoint.toValue(a), CompactTypeJubjubPoint.toValue(b)));
}

/**
 * The Compact builtin `ecNeg` function
 *
 * This function negates an elliptic curve point. On the JubJub twisted
 * Edwards curve, the negation of (x, y) is (-x, y).
 */
export function ecNeg(a: JubjubPoint): JubjubPoint {
  return constructJubjubPoint(a.x === 0n ? 0n : FIELD_MODULUS - a.x, a.y);
}

/**
 * The Compact builtin `ecMul` function
 *
 * This function multiplies an elliptic curve point by a scalar (in
 * multiplicative notation)
 */
export function ecMul(a: JubjubPoint, b: bigint): JubjubPoint {
  return CompactTypeJubjubPoint.fromValue(ocrt.ecMul(CompactTypeJubjubPoint.toValue(a), ocrt.bigIntToValue(b)));
}

/**
 * The Compact builtin `ecMulGenerator` function
 *
 * This function multiplies the primary group generator of the embedded curve
 * by a scalar (in multiplicative notation)
 */
export function ecMulGenerator(b: bigint): JubjubPoint {
  return CompactTypeJubjubPoint.fromValue(ocrt.ecMulGenerator(ocrt.bigIntToValue(b)));
}

/**
 * Secp256k1 scalar field addition
 *
 * This function returns x + y in the secp256k1 scalar field (modulo
 * SECP256K1_SCALAR_MODULUS).
 */
export function secp256k1ScalarAdd(x: bigint, y: bigint): bigint {
  return (x + y) % SECP256K1_SCALAR_MODULUS;
}

/**
 * Secp256k1 scalar field negation
 *
 * This function returns the negation of x in the secp256k1 scalar field.  That
 * is, a value y such that x + y = 0 (modulo SECP256K1_SCALAR_MODULUS).  x is
 * assumed to be in the range [0, SECP256K1_SCALAR_MODULUS).
 */
export function secp256k1ScalarNeg(x: bigint): bigint {
  return x == 0n ? x : SECP256K1_SCALAR_MODULUS - x;
}

/**
 * Secp256k1 scalar field multiplication
 *
 * This function returns x * y in the secp256k1 scalar field (modulo
 * SECP256K1_SCALAR_MODULUS).
 */
export function secp256k1ScalarMul(x: bigint, y: bigint): bigint {
  return (x * y) % SECP256K1_SCALAR_MODULUS;
}

/**
 * Secp256k1 scalar field inverse
 *
 * This function returns the multiplicative inverse of x in the secp256k1 scalar
 * field.  That is, a value y such that x * y = 1 (modulo
 * SECP256K1_SCALAR_MODULUS).  x is assumed to be in the range 
 * (0, SECP256K1_SCALAR_MODULUS).
 */
export function secp256k1ScalarInv(x: bigint): bigint {
  if (x === 0n) {
    throw new CompactError('Cannot compute inverse on input 0');
  }
  return secp256k1.Point.Fn.inv(x);
}

/**
 * Secp256k1 base field addition
 *
 * This function returns x + y in the secp256k1 base field (modulo
 * SECP256K1_BASE_MODULUS). 
 */
export function secp256k1BaseAdd(x: bigint, y: bigint): bigint {
  return (x + y) % SECP256K1_BASE_MODULUS;
}

/**
 * Secp256k1 base field negation
 *
 * This function returns the negation of x in the secp256k1 base field.  That
 * is, a value y such that x + y = 0 (modulo SECP256K1_BASE_MODULUS).  x is
 * assumed to be in the range [0, SECP256K1_BASE_MODULUS).
 */
export function secp256k1BaseNeg(x: bigint): bigint {
  return x == 0n ? x : SECP256K1_BASE_MODULUS - x;
}

/**
 * Secp256k1 base field multiplication
 *
 * This function returns x * y in the secp256k1 base field (modulo
 * SECP256K1_BASE_MODULUS).
 */
export function secp256k1BaseMul(x: bigint, y: bigint): bigint {
  return (x * y) % SECP256K1_BASE_MODULUS;
}

/**
 * Secp256k1 base field inverse
 *
 * This function returns the multiplicative inverse of x in the secp256k1 base
 * field.  That is, a value y such that x * y = 1 (modulo SECP256K1_BASE_MODULUS).
 * x is assumed to be in the range (0, SECP256K1_BASE_MODULUS).
 */
export function secp256k1BaseInv(x: bigint): bigint {
  if (x === 0n) {
    throw new CompactError('secp256k1 scalar field has no inverse for 0');
  }
  return secp256k1.Point.Fp.inv(x);
}

/**
 * The Compact builtin `secp256k1PointX` function
 *
 * This function extracts the affine X-coordinate of a Compact `Secp256k1Point`.
 */
export function secp256k1PointX(pt: Secp256k1Point): bigint {
  return pt.x;
}

/**
 * The Compact builtin `secp256k1PointY` function
 *
 * This function extracts the affine Y-coordinate of a Compact `Secp256k1Point`.
 */
export function secp256k1PointY(pt: Secp256k1Point): bigint {
  return pt.y;
}

/**
 * Lift the simple affine `Secp256k1Point` representation into a noble-curves
 * projective point. Identity maps to `Point.ZERO`; every other input is validated
 * to lie on the curve by `fromAffine`.
 */
function secp256k1ToProjective(p: Secp256k1Point): ReturnType<typeof secp256k1.Point.fromAffine> {
  if (p.identity) {
    return secp256k1.Point.ZERO;
  }
  return secp256k1.Point.fromAffine({ x: p.x, y: p.y });
}

/**
 * Project a noble-curves point back down to the simple affine
 * `Secp256k1Point` representation.
 */
function secp256k1FromProjective(p: ReturnType<typeof secp256k1.Point.fromAffine>): Secp256k1Point {
  const k = p.toAffine();
  if (/* k == secp256k1.Point.ZERO */ k.x == 0n && k.y == 0n) {
    return { x: 0n, y: 0n, identity: true };
  } else {
    const { x, y } = k;
    return { x: x, y: y, identity: false };
  }
}

/**
 * The Compact builtin `ecAdd` function for secp256k1 points.
 *
 * This function adds two elliptic curve points.
 */
export function secp256k1Add(a: Secp256k1Point, b: Secp256k1Point): Secp256k1Point {
  return secp256k1FromProjective(secp256k1ToProjective(a).add(secp256k1ToProjective(b)));
}

/**
 * The Compact builtin `ecMul` function for secp256k1 points.
 *
 * `multiplyUnsafe` is used, instead of `multiply`, because the latter rejects a zero scalar; the
 * "unsafe" (variable-time) is due to non-constant time operations, which we don't guarantee
 * anyways.
 */
export function secp256k1Mul(a: Secp256k1Point, b: bigint): Secp256k1Point {
  return secp256k1FromProjective(secp256k1ToProjective(a).multiplyUnsafe(b));
}

/**
 * The Compact builtin `ecMulGenerator` function for secp256k1 points.
 *
 * `multiplyUnsafe` is used, instead of `multiply`, because the latter rejects a zero scalar; the
 * "unsafe" (variable-time) is due to non-constant time operations, which we don't guarantee
 * anyways.
 */
export function secp256k1MulGenerator(b: bigint): Secp256k1Point {
  return secp256k1FromProjective(secp256k1.Point.BASE.multiplyUnsafe(b));
}

/**
 * Concatenates multiple {@link AlignedValue}s
 * @internal
 */
export function alignedConcat(...values: ocrt.AlignedValue[]): ocrt.AlignedValue {
  const res: ocrt.AlignedValue = { value: [], alignment: [] };
  for (const value of values) {
    res.value = res.value.concat(value.value);
    res.alignment = res.alignment.concat(value.alignment);
  }
  return res;
}

/**
 * Samples a random JubJub scalar.
 *
 * The returned value is in the range [0, JUBJUB_SCALAR_MODULUS).
 */
export function jubjubSampleScalar(): bigint {
  return ocrt.valueToBigInt(ocrt.jubjubSampleScalar());
}

/**
 * Alias for {@link jubjubSampleScalar}. Samples a random JubJub Schnorr signing key.
 */
export const sampleJubjubSchnorrSk = jubjubSampleScalar;

/**
 * Derives the Schnorr verifying key (public key) from a signing key.
 *
 * Equivalent to {@link ecMulGenerator}(signingKey).
 */
export function jubjubSchnorrVerifyingKey(signingKey: bigint): JubjubPoint {
  return ecMulGenerator(convertNumericToJubjubScalar(signingKey));
}

/**
 * Produces a Schnorr signature over the JubJub curve.
 *
 * - `rtType` / `msg`: the message as a typed Compact value
 * - `sk`: signing key as a JubJub scalar (e.g. as returned by {@link jubjubSampleScalar})
 *
 * The signature scheme:
 * - Nonce `r` sampled uniformly at random
 * - Announcement `R = r·G`
 * - Challenge `c = PoseidonHash(R.x, R.y, pk.x, pk.y, msg...)`
 * - Response `s = r + c·sk` (in the JubJub scalar field)
 */
export function jubjubSchnorrSign<A>(rtType: CompactType<A>, msg: A, signingKey: bigint): JubjubSchnorrSignature {
  const r = jubjubSampleScalar();
  const announcement = ecMulGenerator(r);
  const verifyingKey = ecMulGenerator(signingKey);

  const challengeAlignment: ocrt.Alignment = [
    ...CompactTypeJubjubPoint.alignment(),
    ...CompactTypeJubjubPoint.alignment(),
    ...rtType.alignment(),
  ];
  const challengeValue: ocrt.Value = [
    ...CompactTypeJubjubPoint.toValue(announcement),
    ...CompactTypeJubjubPoint.toValue(verifyingKey),
    ...rtType.toValue(msg),
  ];
  const c = convertNumericToJubjubScalar(ocrt.valueToBigInt(ocrt.transientHash(challengeAlignment, challengeValue)));

  const response = convertNumericToJubjubScalar(r + c * signingKey);
  return { announcement, response };
}

/**
 * Verifies a Schnorr signature over the JubJub curve.
 *
 * - `rtType` / `msg`: the message as a typed Compact value
 * - `pk`: verifying key (a JubJubPoint / EmbeddedGroupAffine)
 * - `sig`: signature as returned by {@link jubjubSchnorrSign}
 *
 * Returns `true` if the signature is valid (i.e. `s·G == R + c·pk`).
 */
export function jubjubSchnorrVerify<A>(
  rtType: CompactType<A>,
  msg: A,
  verifyingKey: JubjubPoint,
  sig: JubjubSchnorrSignature,
): boolean {
  const { announcement, response } = sig;

  const challengeAlignment: ocrt.Alignment = [
    ...CompactTypeJubjubPoint.alignment(),
    ...CompactTypeJubjubPoint.alignment(),
    ...rtType.alignment(),
  ];
  const challengeValue: ocrt.Value = [
    ...CompactTypeJubjubPoint.toValue(announcement),
    ...CompactTypeJubjubPoint.toValue(verifyingKey),
    ...rtType.toValue(msg),
  ];
  const c = convertNumericToJubjubScalar(ocrt.valueToBigInt(ocrt.transientHash(challengeAlignment, challengeValue)));

  const lhs = ecMulGenerator(response);
  const rhs = ecAdd(announcement, ecMul(verifyingKey, c));

  return lhs.x === rhs.x && lhs.y === rhs.y;
}
