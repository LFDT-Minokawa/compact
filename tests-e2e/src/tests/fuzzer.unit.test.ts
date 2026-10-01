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

import { ENTRY_POINTS, TERMINALS, grammar, validate, validateCategories, type FuzzerName } from '../fuzzer/grammar';
import { DEFAULT_CONTRACTS_PER_FUZZER, MAX_CONTRACTS_PER_FUZZER, resolveContractCount } from '../fuzzer/fuzzers';
import { Fuzzer } from '../fuzzer/utils/fuzzer';
import type { Grammar } from '../fuzzer/grammar/types';

const fuzzerNames = Object.keys(ENTRY_POINTS) as FuzzerName[];

describe('[UNIT] fuzzer grammar', () => {
    test('the production grammar validates cleanly', () => {
        expect(validate()).toEqual([]);
    });

    test('every entry point resolves to a defined production', () => {
        for (const [name, entry] of Object.entries(ENTRY_POINTS)) {
            expect(grammar, `entry point '${name}'`).toHaveProperty(entry);
        }
    });

    test.each(fuzzerNames)("fuzzer '%s' generates non-empty output", (name) => {
        const fuzzer = new Fuzzer(name, '/tmp/unused', 0);
        for (let i = 0; i < 25; i++) {
            expect(fuzzer.generate().trim().length).toBeGreaterThan(0);
        }
    });
});

describe('[UNIT] fuzzer grammar validation catches regressions', () => {
    test('a dangling nonterminal reference is reported', () => {
        const table: Grammar = { ...grammar, statements: [['valid_type']] };
        expect(validate({ table })).toContainEqual(expect.stringContaining("references 'valid_type'"));
    });

    test('a near-miss reference names the production it was probably meant to be', () => {
        const table: Grammar = { ...grammar, statements: [['valid_typess']] };
        expect(validate({ table })).toContainEqual(expect.stringContaining("within two edits of 'valid_types'"));
    });

    test('a production named without an underscore is reported', () => {
        const table: Grammar = { ...grammar, counter: [['1']] };
        const categories = { statements: { counter: [['1']] } as Grammar };
        expect(validate({ table, categories })).toContainEqual(
            expect.stringContaining("'counter' (statements) has no underscore"),
        );
    });

    test('a production defined in two categories is reported', () => {
        const problems = validateCategories({
            first: { shared_production: [['a']] },
            second: { shared_production: [['b']] },
        });
        expect(problems).toEqual([expect.stringContaining("'shared_production' is defined in both 'first' and 'second'")]);
    });

    test('an unreachable production is reported', () => {
        const table: Grammar = { ...grammar, orphan_production: [['a']] };
        expect(validate({ table })).toContainEqual(expect.stringContaining("'orphan_production'"));
    });

    test('a terminal no reachable production references is reported', () => {
        const terminals = [...TERMINALS, 'generate_nested_if'];
        expect(validate({ terminals })).toEqual([
            expect.stringContaining("terminal 'generate_nested_if' is declared and generated"),
        ]);
    });
});

describe('[UNIT] fuzzer contract count', () => {
    test.each([
        ['1', 1],
        ['250', 250],
        [String(MAX_CONTRACTS_PER_FUZZER), MAX_CONTRACTS_PER_FUZZER],
    ])('a usable count is taken as given: %s', (raw, expected) => {
        expect(resolveContractCount(raw)).toBe(expected);
    });

    test.each([
        ['undefined', undefined],
        ['empty', ''],
        ['whitespace', '   '],
        ['non-numeric', 'abc'],
        ['zero', '0'],
        ['negative', '-1'],
        ['fractional', '3.7'],
        ['Infinity', 'Infinity'],
        ['NaN', 'NaN'],
        ['above the cap', String(MAX_CONTRACTS_PER_FUZZER + 1)],
        ['absurd', '1e9'],
    ])('%s falls back to the default', (_label, raw) => {
        expect(resolveContractCount(raw)).toBe(DEFAULT_CONTRACTS_PER_FUZZER);
    });
});
