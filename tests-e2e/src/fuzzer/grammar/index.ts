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
 * Grammar assembly and health checks.
 *
 * The grammar itself lives in compact.ts. This module only puts the categories
 * together and guards against the ways the table can rot.
 */

import { Alternative, Grammar, Token } from './types';
import { CATEGORIES, ENTRY_POINTS, TERMINALS, compact, type Category, type FuzzerName } from './compact';

export { CATEGORIES, ENTRY_POINTS, TERMINALS, type Category, type FuzzerName };

export const grammar: Grammar = compact;

const categoryOf = (name: string): Category | 'unknown' => {
    for (const [category, productions] of Object.entries(CATEGORIES)) {
        if (name in productions) return category as Category;
    }
    return 'unknown';
};

/**
 * Levenshtein distance, answered only as "within `max`" so the walk can stop early.
 */
function editDistanceWithin(a: string, b: string, max: number): boolean {
    if (Math.abs(a.length - b.length) > max) return false;
    let prev = Array.from({ length: b.length + 1 }, (_, i) => i);
    for (let i = 1; i <= a.length; i++) {
        const row = [i];
        let best = i;
        for (let j = 1; j <= b.length; j++) {
            row[j] = Math.min(prev[j] + 1, row[j - 1] + 1, prev[j - 1] + (a[i - 1] === b[j - 1] ? 0 : 1));
            best = Math.min(best, row[j]);
        }
        if (best > max) return false;
        prev = row;
    }
    return prev[b.length] <= max;
}

/*
 * Literal identifiers the grammar emits on purpose. Anything else written like a
 * nonterminal but not defined is a reference to a production that never existed or
 * has been removed -- the generator emits an unknown node as literal text, so
 * `valid_type` where `valid_types` was meant silently produces the word instead of
 * a type. That shipped for months.
 */
const INTENTIONAL_LITERALS = new Set([
    'var_struct', 'var_counter', 'var_set', 'var_map', 'var_list', 'var_mt', 'var_hmt',
    'language_version', 'compiler_version', 'path', 'to',
]);

/** Written like a nonterminal: lowercase snake_case with at least one underscore. */
const looksLikeNonterminal = (token: Token): boolean => /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/.test(token);

/**
 * A production defined in two categories: `Object.assign` keeps the last one
 * silently. TypeScript catches a duplicate key *within* one object literal
 * (ts1117); it cannot see a name used in two different categories.
 */
function crossCategoryCollisions(): string[] {
    const owner = new Map<string, Category>();
    const problems: string[] = [];
    for (const [category, productions] of Object.entries(CATEGORIES)) {
        for (const name of Object.keys(productions)) {
            const previous = owner.get(name);
            if (previous) {
                problems.push(`'${name}' is defined in both '${previous}' and '${category}'; only the last survives`);
            }
            owner.set(name, category as Category);
        }
    }
    return problems;
}

/** Productions no entry point can reach: left behind when a caller was rewritten. */
function unreachable(table: Grammar): string[] {
    const reached = new Set<string>();
    const walk = (node: string): void => {
        if (reached.has(node) || !(node in table)) return;
        reached.add(node);
        for (const alternative of table[node]) {
            if (!Array.isArray(alternative)) continue;
            for (const child of alternative as Alternative) walk(child);
        }
    };
    for (const entry of Object.values(ENTRY_POINTS)) walk(entry);
    return Object.keys(table).filter((name) => !reached.has(name));
}

export function validate(table: Grammar = grammar): string[] {
    const problems: string[] = [...crossCategoryCollisions()];
    const defined = new Set<string>([...Object.keys(table), ...TERMINALS]);

    const reported = new Set<string>();
    for (const [name, alternatives] of Object.entries(table)) {
        for (const alternative of alternatives) {
            if (!Array.isArray(alternative)) continue;
            for (const node of alternative as Alternative) {
                if (!looksLikeNonterminal(node) || defined.has(node) || INTENTIONAL_LITERALS.has(node)) continue;
                const key = `${name}:${node}`;
                if (reported.has(key)) continue;
                reported.add(key);
                const near = [...defined].find((d) => d !== node && editDistanceWithin(node, d, 2));
                problems.push(
                    near
                        ? `'${name}' (${categoryOf(name)}) references '${node}', undefined but within two edits of '${near}' -- emitted as literal text`
                        : `'${name}' (${categoryOf(name)}) references '${node}', which is not defined -- emitted as literal text`,
                );
            }
        }
    }

    for (const name of unreachable(table)) {
        problems.push(`'${name}' (${categoryOf(name)}) is unreachable from every entry point`);
    }

    return problems;
}
