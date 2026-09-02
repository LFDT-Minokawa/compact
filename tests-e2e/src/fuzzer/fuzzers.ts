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

import { ENTRY_POINTS, type FuzzerName } from './grammar';
import { buildConfig } from './utils/config';
import { Fuzzer } from './utils/fuzzer';

/**
 * Generate contracts for every fuzzer.
 *
 * All fuzzers share one grammar table (grammar/compact.ts); a fuzzer is just an
 * entry nonterminal into it.
 */
export function generate(outputDir: string, amount: number): void {
    for (const name of Object.keys(ENTRY_POINTS) as FuzzerName[]) {
        new Fuzzer(buildConfig(name, outputDir, amount)).saveContracts();
    }
}
