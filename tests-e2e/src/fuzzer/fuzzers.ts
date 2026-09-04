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

import { ENTRY_POINTS, validate, type FuzzerName } from './grammar';
import { Fuzzer } from './utils/fuzzer';

/**
 * Generate contracts for every fuzzer.
 *
 * All fuzzers share one grammar table (grammar/compact.ts); a fuzzer is just an
 * entry nonterminal into it.
 *
 * The table is checked first. Every problem `validate()` reports is one that
 * quietly degrades what the fuzzer generates rather than failing -- an undefined
 * nonterminal is emitted as its own name, a production defined twice loses one
 * definition -- so a contract built on a broken table tests nothing, and it is
 * better to stop here than to spend a suite compiling junk.
 */
export function generate(outputDir: string, amount: number): void {
    const problems = validate();
    if (problems.length > 0) {
        throw new Error(`fuzzer grammar is invalid:\n  ${problems.join('\n  ')}`);
    }

    for (const name of Object.keys(ENTRY_POINTS) as FuzzerName[]) {
        new Fuzzer(name, outputDir, amount).saveContracts();
    }
}
