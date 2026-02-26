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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v3';
import { CompactType } from './compact-types.js';
import { JubjubPoint, FieldElement } from './curves.js';
import { CompactError } from './error.js';

/**
 * The Compact builtin `transient_hash` function
 *
 * This function is a circuit-efficient compression function from arbitrary
 * data to field elements, which is not guaranteed to persist between upgrades.
 * It should not be used to derive state data, but can be used for consistency
 * checks.
 */
export function transientHash<A>(rtType: CompactType<A>, value: A): FieldElement {
  return FieldElement.fromValue(ocrt.transientHash(rtType.alignment(), rtType.toValue(value)));
}

/**
 * The Compact builtin `transient_commit` function
 *
 * This function is a circuit-efficient commitment function from arbitrary
 * values representable in Compact, and a field element commitment opening, to
 * field elements, which is not guaranteed to persist between
 * upgrades. It should not be used to derive state data, but can be used for
 * consistency checks.
 *
 * @throws If `opening` is out of range for field elements
 */
export function transientCommit<A>(rtType: CompactType<A>, value: A, opening: FieldElement): FieldElement {
  return FieldElement.fromValue(ocrt.transientCommit(rtType.alignment(), rtType.toValue(value), ocrt.bigIntToValue(opening.value)));
}

/**
 * The Compact builtin `persistent_hash` function
 *
 * This function is a non-circuit-optimised hash function for mostly arbitrary
 * data. It is guaranteed to persist between upgrades, with the exception of
 * devnet. It *should* be used to derive state data, and not for consistency
 * checks where avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rtType` encodes a type containing Compact 'Opaque' types
 */
export function persistentHash<A>(rtType: CompactType<A>, value: A): Uint8Array {
  const wrapped = ocrt.persistentHash(rtType.alignment(), rtType.toValue(value))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `persistent_commit` function
 *
 * This function is a non-circuit-optimised commitment function from arbitrary
 * values representable in Compact, and a 256-bit bytestring opening, to a
 * 256-bit bytestring. It is guaranteed to persist between upgrades. It
 * *should* be used to derive state data, and not for consistency checks where
 * avoidable.
 *
 * Note that data containing `Opaque` elements *may* throw runtime errors, and
 * cannot be relied upon as a consistent representation.
 *
 * @throws If `rtType` encodes a type containing Compact 'Opaque' types, or
 * `opening` is not 32 bytes long
 */
export function persistentCommit<A>(rtType: CompactType<A>, value: A, opening: Uint8Array): Uint8Array {
  if (opening.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  const wrapped = ocrt.persistentCommit(rtType.alignment(), rtType.toValue(value), [opening])[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `degrade_to_transient` function
 *
 * This function "degrades" the output of a {@link persistentHash} or
 * {@link persistentCommit} to a field element, which can then be used in
 * {@link transientHash} or {@link transientCommit}.
 *
 * @throws If `x` is not 32 bytes long
 */
export function degradeToTransient(x: Uint8Array): FieldElement {
  if (x.length != 32) {
    throw new CompactError('Expected 32-byte string');
  }
  return FieldElement.fromValue(ocrt.degradeToTransient([x]));
}

/**
 * The Compact builtin `upgrade_from_transient` function
 *
 * This function "upgrades" the output of a {@link transientHash} or
 * {@link transientCommit} to 256-bit byte string, which can then be used in
 * {@link persistentHash} or {@link persistentCommit}.
 *
 * @throws If `x` is not a valid field element
 */
export function upgradeFromTransient(x: FieldElement): Uint8Array {
  const wrapped = ocrt.upgradeFromTransient(ocrt.bigIntToValue(x.value))[0];
  const res = new Uint8Array(32);
  res.set(wrapped, 0);
  return res;
}

/**
 * The Compact builtin `hash_to_curve` function
 *
 * This function maps arbitrary values representable in Compact to elliptic
 * curve points in the proof system's embedded curve.
 *
 * Outputs are guaranteed to have unknown discrete logarithm with respect to
 * the group base, and any other output, but are not guaranteed to be unique (a
 * given input can be proven correct for multiple outputs).
 *
 * Inputs of different types may have the same output, if they have the same
 * field-aligned binary representation.
 */
export function hashToCurve<A>(rtType: CompactType<A>, x: A): JubjubPoint {
  return JubjubPoint.fromValue(ocrt.hashToCurve(rtType.alignment(), rtType.toValue(x)));
}

/**
 * Concatenates multiple {@link AlignedValue}s
 * @internal
 */
export function alignedConcat(...values: ocrt.AlignedValue[]): ocrt.AlignedValue {
  const res: ocrt.AlignedValue = { value: [], alignment: [] };
  for (const value of values) {
    res.value = res.value.concat(value.value);
    res.alignment = res.alignment.concat(value.alignment);
  }
  return res;
}
