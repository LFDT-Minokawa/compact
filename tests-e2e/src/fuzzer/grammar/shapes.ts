// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
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

/*
 * List combinators over grammar alternatives.
 *
 * Deliberately free of Compact syntax -- every literal token of the language
 * lives in compact.ts, so there is one place to look when the language changes.
 */

import { Token } from './types';

/** [a, b, c] with `sep` between each: [a, sep, b, sep, c] */
export const join = (nodes: Token[], sep: Token): Token[] =>
    nodes.flatMap((node, i) => (i ? [sep, node] : [node]));

/** `node` repeated `count` times, separated by `sep` */
export const repeat = (node: Token, count: number, sep: Token): Token[] =>
    join(Array.from({ length: count }, () => node), sep);
