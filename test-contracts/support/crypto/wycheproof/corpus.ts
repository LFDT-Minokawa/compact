// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { buildReport, formatFailure, type KatOutcome } from '../kat.ts';

// Shared Wycheproof parts: the file shape, the loader, and the runner.
// Each signature scheme decodes its own signatures and keys.

const dataDir = path.join(
    path.dirname(fileURLToPath(import.meta.url)),
    '..',
    'data',
);

type CorpusResult = 'valid' | 'invalid';

/** One test case, in the shape every Wycheproof file uses. */
export type CorpusTest = {
    tcId: number;
    comment: string;
    flags?: string[];
    /** Hex message. */
    msg: string;
    /** Signature as hex; each scheme decodes it its own way. */
    sig: string;
    result: CorpusResult;
};

/** The file envelope. `Group` varies by crypto signature scheme. */
export type CorpusRoot<Group> = {
    algorithm: string;
    schema: string;
    numberOfTests: number;
    testGroups: Group[];
};

export function loadCorpus<Root>(vectorsFile: string): Root {
    return JSON.parse(
        fs.readFileSync(path.join(dataDir, vectorsFile), 'utf8'),
    ) as Root;
}

/** What a vector should do; `abort` means the circuit must fail. */
export type Expectation = 'valid' | 'invalid' | 'abort';

export type DrivenVector = {
    tcId: number;
    comment: string;
    expectation: Expectation;
};

/** Vectors a suite chose not to run, kept so the count stays visible. */
export type Excluded = {
    reason: string;
    tcIds: number[];
};

export type Classified<V extends DrivenVector> = {
    total: number;
    driven: V[];
    excluded: Excluded[];
};

/** The counts a suite expects, so a corpus change is noticed. */
export type Coverage = {
    total: number;
    driven: number;
    excluded: Record<string, number>;
};

/** Runs every vector and checks it did what was expected. */
export function runCorpusKat<V extends DrivenVector>(
    label: string,
    classified: Classified<V>,
    drive: (vector: V) => boolean,
    isExpectedAbort: (error: unknown) => boolean,
    notes?: (classified: Classified<V>) => string[],
): Classified<V> {
    const outcomes: KatOutcome[] = [];

    for (const vector of classified.driven) {
        const vectorLabel = `tcId ${vector.tcId} (${vector.comment})`;
        let got: Expectation;

        try {
            got = drive(vector) ? 'valid' : 'invalid';
        } catch (error) {
            if (vector.expectation === 'abort' && isExpectedAbort(error)) {
                outcomes.push({ label: vectorLabel, ok: true });
                continue;
            }

            outcomes.push({
                label: vectorLabel,
                ok: false,
                detail: `expected ${vector.expectation}, failed instead: ${
                    error instanceof Error ? error.message : String(error)
                }`,
            });
            continue;
        }

        outcomes.push(
            got === vector.expectation
                ? { label: vectorLabel, ok: true }
                : {
                      label: vectorLabel,
                      ok: false,
                      detail: `expected ${vector.expectation}, got ${got}`,
                  },
        );
    }

    const report = buildReport(label, outcomes);

    if (report.failed.length > 0) {
        throw new Error(
            formatFailure(report, {
                notes: coverageLines(classified, notes?.(classified) ?? []),
            }),
        );
    }

    return classified;
}

function coverageLines<V extends DrivenVector>(
    classified: Classified<V>,
    notes: string[],
): string[] {
    return [
        `corpus:  ${classified.total} vectors`,
        `driven:  ${classified.driven.length}`,
        ...classified.excluded.map(
            ({ reason, tcIds }) =>
                `excluded (${reason}): ${tcIds.length}${
                    tcIds.length > 0 && tcIds.length <= 8
                        ? ` (tcIds ${tcIds.join(', ')})`
                        : ''
                }`,
        ),
        ...notes,
    ];
}

/**
 * Fails when the buckets drift from what was pinned. Coverage reported only on
 * failure can shrink silently; this makes a corpus refresh an explicit update.
 */
export function assertCoverage<V extends DrivenVector>(
    name: string,
    classified: Classified<V>,
    coverage: Coverage,
): void {
    const actual: Coverage = {
        total: classified.total,
        driven: classified.driven.length,
        excluded: Object.fromEntries(
            classified.excluded.map(({ reason, tcIds }) => [
                reason,
                tcIds.length,
            ]),
        ),
    };
    const drift: string[] = [];

    if (actual.total !== coverage.total) {
        drift.push(`total: expected ${coverage.total}, got ${actual.total}`);
    }

    if (actual.driven !== coverage.driven) {
        drift.push(`driven: expected ${coverage.driven}, got ${actual.driven}`);
    }

    for (const [reason, want] of Object.entries(coverage.excluded)) {
        if (actual.excluded[reason] !== want) {
            drift.push(
                `${reason}: expected ${want}, got ${actual.excluded[reason] ?? 0}`,
            );
        }
    }

    if (drift.length > 0) {
        throw new Error(
            `${name} coverage drifted (${drift.join('; ')}). If the vectors were refreshed, ` +
                'update the suite coverage and the checksums in support/crypto/data/README.md.',
        );
    }
}
