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
import * as runtime from '../src/index.js';

const PRIV_KEY = secp256k1.utils.randomPrivateKey();
const PUB_KEY_POINT = secp256k1.ProjectivePoint.fromPrivateKey(PRIV_KEY);

function toSecp256k1Point(pt: { x: bigint; y: bigint }): runtime.Secp256k1Point {
  return { x: pt.x, y: pt.y, identity: pt.x == 0n && pt.y == 0n };
}

// ==== Type descriptor tests ====

describe('Secp256k1 type descriptors', () => {
  test('Secp256k1Scalar round-trips through CompactType', () => {
    const scalar: bigint = 0xdeadbeefn;
    const recovered = runtime.CompactTypeSecp256k1Scalar.fromValue(
      runtime.CompactTypeSecp256k1Scalar.toValue(scalar));
    expect(recovered).toEqual(scalar);
  });

  test('Secp256k1Point round-trips through CompactType', () => {
    const point = toSecp256k1Point(PUB_KEY_POINT);
    const roundTripped = runtime.CompactTypeSecp256k1Point.fromValue(
      runtime.CompactTypeSecp256k1Point.toValue(point));
    expect(roundTripped).toEqual(point);
  });
});
