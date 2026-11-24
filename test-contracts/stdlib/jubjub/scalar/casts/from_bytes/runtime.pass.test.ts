// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import { numberToBytesLE } from '@noble/curves/utils.js';
import { MAX_JUBJUB_SCALAR } from '@midnight-ntwrk/compact-runtime';
import { expect } from 'vitest';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';

const R = MAX_JUBJUB_SCALAR + 1n;

const VALUES = [0n, MAX_JUBJUB_SCALAR, R, (1n << 256n) - 1n];

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        for (const value of VALUES) {
            expect(
                pure.jubjub_scalar_casts_from_bytes(numberToBytesLE(value, 32)),
            ).toBe(value % R);
        }
    },
);
