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
import * as runtime from '@midnight-ntwrk/compact-runtime';

// TypeScript shapes of the runtime representations used by the generated circuits.
type Signature = { r: bigint; s: bigint };
// Ethereum-style recoverable signature: r, s, and the recovery id v.
type PkRecoverableSignature = Signature & { recovery: number };

const EXAMPLE = buildPathTo('ecdsa/example_one.compact');

describe('[ECDSA] examples/ecdsa/example_one.compact', () => {
    let pureCircuits;

    // A single key pair, reused across the cases.
    const sk = secp256k1.utils.randomSecretKey();
    const pubAffine = secp256k1.Point.fromBytes(secp256k1.getPublicKey(sk)).toAffine();
    const pk: runtime.Secp256k1Point = { x: pubAffine.x, y: pubAffine.y, identity: false };

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
    function recoverPk(digest: Uint8Array, sig: PkRecoverableSignature): runtime.Secp256k1Point {
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
        ({ pureCircuits } = (await import(`${outputDir}contract/index.js`)) as { pureCircuits });
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

    test('secp256k1EthereumAddress hashes a recovered public key to 20 bytes [WIP gates]', () => {
        const recovered = recoverPk(keccak_256(ethMsg), ethSig);
        const address = pureCircuits.secp256k1EthereumAddress(recovered);
        expect(address).toBeInstanceOf(Uint8Array);
        expect(address.length).toBe(20);
    });

    test('secp256k1EthereumAddress rejects the point at infinity', () => {
        // The identity has no Ethereum address, and its coordinates are
        // unconstrained, so the circuit must reject it via its identity flag.
        const identity: runtime.Secp256k1Point = { x: 0n, y: 0n, identity: true };
        expect(() => pureCircuits.secp256k1EthereumAddress(identity)).toThrow();
    });

    test('secp256k1EthereumAddress can recover a known Ethereum address', () => {
      // A public key and (case insensitive) address from a random private key
      // (secp256k1 scalar), generated by
      // https://www.rfctools.com/ethereum-address-test-tool/.
      const pk: runtime.Secp256k1Point = {
          x: 0xd06cae31b20a8c528186917358a5eceac665029d8afc30eee8e3abaa5a24e9ean,
          y: 0x9cd8a23f97228ae2f1cb89cc93530783ac6970f2af443e5a87da50c835984f06n,
          identity: false,
      };
      const expected = new Uint8Array([
          0x3d, 0x81, 0xac, 0x81, 0x76, 0x4e, 0xb1, 0xa4, 0x4a, 0xfb,
          0xc2, 0x45, 0xfc, 0x1d, 0x92, 0x54, 0xc0, 0xd0, 0x77, 0x2a,
      ]);
      expect(pureCircuits.secp256k1EthereumAddress(pk)).toEqual(expected);
    });

    test('mul reduces modulo the secp256k1 group order n, not the BLS field modulus', () => {
        // Two large scalars whose product wraps differently under n vs. the BLS
        // field modulus, so the test distinguishes the correct reduction.
        const x = runtime.SECP256K1_SCALAR_MODULUS - 2n;
        const y = runtime.SECP256K1_SCALAR_MODULUS - 12345n;
        const product = x * y;

        const got = pureCircuits.scalarMul(x, y);
        // Correct: (n - 2)(n - 12345) === (-2)(-12345) === 24690 (mod n).
        expect(got).toBe(product % runtime.SECP256K1_SCALAR_MODULUS);
        expect(got).toBe(24690n);
        // Regression guard: a `*`-style lowering would reduce mod the BLS field
        // modulus and produce a different value.
        expect(got).not.toBe(product % runtime.FIELD_MODULUS);
    });

    test('scalarMul wraps (n - 1)^2 to 1 modulo n', () => {
        const nMinus1 = runtime.SECP256K1_SCALAR_MODULUS - 1n;
        expect(pureCircuits.scalarMul(nMinus1, nMinus1)).toBe(1n);
    });
});
