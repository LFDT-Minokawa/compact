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

// Runs a whole table of vectors and reports every failure, not just the first.

export type KatOutcome = {
    /** Short vector identity, e.g. `Bytes<62>` or `tcId 388`. */
    label: string;
    ok: boolean;
    /** The failure message; absent when the vector passed. */
    detail?: string;
};

export type KatReport = {
    label: string;
    outcomes: KatOutcome[];
    passed: number;
    failed: KatOutcome[];
};

export type KatOptions = {
    /** Extra summary lines, so vectors a fixture skipped stay visible. */
    notes?: string[];
    /** Failing vectors named in the thrown message before it elides the rest. */
    sampleSize?: number;
};

/** Runs every vector, then throws once if any of them failed. */
export function runKat<V>(
    label: string,
    vectors: readonly V[],
    labelOf: (vector: V) => string,
    check: (vector: V) => void,
    options: KatOptions = {},
): KatReport {
    const outcomes: KatOutcome[] = [];

    for (const vector of vectors) {
        const vectorLabel = labelOf(vector);

        try {
            check(vector);
            outcomes.push({ label: vectorLabel, ok: true });
        } catch (error) {
            outcomes.push(failure(vectorLabel, error));
        }
    }

    return finish(label, outcomes, options);
}

/** Same as runKat, for checks that await. */
export async function runKatAsync<V>(
    label: string,
    vectors: readonly V[],
    labelOf: (vector: V) => string,
    check: (vector: V) => void | Promise<void>,
    options: KatOptions = {},
): Promise<KatReport> {
    const outcomes: KatOutcome[] = [];

    for (const vector of vectors) {
        const vectorLabel = labelOf(vector);

        try {
            await check(vector);
            outcomes.push({ label: vectorLabel, ok: true });
        } catch (error) {
            outcomes.push(failure(vectorLabel, error));
        }
    }

    return finish(label, outcomes, options);
}

/** Records one thrown error as a failed vector. */
function failure(label: string, error: unknown): KatOutcome {
    return {
        label,
        ok: false,
        detail: error instanceof Error ? error.message : String(error),
    };
}

/** Builds the report and throws if anything failed. */
function finish(
    label: string,
    outcomes: KatOutcome[],
    options: KatOptions,
): KatReport {
    const report = buildReport(label, outcomes);

    if (report.failed.length > 0) {
        throw new Error(formatFailure(report, options));
    }

    return report;
}

/** Groups outcomes into a report, for callers that drive their own vectors. */
export function buildReport(label: string, outcomes: KatOutcome[]): KatReport {
    const failed = outcomes.filter((outcome) => !outcome.ok);

    return {
        label,
        outcomes,
        passed: outcomes.length - failed.length,
        failed,
    };
}

/** Turns a report into the message of the one error a failed run throws. */
export function formatFailure(
    report: KatReport,
    options: KatOptions = {},
): string {
    const { notes = [], sampleSize = 8 } = options;
    const { label, outcomes, passed, failed } = report;
    const sample = failed
        .slice(0, sampleSize)
        .map((outcome) => `${outcome.label}: ${outcome.detail}`);
    const elided = failed.length - sample.length;

    return [
        `${label}: ${failed.length}/${outcomes.length} vectors failed (${passed} passed).`,
        ...notes.map((note) => `  ${note}`),
        ...sample.map((line) => `  ${line}`),
        ...(elided > 0 ? [`  ...and ${elided} more`] : []),
    ].join('\n');
}
