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

import { ContractAddress } from '@midnight-ntwrk/onchain-runtime';
import { EncodedContractAddress } from './zswap.js';

/**
 * Regex matching hex strings of even length.
 */
export const HEX_REGEX_NO_PREFIX = /^([0-9A-Fa-f]{2})*$/;

/**
 * The expected length (in bytes) of a contract address.
 */
export const CONTRACT_ADDRESS_BYTE_LENGTH = 34;

/**
 * Tests whether the input value is a {@link ContractAddress}, i.e., string.
 *
 * @param x The value that is tested to be a {@link ContractAddress}.
 */
export function isContractAddress(x: unknown): x is ContractAddress {
  return typeof x === 'string' && x.length === CONTRACT_ADDRESS_BYTE_LENGTH * 2 && HEX_REGEX_NO_PREFIX.test(x);
}

export function isEncodedContractAddress(x: unknown): x is EncodedContractAddress {
  return (
    typeof x === 'object' &&
    x !== null &&
    x !== undefined &&
    'bytes' in x &&
    x.bytes instanceof Uint8Array &&
    x.bytes.length == CONTRACT_ADDRESS_BYTE_LENGTH
  );
}

export const fromHex = (s: string): Uint8Array => Buffer.from(s, 'hex');

export const toHex = (s: Uint8Array): string => Buffer.from(s).toString('hex');
