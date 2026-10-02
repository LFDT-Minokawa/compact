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

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import {
    assertCoverage,
    runEcdsaKat,
    SECP256R1,
    type EcdsaVector,
} from '@test/crypto';

// Checks signatures over the Wycheproof vectors (see
// support/crypto/data/README.md), with the digest hashed outside the circuit,
// so only the curve maths is tested. Each expected answer comes from both the
// vectors and @noble/curves.

// Out-of-range r or s never reach the circuit, and count as a bad signature.
function drive(pure: PureCircuits, vector: EcdsaVector): boolean {
    return (
        vector.scalarsInRange &&
        pure.verifyEcdsa(vector.e, vector.sig, vector.pk)
    );
}

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        const classified = runEcdsaKat(
            SECP256R1,
            'verifyEcdsa (pre-hashed digest)',
            (vector) => drive(pure, vector),
        );

        assertCoverage(SECP256R1.name, classified, SECP256R1.coverage);
    },
);
