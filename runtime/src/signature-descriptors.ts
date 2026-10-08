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

import {
  CompactType,
  CompactTypeBoolean,
  CompactTypeBytes,
  CompactTypeCurve25519Base,
  CompactTypeCurve25519Point,
  CompactTypeCurve25519Scalar,
  CompactTypeEnum,
  CompactTypeField,
  CompactTypeJubjubPoint,
  CompactTypeJubjubScalar,
  CompactTypeOpaqueString,
  CompactTypeOpaqueUint8Array,
  CompactTypeSecp256k1Base,
  CompactTypeSecp256k1Point,
  CompactTypeSecp256k1Scalar,
  CompactTypeSecp256r1Base,
  CompactTypeSecp256r1Point,
  CompactTypeSecp256r1Scalar,
  CompactTypeStruct,
  CompactTypeTuple,
  CompactTypeUnsignedInteger,
  CompactTypeVector,
} from './compact-types.js';
import { CompactError } from './error.js';
import { SignatureType } from './interface-descriptor.js';

const bitLength = (n: bigint): number => (n === 0n ? 0 : n.toString(2).length);

/**
 * The number of bytes the compiler gives a `Uint` or an `Enum` whose largest value is `max`:
 * enough for its bits, and one even when `max` is zero.
 */
const byteLength = (max: bigint): number => Math.max(1, Math.ceil(bitLength(max) / 8));

/** The encoding the compiler gives the `Contract` tag: a contract reference is its address. */
const CONTRACT_ADDRESS_DESCRIPTOR = new CompactTypeStruct<{ bytes: Uint8Array }>([['bytes', new CompactTypeBytes(32)]]);

/**
 * The codec for values of a signature type, as the compiler would have emitted it into a module:
 * the same classes, widths and element order, therefore the same binary form. A party without the
 * module, such as a DApp encoding a call's arguments for a wallet, uses this in the module's place,
 * and the wallet decodes the bytes it receives with the same function.
 *
 * `Opaque` values are supported for the TypeScript types the compiler supports, `string` and
 * `Uint8Array`.
 */
export const descriptorOf = (type: SignatureType): CompactType<unknown> => {
  switch (type.tag) {
    case 'Boolean':
      return CompactTypeBoolean;
    case 'Field':
      return CompactTypeField;
    case 'JubjubScalar':
      return CompactTypeJubjubScalar;
    case 'JubjubPoint':
      return CompactTypeJubjubPoint;
    case 'Secp256k1Base':
      return CompactTypeSecp256k1Base;
    case 'Secp256k1Scalar':
      return CompactTypeSecp256k1Scalar;
    case 'Secp256k1Point':
      return CompactTypeSecp256k1Point;
    case 'Secp256r1Base':
      return CompactTypeSecp256r1Base;
    case 'Secp256r1Scalar':
      return CompactTypeSecp256r1Scalar;
    case 'Secp256r1Point':
      return CompactTypeSecp256r1Point;
    case 'Curve25519Base':
      return CompactTypeCurve25519Base;
    case 'Curve25519Scalar':
      return CompactTypeCurve25519Scalar;
    case 'Curve25519Point':
      return CompactTypeCurve25519Point;
    case 'Uint': {
      const max = BigInt(type.maxval);
      return new CompactTypeUnsignedInteger(max, byteLength(max));
    }
    case 'Bytes':
      return new CompactTypeBytes(type.length);
    case 'Opaque':
      switch (type.tsType) {
        case 'string':
          return CompactTypeOpaqueString;
        case 'Uint8Array':
          return CompactTypeOpaqueUint8Array;
        default:
          throw new CompactError(`opaque type ${type.tsType} is not supported`);
      }
    case 'Vector':
      return new CompactTypeVector(type.length, descriptorOf(type.type));
    case 'Tuple':
      return new CompactTypeTuple(type.types.map(descriptorOf));
    case 'Enum':
      return new CompactTypeEnum(type.elements.length - 1, byteLength(BigInt(type.elements.length - 1)));
    case 'Struct':
      return new CompactTypeStruct(type.elements.map((element) => [element.name, descriptorOf(element.type)] as const));
    // A nominal alias is a distinct type to the type checker and the same codec to the runtime.
    case 'Alias':
      return descriptorOf(type.type);
    case 'Contract':
      return CONTRACT_ADDRESS_DESCRIPTOR;
  }
};
