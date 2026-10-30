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

import { expect } from 'vitest';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        expect(pure.mul_bit(1n, 1n)).toBe(1n);
        expect(pure.mul_bit(1n, 0n)).toBe(0n);
        expect(pure.mul_bit(0n, 0n)).toBe(0n);

        expect(pure.mul_bit_range(1n, 1n)).toBe(1n);
        expect(pure.mul_bit_range(0n, 1n)).toBe(0n);

        expect(pure.add_zero(0n, 0n)).toBe(0n);
        expect(pure.mul_zero(0n, 0n)).toBe(0n);

        expect(pure.sub_bit(1n, 1n)).toBe(0n);
        expect(pure.sub_bit(1n, 0n)).toBe(1n);
    },
);
