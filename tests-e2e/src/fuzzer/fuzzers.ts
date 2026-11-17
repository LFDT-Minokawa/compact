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

import { ENTRY_POINTS, FEATURES, buildGrammar, validate, validateCatalogue, type Feature, type FuzzerName } from './grammar';
import { Fuzzer } from './utils/fuzzer';

/** A generated contract and the compiler flags it has to be compiled with. */
export interface GeneratedContract {
    file: string;
    flags: string[];
}

/*
 * One run with no flags, then one per opt-in compiler feature. The list follows
 * `FEATURES`, so a backend arriving or shipping as the default changes nothing here.
 */
const variants = (): { label: string; features: Feature[] }[] => [
    { label: '', features: [] },
    ...(Object.keys(FEATURES) as Feature[]).map((feature) => ({ label: feature, features: [feature] })),
];

export const DEFAULT_CONTRACTS_PER_FUZZER = 1000;

export const MAX_CONTRACTS_PER_FUZZER = 2_000;

export function resolveContractCount(raw: string | undefined): number {
    const requested = Number(raw);
    if (!Number.isSafeInteger(requested) || requested < 1 || requested > MAX_CONTRACTS_PER_FUZZER) {
        return DEFAULT_CONTRACTS_PER_FUZZER;
    }
    return requested;
}

export function generate(outputDir: string, amount: number): GeneratedContract[] {
    /* Build every grammar first: a type may be reachable only under a feature flag. */
    const built = variants().map((variant) => ({ ...variant, table: buildGrammar(variant.features) }));

    const problems = [...built.flatMap(({ table }) => validate({ table })), ...validateCatalogue()];
    if (problems.length > 0) {
        throw new Error(`fuzzer grammar is invalid:\n  ${[...new Set(problems)].join('\n  ')}`);
    }

    const written: GeneratedContract[] = [];
    for (const { label, features, table } of built) {
        const flags = features.map((feature) => FEATURES[feature]);
        for (const name of Object.keys(ENTRY_POINTS) as FuzzerName[]) {
            const fuzzer = new Fuzzer(name, outputDir, amount, {
                grammar: table,
                label: label ? `${name}_${label}` : name,
            });
            for (const file of fuzzer.saveContracts()) written.push({ file, flags });
        }
    }
    return written;
}
