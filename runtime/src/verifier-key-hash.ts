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

import { sha256 } from '@noble/hashes/sha2.js';
import { bytesToHex } from '@noble/hashes/utils.js';
import { CompactError } from './error.js';

declare const VerifierKeyHashBrand: unique symbol;

/**
 * The SHA-256 of one deployed operation's verifier key, as lowercase hex.
 *
 * Branded so both sides of the implementation check are validated before they meet, and can differ
 * only in content — a format difference would otherwise read as a substituted contract.
 */
export type VerifierKeyHash = string & { readonly [VerifierKeyHashBrand]: 'VerifierKeyHash' };

const VERIFIER_KEY_HASH_REGEX = /^[0-9a-f]{64}$/;

/** Whether `x` is 64 lowercase hex digits. */
export function isVerifierKeyHash(x: unknown): x is VerifierKeyHash {
  return typeof x === 'string' && VERIFIER_KEY_HASH_REGEX.test(x);
}

/**
 * Converts a raw digest to the brand. Rejects rather than normalizes: a digest that needed
 * normalizing didn't come from `compactc` or the ledger.
 */
export function asVerifierKeyHash(hex: string): VerifierKeyHash {
  if (!isVerifierKeyHash(hex)) {
    throw new CompactError(`Expected a verifier key hash: 64 lowercase hex digits (32 bytes of SHA-256), but received '${hex}'`);
  }
  return hex;
}

/**
 * Fingerprints a deployed operation's verifier key, by the same computation the compiler applies to
 * `keys/<circuit>.verifier`. Throws on an empty key: that is `OperationAbsent`, for the caller to
 * raise.
 */
export function verifierKeyHashOf(verifierKey: Uint8Array): VerifierKeyHash {
  if (verifierKey.length === 0) {
    throw new CompactError('Cannot fingerprint an empty verifier key');
  }
  return asVerifierKeyHash(bytesToHex(sha256(verifierKey)));
}
