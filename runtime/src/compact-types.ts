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
import { CompactError } from './error.js';
import {
  MAX_SECP256K1_BASE,
  MAX_SECP256K1_SCALAR,
  MAX_SECP256R1_BASE,
  MAX_SECP256R1_SCALAR,
} from './constants.js';

/**
 * A runtime representation of a type in Compact
 */
export interface CompactType<A> {
  /**
   * The field-aligned binary alignment of this type.
   */
  alignment(): ocrt.Alignment;

  /**
   * Converts this type's TypeScript representation to its field-aligned binary
   * representation
   */
  toValue(value: A): ocrt.Value;

  /**
   * Converts this type's field-aligned binary representation to its TypeScript
   * representation destructively; (partially) consuming the input, and
   * ignoring superflous data for chaining.
   */
  fromValue(value: ocrt.Value): A;
}

/**
 * A point in the embedded elliptic curve. TypeScript representation of the
 * Compact type of the same name
 */
export interface JubjubPoint {
  readonly x: bigint;
  readonly y: bigint;
}

/**
 * A point in the foreign secp256k1 elliptic curve. TypeScript representation of the
 * Compact type of the same name.  When identity = true, x and y should be 0.
 */
export interface Secp256k1Point {
  readonly x: bigint;
  readonly y: bigint;
  readonly identity: boolean;
}

/**
 * A point in the foreign secp256r1 elliptic curve. TypeScript representation of the
 * Compact type of the same name.  When identity = true, x and y should be 0.
 */
export interface Secp256r1Point {
  readonly x: bigint;
  readonly y: bigint;
  readonly identity: boolean;
}

/**
 * Runtime type of {@link JubjubPoint}
 */
export const CompactTypeJubjubPoint: CompactType<JubjubPoint> = {
  alignment(): ocrt.Alignment {
    return [
      { tag: 'atom', value: { tag: 'field' } },
      { tag: 'atom', value: { tag: 'field' } },
    ];
  },
  fromValue(value: ocrt.Value): JubjubPoint {
    if (value.length < 2 || value[0] == undefined || value[1] == undefined) {
      throw new CompactError('expected JubjubPoint');
    }
    const coordinates = value.splice(0, 2);
    return {
      x: ocrt.valueToBigInt([coordinates[0]]),
      y: ocrt.valueToBigInt([coordinates[1]]),
    };
  },
  toValue(value: JubjubPoint): ocrt.Value {
    return ocrt.bigIntToValue(value.x).concat(ocrt.bigIntToValue(value.y));
  },
};

/**
 * Runtime type of {@link Secp256k1Point}
 */
export const CompactTypeSecp256k1Point: CompactType<Secp256k1Point> = {
  // One base containing the x cordinate
  // One base containing the y cordinate
  // One native field containing the identity flag
  alignment(): ocrt.Alignment {
    return CompactTypeSecp256k1Base.alignment()
      .concat(CompactTypeSecp256k1Base.alignment())
      .concat([{ tag: 'atom', value: { tag: 'field' } }]);
  },
  fromValue(value: ocrt.Value): Secp256k1Point {
    if (value.length < 5) {
      throw new CompactError('expected Secp256k1Point');
    }
    // This might throw CompactError('expected Secp256k1Base').
    const x = CompactTypeSecp256k1Base.fromValue(value);
    const y = CompactTypeSecp256k1Base.fromValue(value);
    const identity = value.shift();
    if (identity == undefined) {
      throw new CompactError('expected Secp256k1Point');
    }
    const flag = ocrt.valueToBigInt([identity]);
    if (flag != 0n && flag != 1n) {
      throw new CompactError('expected Secp256k1Point');
    }
    return { x: x, y: y, identity: flag === 1n };
  },
  toValue(value: Secp256k1Point): ocrt.Value {
    return CompactTypeSecp256k1Base.toValue(value.x)
      .concat(CompactTypeSecp256k1Base.toValue(value.y))
      .concat(ocrt.bigIntToValue(value.identity ? 1n : 0n));
  },
};

/**
 * Runtime type of {@link Secp256r1Point}
 */
export const CompactTypeSecp256r1Point: CompactType<Secp256r1Point> = {
  // One base containing the x cordinate
  // One base containing the y cordinate
  // One native field containing the identity flag
  alignment(): ocrt.Alignment {
    return CompactTypeSecp256r1Base.alignment()
      .concat(CompactTypeSecp256r1Base.alignment())
      .concat([{ tag: 'atom', value: { tag: 'field' } }]);
  },
  fromValue(value: ocrt.Value): Secp256r1Point {
    if (value.length < 5) {
      throw new CompactError('expected Secp256r1Point');
    }
    // This might throw CompactError('expected Secp256r1Base').
    const x = CompactTypeSecp256r1Base.fromValue(value);
    const y = CompactTypeSecp256r1Base.fromValue(value);
    const identity = value.shift();
    if (identity == undefined) {
      throw new CompactError('expected Secp256r1Point');
    }
    const flag = ocrt.valueToBigInt([identity]);
    if (flag != 0n && flag != 1n) {
      throw new CompactError('expected Secp256r1Point');
    }
    return { x: x, y: y, identity: flag === 1n };
  },
  toValue(value: Secp256r1Point): ocrt.Value {
    return CompactTypeSecp256r1Base.toValue(value.x)
      .concat(CompactTypeSecp256r1Base.toValue(value.y))
      .concat(ocrt.bigIntToValue(value.identity ? 1n : 0n));
  },
};

// These MerkleTree types and their descriptors are used by JS implementations
// of MerkleTree ledger operations.
/**
 * The hash value of a Merkle tree. TypeScript representation of the Compact
 * type of the same name
 */
export interface MerkleTreeDigest {
  readonly field: bigint;
}

/**
 * An entry in a Merkle path. TypeScript representation of the Compact type of
 * the same name.
 */
export interface MerkleTreePathEntry {
  readonly sibling: MerkleTreeDigest;
  readonly goes_left: boolean;
}

/**
 * A path demonstrating inclusion in a Merkle tree. TypeScript representation
 * of the Compact type of the same name.
 */
export interface MerkleTreePath<A> {
  readonly leaf: A;
  readonly path: MerkleTreePathEntry[];
}

/**
 * Runtime type of {@link MerkleTreeDigest}
 */
export const CompactTypeMerkleTreeDigest: CompactType<MerkleTreeDigest> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'field' } }];
  },
  fromValue(value: ocrt.Value): MerkleTreeDigest {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError('expected MerkleTreeDigest');
    } else {
      return { field: ocrt.valueToBigInt([val]) };
    }
  },
  toValue(value: MerkleTreeDigest): ocrt.Value {
    return ocrt.bigIntToValue(value.field);
  },
};

/**
 * Runtime type of {@link MerkleTreePathEntry}
 */
export const CompactTypeMerkleTreePathEntry: CompactType<MerkleTreePathEntry> = {
  alignment(): ocrt.Alignment {
    return CompactTypeMerkleTreeDigest.alignment().concat(CompactTypeBoolean.alignment());
  },
  fromValue(value: ocrt.Value): MerkleTreePathEntry {
    const sibling = CompactTypeMerkleTreeDigest.fromValue(value);
    const goes_left = CompactTypeBoolean.fromValue(value);
    return {
      sibling: sibling,
      goes_left: goes_left,
    };
  },
  toValue(value: MerkleTreePathEntry): ocrt.Value {
    return CompactTypeMerkleTreeDigest.toValue(value.sibling).concat(CompactTypeBoolean.toValue(value.goes_left));
  },
};

/**
 * Runtime type of {@link MerkleTreePath}
 */
export class CompactTypeMerkleTreePath<A> implements CompactType<MerkleTreePath<A>> {
  readonly leaf: CompactType<A>;
  readonly path: CompactTypeVector<MerkleTreePathEntry>;

  constructor(n: number, leaf: CompactType<A>) {
    this.leaf = leaf;
    this.path = new CompactTypeVector(n, CompactTypeMerkleTreePathEntry);
  }

  alignment(): ocrt.Alignment {
    return this.leaf.alignment().concat(this.path.alignment());
  }

  fromValue(value: ocrt.Value): MerkleTreePath<A> {
    const leaf = this.leaf.fromValue(value);
    const path = this.path.fromValue(value);
    return {
      leaf: leaf,
      path: path,
    };
  }

  toValue(value: MerkleTreePath<A>): ocrt.Value {
    return this.leaf.toValue(value.leaf).concat(this.path.toValue(value.path));
  }
}

/**
 * Runtime type of the builtin `Field` type
 */
export const CompactTypeField: CompactType<bigint> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'field' } }];
  },
  fromValue(value: ocrt.Value): bigint {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError('expected Field');
    } else {
      return ocrt.valueToBigInt([val]);
    }
  },
  toValue(value: bigint): ocrt.Value {
    return ocrt.bigIntToValue(value);
  },
};

// Implementation of foreign field values up to 32 bytes, encoded as the low 24
// bytes (3 64-bit "limbs") and the high 8 bytes (one64-bit "limb"), and where
// the encoded value has had 1 subtracted (in the field).
class ForeignField8_24 implements CompactType<bigint> {
  readonly max: bigint;
  readonly name: string;

  constructor(max: bigint, name: string) {
    this.max = max;
    this.name = name;
  }

  alignment(): ocrt.Alignment {
    // One native field containing the low-order 192 bits.
    // One native field containing the high-order 64 bits.
    return [
      { tag: 'atom', value: { tag: 'bytes', length: 24 } },
      { tag: 'atom', value: { tag: 'bytes', length: 8 } },
    ];
  }

  fromValue(value: ocrt.Value): bigint {
    if (value.length < 2 || value[0] == undefined || value[1] == undefined) {
      throw new CompactError(`expected ${this.name}`);
    }
    const limbs = value.splice(0, 2);
    const low192 = ocrt.valueToBigInt([limbs[0]]);
    const high64 = ocrt.valueToBigInt([limbs[1]]);
    if (low192 >= 1n << 192n) {
      throw new CompactError(`expected ${this.name}`);
    }
    let res = high64 << 192n | low192;
    // The ZKIR representation subtracts 1 from the value.
    res = (res == this.max) ? 0n : res + 1n;
    if (res > this.max) {
      throw new CompactError(`expected ${this.name}`);
    }
    return res;
  }

  toValue(value: bigint): ocrt.Value {
    if (value < 0n || value > this.max) {
      throw new CompactError(`expected ${this.name}`);
    }
    // The ZKIR representation subtracts 1 from the value.
    value = (value == 0n) ? this.max : value - 1n;
    return ocrt.bigIntToValue(value & ((1n << 192n) - 1n))
      .concat(ocrt.bigIntToValue(value >> 192n));
  }
}

/**
 * Runtime type of the standard library's `Secp256k1Base` type
 */
export const CompactTypeSecp256k1Base: CompactType<bigint> =
  new ForeignField8_24(MAX_SECP256K1_BASE, 'Secp256k1Base');

/**
 * Runtime type of the standard library's `Secp256k1Scalar` type
 */
export const CompactTypeSecp256k1Scalar: CompactType<bigint> =
  new ForeignField8_24(MAX_SECP256K1_SCALAR, 'Secp256k1Scalar');

/**
 * Runtime type of the standard library's `Secp256r1Base` type
 */
export const CompactTypeSecp256r1Base: CompactType<bigint> =
  new ForeignField8_24(MAX_SECP256R1_BASE, 'Secp256r1Base');

/**
 * Runtime type of the standard library's `Secp256r1Scalar` type
 */
export const CompactTypeSecp256r1Scalar: CompactType<bigint> =
  new ForeignField8_24(MAX_SECP256R1_SCALAR, 'Secp256r1Scalar');

/**
 * Runtime type of an enum with a given number of entries
 */
export class CompactTypeEnum implements CompactType<number> {
  readonly maxValue: number;
  readonly length: number;

  constructor(maxValue: number, length: number) {
    this.maxValue = maxValue;
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): number {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError(`expected Enum[<=${this.maxValue}]`);
    } else {
      let res = 0;
      for (let i = 0; i < val.length; i++) {
        res += (1 << (8 * i)) * val[i];
      }
      if (res > this.maxValue) {
        throw new CompactError(`expected Enum[<=${this.maxValue}]`);
      }
      return res;
    }
  }

  toValue(value: number): ocrt.Value {
    if (!Number.isInteger(value) || value < 0 || value > this.maxValue) {
      throw new CompactError(`expected Enum[<=${this.maxValue}]`);
    }
    return CompactTypeField.toValue(BigInt(value));
  }
}

/**
 * Runtime type of the builtin `Unsigned Integer` types
 */
export class CompactTypeUnsignedInteger implements CompactType<bigint> {
  readonly maxValue: bigint;
  readonly length: number;

  constructor(maxValue: bigint, length: number) {
    this.maxValue = maxValue;
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): bigint {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
    } else {
      let res = 0n;
      for (let i = 0; i < val.length; i++) {
        res += (1n << (8n * BigInt(i))) * BigInt(val[i]);
      }
      if (res > this.maxValue) {
        throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
      }
      return res;
    }
  }

  toValue(value: bigint): ocrt.Value {
    if (value < 0n || value > this.maxValue) {
      throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
    }
    return CompactTypeField.toValue(value);
  }
}

/**
 * Runtime type of the builtin `Vector` types
 */
export class CompactTypeVector<A> implements CompactType<A[]> {
  readonly length: number;
  readonly type: CompactType<A>;

  constructor(length: number, type: CompactType<A>) {
    this.length = length;
    this.type = type;
  }

  alignment(): ocrt.Alignment {
    const inner = this.type.alignment();
    let res: ocrt.Alignment = [];
    for (let i = 0; i < this.length; i++) {
      res = res.concat(inner);
    }
    return res;
  }

  fromValue(value: ocrt.Value): A[] {
    const res = [];
    for (let i = 0; i < this.length; i++) {
      res.push(this.type.fromValue(value));
    }
    return res;
  }

  toValue(value: A[]): ocrt.Value {
    if (value.length != this.length) {
      throw new CompactError(`expected ${this.length}-element array`);
    }
    let res: ocrt.Value = [];
    for (let i = 0; i < this.length; i++) {
      res = res.concat(this.type.toValue(value[i]));
    }
    return res;
  }
}

/**
 * Runtime type of the builtin `Boolean` type
 */
export const CompactTypeBoolean: CompactType<boolean> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: 1 } }];
  },
  fromValue(value: ocrt.Value): boolean {
    const val = value.shift();
    if (val == undefined || val.length > 1 || (val.length == 1 && val[0] != 1)) {
      throw new CompactError('expected Boolean');
    }
    return val.length == 1;
  },
  toValue(value: boolean): ocrt.Value {
    if (value) {
      return [new Uint8Array([1])];
    } else {
      return [new Uint8Array(0)];
    }
  },
};

/**
 * Runtime type of the builtin `Bytes` types
 */
export class CompactTypeBytes implements CompactType<Uint8Array> {
  readonly length: number;

  constructor(length: number) {
    this.length = length;
  }

  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: this.length } }];
  }

  fromValue(value: ocrt.Value): Uint8Array {
    const val = value.shift();
    if (val == undefined || val.length > this.length) {
      throw new CompactError(`expected Bytes[${this.length}]`);
    }
    // The atom belongs to the value we were handed, so copy it.
    // Otherwise, mutating the decoded bytes mutates what they came from.
    const res = new Uint8Array(this.length);
    res.set(val, 0);
    return res;
  }

  toValue(value: Uint8Array): ocrt.Value {
    if (value.length > this.length) {
      throw new CompactError(`expected Bytes[${this.length}]`);
    }
    let end = value.length;
    while (end > 0 && value[end - 1] == 0) {
      end -= 1;
    }
    return [value.slice(0, end)];
  }
}

/**
 * Runtime type of `Opaque["Uint8Array"]`
 */
export const CompactTypeOpaqueUint8Array: CompactType<Uint8Array> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'compress' } }];
  },
  fromValue(value: ocrt.Value): Uint8Array {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError("expected Opaque<'Uint8Array'>");
    }
    return val;
  },
  toValue(value: Uint8Array): ocrt.Value {
    return [value];
  },
};

/**
 * Runtime type of `Opaque["string"]`
 */
export const CompactTypeOpaqueString: CompactType<string> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'compress' } }];
  },
  fromValue(value: ocrt.Value): string {
    const val = value.shift();
    if (val == undefined) {
      throw new CompactError("expected Opaque<'string'>");
    }
    return new TextDecoder('utf-8').decode(val);
  },
  toValue(value: string): ocrt.Value {
    return [new TextEncoder().encode(value)];
  },
};

export function toBinaryRepr<A>(rtType: CompactType<A>, value: A): Uint8Array {
  const ocrtValue = rtType.toValue(value);
  const alignment = rtType.alignment();

  // 1. Accumulate Uint8Array pieces.
  const arrays = [];
  let length = 0;
  for (let i = 0; i < alignment.length; ++i) {
    const segment = alignment[i];
    if (segment.tag != 'atom') {
      // We are decoding our own FAB representation and we only use 'atom'.
      throw new CompactError(`unexpected segment tag ${segment.tag} in toBinaryRepr`);
    }
    switch (segment.value.tag) {
        // Compress atoms will be represented differently on-chain (as a Poseidon hash) and off (as
        // the unhashed payload).  There's no correct way to encode them here.
      case 'compress':
        throw new CompactError('cannot convert JS opaque values in toBinaryRepr');
      case 'field': {
        arrays.push(ocrtValue[i]);
        const extra = 32 - ocrtValue[i].length;
        if (extra > 0) {
          arrays.push(new Uint8Array(extra));
        }
        length += 32;
        break;
      }
      case 'bytes': {
        if (ocrtValue[i].length > 0) {
          arrays.push(ocrtValue[i]);
        }
        const extra = segment.value.length - ocrtValue[i].length;
        if (extra > 0) {
          arrays.push(new Uint8Array(extra));
        }
        length += segment.value.length;
        break;
      }
    }
  }

  // 2. Concatenate them into a result.
  const result = new Uint8Array(length);
  let index = 0;
  for (const a of arrays) {
    result.set(a, index);
    index += a.length;
  }
  return result;
}
