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

import type { SerializedError } from 'vitest';
import type {
    TestCase,
    TestModule,
    TestRunEndReason,
    TestState,
} from 'vitest/node';
import { DefaultReporter } from 'vitest/reporters';

import type { FixtureTestMetadata } from './types.ts';
import { fixtureMetadataKey, normalizePath } from './utils.ts';

type SlowCompileCase = {
    duration: number;
    filePath: string;
};

/**
 * A fixture path split into tree headers plus the leaf line to print.
 */
type FixtureDisplay = {
    groupParts: string[];
    indent: string;
    leafPath: string;
};

const orchestratorFile = 'compact-test-orchestrator.test.ts';
const ansiReset = '\u001b[0m';
const ansiColors = {
    dim: '\u001b[2m',
    green: '\u001b[32m',
    red: '\u001b[31m',
    yellow: '\u001b[33m',
};

export default class CompactTestFixtureReporter extends DefaultReporter {
    lastHeaderParts: string[] = [];
    slowCompileCases: SlowCompileCase[] = [];

    onTestCaseResult(testCase: TestCase) {
        const fixtureCase = fixtureCaseFromTest(testCase);

        if (fixtureCase === undefined) {
            super.onTestCaseResult(testCase);
            return;
        }

        super.onTestCaseResult(testCase);
        this.logFixtureCase(testCase, fixtureCase);

        if (isSlowCompileCase(fixtureCase)) {
            this.slowCompileCases.push({
                duration: Math.round(testCase.diagnostic()?.duration ?? 0),
                filePath: fixtureCase.filePath,
            });
        }
    }

    onTestModuleEnd(testModule: TestModule) {
        if (isOrchestratorModule(testModule.moduleId)) {
            return;
        }

        super.onTestModuleEnd(testModule);
    }

    onTestRunEnd(
        testModules: ReadonlyArray<TestModule>,
        unhandledErrors: ReadonlyArray<SerializedError>,
        reason: TestRunEndReason,
    ) {
        this.logSlowCompileSummary();
        super.onTestRunEnd(testModules, unhandledErrors, reason);
    }

    logFixtureCase(testCase: TestCase, fixtureCase: FixtureTestMetadata) {
        const display = fixtureDisplayFromPath(fixtureCase.filePath);

        for (const header of headerLines(
            display.groupParts,
            this.lastHeaderParts,
        )) {
            this.log(header);
        }

        this.lastHeaderParts = display.groupParts;
        this.log(
            formatFixtureLine(
                testCase,
                fixtureCase,
                display.leafPath,
                display.indent,
                this,
            ),
        );
    }

    logSlowCompileSummary() {
        if (this.slowCompileCases.length === 0) {
            return;
        }

        this.log('');
        this.log('Slow compile fixtures');

        let lastHeaderParts: string[] = [];

        for (const fixtureCase of this.slowCompileCases.toSorted(
            (left, right) => left.filePath.localeCompare(right.filePath),
        )) {
            const display = slowSummaryDisplayFromPath(fixtureCase.filePath);

            for (const header of headerLines(
                display.groupParts,
                lastHeaderParts,
            )) {
                this.log(header);
            }

            lastHeaderParts = display.groupParts;
            this.log(
                `${display.indent}${display.leafPath} ${formatDuration(fixtureCase.duration)}`,
            );
        }
    }
}

/**
 * Maps an orchestrated Vitest test case back to its fixture test file.
 */
function fixtureCaseFromTest(
    testCase: TestCase,
): FixtureTestMetadata | undefined {
    if (!isOrchestratorModule(testCase.module.moduleId)) {
        return undefined;
    }

    const metadata = (testCase.meta() as Record<string, unknown>)[
        fixtureMetadataKey
    ];

    if (!isFixtureMetadata(metadata)) {
        return undefined;
    }

    return metadata;
}

/**
 * Formats one completed fixture case like Vitest's file-level output.
 */
function formatFixtureLine(
    testCase: TestCase,
    fixtureCase: FixtureTestMetadata,
    leafPath: string,
    indent: string,
    reporter: CompactTestFixtureReporter,
): string {
    const duration = Math.round(
        fixtureCase.durationMs ?? testCase.diagnostic()?.duration ?? 0,
    );
    const state = testCase.result().state;
    const useColors = shouldUseColors(reporter);
    const mark = colorByState(state, stateMark(state), useColors);
    const testCount = colorize('(1 test)', ansiColors.dim, useColors);
    const durationText = colorize(
        formatDuration(duration),
        durationColor(state, duration, reporter),
        useColors,
    );

    return `${indent}${mark} ${leafPath} ${testCount} ${durationText}`;
}

/**
 * Converts one fixture path into tree headers plus its display leaf.
 */
function fixtureDisplayFromPath(filePath: string): FixtureDisplay {
    const parts = normalizePath(filePath).split('/');
    const fileName = parts.at(-1) ?? '';
    const phase = fileName.startsWith('runtime.') ? 'runtime' : 'compile';
    const groupParts = [phase, ...parts.slice(0, -2)];

    return {
        groupParts,
        indent: '  '.repeat(groupParts.length),
        leafPath: parts.slice(-2).join('/'),
    };
}

/**
 * Converts one slow fixture path into a tree summary without a phase root.
 */
function slowSummaryDisplayFromPath(filePath: string): FixtureDisplay {
    const parts = normalizePath(filePath).split('/');
    const groupParts = parts.slice(0, -2);

    return {
        groupParts,
        indent: '  '.repeat(groupParts.length),
        leafPath: parts.slice(-2).join('/'),
    };
}

/**
 * Returns the new tree headers needed after moving from the previous group.
 */
function headerLines(
    groupParts: string[],
    previousGroupParts: string[],
): string[] {
    const commonLength = commonPrefixLength(groupParts, previousGroupParts);

    return groupParts.slice(commonLength).map((part, index) => {
        const depth = commonLength + index;

        return `${'  '.repeat(depth)}${part}/`;
    });
}

/**
 * Finds the shared prefix between two tree paths.
 */
function commonPrefixLength(left: string[], right: string[]): number {
    const maxLength = Math.min(left.length, right.length);

    for (let index = 0; index < maxLength; index += 1) {
        if (left[index] !== right[index]) {
            return index;
        }
    }

    return maxLength;
}

/**
 * Chooses a compact status marker for one finished test.
 */
function stateMark(state: TestState): string {
    if (state === 'passed') {
        return '✓';
    }

    if (state === 'skipped') {
        return '↓';
    }

    return '×';
}

/**
 * Applies a Vitest-like state color to one completed fixture line.
 */
function colorByState(
    state: TestState,
    value: string,
    useColors: boolean,
): string {
    if (state === 'passed') {
        return colorize(value, ansiColors.green, useColors);
    }

    if (state === 'skipped') {
        return colorize(value, ansiColors.yellow, useColors);
    }

    return colorize(value, ansiColors.red, useColors);
}

/**
 * Chooses a duration color close to Vitest's default reporter.
 */
function durationColor(
    state: TestState,
    duration: number,
    reporter: CompactTestFixtureReporter,
): string {
    if (state === 'failed') {
        return ansiColors.red;
    }

    return duration > reporter.ctx.config.slowTestThreshold
        ? ansiColors.yellow
        : ansiColors.green;
}

/**
 * Formats durations compactly while keeping long compiler work readable.
 */
function formatDuration(duration: number): string {
    return duration >= 1000
        ? `${(duration / 1000).toFixed(2)}s`
        : `${duration}ms`;
}

/**
 * Colors text only when terminal output supports ANSI colors.
 */
function colorize(value: string, color: string, useColors: boolean): string {
    return useColors ? `${color}${value}${ansiReset}` : value;
}

/**
 * Checks whether this reporter should emit ANSI color escapes.
 */
function shouldUseColors(reporter: CompactTestFixtureReporter): boolean {
    if (process.env.FORCE_COLOR === '0') {
        return false;
    }

    if (process.env.FORCE_COLOR !== undefined) {
        return true;
    }

    if (process.env.NO_COLOR !== undefined) {
        return false;
    }

    return reporter.isTTY;
}

/**
 * Checks whether a reporter event belongs to the hidden orchestrator module.
 */
function isOrchestratorModule(moduleId: string): boolean {
    return normalizePath(moduleId).endsWith(`/${orchestratorFile}`);
}

/**
 * Checks whether Vitest task metadata has the fixture fields this reporter needs.
 */
function isFixtureMetadata(value: unknown): value is FixtureTestMetadata {
    return (
        typeof value === 'object' &&
        value !== null &&
        typeof (value as FixtureTestMetadata).filePath === 'string'
    );
}

/**
 * Checks whether a fixture result belongs in the slow compile summary.
 */
function isSlowCompileCase(fixtureCase: FixtureTestMetadata): boolean {
    const parts = normalizePath(fixtureCase.filePath).split('/');
    const fileName = parts.at(-1) ?? '';

    return parts.includes('slow') && fileName.startsWith('compile.');
}
