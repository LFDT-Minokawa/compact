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

import path from 'node:path';

import { DefaultReporter } from 'vitest/reporters';

const orchestratorFile = 'compact-test-orchestrator.test.ts';
const fixtureMetadataKey = 'compactFixture';
const ansiReset = '\u001b[0m';
const ansiColors = {
    dim: '\u001b[2m',
    green: '\u001b[32m',
    red: '\u001b[31m',
    yellow: '\u001b[33m',
};

export default class CompactTestFixtureReporter extends DefaultReporter {
    lastHeaderParts = [];
    slowCompileCases = [];

    onTestCaseResult(testCase) {
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

    onTestModuleEnd(testModule) {
        if (isOrchestratorModule(testModule.moduleId)) {
            return;
        }

        super.onTestModuleEnd(testModule);
    }

    onTestRunEnd() {
        this.logSlowCompileSummary();
        super.onTestRunEnd();
    }

    logFixtureCase(testCase, fixtureCase) {
        const display = fixtureDisplayFromPath(fixtureCase.filePath);

        for (const header of headerLines(display.groupParts, this.lastHeaderParts)) {
            this.log(header);
        }

        this.lastHeaderParts = display.groupParts;
        this.log(formatFixtureLine(
            testCase,
            fixtureCase,
            display.leafPath,
            display.indent,
            this,
        ));
    }

    logSlowCompileSummary() {
        if (this.slowCompileCases.length === 0) {
            return;
        }

        this.log('');
        this.log('Slow compile fixtures');

        let lastHeaderParts = [];

        for (const fixtureCase of this.slowCompileCases.toSorted((left, right) => (
            left.filePath.localeCompare(right.filePath)
        ))) {
            const display = slowSummaryDisplayFromPath(fixtureCase.filePath);

            for (const header of headerLines(display.groupParts, lastHeaderParts)) {
                this.log(header);
            }

            lastHeaderParts = display.groupParts;
            this.log(`${display.indent}${display.leafPath} ${formatDuration(fixtureCase.duration)}`);
        }
    }
}

/**
 * Maps an orchestrated Vitest test case back to its fixture test file.
 */
function fixtureCaseFromTest(testCase) {
    if (!isOrchestratorModule(testCase.module.moduleId)) {
        return undefined;
    }

    const metadata = testCase.meta()[fixtureMetadataKey];

    if (!isFixtureMetadata(metadata)) {
        return undefined;
    }

    return metadata;
}

/**
 * Formats one completed fixture case like Vitest's file-level output.
 */
function formatFixtureLine(testCase, fixtureCase, leafPath, indent, reporter) {
    const duration = Math.round(
        fixtureCase.durationMs ?? testCase.diagnostic()?.duration ?? 0,
    );
    const state = testCase.result().state;
    const useColors = shouldUseColors(reporter);
    const mark = colorByState(state, stateMark(state), useColors);
    const testCount = colorize(
        '(1 test)',
        ansiColors.dim,
        useColors,
    );
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
function fixtureDisplayFromPath(filePath) {
    const parts = normalizePath(filePath).split('/');
    const fileName = parts.at(-1) ?? '';
    const phase = fileName.startsWith('runtime.')
        ? 'runtime'
        : 'compile';
    const groupParts = [
        phase,
        ...parts.slice(0, -2),
    ];

    return {
        groupParts,
        indent: '  '.repeat(groupParts.length),
        leafPath: parts.slice(-2).join('/'),
    };
}

/**
 * Converts one slow fixture path into a tree summary without a phase root.
 */
function slowSummaryDisplayFromPath(filePath) {
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
function headerLines(groupParts, previousGroupParts) {
    const commonLength = commonPrefixLength(groupParts, previousGroupParts);

    return groupParts.slice(commonLength).map((part, index) => {
        const depth = commonLength + index;

        return `${'  '.repeat(depth)}${part}/`;
    });
}

/**
 * Finds the shared prefix between two tree paths.
 */
function commonPrefixLength(left, right) {
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
function stateMark(state) {
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
function colorByState(state, value, useColors) {
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
function durationColor(state, duration, reporter) {
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
function formatDuration(duration) {
    return duration >= 1000
        ? `${(duration / 1000).toFixed(2)}s`
        : `${duration}ms`;
}

/**
 * Colors text only when terminal output supports ANSI colors.
 */
function colorize(value, color, useColors) {
    return useColors
        ? `${color}${value}${ansiReset}`
        : value;
}

/**
 * Checks whether this reporter should emit ANSI color escapes.
 */
function shouldUseColors(reporter) {
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
function isOrchestratorModule(moduleId) {
    return normalizePath(moduleId).endsWith(`/${orchestratorFile}`);
}

/**
 * Checks whether Vitest task metadata has the fixture fields this reporter needs.
 */
function isFixtureMetadata(value) {
    return typeof value === 'object' &&
        value !== null &&
        typeof value.filePath === 'string';
}

/**
 * Checks whether a fixture result belongs in the slow compile summary.
 */
function isSlowCompileCase(fixtureCase) {
    const parts = normalizePath(fixtureCase.filePath).split('/');
    const fileName = parts.at(-1) ?? '';

    return parts.includes('slow') && fileName.startsWith('compile.');
}

/**
 * Normalizes path separators for stable module matching.
 */
function normalizePath(value) {
    return value.split(path.sep).join('/');
}
