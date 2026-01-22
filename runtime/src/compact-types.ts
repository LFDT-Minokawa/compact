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
import { CompactError } from './error.js';

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
export interface NativePoint {
  readonly x: bigint;
  readonly y: bigint;
}

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
 * The recipient of a coin produced by a circuit.
 */
export interface Recipient {
  /**
   * Whether the recipient is a user or a contract.
   */
  readonly is_left: boolean;
  /**
   * The recipient's public key, if the recipient is a user.
   */
  readonly left: ocrt.CoinPublicKey;
  /**
   * The recipient's contract address, if the recipient is a contract.
   */
  readonly right: ocrt.ContractAddress;
}

/**
 * Runtime type of {@link NativePoint}
 */
export const CompactTypeNativePoint: CompactType<NativePoint> = {
  alignment(): ocrt.Alignment {
    return [
      { tag: 'atom', value: { tag: 'field' } },
      { tag: 'atom', value: { tag: 'field' } },
    ];
  },
  fromValue(value: ocrt.Value): NativePoint {
    const x = value.shift();
    const y = value.shift();
    if (x == undefined || y == undefined) {
      throw new CompactError('expected NativePoint');
    } else {
      return {
        x: ocrt.valueToBigInt([x]),
        y: ocrt.valueToBigInt([y]),
      };
    }
  },
  toValue(value: NativePoint): ocrt.Value {
    return ocrt.bigIntToValue(value.x).concat(ocrt.bigIntToValue(value.y));
  },
};

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
        throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
      }
      return res;
    }
  }

  toValue(value: number): ocrt.Value {
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
    if (val.length == this.length) {
      return val;
    }
    const res = new Uint8Array(this.length);
    res.set(val, 0);
    return res;
  }

  toValue(value: Uint8Array): ocrt.Value {
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
    return value.shift() as Uint8Array;
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
    return new TextDecoder('utf-8').decode(value.shift());
  },
  toValue(value: string): ocrt.Value {
    return [new TextEncoder().encode(value)];
  },
};

/**
 * The following are type descriptors used to implement {@link createCoinCommitment}. They are not intended for direct
 * consumption.
 */

export const Bytes32Descriptor = new CompactTypeBytes(32);

export const MaxUint8Descriptor = new CompactTypeUnsignedInteger(18446744073709551615n, 8);

export const ShieldedCoinInfoDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment().concat(Bytes32Descriptor.alignment().concat(MaxUint8Descriptor.alignment()));
  },
  fromValue(value: ocrt.Value): { nonce: Uint8Array; color: Uint8Array; value: bigint } {
    return {
      nonce: Bytes32Descriptor.fromValue(value),
      color: Bytes32Descriptor.fromValue(value),
      value: MaxUint8Descriptor.fromValue(value),
    };
  },
  toValue(value: { nonce: Uint8Array; color: Uint8Array; value: bigint }): ocrt.Value {
    return Bytes32Descriptor.toValue(value.nonce).concat(
      Bytes32Descriptor.toValue(value.color).concat(MaxUint8Descriptor.toValue(value.value)),
    );
  },
};

export const ZswapCoinPublicKeyDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment();
  },
  fromValue(value: ocrt.Value): { bytes: Uint8Array } {
    return {
      bytes: Bytes32Descriptor.fromValue(value),
    };
  },
  toValue(value: { bytes: Uint8Array }): ocrt.Value {
    return Bytes32Descriptor.toValue(value.bytes);
  },
};

export const ContractAddressDescriptor = {
  alignment(): ocrt.Alignment {
    return Bytes32Descriptor.alignment();
  },
  fromValue(value: ocrt.Value): { bytes: Uint8Array } {
    return {
      bytes: Bytes32Descriptor.fromValue(value),
    };
  },
  toValue(value: { bytes: Uint8Array }): ocrt.Value {
    return Bytes32Descriptor.toValue(value.bytes);
  },
};

export const ShieldedCoinRecipientDescriptor = {
  alignment(): ocrt.Alignment {
    return CompactTypeBoolean.alignment().concat(
      ZswapCoinPublicKeyDescriptor.alignment().concat(ContractAddressDescriptor.alignment()),
    );
  },
  fromValue(value: ocrt.Value): { is_left: boolean; left: { bytes: Uint8Array }; right: { bytes: Uint8Array } } {
    return {
      is_left: CompactTypeBoolean.fromValue(value),
      left: ZswapCoinPublicKeyDescriptor.fromValue(value),
      right: ContractAddressDescriptor.fromValue(value),
    };
  },
  toValue(value: { is_left: boolean; left: { bytes: Uint8Array }; right: { bytes: Uint8Array } }): ocrt.Value {
    return CompactTypeBoolean.toValue(value.is_left).concat(
      ZswapCoinPublicKeyDescriptor.toValue(value.left).concat(ContractAddressDescriptor.toValue(value.right)),
    );
  },
};
