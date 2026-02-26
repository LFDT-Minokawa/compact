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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v3';
import type { CompactType } from './compact-types.js';

// ============================================================
// Curves, Points, and Fields
// ============================================================
//
// An elliptic curve defines two distinct finite fields and a set of points:
//
//   Base field    – the field F_p over which the curve equation is defined.
//                   Both coordinates x and y of the point (x, y) are elements 
//                   of this field.
//
//   Scalar field  – the field F_r whose order equals the number of points
//                   on the curve (the "group order").  Scalars live here:
//                   when you multiply a point P by a scalar k, k is reduced
//                   mod r.
//
//   Points        – solutions (x, y) in F_p to the curve equation, plus
//                   the point at infinity.  Points form a group under
//                   addition; scalar multiplication is repeated addition.
//
// These three concepts are independent.  A single curve gives rise to one
// base field, one scalar field, and one group of points — but the base and
// scalar fields are generally different (p ≠ r), so arithmetic in one is
// not interchangeable with arithmetic in the other.
//
// Naming convention in this file:
//
//   <Curve>Point         – a point on the curve
//   <Curve>BaseElement   – an element of the curve's base field (F_p)
//   <Curve>ScalarElement – an element of the curve's scalar field (F_r)
//   FieldElement         – the "native" field of the proof system, which 
//                          for Midnight is the BLS12-381 scalar field.
//                          This is the field that Compact's `Field` type maps to.
//
// Why is there a Secp256k1ScalarElement but no BLS12381ScalarElement?
// Because the BLS12-381 scalar field *is* the native field — it is already
// exported as FieldElement.  Adding a separate BLS12381ScalarElement
// would be redundant.  Conversely, secp256k1 is a non-native curve whose
// scalar field differs from the native field, so it needs its own type.
//
// ============================================================

/**
 * Available curves for which we may have point values.
 * Native refers to the native curve of the proof system (Jubjub for Midnight).
 */
export type Curve = 'Native' | 'BLS12381' | 'Jubjub' | 'Secp256k1';

/**
 * For fields associated with a curve, specifies whether we are referring
 * to the base or scalar field of that curve.
 */
export type FieldType = 'Scalar' | 'Base';

/**
 * Fields exist in three flavors:
 * - Native: the native field of the underlying proof system (BLS scalar for Midnight)
 * - CurveField: base or scalar field associated with a supported curve
 * - Standalone: fields not associated with any curve
 */
export type Field =
  | { tag: 'Native' }
  | { tag: 'CurveField'; curve: Curve; fieldType: FieldType }
  | { tag: 'Standalone'; name: string };

// ============================================================
// Point Interface
// ============================================================

/**
 * Common interface for all curve points.
 */
export interface IPointBase {
  readonly x: FieldElement;
  readonly y: FieldElement;

  toValue(): ocrt.Value;

  equals(other: IPointBase): boolean;
}

// ============================================================
// Point Class Factory
// ============================================================

/**
 * Maps the Curve type tag to the lowercase curve name expected by onchain-runtime.
 */
const curveRuntimeNames: Record<Curve, ocrt.CurveName> = {
  Jubjub: 'jubjub',
  Native: 'native',
  Secp256k1: 'secp256k1',
  BLS12381: 'bls12381',
};

/**
 * Creates a PointBase class for a specific curve.
 *
 * This factory pattern (used by libraries like noble-curves) generates
 * a self-contained class for each curve, avoiding inheritance complexity
 * while maintaining type safety between different curves.
 *
 * Internally stores the point as an ocrt.Value to avoid repeated conversions
 * during arithmetic operations. Coordinates are parsed lazily on access.
 *
 * The returned class also satisfies CompactType<P>, so it can be used directly
 * as a type descriptor for serialization.
 *
 * All curve operations delegate directly to the onchain-runtime's
 * curve-parameterized functions (pointAdd, pointMul, etc.).
 */
function createPointClass<C extends Curve>(curve: C) {
  const runtimeName = curveRuntimeNames[curve];

  return class PointBase implements IPointBase {
    /** Brand that distinguishes point types at compile time */
    declare readonly _curve: C;

    /** Internal representation - avoids conversion during operations */
    readonly #value: ocrt.Value;

    private constructor(value: ocrt.Value) {
      this.#value = value;
    }

    /** The curve this point belongs to */
    static readonly curve: C = curve;

    /** Returns the alignment for this point type */
    static alignment(): ocrt.Alignment {
      return [
        { tag: 'atom', value: { tag: 'field' } },
        { tag: 'atom', value: { tag: 'field' } },
      ];
    }

    /** Converts a point to its Value representation (CompactType compatibility) */
    static toValue(point: PointBase): ocrt.Value {
      return point.toValue();
    }

    /** Creates a point from a field-aligned binary representation */
    static fromValue(value: ocrt.Value): PointBase {
      if (value.length < 2) {
        throw new Error(`Expected ${curve} point: insufficient data`);
      }
      return new PointBase([...value.splice(0, 2)]);
    }

    /** Creates a point from coordinates, validating they are on the curve */
    static create(x: FieldElement, y: FieldElement): PointBase {
      const xVal = ocrt.bigIntToValue(x.value);
      const yVal = ocrt.bigIntToValue(y.value);
      if (!ocrt.pointValidate(runtimeName, xVal, yVal)) {
        throw new Error(`(${x.value}, ${y.value}) is not a valid point on the ${curve} curve`);
      }
      const value = ocrt.bigIntToValue(x.value).concat(ocrt.bigIntToValue(y.value));
      return new PointBase(value);
    }

    /** Returns the generator point for this curve */
    static generator(): PointBase {
      return new PointBase(ocrt.pointGenerator(runtimeName));
    }

    /** Multiplies the generator by a scalar */
    static mulGenerator(scalar: FieldElement): PointBase {
      return new PointBase(ocrt.pointMulGenerator(runtimeName, ocrt.bigIntToValue(scalar.value)));
    }

    /** The x-coordinate (parsed lazily) */
    get x(): FieldElement {
      return FieldElement.fromValue([this.#value[0]]);
    }

    /** The y-coordinate (parsed lazily) */
    get y(): FieldElement {
      return FieldElement.fromValue([this.#value[1]]);
    }

    /** Returns the internal Value representation (no copy) */
    toValue(): ocrt.Value {
      return this.#value;
    }

    /** Adds this point to another point */
    add(other: PointBase): PointBase {
      return new PointBase(ocrt.pointAdd(runtimeName, this.#value, other.#value));
    }

    /** Multiplies this point by a scalar */
    mul(scalar: FieldElement): PointBase {
      return new PointBase(ocrt.pointMul(runtimeName, this.#value, ocrt.bigIntToValue(scalar.value)));
    }

    /** Negates this point */
    neg(): PointBase {
      return new PointBase(ocrt.pointNeg(runtimeName, this.#value));
    }

    /** Checks equality with another point */
    equals(other: IPointBase): boolean {
      return this.x.value === other.x.value && this.y.value === other.y.value;
    }
  };
}

// ============================================================
// Field Element Class Factory
// ============================================================

/**
 * Common interface for all field elements.
 */
export interface IFieldElementBase {
  readonly value: bigint;

  toValue(): ocrt.Value;

  equals(other: IFieldElementBase): boolean;
}

/**
 * Maps a Field descriptor to the runtime name expected by onchain-runtime's
 * field-parameterized functions (fieldAdd, fieldMul, etc.).
 */
function fieldToRuntimeName(field: Field): ocrt.FieldName {
  if (field.tag === 'Native') return 'native';
  if (field.tag === 'CurveField') return `${curveRuntimeNames[field.curve]}.${field.fieldType.toLowerCase()}` as ocrt.FieldName;
  return field.name as ocrt.FieldName; // Standalone — assumed to be a valid runtime field name
}

/**
 * Creates a FieldElement class for a specific field.
 *
 * The returned class also satisfies CompactType<E>, so it can be used directly
 * as a type descriptor for serialization.
 *
 * All field operations delegate directly to the onchain-runtime's
 * field-parameterized functions (fieldAdd, fieldSub, etc.).
 */
function createFieldElementClass<F extends Field>(field: F) {
  const runtimeName = fieldToRuntimeName(field);

  return class FieldElementBase implements IFieldElementBase {
    /** Brand that distinguishes field element types at compile time */
    declare readonly _Field: F;

    readonly value: bigint;

    /**
     * Constructs a field element without validation.
     * Prefer `FieldElement.create()` or `FieldElement.fromValue()` for validated construction.
     */
    constructor(value: bigint) {
      this.value = value;
    }

    /** The field this element belongs to */
    static readonly field: F = field;

    /** Returns the alignment for this field element type */
    static alignment(): ocrt.Alignment {
      return [{ tag: 'atom', value: { tag: 'field' } }];
    }

    /** Converts an element to its Value representation (CompactType compatibility) */
    static toValue(element: FieldElementBase): ocrt.Value {
      return element.toValue();
    }

    /** Creates an element from a field-aligned binary representation */
    static fromValue(value: ocrt.Value): FieldElementBase {
      const bytes = value.shift();
      if (bytes === undefined) {
        throw new Error('Expected field element: insufficient data');
      }
      return FieldElementBase.create(ocrt.valueToBigInt([bytes]));
    }

    /** Creates an element, validating it is in the field */
    static create(value: bigint): FieldElementBase {
      if (!ocrt.fieldValidate(runtimeName, value)) {
        throw new Error(`${value} is not a valid element of field "${runtimeName}"`);
      }
      return new FieldElementBase(value);
    }

    /** Returns the zero element */
    static zero(): FieldElementBase {
      return new FieldElementBase(0n);
    }

    /** Returns the one element */
    static one(): FieldElementBase {
      return new FieldElementBase(1n);
    }

    /** Returns the prime modulus of this field */
    static modulus(): bigint {
      return ocrt.fieldModulus(runtimeName);
    }

    /** Converts to field-aligned binary representation */
    toValue(): ocrt.Value {
      return ocrt.bigIntToValue(this.value);
    }

    /** Adds this element to another */
    add(other: FieldElementBase): FieldElementBase {
      return new FieldElementBase(ocrt.fieldAdd(runtimeName, this.value, other.value));
    }

    /** Subtracts another element from this */
    sub(other: FieldElementBase): FieldElementBase {
      return new FieldElementBase(ocrt.fieldSub(runtimeName, this.value, other.value));
    }

    /** Multiplies this element by another */
    mul(other: FieldElementBase): FieldElementBase {
      return new FieldElementBase(ocrt.fieldMul(runtimeName, this.value, other.value));
    }

    /** Negates this element */
    neg(): FieldElementBase {
      return new FieldElementBase(ocrt.fieldNeg(runtimeName, this.value));
    }

    /** Computes the multiplicative inverse */
    inv(): FieldElementBase {
      return new FieldElementBase(ocrt.fieldInv(runtimeName, this.value));
    }

    /** Checks equality with another element */
    equals(other: IFieldElementBase): boolean {
      return this.value === other.value;
    }
  };
}

// ============================================================
// Point Type Definitions (for better error messages)
// ============================================================

/** Instance interface for a Point on curve C */
interface IPointInstance<C extends Curve> extends IPointBase {
  readonly _curve: C;

  add(other: IPointInstance<C>): IPointInstance<C>;

  mul(scalar: FieldElement): IPointInstance<C>;

  neg(): IPointInstance<C>;
}

/** Static interface for a Point class on curve C - also satisfies CompactType<P> */
interface IPointBuilder<C extends Curve, P extends IPointInstance<C>> extends CompactType<P> {
  readonly curve: C;

  create(x: FieldElement, y: FieldElement): P;

  generator(): P;

  mulGenerator(scalar: FieldElement): P;
}

// ============================================================
// Concrete Point Classes
// ============================================================

/** A point on the Jubjub curve */
export interface JubjubPoint extends IPointInstance<'Jubjub'> {
  add(other: JubjubPoint): JubjubPoint;

  mul(scalar: FieldElement): JubjubPoint;

  neg(): JubjubPoint;
}

export const JubjubPoint: IPointBuilder<'Jubjub', JubjubPoint> = createPointClass('Jubjub');

/** A point on the native curve (Jubjub for Midnight) */
export interface NativePoint extends IPointInstance<'Native'> {
  add(other: NativePoint): NativePoint;

  mul(scalar: FieldElement): NativePoint;

  neg(): NativePoint;
}

export const NativePoint: IPointBuilder<'Native', NativePoint> = createPointClass('Native');

/** A point on the secp256k1 curve */
export interface Secp256k1Point extends IPointInstance<'Secp256k1'> {
  add(other: Secp256k1Point): Secp256k1Point;

  mul(scalar: FieldElement): Secp256k1Point;

  neg(): Secp256k1Point;
}

export const Secp256k1Point: IPointBuilder<'Secp256k1', Secp256k1Point> = createPointClass('Secp256k1');

/** A point on the BLS12-381 curve */
export interface BLS12381Point extends IPointInstance<'BLS12381'> {
  add(other: BLS12381Point): BLS12381Point;

  mul(scalar: FieldElement): BLS12381Point;

  neg(): BLS12381Point;
}

export const BLS12381Point: IPointBuilder<'BLS12381', BLS12381Point> = createPointClass('BLS12381');

// ============================================================
// Concrete Field Element Classes
// ============================================================

/** An element of the native field (BLS12-381 scalar for Midnight) */
export const FieldElement = createFieldElementClass({ tag: 'Native' } as const);
export type FieldElement = InstanceType<typeof FieldElement>;

/** An element of the Jubjub scalar field */
export const JubjubScalarElement = createFieldElementClass({ tag: 'CurveField', curve: 'Jubjub', fieldType: 'Scalar' } as const);
export type JubjubScalarElement = InstanceType<typeof JubjubScalarElement>;

/** An element of the Jubjub base field */
export const JubjubBaseElement = createFieldElementClass({ tag: 'CurveField', curve: 'Jubjub', fieldType: 'Base' } as const);
export type JubjubBaseElement = InstanceType<typeof JubjubBaseElement>;

/** An element of the secp256k1 scalar field */
export const Secp256k1ScalarElement = createFieldElementClass({
  tag: 'CurveField',
  curve: 'Secp256k1',
  fieldType: 'Scalar',
} as const);
export type Secp256k1ScalarElement = InstanceType<typeof Secp256k1ScalarElement>;

/** An element of the secp256k1 base field */
export const Secp256k1BaseElement = createFieldElementClass({
  tag: 'CurveField',
  curve: 'Secp256k1',
  fieldType: 'Base',
} as const);
export type Secp256k1BaseElement = InstanceType<typeof Secp256k1BaseElement>;
