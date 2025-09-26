import * as ocrt from '@midnight-ntwrk/onchain-runtime';
import { CompactError } from './error';
import type { EncodedShieldedCoinInfo, EncodedCoinPublicKey, EncodedContractAddress, EncodedRecipient } from './zswap';

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
 * A point in the embedded elliptic curve. TypeScript representation of the
 * Compact type of the same name
 */
export interface CurvePoint {
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
 * Runtime type of the builtin `Boolean` type
 */
export const CompactTypeBoolean: CompactType<boolean> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'bytes', length: 1 } }];
  },
  fromValue(value: ocrt.Value): boolean {
    const val = value.shift();
    if (val === undefined || val.length > 1 || (val.length === 1 && val[0] !== 1)) {
      throw new CompactError('expected Boolean');
    }
    return val.length === 1;
  },
  toValue(value: boolean): ocrt.Value {
    if (value) {
      return [new Uint8Array([1])];
    }
    return [new Uint8Array(0)];
  },
};

/**
 * Runtime type of the builtin `Field` type
 */
export const CompactTypeField: CompactType<bigint> = {
  alignment(): ocrt.Alignment {
    return [{ tag: 'atom', value: { tag: 'field' } }];
  },
  fromValue(value: ocrt.Value): bigint {
    const val = value.shift();
    if (val === undefined) {
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
 * Runtime type of {@link CurvePoint}
 */
export const CompactTypeCurvePoint: CompactType<CurvePoint> = {
  alignment(): ocrt.Alignment {
    return [
      { tag: 'atom', value: { tag: 'field' } },
      { tag: 'atom', value: { tag: 'field' } },
    ];
  },
  fromValue(value: ocrt.Value): CurvePoint {
    const x = value.shift();
    const y = value.shift();
    if (x === undefined || y === undefined) {
      throw new CompactError('expected CurvePoint');
    } else {
      return {
        x: ocrt.valueToBigInt([x]),
        y: ocrt.valueToBigInt([y]),
      };
    }
  },
  toValue(value: CurvePoint): ocrt.Value {
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
    if (val === undefined) {
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
      sibling,
      goes_left,
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
      leaf,
      path,
    };
  }

  toValue(value: MerkleTreePath<A>): ocrt.Value {
    return this.leaf.toValue(value.leaf).concat(this.path.toValue(value.path));
  }
}

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
    if (val === undefined) {
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
    if (val === undefined) {
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
    if (value.length !== this.length) {
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
    if (val === undefined || val.length > this.length) {
      throw new CompactError(`expected Bytes[${this.length}]`);
    }
    if (val.length === this.length) {
      return val;
    }
    const res = new Uint8Array(this.length);
    res.set(val, 0);
    return res;
  }

  toValue(value: Uint8Array): ocrt.Value {
    let end = value.length;
    while (end > 0 && value[end - 1] === 0) {
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
 * Runtime type of `Bytes[32]`
 */
export const CompactTypeBytes32 = new CompactTypeBytes(32);

/**
 * Runtime type of maximum `Unsigned Integer[18446744073709551615]`
 */
export const CompactTypeUInt64 = new CompactTypeUnsignedInteger(18446744073709551615n, 8);

/**
 * Runtime type of maximum `Unsigned Integer[255]`
 */
export const CompactTypeUInt8 = new CompactTypeUnsignedInteger(255n, 1);

/**
 * Runtime type of `CoinInfo` from the Compact standard library
 */
export const CompactTypeCoinInfo: CompactType<EncodedShieldedCoinInfo> = {
  alignment(): ocrt.Alignment {
    return CompactTypeBytes32.alignment().concat(CompactTypeBytes32.alignment().concat(CompactTypeUInt64.alignment()));
  },
  fromValue(value: ocrt.Value): EncodedShieldedCoinInfo {
    return {
      nonce: CompactTypeBytes32.fromValue(value),
      color: CompactTypeBytes32.fromValue(value),
      value: CompactTypeUInt64.fromValue(value),
    };
  },
  toValue(value: EncodedShieldedCoinInfo): ocrt.Value {
    return CompactTypeBytes32.toValue(value.nonce).concat(
      CompactTypeBytes32.toValue(value.color).concat(CompactTypeUInt64.toValue(value.value)),
    );
  },
};

/**
 * Runtime type of `ZswapCoinPublicKey` from the Compact standard library
 */
export const CompactTypeZswapCoinPublicKey: CompactType<EncodedCoinPublicKey> = {
  alignment(): ocrt.Alignment {
    return CompactTypeBytes32.alignment();
  },
  fromValue(value: ocrt.Value): EncodedCoinPublicKey {
    return {
      bytes: CompactTypeBytes32.fromValue(value),
    };
  },
  toValue(value: EncodedCoinPublicKey): ocrt.Value {
    return CompactTypeBytes32.toValue(value.bytes);
  },
};

/**
 * Runtime type of `ContractAddress` from the Compact standard library
 */
export const CompactTypeContractAddress: CompactType<EncodedContractAddress> = {
  alignment(): ocrt.Alignment {
    return CompactTypeBytes32.alignment();
  },
  fromValue(value: ocrt.Value): EncodedContractAddress {
    return {
      bytes: CompactTypeBytes32.fromValue(value),
    };
  },
  toValue(value: EncodedContractAddress): ocrt.Value {
    return CompactTypeBytes32.toValue(value.bytes);
  },
};

/**
 * Runtime type of `CoinInfo` from the Compact standard library
 */
export const CompactTypeRecipient: CompactType<EncodedRecipient> = {
  alignment(): ocrt.Alignment {
    return CompactTypeBoolean.alignment().concat(
      CompactTypeZswapCoinPublicKey.alignment().concat(CompactTypeContractAddress.alignment()),
    );
  },
  fromValue(value: ocrt.Value): EncodedRecipient {
    return {
      is_left: CompactTypeBoolean.fromValue(value),
      left: CompactTypeZswapCoinPublicKey.fromValue(value),
      right: CompactTypeContractAddress.fromValue(value),
    };
  },
  toValue(value: EncodedRecipient): ocrt.Value {
    return CompactTypeBoolean.toValue(value.is_left).concat(
      CompactTypeZswapCoinPublicKey.toValue(value.left).concat(CompactTypeContractAddress.toValue(value.right)),
    );
  },
};
