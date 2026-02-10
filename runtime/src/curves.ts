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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v2';
import type { CompactType } from './compact-types.js';

// ============================================================
// Type Definitions - mirrors the Lean/Agda ZKIR spec
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
// Curve Operations Interface
// ============================================================

/**
 * Operations that must be provided for each curve.
 * These are typically implemented by the onchain-runtime.
 */
export interface CurveOps {
  /** Validates that (x, y) is a valid point on the curve */
  validate(x: bigint, y: bigint): void;

  /** Adds two points */
  add(a: ocrt.Value, b: ocrt.Value): ocrt.Value;

  /** Multiplies a point by a scalar */
  mul(point: ocrt.Value, scalar: ocrt.Value): ocrt.Value;

  /** Negates a point */
  neg(point: ocrt.Value): ocrt.Value;

  /** Returns the generator point */
  generator(): ocrt.Value;

  /** Multiplies the generator by a scalar */
  mulGenerator(scalar: ocrt.Value): ocrt.Value;
}

/**
 * Operations that must be provided for each field.
 */
export interface FieldOps {
  /** Validates that a value is in the field */
  validate(value: bigint): void;

  /** Adds two field elements */
  add(a: bigint, b: bigint): bigint;

  /** Subtracts two field elements */
  sub(a: bigint, b: bigint): bigint;

  /** Multiplies two field elements */
  mul(a: bigint, b: bigint): bigint;

  /** Negates a field element */
  neg(a: bigint): bigint;

  /** Computes the multiplicative inverse */
  inv(a: bigint): bigint;
}

// ============================================================
// Point Interface
// ============================================================

/**
 * Common interface for all curve points.
 */
export interface IPointBase {
  readonly x: bigint;
  readonly y: bigint;

  toValue(): ocrt.Value;

  equals(other: IPointBase): boolean;
}

// ============================================================
// Point Class Factory
// ============================================================

/** Alignment for point types (two field elements) */
const pointAlignment: ocrt.Alignment = [
  { tag: 'atom', value: { tag: 'field' } },
  { tag: 'atom', value: { tag: 'field' } },
];

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
 */
function createPointClass<C extends Curve>(curve: C, ops: CurveOps) {
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
      return pointAlignment;
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
      // Store the value directly, coordinates parsed lazily
      return new PointBase([...value.splice(0, 2)]);
    }

    // ---- Factory methods ----

    /** Creates a point from coordinates, validating they are on the curve */
    static create(x: bigint, y: bigint): PointBase {
      ops.validate(x, y);
      const value = ocrt.bigIntToValue(x).concat(ocrt.bigIntToValue(y));
      const point = new PointBase(value);
      return point;
    }

    /** Returns the generator point for this curve */
    static generator(): PointBase {
      return new PointBase(ops.generator());
    }

    /** Multiplies the generator by a scalar */
    static mulGenerator(scalar: bigint): PointBase {
      return new PointBase(ops.mulGenerator(ocrt.bigIntToValue(scalar)));
    }

    /** The x-coordinate (parsed lazily) */
    get x(): bigint {
      return ocrt.valueToBigInt([this.#value[0]]);
    }

    /** The y-coordinate (parsed lazily) */
    get y(): bigint {
      return ocrt.valueToBigInt([this.#value[1]]);
    }

    /** Returns the internal Value representation (no copy) */
    toValue(): ocrt.Value {
      return this.#value;
    }

    /** Adds this point to another point */
    add(other: PointBase): PointBase {
      return new PointBase(ops.add(this.#value, other.#value));
    }

    /** Multiplies this point by a scalar */
    mul(scalar: bigint): PointBase {
      return new PointBase(ops.mul(this.#value, ocrt.bigIntToValue(scalar)));
    }

    /** Negates this point */
    neg(): PointBase {
      return new PointBase(ops.neg(this.#value));
    }

    /** Checks equality with another point */
    equals(other: IPointBase): boolean {
      return this.x === other.x && this.y === other.y;
    }
  };
}

// ============================================================
// Field Element Class Factory
// ============================================================

/**
 * Common interface for all field elements.
 */
export interface IFieldElement {
  readonly value: bigint;

  toValue(): ocrt.Value;

  equals(other: IFieldElement): boolean;
}

/** Alignment for field element types (one field element) */
const fieldAlignment: ocrt.Alignment = [{ tag: 'atom', value: { tag: 'field' } }];

/**
 * Creates a FieldElement class for a specific field.
 *
 * The returned class also satisfies CompactType<E>, so it can be used directly
 * as a type descriptor for serialization.
 */
function createFieldElementClass<F extends Field>(field: F, ops: FieldOps) {
  return class FieldElement implements IFieldElement {
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
      return fieldAlignment;
    }

    /** Converts an element to its Value representation (CompactType compatibility) */
    static toValue(element: FieldElement): ocrt.Value {
      return element.toValue();
    }

    /** Creates an element from a field-aligned binary representation */
    static fromValue(value: ocrt.Value): FieldElement {
      const bytes = value.shift();
      if (bytes === undefined) {
        throw new Error('Expected field element: insufficient data');
      }
      return FieldElement.create(ocrt.valueToBigInt([bytes]));
    }

    /** Creates an element, validating it is in the field */
    static create(value: bigint): FieldElement {
      ops.validate(value);
      return new FieldElement(value);
    }

    /** Returns the zero element */
    static zero(): FieldElement {
      return new FieldElement(0n);
    }

    /** Returns the one element */
    static one(): FieldElement {
      return new FieldElement(1n);
    }

    /** Converts to field-aligned binary representation */
    toValue(): ocrt.Value {
      return ocrt.bigIntToValue(this.value);
    }

    /** Adds this element to another */
    add(other: FieldElement): FieldElement {
      return new FieldElement(ops.add(this.value, other.value));
    }

    /** Subtracts another element from this */
    sub(other: FieldElement): FieldElement {
      return new FieldElement(ops.sub(this.value, other.value));
    }

    /** Multiplies this element by another */
    mul(other: FieldElement): FieldElement {
      return new FieldElement(ops.mul(this.value, other.value));
    }

    /** Negates this element */
    neg(): FieldElement {
      return new FieldElement(ops.neg(this.value));
    }

    /** Computes the multiplicative inverse */
    inv(): FieldElement {
      return new FieldElement(ops.inv(this.value));
    }

    /** Checks equality with another element */
    equals(other: IFieldElement): boolean {
      return this.value === other.value;
    }
  };
}

// ============================================================
// Curve Operations Implementations
// ============================================================

// Placeholder operations - to be replaced with actual onchain-runtime calls
const jubjubOps: CurveOps = {
  validate(x: bigint, y: bigint): void {
    // TODO: Implement proper validation in onchain-runtime
  },
  add(a: ocrt.Value, b: ocrt.Value): ocrt.Value {
    return ocrt.ecAdd(a, b);
  },
  mul(point: ocrt.Value, scalar: ocrt.Value): ocrt.Value {
    return ocrt.ecMul(point, scalar);
  },
  neg(point: ocrt.Value): ocrt.Value {
    // TODO: Implement in onchain-runtime
    throw new Error('pointNeg not yet implemented for Jubjub');
  },
  generator(): ocrt.Value {
    // TODO: Implement in onchain-runtime
    throw new Error('generator not yet implemented for Jubjub');
  },
  mulGenerator(scalar: ocrt.Value): ocrt.Value {
    return ocrt.ecMulGenerator(scalar);
  },
};

// Native curve uses the same operations as Jubjub (they're the same curve for Midnight)
const nativeOps: CurveOps = jubjubOps;

const secp256k1Ops: CurveOps = {
  validate(x: bigint, y: bigint): void {
    // TODO: Implement in onchain-runtime
  },
  add(a: ocrt.Value, b: ocrt.Value): ocrt.Value {
    throw new Error('pointAdd not yet implemented for Secp256k1');
  },
  mul(point: ocrt.Value, scalar: ocrt.Value): ocrt.Value {
    throw new Error('pointMul not yet implemented for Secp256k1');
  },
  neg(point: ocrt.Value): ocrt.Value {
    throw new Error('pointNeg not yet implemented for Secp256k1');
  },
  generator(): ocrt.Value {
    throw new Error('generator not yet implemented for Secp256k1');
  },
  mulGenerator(scalar: ocrt.Value): ocrt.Value {
    throw new Error('mulGenerator not yet implemented for Secp256k1');
  },
};

const bls12381Ops: CurveOps = {
  validate(x: bigint, y: bigint): void {
    // TODO: Implement in onchain-runtime
  },
  add(a: ocrt.Value, b: ocrt.Value): ocrt.Value {
    throw new Error('pointAdd not yet implemented for BLS12381');
  },
  mul(point: ocrt.Value, scalar: ocrt.Value): ocrt.Value {
    throw new Error('pointMul not yet implemented for BLS12381');
  },
  neg(point: ocrt.Value): ocrt.Value {
    throw new Error('pointNeg not yet implemented for BLS12381');
  },
  generator(): ocrt.Value {
    throw new Error('generator not yet implemented for BLS12381');
  },
  mulGenerator(scalar: ocrt.Value): ocrt.Value {
    throw new Error('mulGenerator not yet implemented for BLS12381');
  },
};

// ============================================================
// Field Operations Implementations
// ============================================================

const nativeFieldOps: FieldOps = {
  validate(value: bigint): void {
    // TODO: Implement proper validation
  },
  add(a: bigint, b: bigint): bigint {
    throw new Error('fieldAdd not yet implemented for Native');
  },
  sub(a: bigint, b: bigint): bigint {
    throw new Error('fieldSub not yet implemented for Native');
  },
  mul(a: bigint, b: bigint): bigint {
    throw new Error('fieldMul not yet implemented for Native');
  },
  neg(a: bigint): bigint {
    throw new Error('fieldNeg not yet implemented for Native');
  },
  inv(a: bigint): bigint {
    throw new Error('fieldInv not yet implemented for Native');
  },
};

const jubjubScalarOps: FieldOps = nativeFieldOps; // Same field
const jubjubBaseOps: FieldOps = nativeFieldOps; // TODO: Different modulus

const secp256k1ScalarOps: FieldOps = {
  validate(value: bigint): void {},
  add(a: bigint, b: bigint): bigint {
    throw new Error('fieldAdd not yet implemented for Secp256k1 scalar');
  },
  sub(a: bigint, b: bigint): bigint {
    throw new Error('fieldSub not yet implemented for Secp256k1 scalar');
  },
  mul(a: bigint, b: bigint): bigint {
    throw new Error('fieldMul not yet implemented for Secp256k1 scalar');
  },
  neg(a: bigint): bigint {
    throw new Error('fieldNeg not yet implemented for Secp256k1 scalar');
  },
  inv(a: bigint): bigint {
    throw new Error('fieldInv not yet implemented for Secp256k1 scalar');
  },
};

const secp256k1BaseOps: FieldOps = secp256k1ScalarOps; // TODO: Different modulus

// ============================================================
// Point Type Definitions (for better error messages)
// ============================================================

/** Instance interface for a Point on curve C */
interface IPointInstance<C extends Curve> extends IPointBase {
  readonly _curve: C;

  add(other: IPointInstance<C>): IPointInstance<C>;

  mul(scalar: bigint): IPointInstance<C>;

  neg(): IPointInstance<C>;
}

/** Static interface for a Point class on curve C - also satisfies CompactType<P> */
interface IPointBuilder<C extends Curve, P extends IPointInstance<C>> extends CompactType<P> {
  readonly curve: C;

  create(x: bigint, y: bigint): P;

  generator(): P;

  mulGenerator(scalar: bigint): P;
}

// ============================================================
// Concrete Point Classes
// ============================================================

/** A point on the Jubjub curve */
export interface JubjubPoint extends IPointInstance<'Jubjub'> {
  add(other: JubjubPoint): JubjubPoint;
  mul(scalar: bigint): JubjubPoint;
  neg(): JubjubPoint;
}

export const JubjubPoint: IPointBuilder<'Jubjub', JubjubPoint> = createPointClass('Jubjub', jubjubOps);

/** A point on the native curve (Jubjub for Midnight) */
export interface NativePoint extends IPointInstance<'Native'> {
  add(other: NativePoint): NativePoint;
  mul(scalar: bigint): NativePoint;
  neg(): NativePoint;
}

export const NativePoint: IPointBuilder<'Native', NativePoint> = createPointClass('Native', nativeOps);

/** A point on the secp256k1 curve */
export interface Secp256k1Point extends IPointInstance<'Secp256k1'> {
  add(other: Secp256k1Point): Secp256k1Point;
  mul(scalar: bigint): Secp256k1Point;
  neg(): Secp256k1Point;
}

export const Secp256k1Point: IPointBuilder<'Secp256k1', Secp256k1Point> = createPointClass('Secp256k1', secp256k1Ops);

/** A point on the BLS12-381 curve */
export interface BLS12381Point extends IPointInstance<'BLS12381'> {
  add(other: BLS12381Point): BLS12381Point;
  mul(scalar: bigint): BLS12381Point;
  neg(): BLS12381Point;
}

export const BLS12381Point: IPointBuilder<'BLS12381', BLS12381Point> = createPointClass('BLS12381', bls12381Ops);

// ============================================================
// Concrete Field Element Classes
// ============================================================

/** An element of the native field (BLS12-381 scalar for Midnight) */
export const NativeFieldElement = createFieldElementClass({ tag: 'Native' } as const, nativeFieldOps);
export type NativeFieldElement = InstanceType<typeof NativeFieldElement>;

/** An element of the Jubjub scalar field */
export const JubjubScalarElement = createFieldElementClass(
  { tag: 'CurveField', curve: 'Jubjub', fieldType: 'Scalar' } as const,
  jubjubScalarOps,
);
export type JubjubScalarElement = InstanceType<typeof JubjubScalarElement>;

/** An element of the Jubjub base field */
export const JubjubBaseElement = createFieldElementClass(
  { tag: 'CurveField', curve: 'Jubjub', fieldType: 'Base' } as const,
  jubjubBaseOps,
);
export type JubjubBaseElement = InstanceType<typeof JubjubBaseElement>;

/** An element of the secp256k1 scalar field */
export const Secp256k1ScalarElement = createFieldElementClass(
  { tag: 'CurveField', curve: 'Secp256k1', fieldType: 'Scalar' } as const,
  secp256k1ScalarOps,
);
export type Secp256k1ScalarElement = InstanceType<typeof Secp256k1ScalarElement>;

/** An element of the secp256k1 base field */
export const Secp256k1BaseElement = createFieldElementClass(
  { tag: 'CurveField', curve: 'Secp256k1', fieldType: 'Base' } as const,
  secp256k1BaseOps,
);
export type Secp256k1BaseElement = InstanceType<typeof Secp256k1BaseElement>;

const a = NativePoint.create(1n, 2n);
const b = NativePoint.create(3n, 7n);
const c = a.add(b);

const d = BLS12381Point.create(1n, 2n);
const e = a.add(d);
