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

import { MAX_FIELD } from './constants.js';
import { FieldElement } from './curves.js';
import { CompactError } from './error.js';

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convertFieldToBytes(n: number, x: FieldElement, src: string): Uint8Array {
  let v = x.value;
  const v_0 = v;
  const a = new Uint8Array(n);
  // counting on new Uint8Array setting all elements to zero; those not set are
  // intentionally left with a value of zero
  for (let i = 0; i < n; i++) {
    a[i] = Number(v & 0xffn);
    v = v / 0x100n;
    if (v == 0n) return a;
  }
  const msg = `range error at ${src}: Field or Uint value ${v_0} does not fit into ${n} bytes`;
  throw new CompactError(msg);
}

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convertBytesToField(n: number, a: Uint8Array, src: string): FieldElement {
  let x = 0n;
  for (let i = n - 1; i >= 0; i -= 1) {
    x = x * 0x100n + BigInt(a[i]);
    if (x > MAX_FIELD) {
      const msg = `range error at ${src}: the integer value of ${a} is greater than the maximum value of a Field`;
      throw new CompactError(msg);
    }
  }
  return FieldElement.create(x);
}

/**
 * Compiler internal for typecasts
 * @internal
 */
export function convertBytesToUint(maxval: number, n: number, a: Uint8Array, src: string): bigint {
  let x = 0n;
  for (let i = n - 1; i >= 0; i -= 1) {
    x = x * 0x100n + BigInt(a[i]);
    if (x > maxval) {
      const msg = `range error at ${src}: the integer value of ${a} is greater than the maximum value of Uint<0..${maxval + 1}>`;
      throw new CompactError(msg);
    }
  }
  return x;
}
