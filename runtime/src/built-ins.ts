import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import type { CompactType } from './compact-type';
import { CompactTypeCurvePoint } from './compact-type';
import { CompactError } from './error';
import type { CurvePoint } from './index';
import { MAX_FIELD } from './constants';

const FIELD_MODULUS: bigint = MAX_FIELD + 1n;

/**
 * The Compact builtin `transient_hash` function
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
 * The Compact builtin `transient_commit` function
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
 * The Compact builtin `persistent_hash` function
 *
 * This function is a non-circuit-optimised hash function for mostly arbitrary
 * data. It is guaranteed to persist between upgrades, with the exception of
 * devnet. It *should* be used to derive state data, and not for consistency
 * checks where avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rt_type` encodes a type containing Compact 'Opaque' types
 */
export function persistentHash<A>(rtType: CompactType<A>, value: A): Uint8Array {
  const wrapped = ocrt.persistentHash(rtType.alignment(), rtType.toValue(value))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `persistent_commit` function
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
 * @throws If `rt_type` encodes a type containing Compact 'Opaque' types, or
 * `opening` is not 32 bytes long
 */
export function persistentCommit<A>(rt_type: CompactType<A>, value: A, opening: Uint8Array): Uint8Array {
  if (opening.length !== 32) {
    throw new CompactError('Expected 32-byte string');
  }
  const wrapped = ocrt.persistentCommit(rt_type.alignment(), rt_type.toValue(value), [opening])[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `degrade_to_transient` function
 *
 * This function "degrades" the output of a {@link persistentHash} or
 * {@link persistentCommit} to a field element, which can then be used in
 * {@link transientHash} or {@link transientCommit}.
 *
 * @throws If `x` is not 32 bytes long
 */
export function degradeToTransient(x: Uint8Array): bigint {
  if (x.length !== 32) {
    throw new CompactError('Expected 32-byte string');
  }
  return ocrt.valueToBigInt(ocrt.degradeToTransient([x]));
}
/**
 * The Compact builtin `upgrade_from_transient` function
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
 * The Compact builtin `hash_to_curve` function
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
export function hashToCurve<A>(rtType: CompactType<A>, x: A): CurvePoint {
  return CompactTypeCurvePoint.fromValue(ocrt.hashToCurve(rtType.alignment(), rtType.toValue(x)));
}

/**
 * The Compact builtin `ec_add` function
 *
 * This function add two elliptic curve points (in multiplicative notation)
 */
export function ecAdd(a: CurvePoint, b: CurvePoint): CurvePoint {
  return CompactTypeCurvePoint.fromValue(ocrt.ecAdd(CompactTypeCurvePoint.toValue(a), CompactTypeCurvePoint.toValue(b)));
}

/**
 * The Compact builtin `ec_mul` function
 *
 * This function multiplies an elliptic curve point by a scalar (in
 * multiplicative notation)
 */
export function ecMul(a: CurvePoint, b: bigint): CurvePoint {
  return CompactTypeCurvePoint.fromValue(ocrt.ecMul(CompactTypeCurvePoint.toValue(a), ocrt.bigIntToValue(b)));
}

/**
 * The Compact builtin `ec_mul_generator` function
 *
 * This function multiplies the primary group generator of the embedded curve
 * by a scalar (in multiplicative notation)
 */
export function ecMulGenerator(b: bigint): CurvePoint {
  return CompactTypeCurvePoint.fromValue(ocrt.ecMulGenerator(ocrt.bigIntToValue(b)));
}

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

