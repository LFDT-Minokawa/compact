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

/**
 * The maximum value representable in Compact's `Field` type
 *
 * One less than the prime modulus of the proof system's scalar field.
 */
export const MAX_FIELD: bigint = ocrt.maxField();

/**
 * The order of Compact's native `Field` type
 */
export const FIELD_MODULUS: bigint = MAX_FIELD + 1n;

/**
 * The order of the JubJub scalar field
 */
export const JUBJUB_SCALAR_MODULUS: bigint =
    0xe7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb7n;

export const MAX_JUBJUB_SCALAR: bigint = JUBJUB_SCALAR_MODULUS - 1n;

/**
 * The maximum value of a `Secp256k1Base` foreign field value.
 */
export const MAX_SECP256K1_BASE: bigint = (2n**256n - 2n**32n - 977n) - 1n;

/**
 * The maximum value of a `Secp256k1Scalar` foreign field value.
 */
export const MAX_SECP256K1_SCALAR: bigint =
    0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140n;

/**
 * A valid placeholder contract address
 *
 * @deprecated Cannot handle {@link NetworkId}s, use
 * {@link dummyContractAddress} instead.
 */
export const DUMMY_ADDRESS: string = ocrt.dummyContractAddress();
