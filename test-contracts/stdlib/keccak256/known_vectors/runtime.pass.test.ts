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
import { checkWidthVector, pinned, runKat, vectorLabel } from '@test/crypto';

// Published Keccak-256 digests, written out on purpose.
//
// The runtime computes keccak with the same library the tests import, so a
// digest computed here would only recheck the encoding. These constants come
// from elsewhere, so they check the hash itself.
//
// Each vector's length picks its circuit.
const vectors = [
    pinned(
        '',
        'c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470',
        'empty input',
    ),
    pinned(
        '00',
        'bc36789e7a1e281436464229828f817d6612f7b477d66591ff96a9e064bcc98a',
        '1 zero byte',
    ),
    pinned(
        '0000',
        '54a8c0ab653c15bfb48b47fd011ba2b9617af01cb45cab344acd57c924d56798',
        '2 zero bytes',
    ),
    pinned(
        '74657374',
        '9c22ff5f21f0b81b113e63f7db6da94fedef11b2119b4088b89664fb9a3cb658',
        '"test"',
    ),
    pinned(
        '0000000000',
        'c41589e7559804ea4a2080dad19d876a024ccb05117835447d72ce08c1d020ec',
        '5 zero bytes',
    ),
    pinned(
        '00000000000000000000',
        '6bd2dd6bd408cbee33429358bf24fdc64612fbf8b1b4db604518f40ffd34b607',
        '10 zero bytes',
    ),
    pinned(
        '6c6f6e676572207465737420737472696e67',
        '47bed17bfbbc08d6b5a0f603eff1b3e932c37c10b865847a7bc73d55b260f32a',
        '"longer test string"',
    ),
];

export default defineRuntimeTest<typeof Contract, PureCircuits>(
    import.meta.url,
    (_Contract, pure) => {
        runKat('keccak256 published vectors', vectors, vectorLabel, (vector) =>
            checkWidthVector(pure, vector),
        );
    },
);
