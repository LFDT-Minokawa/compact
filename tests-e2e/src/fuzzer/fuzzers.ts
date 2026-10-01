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

export const DEFAULT_CONTRACTS_PER_FUZZER = 1000;

export const MAX_CONTRACTS_PER_FUZZER = 2_000;

export function resolveContractCount(raw: string | undefined): number {
    const requested = Number(raw);
    if (!Number.isSafeInteger(requested) || requested < 1 || requested > MAX_CONTRACTS_PER_FUZZER) {
        return DEFAULT_CONTRACTS_PER_FUZZER;
    }
    return requested;
}

export function generate(outputDir: string, amount: number): void {
    const problems = validate();
    if (problems.length > 0) {
        throw new Error(`fuzzer grammar is invalid:\n  ${problems.join('\n  ')}`);
    }

    for (const name of Object.keys(ENTRY_POINTS) as FuzzerName[]) {
        new Fuzzer(name, outputDir, amount).saveContracts();
    }
}
