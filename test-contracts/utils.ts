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

import { spawn } from 'node:child_process';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

import type {
    CompileOutcome,
    CompileTestDefinition,
    DiscoveredFixture,
    FixtureTestFile,
    TestPhase,
    TestResult,
} from './types.ts';

export const testRoot = path.dirname(fileURLToPath(import.meta.url));
export const compactTestFilePattern =
    /^(compile|runtime)\.(pass|fail)\.test\.ts$/;
export const fixtureMetadataKey = 'compactFixture';

const ignoredDirectories = new Set([
    '.build',
    '.compact-test-build',
    'node_modules',
]);

/**
 * Discovers self-contained fixture directories beneath the package root.
 */
export async function discoverFixtures(
    rootDir: string,
): Promise<DiscoveredFixture[]> {
    const testFiles = await findFixtureTestFiles(rootDir);
    const byFixtureDir = new Map<string, FixtureTestFile[]>();

    for (const filePath of testFiles) {
        const parsed = parseFixtureTestFile(filePath);
        const fixtureDir = path.dirname(filePath);
        const files = byFixtureDir.get(fixtureDir) ?? [];

        files.push(parsed);
        byFixtureDir.set(fixtureDir, files);
    }

    return [...byFixtureDir.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([fixtureDir, files]) =>
            buildDiscoveredFixture(fixtureDir, files),
        );
}

/**
 * Walks the package tree and returns every compile/runtime fixture module.
 */
async function findFixtureTestFiles(rootDir: string): Promise<string[]> {
    const entries = await fs.readdir(rootDir, {
        withFileTypes: true,
    });
    const files: string[] = [];

    for (const entry of entries) {
        if (ignoredDirectories.has(entry.name)) {
            continue;
        }

        const entryPath = path.join(rootDir, entry.name);

        if (entry.isDirectory()) {
            files.push(...(await findFixtureTestFiles(entryPath)));
            continue;
        }

        if (entry.isFile() && compactTestFilePattern.test(entry.name)) {
            files.push(entryPath);
        }
    }

    return files;
}

/**
 * Groups compile/runtime files into a single fixture record.
 */
function buildDiscoveredFixture(
    fixtureDir: string,
    files: FixtureTestFile[],
): DiscoveredFixture {
    const compileFiles = files.filter((file) => file.phase === 'compile');
    const runtimeFiles = files.filter((file) => file.phase === 'runtime');

    if (compileFiles.length > 1) {
        throw new Error(`${fixtureDir} has multiple compile test files`);
    }

    if (runtimeFiles.length > 1) {
        throw new Error(`${fixtureDir} has multiple runtime test files`);
    }

    return {
        fixtureDir,
        relativeFixtureDir: path.relative(testRoot, fixtureDir),
        compile: compileFiles[0],
        runtime: runtimeFiles[0],
    };
}

/**
 * Parses phase and expected result directly from a fixture test file name.
 */
function parseFixtureTestFile(filePath: string): FixtureTestFile {
    const match = compactTestFilePattern.exec(path.basename(filePath));

    if (match === null) {
        throw new Error(`Invalid Compact test file name: ${filePath}`);
    }

    return {
        filePath,
        phase: match[1] as TestPhase,
        result: match[2] as TestResult,
    };
}

/**
 * Resolves the single `.compact` source owned by a fixture directory.
 */
export async function findFixtureContract(fixtureDir: string): Promise<string> {
    const entries = await fs.readdir(fixtureDir);
    const contracts = entries.filter((entry) => entry.endsWith('.compact'));

    if (contracts.length !== 1) {
        throw new Error(
            `${fixtureDir} must contain exactly one .compact contract, found ${contracts.length}`,
        );
    }

    return path.join(fixtureDir, contracts[0]);
}

/**
 * Builds the fixture-scoped output directory.
 */
export function fixtureOutputDir(fixtureDir: string): string {
    return path.join(fixtureDir, '.build');
}

/**
 * Imports a compile fixture module, which should only export metadata.
 */
export async function loadCompileDefinition(
    filePath: string,
): Promise<CompileTestDefinition> {
    const module = (await import(pathToFileURL(filePath).href)) as {
        default?: unknown;
    };
    const definition = module.default;

    if (!isCompileDefinition(definition)) {
        throw new Error(
            `${filePath} must export default defineCompileTest(import.meta.url, ...)`,
        );
    }

    return definition;
}

/**
 * Narrows imported compile metadata.
 */
function isCompileDefinition(value: unknown): value is CompileTestDefinition {
    return (
        typeof value === 'object' &&
        value !== null &&
        'kind' in value &&
        value.kind === 'compact-compile-test'
    );
}

/**
 * Invokes the Compact compiler and captures stdout, stderr, and exit code.
 */
export function compileContract(
    compilerPath: string,
    contractPath: string,
    outputDir: string,
    fixtureCompilerArgs: string[],
): Promise<CompileOutcome> {
    return new Promise((resolve, reject) => {
        const child = spawn(
            compilerPath,
            compilerArgs(
                compilerPath,
                contractPath,
                outputDir,
                fixtureCompilerArgs,
            ),
            {
                stdio: ['ignore', 'pipe', 'pipe'],
            },
        );
        let stdout = '';
        let stderr = '';

        child.stdout!.on('data', (data) => {
            stdout += data.toString();
        });
        child.stderr!.on('data', (data) => {
            stderr += data.toString();
        });
        child.on('error', (error) => {
            reject(error);
        });
        child.on('close', (code) => {
            resolve({
                stdout,
                stderr,
                exitCode: code ?? 1,
            });
        });
    });
}

/**
 * Builds argv for either the Nix `compactc` binary or a `compact` wrapper,
 * keeping compiler flags ahead of the paths.
 */
function compilerArgs(
    compilerPath: string,
    contractPath: string,
    outputDir: string,
    fixtureCompilerArgs: string[],
): string[] {
    const coreArgs = [...fixtureCompilerArgs, contractPath, outputDir];

    return path.basename(compilerPath) === 'compact'
        ? ['compile', ...coreArgs]
        : coreArgs;
}

/**
 * Checks whether a fixture path matches any CLI path filter.
 */
export function matchesFilters(
    targetPath: string,
    selectedFilters: string[],
): boolean {
    const normalizedTarget = normalizePath(targetPath);
    const relativeTarget = normalizePath(path.relative(testRoot, targetPath));

    return selectedFilters.some((filter) => {
        const normalizedFilter = normalizePath(filter);
        const absoluteFilter = normalizePath(path.resolve(testRoot, filter));

        return (
            relativeTarget.includes(normalizedFilter) ||
            normalizedTarget.includes(normalizedFilter) ||
            normalizedTarget.includes(absoluteFilter)
        );
    });
}

/**
 * Normalizes path separators for stable substring matching.
 */
export function normalizePath(value: string): string {
    return value.split(path.sep).join('/');
}
