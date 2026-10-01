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

import { Grammar, Token } from './types';
import { CATEGORIES, ENTRY_POINTS, TERMINALS, compact, type Category, type FuzzerName, type Terminal } from './compact';

export { CATEGORIES, ENTRY_POINTS, TERMINALS, type Category, type FuzzerName, type Terminal };

export const grammar: Grammar = compact;

type Categories = Record<string, Grammar>;

export interface GrammarSpec {
    table?: Grammar;
    categories?: Categories;
    entryPoints?: Record<string, string>;
    terminals?: readonly string[];
}

const categoryOf = (name: string, categories: Categories): string => {
    for (const [category, productions] of Object.entries(categories)) {
        if (name in productions) return category;
    }
    return 'unknown';
};

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

const INTENTIONAL_LITERALS = new Set([
    'var_struct',
    'var_counter',
    'var_set',
    'var_map',
    'var_list',
    'var_mt',
    'var_hmt',
    'language_version',
    'compiler_version',
    'path',
    'to',
]);

const looksLikeNonterminal = (token: Token): boolean => /^[a-z][a-z0-9]*(_[a-z0-9]+)+$/.test(token);

const BARE_NAMES_ALLOWED = new Set(['statements', 'statement']);

function bareProductionNames(table: Grammar, categories: Categories): string[] {
    return Object.keys(table)
        .filter((name) => !name.includes('_') && !BARE_NAMES_ALLOWED.has(name))
        .map(
            (name) =>
                `'${name}' (${categoryOf(name, categories)}) has no underscore, so a literal '${name}' anywhere in the ` +
                'grammar would silently expand into it instead of being emitted as text',
        );
}

export function validateCategories(categories: Categories): string[] {
    const owner = new Map<string, string>();
    const problems: string[] = [];
    for (const [category, productions] of Object.entries(categories)) {
        for (const name of Object.keys(productions)) {
            const previous = owner.get(name);
            if (previous) {
                problems.push(`'${name}' is defined in both '${previous}' and '${category}'; only the last survives`);
            }
            owner.set(name, category);
        }
    }
    return problems;
}

function reachable(table: Grammar, entryPoints: Record<string, string>) {
    const productions = new Set<string>();
    const tokens = new Set<string>();
    const walk = (node: string): void => {
        if (productions.has(node) || !(node in table)) return;
        productions.add(node);
        for (const alternative of table[node]) {
            if (!Array.isArray(alternative)) continue;
            for (const child of alternative) {
                tokens.add(child);
                walk(child);
            }
        }
    };
    for (const entry of Object.values(entryPoints)) walk(entry);
    return { productions, tokens };
}

/* Detect failures that otherwise degrade generated coverage silently. */
export function validate(spec: GrammarSpec = {}): string[] {
    const table = spec.table ?? grammar;
    const categories = spec.categories ?? CATEGORIES;
    const entryPoints = spec.entryPoints ?? ENTRY_POINTS;
    const terminals = spec.terminals ?? TERMINALS;

    const problems: string[] = [...validateCategories(categories), ...bareProductionNames(table, categories)];
    const defined = new Set<string>([...Object.keys(table), ...terminals]);

    const reported = new Set<string>();
    for (const [name, alternatives] of Object.entries(table)) {
        for (const alternative of alternatives) {
            if (!Array.isArray(alternative)) continue;
            for (const node of alternative) {
                if (!looksLikeNonterminal(node) || defined.has(node) || INTENTIONAL_LITERALS.has(node)) continue;
                const key = `${name}:${node}`;
                if (reported.has(key)) continue;
                reported.add(key);
                const near = [...defined].find((d) => d !== node && editDistanceWithin(node, d, 2));
                problems.push(
                    near
                        ? `'${name}' (${categoryOf(name, categories)}) references '${node}', undefined but within two edits of '${near}' -- emitted as literal text`
                        : `'${name}' (${categoryOf(name, categories)}) references '${node}', which is not defined -- emitted as literal text`,
                );
            }
        }
    }

    const { productions, tokens } = reachable(table, entryPoints);

    for (const name of Object.keys(table).filter((name) => !productions.has(name))) {
        problems.push(`'${name}' (${categoryOf(name, categories)}) is unreachable from every entry point`);
    }

    for (const terminal of terminals.filter((terminal) => !tokens.has(terminal))) {
        problems.push(`terminal '${terminal}' is declared and generated but no reachable production references it`);
    }

    return problems;
}
