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

import { describe, expect, test } from 'vitest';
import * as runtime from '../src/index.js';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { utf8ToBytes } from '@noble/hashes/utils.js';

// The secp256k1 generator and the group identity (point at infinity, encoded
// as the affine pair (0, 0)).
const G: runtime.Secp256k1Point = {
  x: 55066263022277343669578718895168534326250603453777594175500187360389116729240n,
  y: 32670510020758816978083085130507043184471273380659243275938904335757337482424n,
  identity: false,
};
const IDENTITY: runtime.Secp256k1Point = { x: 0n, y: 0n, identity: true };

describe('secp256k1 group operations', () => {
  test('mulGenerator matches the generator and the identity', () => {
    expect(runtime.secp256k1MulGenerator(1n)).toEqual(G);
    expect(runtime.secp256k1MulGenerator(0n)).toEqual(IDENTITY);
  });

  test('add, mul and mulGenerator agree on doubling', () => {
    const twoG = runtime.secp256k1MulGenerator(2n);
    expect(runtime.secp256k1Add(G, G)).toEqual(twoG);
    expect(runtime.secp256k1Mul(G, 2n)).toEqual(twoG);
  });

  test('the identity is an additive unit and a zero scalar annihilates', () => {
    expect(runtime.secp256k1Add(G, IDENTITY)).toEqual(G);
    expect(runtime.secp256k1Mul(G, 0n)).toEqual(IDENTITY);
  });
});

describe('secp256k1 scalar field operations', () => {
  const N = runtime.SECP256K1_SCALAR_MODULUS;
  const a = 123456789n;
  const b = N - 7n;

  test('add reduces modulo the scalar modulus', () => {
    expect(runtime.secp256k1ScalarAdd(a, b)).toEqual((a + b) % N);
    expect(runtime.secp256k1ScalarAdd(a, N - a)).toEqual(0n);
  });

  test('neg is the additive inverse', () => {
    expect(runtime.secp256k1ScalarAdd(a, runtime.secp256k1ScalarNeg(a))).toEqual(0n);
    expect(runtime.secp256k1ScalarNeg(0n)).toEqual(0n);
  });

  test('mul reduces modulo the scalar modulus', () => {
    expect(runtime.secp256k1ScalarMul(a, b)).toEqual((a * b) % N);
  });

  test('inv is the multiplicative inverse', () => {
    expect(runtime.secp256k1ScalarMul(a, runtime.secp256k1ScalarInv(a))).toEqual(1n);
  });
});

describe('secp256k1 base field operations', () => {
  const P = runtime.SECP256K1_BASE_MODULUS;
  const a = 987654321n;
  const b = P - 11n;

  test('add reduces modulo the base modulus', () => {
    expect(runtime.secp256k1BaseAdd(a, b)).toEqual((a + b) % P);
    expect(runtime.secp256k1BaseAdd(a, P - a)).toEqual(0n);
  });

  test('neg is the additive inverse', () => {
    expect(runtime.secp256k1BaseAdd(a, runtime.secp256k1BaseNeg(a))).toEqual(0n);
    expect(runtime.secp256k1BaseNeg(0n)).toEqual(0n);
  });

  test('mul reduces modulo the base modulus', () => {
    expect(runtime.secp256k1BaseMul(a, b)).toEqual((a * b) % P);
  });

  test('inv is the multiplicative inverse', () => {
    expect(runtime.secp256k1BaseMul(a, runtime.secp256k1BaseInv(a))).toEqual(1n);
  });
});

describe('secp256k1 ECDSA public key recovery', () => {
  // Signing is RFC 6979 deterministic and low-s normalised, so every run
  // produces the same signature and a failure is reproducible.
  const SK = 7n;
  const MESSAGE = 'compact ecrecover test vector';

  const digest = keccak_256(utf8ToBytes(MESSAGE));
  // `recovered` format is the recovery byte followed by r and s.
  const sigBytes = secp256k1.sign(digest, secp256k1.Point.Fn.toBytes(SK), {
    prehash: false,
    format: 'recovered',
  });
  const recoveryId = sigBytes[0];
  const parsed = secp256k1.Signature.fromBytes(sigBytes, 'recovered');
  const sig: runtime.Secp256k1EcdsaSignature = { r: parsed.r, s: parsed.s };
  // The signer's public key, SK*G.
  const pk = runtime.secp256k1MulGenerator(SK);

  test('recovers the signing public key from a known signature', () => {
    expect(runtime.secp256k1EcdsaRecover(digest, sig, recoveryId)).toEqual(pk);
  });

  test('the recovered key agrees with scalar multiplication of the generator', () => {
    expect(runtime.secp256k1EcdsaRecover(digest, sig, recoveryId)).toEqual(runtime.secp256k1MulGenerator(SK));
  });

  test('the other recovery id selects a different candidate key', () => {
    const other = runtime.secp256k1EcdsaRecover(digest, sig, recoveryId ^ 1);
    expect(other).not.toEqual(pk);
  });

  const N = runtime.SECP256K1_SCALAR_MODULUS;
  const highS: runtime.Secp256k1EcdsaSignature = { r: sig.r, s: N - sig.s };

  test('the signature under test is the low-s representative', () => {
    expect(sig.s <= N / 2n).toBe(true);
    expect(highS.s > N / 2n).toBe(true);
  });

  test('accepts high-s and recovers the same key when the id is flipped', () => {
    expect(runtime.secp256k1EcdsaRecover(digest, highS, recoveryId ^ 1)).toEqual(pk);
  });

  test('negating s without flipping the id recovers a different key', () => {
    expect(runtime.secp256k1EcdsaRecover(digest, highS, recoveryId)).not.toEqual(pk);
  });

  test('rejects a message hash that is not 32 bytes', () => {
    expect(() => runtime.secp256k1EcdsaRecover(digest.slice(0, 31), sig, recoveryId)).toThrow(runtime.CompactError);
    expect(() => runtime.secp256k1EcdsaRecover(new Uint8Array(33), sig, recoveryId)).toThrow(runtime.CompactError);
  });

  test('rejects a recovery id outside [0, 3]', () => {
    expect(() => runtime.secp256k1EcdsaRecover(digest, sig, -1)).toThrow(runtime.CompactError);
    expect(() => runtime.secp256k1EcdsaRecover(digest, sig, 4)).toThrow(runtime.CompactError);
    expect(() => runtime.secp256k1EcdsaRecover(digest, sig, 1.5)).toThrow(runtime.CompactError);
  });

  test('rejects r and s outside the scalar field', () => {
    const N = runtime.SECP256K1_SCALAR_MODULUS;
    expect(() => runtime.secp256k1EcdsaRecover(digest, { r: 0n, s: sig.s }, recoveryId)).toThrow();
    expect(() => runtime.secp256k1EcdsaRecover(digest, { r: sig.r, s: 0n }, recoveryId)).toThrow();
    expect(() => runtime.secp256k1EcdsaRecover(digest, { r: N, s: sig.s }, recoveryId)).toThrow();
    expect(() => runtime.secp256k1EcdsaRecover(digest, { r: sig.r, s: N }, recoveryId)).toThrow();
  });
});
