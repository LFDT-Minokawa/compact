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

/**
 * Indexes every name Compact offers against the fixtures that use it.
 *
 * `./compiler/go` cannot answer this: `some` and `mergeCoin` compile through
 * identical code, so no line coverage separates a covered circuit from an
 * uncovered one. Names come from compiler sources, so the list cannot go stale.
 */

import { readdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import type {
    ContractFile,
    NameGroup,
    UsageIndex,
    UsageSite,
} from './types.ts';

const COVERAGE_DIR = path.dirname(fileURLToPath(import.meta.url));
const TEST_ROOT = path.dirname(COVERAGE_DIR);
const REPO_ROOT = path.dirname(TEST_ROOT);
const FIXTURE_ROOT = path.join(TEST_ROOT, 'primitives');
const OUTPUT_PATH = path.join(COVERAGE_DIR, 'usage.md');

const COMPACT_LIBRARIES: readonly string[] = [
    'standard-library.compact',
    'zkir-v3-library.compact',
];

/** `declare-*` macros that introduce no name a developer can write. */
const NOT_NAME_SOURCES: ReadonlySet<string> = new Set([
    'declare-callable', // a local function in a pass, not a macro
    'declare-ledger-type', // ledger-internal spelling: `Uint64` is `Uint<64>`
]);

const prefix: string = 'Invariant failed';

const invariant: (condition: unknown, message?: string) => asserts condition = (
    condition,
    message?: string,
) => {
    if (condition) {
        return;
    }

    throw new Error(message ? `${prefix}: ${message}` : prefix);
};

const unique = <T>(values: T[]): T[] => [...new Set(values)];

const walk = function* (
    directory: string,
    extension: string,
): Generator<string> {
    for (const entry of readdirSync(directory, { withFileTypes: true })) {
        const absolutePath = path.join(directory, entry.name);
        if (entry.isDirectory()) yield* walk(absolutePath, extension);
        else if (entry.name.endsWith(extension)) yield absolutePath;
    }
};

const headMatches = (source: string, pattern: RegExp): string[] =>
    unique([...source.matchAll(pattern)].map(([, name]) => name));

/** The name after `(declare-x`. The leading `(` skips the macro's own definition. */
const declaredBy = (source: string, macro: string): string[] =>
    headMatches(source, new RegExp(String.raw`\(${macro}\s+(\w+)`, 'g')).filter(
        (name) => name !== 'declare' && name !== 'type',
    );

/** Qualified as `Adt.operation`, because Set, Map and MerkleTree all declare `insert`. */
const ledgerOperations = (source: string): string[] => {
    const chunks = source.split(/^\(declare-ledger-adt\s+(\w+)/m);
    const names: string[] = [];

    for (let index = 1; index < chunks.length; index += 2) {
        const adt = chunks[index];
        for (const operation of headMatches(
            chunks[index + 1],
            /^\s*\(function\s+\w+\s+(\w+)/gm,
        )) {
            names.push(`${adt}.${operation}`);
        }
    }

    return names;
};

/** All compiler sources concatenated; naming files per macro silently missed some. */
const readCompilerSources = (): string =>
    [...walk(path.join(REPO_ROOT, 'compiler'), '.ss')]
        .filter((file) => path.basename(file) !== 'test.ss')
        .map((file) => readFileSync(file, 'utf8'))
        .join('\n');

/** Reads every name Compact offers out of the compiler's own declarations. */
const buildGroups = (compilerSources: string): NameGroup[] => {
    const compilerFile = (name: string): string =>
        readFileSync(path.join(REPO_ROOT, 'compiler', name), 'utf8');

    const stdlib = COMPACT_LIBRARIES.map(compilerFile).join('\n');
    const dataTypes =
        /keywordDataTypes[\s\S]*?\(TITLE[^)]*\)\s*\(([^)]*)\)/.exec(
            compilerFile('parser.ss'),
        );
    invariant(
        dataTypes,
        'keywordDataTypes group not found in compiler/parser.ss',
    );

    return [
        {
            title: 'Builtin types',
            source: 'parser.ss — keywordDataTypes',
            names: unique(dataTypes[1].match(/[A-Za-z_]\w*/g) ?? []),
        },
        {
            title: 'Standard library circuits',
            source: 'shipped Compact libraries — export circuit',
            names: headMatches(
                stdlib,
                /^\s*export\s+(?:pure\s+)?circuit\s+(\w+)/gm,
            ),
        },
        {
            title: 'Standard library structs',
            source: 'shipped Compact libraries — export struct',
            names: headMatches(stdlib, /^\s*export\s+struct\s+(\w+)/gm),
        },
        {
            title: 'Ledger ADT operations',
            source: 'compiler sources — declare-ledger-adt',
            macro: 'declare-ledger-adt',
            names: ledgerOperations(compilerSources),
            qualified: true,
        },
        {
            title: 'Event types',
            source: 'compiler sources — declare-event-type',
            macro: 'declare-event-type',
            names: declaredBy(compilerSources, 'declare-event-type'),
        },
        {
            title: 'Native circuits and witnesses',
            source: 'compiler sources — declare-native-entry',
            macro: 'declare-native-entry',
            names: headMatches(
                compilerSources,
                /\(declare-native-entry\s+\w+\s+(\w+)/g,
            ),
        },
        {
            title: 'Native types',
            source: 'compiler sources — declare-native-type',
            macro: 'declare-native-type',
            names: declaredBy(compilerSources, 'declare-native-type'),
        },
        {
            title: 'Inline entries',
            source: 'compiler sources — declare-inline-entry',
            macro: 'declare-inline-entry',
            names: declaredBy(compilerSources, 'declare-inline-entry'),
        },
    ];
};

/** Fails on a `declare-*` macro no group reads, so a new one cannot pass unnoticed. */
const assertEveryDeclarationSiteIsClaimed = (
    groups: NameGroup[],
    compilerSources: string,
): void => {
    const claimed = new Set(groups.map((group) => group.macro).filter(Boolean));
    const invoked = unique(
        [...compilerSources.matchAll(/\((declare-[a-z-]+)\s/g)].map(
            ([, macro]) => macro,
        ),
    );
    const unclaimed = invoked.filter(
        (macro) => !claimed.has(macro) && !NOT_NAME_SOURCES.has(macro),
    );

    invariant(
        unclaimed.length === 0,
        `compiler declares names through unhandled macro(s): ${unclaimed.join(', ')}. ` +
            'Add a group in buildGroups, or list the macro in NOT_NAME_SOURCES.',
    );

    const unreadLibraries = readdirSync(path.join(REPO_ROOT, 'compiler'))
        .filter((entry) => entry.endsWith('.compact'))
        .filter((entry) => !COMPACT_LIBRARIES.includes(entry));

    invariant(
        unreadLibraries.length === 0,
        `compiler ships Compact libraries no group reads: ${unreadLibraries.join(', ')}. ` +
            'Add them to COMPACT_LIBRARIES.',
    );
};

/** Fixtures, sorted so the report is byte-stable for the CI staleness check. */
const collectFixtures = (): ContractFile[] =>
    [...walk(FIXTURE_ROOT, '.compact')]
        .filter((file) => !/[/\\]\.build|\.compact-test-build/.test(file))
        .map((file) => ({
            absolutePath: file,
            path: path.relative(REPO_ROOT, file),
        }))
        .sort((left, right) => left.path.localeCompare(right.path));

/**
 * Blanks comments and string literals; an assert message mentioning `emit`
 * otherwise counts as using it. Comments go first — the licence header has an
 * unbalanced quote. Literals become `""` so line numbers survive.
 */
const sanitize = (source: string): string =>
    source
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/\/\/.*$/gm, '')
        .replace(/"(?:[^"\\\n]|\\.)*"/g, '""')
        .replace(/'(?:[^'\\\n]|\\.)*'/g, "''");

/**
 * `counter` -> `Counter`, so `counter.increment()` resolves to `Counter.increment`.
 * A non-ADT type means a Cell; "Cell" is never written in Compact source.
 */
const ledgerReceivers = (
    source: string,
    adts: ReadonlySet<string>,
): Map<string, string> => {
    const receivers = new Map<string, string>([['kernel', 'Kernel']]);

    for (const [, field, type] of source.matchAll(
        /\bledger\s+(\w+)\s*:\s*(\w+)/g,
    )) {
        receivers.set(field, adts.has(type) ? type : 'Cell');
    }

    return receivers;
};

/** Every usage site per name. Plain names match as words; ledger ops need a receiver. */
const indexUsage = (
    fixtures: ContractFile[],
    groups: NameGroup[],
): UsageIndex => {
    const plainNames = new Set(
        groups
            .filter((group) => !group.qualified)
            .flatMap((group) => group.names),
    );
    const adts = new Set(
        groups
            .filter((group) => group.qualified)
            .flatMap((group) => group.names.map((name) => name.split('.')[0])),
    );

    const usage: UsageIndex = new Map();
    const record = (name: string, site: UsageSite): void => {
        const sites = usage.get(name) ?? [];
        sites.push(site);
        usage.set(name, sites);
    };

    for (const fixture of fixtures) {
        const source = sanitize(readFileSync(fixture.absolutePath, 'utf8'));
        const receivers = ledgerReceivers(source, adts);

        source.split('\n').forEach((text, index) => {
            const site: UsageSite = { line: index + 1, path: fixture.path };

            for (const word of new Set(text.match(/[A-Za-z_]\w*/g) ?? [])) {
                if (plainNames.has(word)) record(word, site);
            }

            for (const [, receiver, operation] of text.matchAll(
                /\b(\w+)\s*\.\s*(\w+)\s*\(/g,
            )) {
                const adt = receivers.get(receiver);
                if (adt) record(`${adt}.${operation}`, site);
            }
        });
    }

    return usage;
};

const renderReport = (
    groups: NameGroup[],
    usage: UsageIndex,
    fixtures: ContractFile[],
): string => {
    const lines: string[] = [];
    const covered = (name: string): UsageSite[] => usage.get(name) ?? [];

    lines.push('# Compact language usage index');
    lines.push('');
    lines.push(
        `Scanned the **${fixtures.length} fixtures** in \`test-contracts/\`.`,
    );
    lines.push('');

    const gaps = groups.flatMap((group) =>
        group.names
            .filter((name) => covered(name).length === 0)
            .map((name) => ({ group: group.title, name })),
    );

    lines.push(`## Not covered by any fixture — ${gaps.length}`);
    lines.push('');
    if (gaps.length === 0) {
        lines.push('Every name is used by at least one fixture.');
    } else {
        lines.push('| name | group |');
        lines.push('|---|---|');
        for (const gap of gaps)
            lines.push(`| \`${gap.name}\` | ${gap.group} |`);
    }
    lines.push('');

    for (const group of groups) {
        const used = group.names.filter((name) => covered(name).length > 0);

        lines.push(
            `## ${group.title} — ${used.length}/${group.names.length} covered`,
        );
        lines.push('');
        lines.push(`Declared in \`${group.source}\`.`);
        lines.push('');
        lines.push('| name | first usage | uses |');
        lines.push('|---|---|---:|');

        for (const name of group.names) {
            const sites = covered(name);
            if (sites.length === 0) {
                lines.push(`| \`${name}\` | **no fixture** | 0 |`);
                continue;
            }

            const [{ path: file, line }] = sites;
            lines.push(
                `| \`${name}\` | [\`${file}:${line}\`](../../${file}#L${line}) | ${sites.length} |`,
            );
        }
        lines.push('');
    }

    lines.push('## What this does and does not show');
    lines.push('');
    lines.push(
        '- **Used is not tested.** A usage site proves a fixture mentions the name. ' +
            "Whether it is meaningfully exercised depends on that fixture's assertions.",
    );
    lines.push(
        '- **Names are matched as words**, after comments and string literals are ' +
            'removed. A local variable sharing a standard-library name would still count.',
    );
    lines.push(
        '- **Generic instantiations are not separated** — `some<Field>` and ' +
            '`some<Bytes<32>>` are one entry.',
    );
    lines.push('');

    return lines.join('\n');
};

const main = (): void => {
    const compilerSources = readCompilerSources();
    const groups = buildGroups(compilerSources);
    assertEveryDeclarationSiteIsClaimed(groups, compilerSources);

    const fixtures = collectFixtures();
    const usage = indexUsage(fixtures, groups);
    writeFileSync(OUTPUT_PATH, renderReport(groups, usage, fixtures));

    const total = groups.reduce(
        (count, group) => count + group.names.length,
        0,
    );
    const used = groups.reduce(
        (count, group) =>
            count +
            group.names.filter((name) => (usage.get(name) ?? []).length > 0)
                .length,
        0,
    );

    console.log(
        `usage index: ${used}/${total} names covered by ${fixtures.length} fixtures; ` +
            `wrote ${path.relative(REPO_ROOT, OUTPUT_PATH)}`,
    );
};

main();

export { buildGroups, indexUsage, renderReport };
