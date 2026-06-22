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

// The secp256k1 generator and the group identity (point at infinity, encoded
// as the affine pair (0, 0)).
const G: runtime.Secp256k1Point = {
  x: 55066263022277343669578718895168534326250603453777594175500187360389116729240n,
  y: 32670510020758816978083085130507043184471273380659243275938904335757337482424n,
};
const IDENTITY: runtime.Secp256k1Point = { x: 0n, y: 0n };

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
