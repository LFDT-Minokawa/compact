// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { beforeAll, describe, expect, test } from 'vitest';
import { Arguments, buildPathTo, compile, createTempFolder, expectCompilerResult } from '@';
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { sha256 } from '@noble/hashes/sha2.js';

// TypeScript shapes of the runtime representations used by the generated circuits.
// A Secp256k1Point is an affine point; a Secp256k1Scalar is a bare bigint.
type Point = { x: bigint; y: bigint };
type Signature = { r: bigint; s: bigint };
// Ethereum-style recoverable signature: r, s, and the recovery id v.
type PkRecoverableSignature = Signature & { recovery: number };

// The exported circuits of examples/ecdsa/example_one.compact, as plain pure functions.
interface EcdsaPureCircuits {
    proveEthereumSignature(msg: Uint8Array, sig: Signature, pk: Point): boolean;
    proveBitcoinSignature(msg: Uint8Array, sig: Signature, pk: Point): boolean;
    ethereumAddress(pk: Point): Uint8Array;
    // A Secp256k1Scalar is a bare bigint at runtime.
    scalarMul(x: bigint, y: bigint): bigint;
}

// The two moduli that the scalar multiply must NOT confuse:
//   n - the secp256k1 group order (SECP256K1_SCALAR_MODULUS), the correct modulus.
//   r - the proof system's BLS12-381 scalar field (FIELD_MODULUS), used by mulField.
const SECP256K1_SCALAR_MODULUS = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;
const BLS12_381_FIELD_MODULUS = 0x73eda753299d7d483339d80809a1d80553bda402fffe5bfeffffffff00000001n;

const EXAMPLE = buildPathTo('ecdsa/example_one.compact');

describe('[ECDSA] examples/ecdsa/example_one.compact', () => {
    let pureCircuits: EcdsaPureCircuits;

    // A single key pair, reused across the cases.
    const sk = secp256k1.utils.randomSecretKey();
    const pubAffine = secp256k1.Point.fromBytes(secp256k1.getPublicKey(sk)).toAffine();
    const pk: Point = { x: pubAffine.x, y: pubAffine.y };

    // Sign a (already hashed) digest, returning r, s, and the recovery id v.
    function sign(digest: Uint8Array): PkRecoverableSignature {
        const sig = secp256k1.Signature.fromBytes(
            secp256k1.sign(digest, sk, { format: 'recovered', prehash: false }),
            'recovered',
        );
        return { r: sig.r, s: sig.s, recovery: sig.recovery! };
    }

    // Recover the public key off-circuit from the same inputs Ethereum's
    // ecrecover takes: the message hash, r, s, and the recovery id v.
    function recoverPk(digest: Uint8Array, sig: PkRecoverableSignature): Point {
        const p = new secp256k1.Signature(sig.r, sig.s, sig.recovery).recoverPublicKey(digest).toAffine();
        return { x: p.x, y: p.y };
    }

    // Ethereum signs keccak256(msg); Bitcoin signs sha256(msg).
    const ethMsg = new Uint8Array(32).fill(0xab);
    const ethSig = sign(keccak_256(ethMsg));
    const btcMsg = new Uint8Array(32).fill(0xcd);
    const btcSig = sign(sha256(btcMsg));

    // Tamper helper: bump s so the signature no longer verifies.
    const tamper = (sig: Signature): Signature => ({ r: sig.r, s: sig.s + 1n });

    beforeAll(async () => {
        const outputDir = createTempFolder();
        const result = await compile([Arguments.FEATURE_V3, EXAMPLE, outputDir]);
        expectCompilerResult(result).toCompileWithoutErrors();
        ({ pureCircuits } = (await import(`${outputDir}contract/index.js`)) as { pureCircuits: EcdsaPureCircuits });
    }, 180_000);

    test('proveEthereumSignature accepts a valid signature [WIP gates]', () => {
        expect(pureCircuits.proveEthereumSignature(ethMsg, { r: ethSig.r, s: ethSig.s }, pk)).toBe(true);
    });

    test('proveEthereumSignature rejects a tampered signature', () => {
        expect(pureCircuits.proveEthereumSignature(ethMsg, tamper(ethSig), pk)).toBe(false);
    });

    test('proveBitcoinSignature accepts a valid signature [WIP gates]', () => {
        expect(pureCircuits.proveBitcoinSignature(btcMsg, { r: btcSig.r, s: btcSig.s }, pk)).toBe(true);
    });

    test('proveBitcoinSignature rejects a tampered signature', () => {
        expect(pureCircuits.proveBitcoinSignature(btcMsg, tamper(btcSig), pk)).toBe(false);
    });

    test('off-circuit recovery yields the signing public key', () => {
        const recovered = recoverPk(keccak_256(ethMsg), ethSig);
        expect(recovered.x).toBe(pk.x);
        expect(recovered.y).toBe(pk.y);
    });

    test('ethereumAddress hashes a recovered public key to 20 bytes [WIP gates]', () => {
        const recovered = recoverPk(keccak_256(ethMsg), ethSig);
        const address = pureCircuits.ethereumAddress(recovered);
        expect(address).toBeInstanceOf(Uint8Array);
        expect(address.length).toBe(20);
    });

    test('scalarMul reduces modulo the secp256k1 group order n, not the BLS field modulus', () => {
        // Two large scalars whose product wraps differently under n vs. the BLS
        // field modulus, so the test distinguishes the correct reduction.
        const x = SECP256K1_SCALAR_MODULUS - 2n;
        const y = SECP256K1_SCALAR_MODULUS - 12345n;
        const product = x * y;

        const got = pureCircuits.scalarMul(x, y);
        // Correct: (n - 2)(n - 12345) === (-2)(-12345) === 24690 (mod n).
        expect(got).toBe(product % SECP256K1_SCALAR_MODULUS);
        expect(got).toBe(24690n);
        // Regression guard: a `*`-style lowering would reduce mod the BLS field
        // modulus and produce a different value.
        expect(got).not.toBe(product % BLS12_381_FIELD_MODULUS);
    });

    test('scalarMul wraps (n - 1)^2 to 1 modulo n', () => {
        const nMinus1 = SECP256K1_SCALAR_MODULUS - 1n;
        expect(pureCircuits.scalarMul(nMinus1, nMinus1)).toBe(1n);
    });
});
