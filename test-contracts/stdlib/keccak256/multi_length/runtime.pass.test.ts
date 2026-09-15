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

import { keccak_256 } from '@noble/hashes/sha3.js';

import type { Contract, PureCircuits } from './.build/contract/index.js';
import { defineRuntimeTest } from '@test/compact-test';
import {
    checkWidthVector,
    runKat,
    sweepVectors,
    vectorLabel,
} from '@test/crypto';

// Widths from 1 byte to 1024.
//
// The expected digests come from the same library the runtime uses, so this
// checks the encoding across packing boundaries rather than the hash itself.
// Published digests are in ../known_vectors.
const vectors = sweepVectors(keccak_256);

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat('keccak256 multi-length', vectors, vectorLabel, (vector) =>
            checkWidthVector(pure, vector),
        );
    },
);
