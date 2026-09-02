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

import { ENTRY_POINTS, grammar, type FuzzerName } from '../grammar';
import { Grammar } from '../grammar/types';

export interface FuzzerConfig {
    grammar: Grammar;
    startNode: string;
    outputDir: string;
    outputName: string;
    contractAmount: number;
    stringLength: number;
    numberPower: number;
    tableLength: number;
}

/**
 * Configure one fuzzer.
 *
 * Every fuzzer shares the one grammar table; `name` only selects the entry
 * nonterminal and the output file prefix.
 */
export function buildConfig(name: FuzzerName, outputDir: string, contractAmount: number): FuzzerConfig {
    return {
        grammar,
        startNode: ENTRY_POINTS[name],
        outputDir,
        outputName: name,
        contractAmount,
        stringLength: 32,
        numberPower: 128,
        tableLength: 200,
    };
}
