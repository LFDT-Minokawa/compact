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

// Canonical form is 64 lowercase hex digits, and anything else is rejected.

import { describe, expect, test } from 'vitest';
import { CompactError, asVerifierKeyHash, isVerifierKeyHash, verifierKeyHashOf } from '../src/index.js';

// SHA-256('abc'), the FIPS 180-4 test vector.
const SHA256_ABC = 'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad';

describe('isVerifierKeyHash', () => {
  test('accepts 64 lowercase hex digits', () => {
    expect(isVerifierKeyHash(SHA256_ABC)).toEqual(true);
    expect(isVerifierKeyHash('0'.repeat(64))).toEqual(true);
    expect(isVerifierKeyHash('f'.repeat(64))).toEqual(true);
  });

  test('rejects uppercase', () => {
    expect(isVerifierKeyHash(SHA256_ABC.toUpperCase())).toEqual(false);
    expect(isVerifierKeyHash('ba7816bf8f01cfeA414140de5dae2223b00361a396177a9cb410ff61f20015ad')).toEqual(false);
  });

  test('rejects wrong lengths, prefixes and non-hex', () => {
    expect(isVerifierKeyHash('')).toEqual(false);
    expect(isVerifierKeyHash('0'.repeat(63))).toEqual(false);
    expect(isVerifierKeyHash('0'.repeat(65))).toEqual(false);
    expect(isVerifierKeyHash(`0x${'0'.repeat(64)}`)).toEqual(false);
    expect(isVerifierKeyHash(`${'0'.repeat(62)}zz`)).toEqual(false);
    expect(isVerifierKeyHash(` ${'0'.repeat(64)}`)).toEqual(false);
  });

  test('rejects non-strings', () => {
    expect(isVerifierKeyHash(undefined)).toEqual(false);
    expect(isVerifierKeyHash(null)).toEqual(false);
    expect(isVerifierKeyHash(0)).toEqual(false);
    expect(isVerifierKeyHash(Buffer.alloc(32))).toEqual(false);
  });
});

describe('asVerifierKeyHash', () => {
  test('returns the digest unchanged when it is already canonical', () => {
    expect(asVerifierKeyHash(SHA256_ABC)).toEqual(SHA256_ABC);
  });

  test('throws on anything not canonical, naming the value', () => {
    expect(() => asVerifierKeyHash(SHA256_ABC.toUpperCase())).toThrow(CompactError);
    expect(() => asVerifierKeyHash('deadbeef')).toThrow(/64 lowercase hex digits/);
    expect(() => asVerifierKeyHash('deadbeef')).toThrow(/deadbeef/);
  });
});

describe('verifierKeyHashOf', () => {
  test('is SHA-256 of the key bytes, lowercase hex', () => {
    expect(verifierKeyHashOf(Buffer.from('abc', 'utf8'))).toEqual(SHA256_ABC);
  });

  test('produces a value that is already canonical', () => {
    const hash = verifierKeyHashOf(Buffer.from([1, 2, 3, 4]));
    expect(isVerifierKeyHash(hash)).toEqual(true);
    expect(asVerifierKeyHash(hash)).toEqual(hash);
  });

  test('distinguishes keys that differ in one byte', () => {
    const a = verifierKeyHashOf(Buffer.from([0, 0, 0, 0]));
    const b = verifierKeyHashOf(Buffer.from([0, 0, 0, 1]));
    expect(a).not.toEqual(b);
  });

  test('refuses to fingerprint an empty key', () => {
    // An absent key is the caller's to report, not ours to hash.
    expect(() => verifierKeyHashOf(new Uint8Array(0))).toThrow(CompactError);
    expect(() => verifierKeyHashOf(new Uint8Array(0))).toThrow(/empty verifier key/);
  });
});
