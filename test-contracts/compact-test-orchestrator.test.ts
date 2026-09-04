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

import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { afterAll, describe, test } from 'vitest';

import type {
    CompactContractConstructor,
    CompileResult,
    CompileTestDefinition,
    DiscoveredFixture,
    FixtureTestMetadata,
    RuntimeTestDefinition,
    TestPhase,
} from './types.ts';
import {
    compileContract,
    discoverFixtures,
    findFixtureContract,
    fixtureMetadataKey,
    fixtureOutputDir,
    loadCompileDefinition,
    matchesFilters,
    normalizePath,
    testRoot,
} from './utils.ts';

type SelectedFixture = DiscoveredFixture & {
    contractPath: string;
    outputDir: string;
    includeRuntime: boolean;
    compileDefinition: CompileTestDefinition;
};

type FixtureStatus = {
    outputDir: string;
    failed: boolean;
};

type FixtureTestContext = {
    task: {
        meta: object;
    };
};

type CompileSlotWaiter = {
    exclusive: boolean;
    resolve: () => void;
};

const maxConcurrentCompiles = 4;
const compileResults = new Map<string, Promise<CompileResult>>();
const fixtureStatuses = new Map<string, FixtureStatus>();
const compileSlotQueue: CompileSlotWaiter[] = [];
let activeNormalCompiles = 0;
let activeExclusiveCompile = false;
const filters = filtersFromEnvironment();
const discoveredFixtures = await discoverFixtures(testRoot);
const selectedFixtures = orderExecutionFixtures(
    await prepareSelectedFixtures(selectFixtures(discoveredFixtures, filters)),
);

if (selectedFixtures.length === 0) {
    throw new Error(
        `No Compact test fixtures matched filters: ${filters.join(', ')}`,
    );
}

afterAll(async () => {
    await cleanupPassedFixtures();
});

describe('Compact test contracts', () => {
    const runtimeFixtures = selectedFixtures.filter(
        (item) => item.includeRuntime,
    );

    for (const fixture of selectedFixtures) {
        test.concurrent(testName(fixture, 'compile'), async (context) => {
            recordFixtureTestMetadata(context, fixture, 'compile');
            await runCompileTest(fixture);
        });
    }

    for (const fixture of runtimeFixtures) {
        test.concurrent(testName(fixture, 'runtime'), async (context) => {
            const metadata = recordFixtureTestMetadata(
                context,
                fixture,
                'runtime',
            );

            await runRuntimeTest(fixture, metadata);
        });
    }
});

/**
 * Applies CLI path filters while adding compile prerequisites for runtime cases.
 */
function selectFixtures(
    fixtures: DiscoveredFixture[],
    selectedFilters: string[],
): Array<
    DiscoveredFixture & {
        includeRuntime: boolean;
    }
> {
    return fixtures.flatMap((fixture) => {
        const includeAll =
            selectedFilters.length === 0 ||
            matchesFilters(fixture.fixtureDir, selectedFilters);
        const compileSelected =
            fixture.compile !== undefined &&
            matchesFilters(fixture.compile.filePath, selectedFilters);
        const runtimeSelected =
            fixture.runtime !== undefined &&
            matchesFilters(fixture.runtime.filePath, selectedFilters);
        const includeRuntime =
            fixture.runtime !== undefined && (includeAll || runtimeSelected);
        const includeFixture = includeAll || compileSelected || runtimeSelected;

        if (!includeFixture) {
            return [];
        }

        if (fixture.compile === undefined) {
            throw new Error(
                `${fixture.relativeFixtureDir} matched a Compact test filter but has no compile test`,
            );
        }

        if (includeRuntime && fixture.compile.result !== 'pass') {
            throw new Error(
                `${fixture.relativeFixtureDir} has a runtime test but no compile.pass.test.ts prerequisite`,
            );
        }

        return [
            {
                ...fixture,
                includeRuntime,
            },
        ];
    });
}

/**
 * Loads compile metadata and resolves fixture-scoped contract/build paths.
 */
async function prepareSelectedFixtures(
    fixtures: Array<
        DiscoveredFixture & {
            includeRuntime: boolean;
        }
    >,
): Promise<SelectedFixture[]> {
    return Promise.all(
        fixtures.map(async (fixture) => {
            const contractPath = await findFixtureContract(fixture.fixtureDir);
            const outputDir = fixtureOutputDir(fixture.fixtureDir);

            return {
                ...fixture,
                contractPath,
                outputDir,
                compileDefinition: await loadCompileDefinition(
                    fixture.compile!.filePath,
                ),
            };
        }),
    );
}

/**
 * Keeps expensive `slow/` fixtures from blocking normal fixture scheduling.
 */
function orderExecutionFixtures(fixtures: SelectedFixture[]) {
    return [...fixtures].sort((left, right) => {
        const slowOrder =
            Number(isSlowFixture(left)) - Number(isSlowFixture(right));

        return slowOrder === 0
            ? left.relativeFixtureDir.localeCompare(right.relativeFixtureDir)
            : slowOrder;
    });
}

/**
 * Imports a runtime fixture after generated artifacts exist.
 */
async function loadRuntimeDefinition(filePath: string) {
    const module = (await import(pathToFileURL(filePath).href)) as {
        default?: unknown;
    };
    const definition = module.default;

    if (!isRuntimeDefinition(definition)) {
        throw new Error(
            `${filePath} must export default defineRuntimeTest(import.meta.url, ...)`,
        );
    }

    return definition;
}

/**
 * Runs and asserts the compile phase for one selected fixture.
 */
async function runCompileTest(fixture: SelectedFixture) {
    try {
        const result = await compileFixture(fixture);

        assertExpectedCompileResult(fixture.compileDefinition, result);
    } catch (error) {
        markFixtureFailed(fixture);
        throw error;
    }
}

/**
 * Runs the runtime fixture only after the compile phase produced artifacts.
 */
async function runRuntimeTest(
    fixture: SelectedFixture,
    metadata: FixtureTestMetadata,
) {
    const compileResult = await compileFixture(fixture);

    if (compileResult.exitCode !== 0) {
        markFixtureFailed(fixture);
        throw new Error(
            `${fixture.relativeFixtureDir} runtime test requires a successful compile.pass.test.ts run`,
        );
    }

    let definition: RuntimeTestDefinition;
    let Contract: CompactContractConstructor;

    try {
        Contract = await loadGeneratedContract(fixture);
        definition = await loadRuntimeDefinition(fixture.runtime!.filePath);
    } catch (error) {
        markFixtureFailed(fixture);
        throw error;
    }

    const runtimeStartedAt = performance.now();

    try {
        await definition.run(Contract);
    } catch (error) {
        metadata.durationMs = performance.now() - runtimeStartedAt;

        if (definition.result === 'fail') {
            try {
                assertExpectedRuntimeError(
                    error,
                    definition.options.expectedError,
                );
            } catch (assertionError) {
                markFixtureFailed(fixture);
                throw assertionError;
            }

            return;
        }

        markFixtureFailed(fixture);
        throw error;
    }

    metadata.durationMs = performance.now() - runtimeStartedAt;

    if (definition.result === 'fail') {
        markFixtureFailed(fixture);
        throw new Error(
            `${fixture.relativeFixtureDir} ran successfully but was expected to fail`,
        );
    }
}

/**
 * Imports the generated contract class after compilation has produced it.
 */
async function loadGeneratedContract(fixture: SelectedFixture) {
    const module = (await import(
        pathToFileURL(path.join(fixture.outputDir, 'contract', 'index.js')).href
    )) as {
        Contract?: unknown;
    };

    if (!isGeneratedContractConstructor(module.Contract)) {
        throw new Error(
            `${fixture.relativeFixtureDir} generated contract module did not export Contract`,
        );
    }

    return module.Contract;
}

/**
 * Compiles a selected fixture once into its fixture-scoped output directory.
 */
async function compileFixture(
    fixture: SelectedFixture,
): Promise<CompileResult> {
    const cached = compileResults.get(fixture.fixtureDir);

    if (cached !== undefined) {
        return cached;
    }

    const result = compileFixtureUncached(fixture);

    compileResults.set(fixture.fixtureDir, result);

    return result;
}

/**
 * Runs the uncached compiler invocation for one selected fixture.
 */
async function compileFixtureUncached(
    fixture: SelectedFixture,
): Promise<CompileResult> {
    return withCompileSlot(fixture, async () => {
        ensureFixtureStatus(fixture);

        await fs.rm(fixture.outputDir, {
            recursive: true,
            force: true,
        });
        await fs.mkdir(fixture.outputDir, {
            recursive: true,
        });

        const result = await compileContract(
            process.env.COMPACT_BINARY ?? 'compactc',
            fixture.contractPath,
            fixture.outputDir,
            fixture.compileDefinition.options.compilerArgs ?? [],
        );

        return {
            contractPath: fixture.contractPath,
            outputDir: fixture.outputDir,
            ...result,
        };
    });
}

/**
 * Runs normal compiler work concurrently while making `slow/` compiles exclusive.
 */
async function withCompileSlot<T>(
    fixture: SelectedFixture,
    work: () => Promise<T>,
): Promise<T> {
    const exclusive = isSlowFixture(fixture);

    await acquireCompileSlot(exclusive);

    try {
        return await work();
    } finally {
        releaseCompileSlot(exclusive);
    }
}

/**
 * Waits for an available compiler slot.
 */
function acquireCompileSlot(exclusive: boolean) {
    return new Promise<void>((resolve) => {
        compileSlotQueue.push({
            exclusive,
            resolve,
        });
        drainCompileSlotQueue();
    });
}

/**
 * Starts queued compiler work while preserving exclusive slow-fixture slots.
 */
function drainCompileSlotQueue() {
    if (activeExclusiveCompile) {
        return;
    }

    for (let index = 0; index < compileSlotQueue.length; ) {
        const waiter = compileSlotQueue[index];

        if (waiter.exclusive) {
            if (activeNormalCompiles !== 0) {
                return;
            }

            compileSlotQueue.splice(index, 1);
            activeExclusiveCompile = true;
            waiter.resolve();
            return;
        }

        if (activeNormalCompiles >= maxConcurrentCompiles) {
            return;
        }

        compileSlotQueue.splice(index, 1);
        activeNormalCompiles += 1;
        waiter.resolve();
    }
}

/**
 * Releases a compiler slot and starts any newly unblocked queued work.
 */
function releaseCompileSlot(exclusive: boolean) {
    if (exclusive) {
        activeExclusiveCompile = false;
    } else {
        activeNormalCompiles -= 1;
    }

    drainCompileSlotQueue();
}

/**
 * Checks whether the compiler result matches the compile fixture expectation.
 */
function assertExpectedCompileResult(
    expectation: CompileTestDefinition,
    result: CompileResult,
) {
    const compiled = result.exitCode === 0;

    if (expectation.result === 'pass' && !compiled) {
        throw new Error(
            `${result.contractPath} failed to compile:\n${compilerOutput(result)}`,
        );
    }

    if (expectation.result === 'fail' && compiled) {
        throw new Error(
            `${result.contractPath} compiled successfully but was expected to fail`,
        );
    }

    if (
        expectation.result === 'fail' &&
        expectation.options.expectedError !== undefined
    ) {
        assertExpectedCompileError(result, expectation.options.expectedError);
    }
}

/**
 * Checks that a compile-fail fixture failed with the intended diagnostic.
 */
function assertExpectedCompileError(
    result: CompileResult,
    expectedError: NonNullable<
        CompileTestDefinition['options']['expectedError']
    >,
) {
    if (
        expectedError instanceof RegExp &&
        expectedError.test(compilerOutput(result))
    ) {
        return;
    }

    if (typeof expectedError === 'function' && expectedError(result)) {
        return;
    }

    throw new Error(
        `Expected compile failure ${describeExpectedCompileError(expectedError)}, got ${compilerOutput(result)}`,
    );
}

/**
 * Combines compiler output streams for diagnostic matching.
 */
function compilerOutput(result: CompileResult) {
    return [result.stdout, result.stderr].filter(Boolean).join('\n');
}

/**
 * Formats a compile-failure expectation for assertion error messages.
 */
function describeExpectedCompileError(
    expectedError: NonNullable<
        CompileTestDefinition['options']['expectedError']
    >,
) {
    return expectedError instanceof RegExp
        ? expectedError.toString()
        : 'matching predicate';
}

/**
 * Checks that a runtime-fail fixture threw the intended error.
 */
function assertExpectedRuntimeError(
    error: unknown,
    expectedError: RuntimeTestDefinition['options']['expectedError'],
) {
    if (expectedError === undefined) {
        return;
    }

    if (
        expectedError instanceof RegExp &&
        expectedError.test(errorMessage(error))
    ) {
        return;
    }

    if (typeof expectedError === 'function' && expectedError(error)) {
        return;
    }

    throw new Error(
        `Expected runtime failure ${describeExpectedError(expectedError)}, got ${errorMessage(error)}`,
    );
}

/**
 * Formats a runtime-failure expectation for assertion error messages.
 */
function describeExpectedError(
    expectedError: NonNullable<
        RuntimeTestDefinition['options']['expectedError']
    >,
) {
    return expectedError instanceof RegExp
        ? expectedError.toString()
        : 'matching predicate';
}

/**
 * Normalizes unknown thrown values into strings for assertion messages.
 */
function errorMessage(error: unknown) {
    return error instanceof Error ? error.message : String(error);
}

/**
 * Marks a selected fixture as failed so generated artifacts are preserved.
 */
function markFixtureFailed(fixture: SelectedFixture) {
    ensureFixtureStatus(fixture).failed = true;
}

/**
 * Ensures cleanup has a status record for a fixture.
 */
function ensureFixtureStatus(fixture: SelectedFixture) {
    const existing = fixtureStatuses.get(fixture.fixtureDir);

    if (existing !== undefined) {
        return existing;
    }

    const status = {
        outputDir: fixture.outputDir,
        failed: false,
    };

    fixtureStatuses.set(fixture.fixtureDir, status);

    return status;
}

/**
 * Removes generated artifacts for selected fixtures whose tests passed.
 */
async function cleanupPassedFixtures() {
    if (keepArtifacts()) {
        return;
    }

    for (const [fixtureDir, status] of fixtureStatuses) {
        if (status.failed) {
            continue;
        }

        await fs.rm(status.outputDir, {
            recursive: true,
            force: true,
        });
        fixtureStatuses.delete(fixtureDir);
        compileResults.delete(fixtureDir);
    }
}

/**
 * Checks whether this run should preserve passing fixture artifacts.
 */
function keepArtifacts() {
    return (
        process.env.COMPACT_TEST_KEEP_ARTIFACTS === '1' ||
        process.env.COMPACT_TEST_KEEP_ARTIFACTS === 'true'
    );
}

/**
 * Checks whether a fixture is marked as expensive compiler coverage.
 */
function isSlowFixture(fixture: Pick<DiscoveredFixture, 'relativeFixtureDir'>) {
    return normalizePath(fixture.relativeFixtureDir)
        .split('/')
        .includes('slow');
}

/**
 * Builds the Vitest display name for a selected fixture phase.
 */
function testName(fixture: SelectedFixture, phase: TestPhase) {
    const result =
        phase === 'compile'
            ? fixture.compileDefinition.result
            : fixture.runtime!.result;

    return `${fixture.relativeFixtureDir} ${phase} ${result}`;
}

/**
 * Stores explicit fixture metadata for the custom reporter.
 */
function recordFixtureTestMetadata(
    context: FixtureTestContext,
    fixture: SelectedFixture,
    phase: TestPhase,
) {
    const metadata = context.task.meta as Record<string, unknown>;
    const fixtureMetadata = fixtureTestMetadata(fixture, phase);

    metadata[fixtureMetadataKey] = fixtureMetadata;

    return fixtureMetadata;
}

/**
 * Builds the original fixture test file path represented by an orchestrated case.
 */
function fixtureTestMetadata(
    fixture: SelectedFixture,
    phase: TestPhase,
): FixtureTestMetadata {
    const result =
        phase === 'compile'
            ? fixture.compileDefinition.result
            : fixture.runtime!.result;

    return {
        filePath: `${fixture.relativeFixtureDir}/${phase}.${result}.test.ts`,
    };
}

/**
 * Reads non-option path filters forwarded by the npm test wrapper.
 */
function filtersFromEnvironment() {
    const rawFilters = process.env.COMPACT_TEST_FILTERS;

    if (rawFilters === undefined || rawFilters.trim() === '') {
        return [];
    }

    const parsed = JSON.parse(rawFilters) as unknown;

    if (!Array.isArray(parsed)) {
        throw new Error('COMPACT_TEST_FILTERS must be a JSON array');
    }

    return parsed.filter(
        (filter): filter is string => typeof filter === 'string',
    );
}

/**
 * Narrows imported runtime metadata.
 */
function isRuntimeDefinition(value: unknown): value is RuntimeTestDefinition {
    return (
        typeof value === 'object' &&
        value !== null &&
        'kind' in value &&
        value.kind === 'compact-runtime-test'
    );
}

/**
 * Narrows the generated module export before passing it to a runtime fixture.
 */
function isGeneratedContractConstructor(
    value: unknown,
): value is CompactContractConstructor {
    return typeof value === 'function';
}
