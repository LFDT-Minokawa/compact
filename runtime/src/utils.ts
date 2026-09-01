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
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { p256 } from '@noble/curves/nist.js';
import { ContractAddress } from '@midnightntwrk/onchain-runtime-v4';
import { EncodedContractAddress } from './zswap.js';
import { CompactError } from './error.js';
import {
  CompactType,
  CompactTypeJubjubPoint,
  JubjubPoint,
  Secp256k1Point,
  Secp256r1Point,
} from './compact-types.js';
import { convertNumericToJubjubScalar } from './casts.js';
import { ecAdd, ecMul, ecMulGenerator } from './built-ins.js';

/**
 * Regex matching hex strings of even length.
 */
export const HEX_REGEX_NO_PREFIX = /^([0-9A-Fa-f]{2})*$/;

/**
 * The expected length (in bytes) of a contract address.
 */
export const CONTRACT_ADDRESS_BYTE_LENGTH = 32;

/**
 * Tests whether the input value is a {@link ContractAddress}, i.e., string.
 *
 * @param x The value that is tested to be a {@link ContractAddress}.
 */
export function isContractAddress(x: unknown): x is ContractAddress {
  return typeof x === 'string' && x.length === CONTRACT_ADDRESS_BYTE_LENGTH * 2 && HEX_REGEX_NO_PREFIX.test(x);
}

export function assertIsContractAddress(x: unknown): asserts x is ContractAddress {
  if (!isContractAddress(x)) {
    throw new CompactError(`Value ${x} is not a contract address`);
  }
}

export function isEncodedContractAddress(x: unknown): x is EncodedContractAddress {
  return (
    typeof x === 'object' &&
    x !== null &&
    x !== undefined &&
    'bytes' in x &&
    x.bytes instanceof Uint8Array &&
    x.bytes.length == CONTRACT_ADDRESS_BYTE_LENGTH
  );
}

export const fromHex = (s: string): Uint8Array => Buffer.from(s, 'hex');

export const toHex = (s: Uint8Array): string => Buffer.from(s).toString('hex');


/**
 * Lift the simple affine `Secp256k1Point` representation into a noble-curves
 * projective point. Identity maps to `Point.ZERO`; every other input is validated
 * to lie on the curve by `fromAffine`.
 */
export function secp256k1ToProjective(p: Secp256k1Point): ReturnType<typeof secp256k1.Point.fromAffine> {
  if (p.identity) {
    return secp256k1.Point.ZERO;
  }
  return secp256k1.Point.fromAffine({ x: p.x, y: p.y });
}

/**
 * Project a noble-curves point back down to the simple affine
 * `Secp256k1Point` representation.
 */
export function secp256k1FromProjective(p: ReturnType<typeof secp256k1.Point.fromAffine>): Secp256k1Point {
  const k = p.toAffine();
  if (/* k == secp256k1.Point.ZERO */ k.x == 0n && k.y == 0n) {
    return { x: 0n, y: 0n, identity: true };
  } else {
    const { x, y } = k;
    return { x: x, y: y, identity: false };
  }
}

/**
 * Lift the simple affine `Secp256r1Point` representation into a noble-curves
 * projective point. Identity maps to `Point.ZERO`; every other input is validated
 * to lie on the curve by `fromAffine`.
 */
export function secp256r1ToProjective(p: Secp256r1Point): ReturnType<typeof p256.Point.fromAffine> {
  if (p.identity) {
    return p256.Point.ZERO;
  }
  return p256.Point.fromAffine({ x: p.x, y: p.y });
}

/**
 * Project a noble-curves point back down to the simple affine
 * `Secp256r1Point` representation.
 */
export function secp256r1FromProjective(p: ReturnType<typeof p256.Point.fromAffine>): Secp256r1Point {
  const k = p.toAffine();
  if (/* k == p256.Point.ZERO */ k.x == 0n && k.y == 0n) {
    return { x: 0n, y: 0n, identity: true };
  } else {
    const { x, y } = k;
    return { x: x, y: y, identity: false };
  }
}

/**
 * Recover the secp256k1 public key from an ECDSA signature and a message hash.
 *
 * ## Recovery ID
 * - bit 0 (`recoveryId & 1`) is the parity of `R.y`: 0 for even, 1 for odd.
 * - bit 1 (`recoveryId >= 2`) says whether the reduction wrapped, i.e. whether
 *   `R.x` is `r` (0, 1) or `r + n` (2, 3).
 *
 * - 0: `R = (r, y)` with `y` even — the common case.
 * - 1: `R = (r, y)` with `y` odd — the other common case.
 * - 2: `R = (r + n, y)` with `y` even.
 * - 3: `R = (r + n, y)` with `y` odd.
 */
export function secp256k1EcdsaRecover(
  msgHash: Uint8Array,
  sig: { readonly r: bigint; readonly s: bigint },
  recoveryId: number,
): Secp256k1Point {
  if (msgHash.length !== 32) {
    throw new CompactError('expected a 32-byte message hash');
  }
  if (!Number.isInteger(recoveryId) || recoveryId < 0 || recoveryId > 3) {
    throw new CompactError('expected a recovery id in the range [0, 3]');
  }
  const nobleSig = new secp256k1.Signature(sig.r, sig.s, recoveryId);
  return secp256k1FromProjective(nobleSig.recoverPublicKey(msgHash));
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
 * A Schnorr signature over the JubJub curve. TypeScript representation of the
 * Compact type of the same name.
 */
export interface JubjubSchnorrSignature {
  readonly announcement: JubjubPoint;
  readonly response: bigint;
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
