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
import { secp256k1 } from '@noble/curves/secp256k1';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { sha256 } from '@noble/hashes/sha256.js';
import * as runtime from '../src/index.js';

const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

interface NobleSignature {
  readonly r: bigint;
  readonly s: bigint;
  readonly recovery?: number;
  recoverPublicKey(msgHash: Uint8Array): { readonly x: bigint; readonly y: bigint };
}

const PRIV_KEY = secp256k1.utils.randomPrivateKey();
const PUB_KEY_POINT = secp256k1.ProjectivePoint.fromPrivateKey(PRIV_KEY);

// Ethereum: keccak256(msg)
const ETH_MSG = new Uint8Array(32).fill(0xab);
const ETH_MSG_HASH = keccak_256(ETH_MSG);
const ETH_SIG: NobleSignature = secp256k1.sign(ETH_MSG_HASH, PRIV_KEY);

// Bitcoin: sha256(msg)
const BTC_MSG = new Uint8Array(32).fill(0xcd);
const BTC_MSG_HASH = sha256(BTC_MSG);
const BTC_SIG: NobleSignature = secp256k1.sign(BTC_MSG_HASH, PRIV_KEY);

function toSecp256k1Point(pt: { x: bigint; y: bigint }): runtime.Secp256k1Point {
  return { x: pt.x, y: pt.y };
}

function toSecp256k1Sig(sig: { r: bigint; s: bigint }): runtime.Secp256k1EcdsaSignature {
  return { r: { value: sig.r }, s: { value: sig.s } };
}

// R is lifted from r and the recovery bit off-circuit to avoid an in-circuit square root.
function toSecp256k1SigWithRecovery(sig: NobleSignature): runtime.Secp256k1EcdsaSignatureWithRecovery {
  const prefix = sig.recovery === 0 ? '02' : '03';
  const R = secp256k1.ProjectivePoint.fromHex(prefix + sig.r.toString(16).padStart(64, '0')).toAffine();
  return { r: { value: sig.r }, s: { value: sig.s }, R: { x: R.x, y: R.y } };
}

// ==== Type descriptor tests ====

describe('Secp256k1 type descriptors', () => {
  test('Secp256k1Scalar round-trips through CompactType', () => {
    const scalar: runtime.Secp256k1Scalar = { value: 0xdeadbeefn };
    const recovered = runtime.CompactTypeSecp256k1Scalar.fromValue([
      ...runtime.CompactTypeSecp256k1Scalar.toValue(scalar),
    ]);
    expect(recovered.value).toBe(scalar.value);
  });

  test('Secp256k1Point round-trips through CompactType', () => {
    const point = toSecp256k1Point(PUB_KEY_POINT);
    const roundTripped = runtime.CompactTypeSecp256k1Point.fromValue([
      ...runtime.CompactTypeSecp256k1Point.toValue(point),
    ]);
    expect(typeof roundTripped.x).toBe('bigint');
    expect(typeof roundTripped.y).toBe('bigint');
  });

  test('Secp256k1EcdsaSignature round-trips through CompactType', () => {
    const sig = toSecp256k1Sig(ETH_SIG);
    const roundTripped = runtime.CompactTypeSecp256k1EcdsaSignature.fromValue([
      ...runtime.CompactTypeSecp256k1EcdsaSignature.toValue(sig),
    ]);
    expect(typeof roundTripped.r.value).toBe('bigint');
    expect(typeof roundTripped.s.value).toBe('bigint');
  });

  test('Secp256k1EcdsaSignatureWithRecovery round-trips through CompactType', () => {
    const sig = toSecp256k1SigWithRecovery(ETH_SIG);
    const roundTripped = runtime.CompactTypeSecp256k1EcdsaSignatureWithRecovery.fromValue([
      ...runtime.CompactTypeSecp256k1EcdsaSignatureWithRecovery.toValue(sig),
    ]);
    expect(typeof roundTripped.r.value).toBe('bigint');
    expect(typeof roundTripped.s.value).toBe('bigint');
    expect(typeof roundTripped.R.x).toBe('bigint');
    expect(typeof roundTripped.R.y).toBe('bigint');
  });
});

// ==== Circuit execution tests (skipped until secp256k1 gates are implemented) ====

describe('Ethereum signature (secp256k1 + keccak256)', () => {
  test.skip('proveEthereumSignature: accepts a valid signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _sig = toSecp256k1Sig(ETH_SIG);

    // const result = <call proveEthereumSignature circuit>(ETH_MSG, _sig, _pk);
    // expect(result).toBe(true);
  });

  test.skip('proveEthereumSignature: rejects a tampered signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _tamperedSig: runtime.Secp256k1EcdsaSignature = {
      r: { value: ETH_SIG.r },
      s: { value: (ETH_SIG.s + 1n) % SECP256K1_N },
    };

    // const result = <call proveEthereumSignature circuit>(ETH_MSG, _tamperedSig, _pk);
    // expect(result).toBe(false);
  });

  test.skip('recoverEthereumPublicKey: recovers the correct public key', () => {
    const _sig = toSecp256k1SigWithRecovery(ETH_SIG);
    const _expectedPk = toSecp256k1Point(PUB_KEY_POINT);

    // const recoveredPk = <call recoverEthereumPublicKey circuit>(ETH_MSG, _sig);
    // expect(recoveredPk.x).toBe(_expectedPk.x);
    // expect(recoveredPk.y).toBe(_expectedPk.y);
  });
});

describe('Bitcoin signature (secp256k1 + sha256)', () => {
  test.skip('proveBitcoinSignature: accepts a valid signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _sig = toSecp256k1Sig(BTC_SIG);

    // const result = <call proveBitcoinSignature circuit>(BTC_MSG, _sig, _pk);
    // expect(result).toBe(true);
  });

  test.skip('proveBitcoinSignature: rejects a tampered signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _tamperedSig: runtime.Secp256k1EcdsaSignature = {
      r: { value: BTC_SIG.r },
      s: { value: (BTC_SIG.s + 1n) % SECP256K1_N },
    };

    // const result = <call proveBitcoinSignature circuit>(BTC_MSG, _tamperedSig, _pk);
    // expect(result).toBe(false);
  });
});
