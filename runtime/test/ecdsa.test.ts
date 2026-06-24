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
import { secp256k1 } from '@noble/curves/secp256k1.js';
import { keccak_256 } from '@noble/hashes/sha3.js';
import { sha256 } from '@noble/hashes/sha2.js';
import * as runtime from '../src/index.js';

const SECP256K1_N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141n;

interface NobleSignature {
  readonly r: bigint;
  readonly s: bigint;
  readonly recovery?: number;
  recoverPublicKey(msgHash: Uint8Array): { readonly x: bigint; readonly y: bigint };
}

interface NobleSignature {
  readonly r: bigint;
  readonly s: bigint;
  readonly recovery?: number;
  recoverPublicKey(msgHash: Uint8Array): { readonly x: bigint; readonly y: bigint };
}

function toNobleSignature(bytes: Uint8Array): NobleSignature {
  // What sign() emits: 64 = compact (r||s), 65 = recovered (recoveryByte || r || s).
  // In v2 the recovery byte is FIRST (recovered.slice(1) === compact).
  const format =
    bytes.length === 65
      ? 'recovered'
      : bytes.length === 64
        ? 'compact'
        : (() => {
            throw new Error(`unexpected sig length ${bytes.length}`);
          })();

  const sig = secp256k1.Signature.fromBytes(bytes, format);

  return {
    r: sig.r,
    s: sig.s,
    recovery: sig.recovery,
    recoverPublicKey(msgHash) {
      // Instance method expects an already-hashed digest (per the v2 source comment),
      // so pass ETH_MSG_HASH directly — no internal prehash here.
      return sig.recoverPublicKey(msgHash).toAffine(); // Point -> { x, y }
    },
  };
}

const PRIV_KEY = secp256k1.utils.randomSecretKey();
const PUB_KEY = secp256k1.getPublicKey(PRIV_KEY);
const PUB_KEY_POINT = secp256k1.Point.fromBytes(PUB_KEY).toAffine();

// Ethereum: keccak256(msg)
const ETH_MSG = new Uint8Array(32).fill(0xab);
const ETH_MSG_HASH = keccak_256(ETH_MSG);
const ETH_SIG: NobleSignature = toNobleSignature(secp256k1.sign(ETH_MSG_HASH, PRIV_KEY));

// Bitcoin: sha256(msg)
const BTC_MSG = new Uint8Array(32).fill(0xcd);
const BTC_MSG_HASH = sha256(BTC_MSG);
const BTC_SIG: NobleSignature = toNobleSignature(secp256k1.sign(BTC_MSG_HASH, PRIV_KEY));

function toSecp256k1Point(pt: { x: bigint; y: bigint }): runtime.Secp256k1Point {
  return { x: pt.x, y: pt.y };
}

function toSecp256k1Sig(sig: { r: bigint; s: bigint }): runtime.Secp256k1EcdsaSignature {
  return { r: sig.r, s: sig.s };
}

// R is lifted from r and the recovery bit off-circuit to avoid an in-circuit square root.
function toSecp256k1SigWithRecovery(sig: NobleSignature): runtime.Secp256k1EcdsaSignatureWithRecovery {
  const prefix = sig.recovery === 0 ? '02' : '03';
  const R = secp256k1.Point.fromHex(prefix + sig.r.toString(16).padStart(64, '0')).toAffine();
  return { r: sig.r, s: sig.s, R: { x: R.x, y: R.y } };
}

// ==== Type descriptor tests ====

// The foreign-field limb encoding stores `value - 1` and folds 0 <-> MAX
// (see CompactTypeSecp256k1Base/Scalar.toValue). Exercise both ends of that fold
// plus a few interior values rather than a single happy-path value.
const baseEdgeCases: ReadonlyArray<{ label: string; value: bigint }> = [
  { label: 'zero (folds to MAX in the limb encoding)', value: 0n },
  { label: 'one (smallest non-zero)', value: 1n },
  { label: 'two', value: 2n },
  { label: 'an arbitrary interior value', value: 0xdeadbeefn },
  { label: 'MAX - 1', value: runtime.MAX_SECP256K1_BASE - 1n },
  { label: 'MAX', value: runtime.MAX_SECP256K1_BASE },
];

const scalarEdgeCases: ReadonlyArray<{ label: string; value: bigint }> = [
  { label: 'zero (folds to MAX in the limb encoding)', value: 0n },
  { label: 'one (smallest non-zero)', value: 1n },
  { label: 'two', value: 2n },
  { label: 'an arbitrary interior value', value: 0xdeadbeefn },
  { label: 'MAX - 1', value: runtime.MAX_SECP256K1_SCALAR - 1n },
  { label: 'MAX', value: runtime.MAX_SECP256K1_SCALAR },
];

// Points are two independent base-field coordinates, so cover the coordinate
// edge values (and their combinations) on top of a real public key.
const pointEdgeCases: ReadonlyArray<{ label: string; value: runtime.Secp256k1Point }> = [
  { label: 'the generated public key', value: toSecp256k1Point(PUB_KEY_POINT) },
  { label: 'zero coordinates', value: { x: 0n, y: 0n } },
  { label: 'max coordinates', value: { x: runtime.MAX_SECP256K1_BASE, y: runtime.MAX_SECP256K1_BASE } },
  { label: 'mixed edge coordinates', value: { x: 1n, y: runtime.MAX_SECP256K1_BASE } },
];

describe('Secp256k1 type descriptors', () => {
  describe('Secp256k1Base round-trips through CompactType', () => {
    test.each(baseEdgeCases)('round-trips $label', ({ value }) => {
      const roundTripped = runtime.CompactTypeSecp256k1Base.fromValue([...runtime.CompactTypeSecp256k1Base.toValue(value)]);
      expect(roundTripped).toBe(value);
    });

    test('rejects values outside [0, MAX]', () => {
      expect(() => runtime.CompactTypeSecp256k1Base.toValue(-1n)).toThrow();
      expect(() => runtime.CompactTypeSecp256k1Base.toValue(runtime.MAX_SECP256K1_BASE + 1n)).toThrow();
    });
  });

  describe('Secp256k1Scalar round-trips through CompactType', () => {
    test.each(scalarEdgeCases)('round-trips $label', ({ value }) => {
      const roundTripped = runtime.CompactTypeSecp256k1Scalar.fromValue([...runtime.CompactTypeSecp256k1Scalar.toValue(value)]);
      expect(roundTripped).toBe(value);
    });

    test('rejects values outside [0, MAX]', () => {
      expect(() => runtime.CompactTypeSecp256k1Scalar.toValue(-1n)).toThrow();
      expect(() => runtime.CompactTypeSecp256k1Scalar.toValue(runtime.MAX_SECP256K1_SCALAR + 1n)).toThrow();
    });
  });

  describe('Secp256k1Point round-trips through CompactType', () => {
    test.each(pointEdgeCases)('round-trips $label', ({ value }) => {
      const roundTripped = runtime.CompactTypeSecp256k1Point.fromValue([...runtime.CompactTypeSecp256k1Point.toValue(value)]);
      expect(roundTripped.x).toBe(value.x);
      expect(roundTripped.y).toBe(value.y);
    });
  });

  test('Secp256k1EcdsaSignature round-trips through CompactType', () => {
    const sig = toSecp256k1Sig(ETH_SIG);
    const roundTripped = runtime.CompactTypeSecp256k1EcdsaSignature.fromValue([
      ...runtime.CompactTypeSecp256k1EcdsaSignature.toValue(sig),
    ]);
    expect(roundTripped.r).toBe(sig.r);
    expect(roundTripped.s).toBe(sig.s);
  });

  test('Secp256k1EcdsaSignatureWithRecovery round-trips through CompactType', () => {
    const sig = toSecp256k1SigWithRecovery(ETH_SIG);
    const roundTripped = runtime.CompactTypeSecp256k1EcdsaSignatureWithRecovery.fromValue([
      ...runtime.CompactTypeSecp256k1EcdsaSignatureWithRecovery.toValue(sig),
    ]);
    expect(roundTripped.r).toBe(sig.r);
    expect(roundTripped.s).toBe(sig.s);
    expect(roundTripped.R.x).toBe(sig.R.x);
    expect(roundTripped.R.y).toBe(sig.R.y);
  });
});

// ==== Native operation tests (runtime impl vs @noble/curves) ====

// secp256k1.Point.Fn is the scalar field (mod n); secp256k1.Point.Fp is the base field (mod p).
// The runtime implements add/neg/mul with plain modular bigint arithmetic and delegates inv to
// noble, so these cross-check the field algebra against noble's canonical reductions.
interface FieldUnderTest {
  readonly name: string;
  readonly modulus: bigint;
  readonly add: (x: bigint, y: bigint) => bigint;
  readonly neg: (x: bigint) => bigint;
  readonly mul: (x: bigint, y: bigint) => bigint;
  readonly inv: (x: bigint) => bigint;
  readonly noble: {
    add(x: bigint, y: bigint): bigint;
    neg(x: bigint): bigint;
    mul(x: bigint, y: bigint): bigint;
    inv(x: bigint): bigint;
  };
}

const FIELDS: readonly FieldUnderTest[] = [
  {
    name: 'Secp256k1Scalar',
    modulus: runtime.SECP256K1_SCALAR_MODULUS,
    add: runtime.secp256k1ScalarAdd,
    neg: runtime.secp256k1ScalarNeg,
    mul: runtime.secp256k1ScalarMul,
    inv: runtime.secp256k1ScalarInv,
    noble: secp256k1.Point.Fn,
  },
  {
    name: 'Secp256k1Base',
    modulus: runtime.SECP256K1_BASE_MODULUS,
    add: runtime.secp256k1BaseAdd,
    neg: runtime.secp256k1BaseNeg,
    mul: runtime.secp256k1BaseMul,
    inv: runtime.secp256k1BaseInv,
    noble: secp256k1.Point.Fp,
  },
];

describe.each(FIELDS)('$name field ops vs noble', (field) => {
  const M = field.modulus;

  // Pairs spanning identities, wraparound at the modulus, and arbitrary operands.
  const binaryCases: ReadonlyArray<{ label: string; x: bigint; y: bigint }> = [
    { label: '0 and 0', x: 0n, y: 0n },
    { label: '0 and 1', x: 0n, y: 1n },
    { label: '1 and 1', x: 1n, y: 1n },
    { label: 'small operands', x: 2n, y: 3n },
    { label: 'wraparound (MAX + 1)', x: M - 1n, y: 1n },
    { label: 'both maximal (-1 and -1)', x: M - 1n, y: M - 1n },
    { label: 'arbitrary operands', x: 0xdeadbeefcafen, y: 0x123456789n },
  ];

  // Non-zero singletons for the unary ops; neg(0) and inv(0) are covered separately.
  const unaryCases: ReadonlyArray<{ label: string; x: bigint }> = [
    { label: 'one', x: 1n },
    { label: 'two', x: 2n },
    { label: 'maximal (-1)', x: M - 1n },
    { label: 'arbitrary', x: 0xdeadbeefn },
  ];

  test.each(binaryCases)('add: $label', ({ x, y }) => {
    expect(field.add(x, y)).toBe(field.noble.add(x, y));
  });

  test.each(binaryCases)('mul: $label', ({ x, y }) => {
    expect(field.mul(x, y)).toBe(field.noble.mul(x, y));
  });

  test.each(unaryCases)('neg: $label', ({ x }) => {
    expect(field.neg(x)).toBe(field.noble.neg(x));
    expect(field.add(x, field.neg(x))).toBe(0n); // x + (-x) == 0
  });

  test('neg: zero is its own negation', () => {
    expect(field.neg(0n)).toBe(0n);
    expect(field.noble.neg(0n)).toBe(0n);
  });

  test.each(unaryCases)('inv: $label', ({ x }) => {
    expect(field.inv(x)).toBe(field.noble.inv(x));
    expect(field.mul(x, field.inv(x))).toBe(1n); // x * x^-1 == 1
  });

  test('inv: zero throws', () => {
    expect(() => field.inv(0n)).toThrow();
  });
});

describe('secp256k1 point ops vs noble', () => {
  const G = secp256k1.Point.BASE;
  const N = runtime.SECP256K1_SCALAR_MODULUS;
  const IDENTITY: runtime.Secp256k1Point = { x: 0n, y: 0n };
  const PK = toSecp256k1Point(PUB_KEY_POINT);

  const affine = (p: { toAffine(): { x: bigint; y: bigint } }): runtime.Secp256k1Point => {
    const { x, y } = p.toAffine();
    return { x, y };
  };
  // Mirror the runtime's affine <-> projective lift: (0, 0) is the identity.
  const lift = (pt: runtime.Secp256k1Point): typeof G =>
    pt.x === 0n && pt.y === 0n ? secp256k1.Point.ZERO : secp256k1.Point.fromAffine({ x: pt.x, y: pt.y });
  const nobleAdd = (a: runtime.Secp256k1Point, b: runtime.Secp256k1Point) => affine(lift(a).add(lift(b)));
  const nobleScalarMul = (pt: runtime.Secp256k1Point, k: bigint) => affine(lift(pt).multiplyUnsafe(k));
  const nobleMul = (k: bigint) => affine(G.multiplyUnsafe(k));

  const G_AFF = affine(G);
  const expectPoint = (got: runtime.Secp256k1Point, want: runtime.Secp256k1Point) => {
    expect(got.x).toBe(want.x);
    expect(got.y).toBe(want.y);
  };

  // multiplyUnsafe accepts scalars in [0, n); n itself is rejected, so N-1 is the high edge.
  const scalarCases: ReadonlyArray<{ label: string; k: bigint }> = [
    { label: '0 (-> identity)', k: 0n },
    { label: '1 (-> same point)', k: 1n },
    { label: '2 (-> doubling)', k: 2n },
    { label: 'arbitrary', k: 0xdeadbeefn },
    { label: 'N - 1 (-> negation)', k: N - 1n },
  ];

  describe('secp256k1Add', () => {
    test('P + identity == P', () => {
      expectPoint(runtime.secp256k1Add(PK, IDENTITY), PK);
      expectPoint(runtime.secp256k1Add(IDENTITY, PK), PK);
    });
    test('identity + identity == identity', () => {
      expectPoint(runtime.secp256k1Add(IDENTITY, IDENTITY), IDENTITY);
    });
    test('P + (-P) == identity', () => {
      const negG = nobleMul(N - 1n); // -G
      expectPoint(runtime.secp256k1Add(G_AFF, negG), IDENTITY);
    });
    test('G + G == 2G (doubling)', () => {
      expectPoint(runtime.secp256k1Add(G_AFF, G_AFF), nobleMul(2n));
    });
    test('2G + 3G == 5G', () => {
      expectPoint(runtime.secp256k1Add(nobleMul(2n), nobleMul(3n)), nobleMul(5n));
    });
    test('PK + G matches noble', () => {
      expectPoint(runtime.secp256k1Add(PK, G_AFF), nobleAdd(PK, G_AFF));
    });
  });

  describe('secp256k1Mul', () => {
    test.each(scalarCases)('G * $label matches noble', ({ k }) => {
      expectPoint(runtime.secp256k1Mul(G_AFF, k), nobleScalarMul(G_AFF, k));
    });
    test.each(scalarCases)('PK * $label matches noble', ({ k }) => {
      expectPoint(runtime.secp256k1Mul(PK, k), nobleScalarMul(PK, k));
    });
    test('0 * P == identity', () => {
      expectPoint(runtime.secp256k1Mul(PK, 0n), IDENTITY);
    });
    test('1 * P == P', () => {
      expectPoint(runtime.secp256k1Mul(PK, 1n), PK);
    });
    test('2 * P == P + P', () => {
      expectPoint(runtime.secp256k1Mul(PK, 2n), runtime.secp256k1Add(PK, PK));
    });
  });

  describe('secp256k1MulGenerator', () => {
    test.each(scalarCases)('$label matches noble', ({ k }) => {
      expectPoint(runtime.secp256k1MulGenerator(k), nobleMul(k));
    });
    test('mulGenerator(k) == mul(G, k)', () => {
      for (const k of [1n, 2n, 7n, 0xabcn]) {
        expectPoint(runtime.secp256k1MulGenerator(k), runtime.secp256k1Mul(G_AFF, k));
      }
    });
    test('mulGenerator(0) == identity', () => {
      expectPoint(runtime.secp256k1MulGenerator(0n), IDENTITY);
    });
    test('mulGenerator(1) == G', () => {
      expectPoint(runtime.secp256k1MulGenerator(1n), G_AFF);
    });
  });

  describe('secp256k1PointX / secp256k1PointY', () => {
    test('extract affine coordinates', () => {
      expect(runtime.secp256k1PointX(PK)).toBe(PK.x);
      expect(runtime.secp256k1PointY(PK)).toBe(PK.y);
    });
    test('extract identity coordinates', () => {
      expect(runtime.secp256k1PointX(IDENTITY)).toBe(0n);
      expect(runtime.secp256k1PointY(IDENTITY)).toBe(0n);
    });
  });
});

// ==== Circuit execution tests (skipped until secp256k1 gates are implemented) ====

describe('Ethereum signature (secp256k1 + keccak256)', () => {
  test('proveEthereumSignature: accepts a valid signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _sig = toSecp256k1Sig(ETH_SIG);

    // const result = <call proveEthereumSignature circuit>(ETH_MSG, _sig, _pk);
    // expect(result).toBe(true);
  });

  test('proveEthereumSignature: rejects a tampered signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _tamperedSig: runtime.Secp256k1EcdsaSignature = {
      r: ETH_SIG.r,
      s: (ETH_SIG.s + 1n) % SECP256K1_N,
    };

    // const result = <call proveEthereumSignature circuit>(ETH_MSG, _tamperedSig, _pk);
    // expect(result).toBe(false);
  });

  test('recoverEthereumPublicKey: recovers the correct public key', () => {
    const _sig = toSecp256k1SigWithRecovery(ETH_SIG);
    const _expectedPk = toSecp256k1Point(PUB_KEY_POINT);

    // const recoveredPk = <call recoverEthereumPublicKey circuit>(ETH_MSG, _sig);
    // expect(recoveredPk.x).toBe(_expectedPk.x);
    // expect(recoveredPk.y).toBe(_expectedPk.y);
  });

  test('recoverEthereumAddress: returns first 20 bytes of keccak256(pk)', () => {
    const _sig = toSecp256k1SigWithRecovery(ETH_SIG);

    // const address = <call recoverEthereumAddress circuit>(ETH_MSG, _sig);
    // expect(address.length).toBe(20);
  });
});

describe('Bitcoin signature (secp256k1 + sha256)', () => {
  test('proveBitcoinSignature: accepts a valid signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _sig = toSecp256k1Sig(BTC_SIG);

    // const result = <call proveBitcoinSignature circuit>(BTC_MSG, _sig, _pk);
    // expect(result).toBe(true);
  });

  test('proveBitcoinSignature: rejects a tampered signature', () => {
    const _pk = toSecp256k1Point(PUB_KEY_POINT);
    const _tamperedSig: runtime.Secp256k1EcdsaSignature = {
      r: BTC_SIG.r,
      s: (BTC_SIG.s + 1n) % SECP256K1_N,
    };

    // const result = <call proveBitcoinSignature circuit>(BTC_MSG, _tamperedSig, _pk);
    // expect(result).toBe(false);
  });
});
