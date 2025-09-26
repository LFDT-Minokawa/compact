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

export const COMPACT_CONTRACT_ADDRESS_BYTE_LENGTH = 32;

export function isCompactContractAddress(x: unknown): x is { bytes: Uint8Array } {
  return (
    typeof x === 'object' &&
    x !== null &&
    x !== undefined &&
    'bytes' in x &&
    x.bytes instanceof Uint8Array &&
    x.bytes.length == COMPACT_CONTRACT_ADDRESS_BYTE_LENGTH
  );
}

export const fromHex = (s: string): Uint8Array => Buffer.from(s, 'hex');
