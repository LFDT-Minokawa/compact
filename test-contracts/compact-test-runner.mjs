#!/usr/bin/env node
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

import { spawn } from 'node:child_process';
import { constants as fsConstants } from 'node:fs';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const testRoot = path.dirname(fileURLToPath(import.meta.url));
const compactTestFilePattern = /^(compile|runtime)\.(pass|fail)\.test\.ts$/;
const prepareArtifactsFlag = '--prepare-artifacts';
const optionsWithValues = new Set([
    '-t',
    '--environment',
    '--maxWorkers',
    '--minWorkers',
    '--pool',
    '--project',
    '--reporter',
    '--testNamePattern',
]);

const {
    filters,
    prepareArtifacts,
    vitestArgs,
} = parseRunnerArgs(process.argv.slice(2));

const resolvedCompilerPath = await requireLocalCompactBinary();
await requireLocalRuntimeBuild();
process.env.COMPACT_BINARY = resolvedCompilerPath;

if (prepareArtifacts) {
    await prepareRuntimeArtifacts();
} else {
    await runVitest(filters, vitestArgs);
}

/**
 * Splits path filters from Vitest options.
 */
function parseRunnerArgs(args) {
    const filters = [];
    const vitestArgs = [];
    let prepareArtifacts = false;

    for (let index = 0; index < args.length; index += 1) {
        const arg = args[index];

        if (arg === prepareArtifactsFlag) {
            prepareArtifacts = true;
            continue;
        }

        if (arg === '-c' || arg === '--config' || arg.startsWith('--config=')) {
            throw new Error(
                'compact-test-runner always uses vitest.config.ts; pass fixture filters or other Vitest options only',
            );
        }

        if (arg.startsWith('-')) {
            vitestArgs.push(arg);

            if (
                optionsWithValues.has(arg) &&
                args[index + 1] !== undefined &&
                !args[index + 1].startsWith('-')
            ) {
                vitestArgs.push(args[index + 1]);
                index += 1;
            }

            continue;
        }

        filters.push(arg);
    }

    return {
        filters,
        prepareArtifacts,
        vitestArgs,
    };
}

/**
 * Runs the single Vitest orchestrator and passes path filters through env.
 */
async function runVitest(filters, vitestArgs) {
    await cleanSelectedFixtureArtifacts(filters);

    const vitestEntry = path.join(testRoot, 'node_modules', 'vitest', 'vitest.mjs');
    const code = await spawnProcess(
        process.execPath,
        [
            vitestEntry,
            'run',
            '--config',
            'vitest.config.ts',
            ...vitestArgs,
        ],
        {
            cwd: testRoot,
            env: {
                ...process.env,
                COMPACT_BINARY: resolvedCompilerPath,
                COMPACT_TEST_FILTERS: JSON.stringify(filters),
            },
            stdio: 'inherit',
        },
    );

    process.exitCode = code;
}

/**
 * Removes stale generated output before Vitest can transform fixture modules.
 */
async function cleanSelectedFixtureArtifacts(filters) {
    const fixtures = await discoverFixtures(testRoot);
    const selectedFixtures = fixtures.filter((fixture) => (
        filters.length === 0 ||
        matchesFilters(fixture.fixtureDir, filters) ||
        (
            fixture.compile !== undefined &&
            matchesFilters(fixture.compile.filePath, filters)
        ) ||
        (
            fixture.runtime !== undefined &&
            matchesFilters(fixture.runtime.filePath, filters)
        )
    ));

    await Promise.all(selectedFixtures.map((fixture) => fs.rm(
        fixtureOutputDir(fixture.fixtureDir),
        {
            recursive: true,
            force: true,
        },
    )));
}

/**
 * Compiles runtime fixture prerequisites so static generated imports typecheck.
 */
async function prepareRuntimeArtifacts() {
    const fixtures = await discoverFixtures(testRoot);
    const runtimeFixtures = fixtures.filter((fixture) => fixture.runtime !== undefined);

    for (const fixture of runtimeFixtures) {
        if (fixture.compile?.result !== 'pass') {
            throw new Error(
                `${fixture.relativeFixtureDir} has a runtime test but no compile.pass.test.ts prerequisite`,
            );
        }

        await compileFixtureForTypecheck(fixture);
    }
}

/**
 * Discovers fixture test files beneath the package root.
 */
async function discoverFixtures(rootDir) {
    const testFiles = await findFixtureTestFiles(rootDir);
    const byFixtureDir = new Map();

    for (const filePath of testFiles) {
        const parsed = parseFixtureTestFile(filePath);
        const fixtureDir = path.dirname(filePath);
        const files = byFixtureDir.get(fixtureDir) ?? [];

        files.push(parsed);
        byFixtureDir.set(fixtureDir, files);
    }

    return [...byFixtureDir.entries()]
        .sort(([left], [right]) => left.localeCompare(right))
        .map(([fixtureDir, files]) => buildDiscoveredFixture(fixtureDir, files));
}

/**
 * Walks the package tree and returns every compile/runtime fixture module.
 */
async function findFixtureTestFiles(rootDir) {
    const entries = await fs.readdir(rootDir, {
        withFileTypes: true,
    });
    const files = [];

    for (const entry of entries) {
        if (
            entry.name === '.build' ||
            entry.name === '.compact-test-build' ||
            entry.name === 'node_modules'
        ) {
            continue;
        }

        const entryPath = path.join(rootDir, entry.name);

        if (entry.isDirectory()) {
            files.push(...await findFixtureTestFiles(entryPath));
            continue;
        }

        if (entry.isFile() && compactTestFilePattern.test(entry.name)) {
            files.push(entryPath);
        }
    }

    return files;
}

/**
 * Groups compile/runtime files into a fixture record.
 */
function buildDiscoveredFixture(fixtureDir, files) {
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
function parseFixtureTestFile(filePath) {
    const match = compactTestFilePattern.exec(path.basename(filePath));

    if (match === null) {
        throw new Error(`Invalid Compact test file name: ${filePath}`);
    }

    return {
        filePath,
        phase: match[1],
        result: match[2],
    };
}

/**
 * Compiles one fixture for TypeScript static import resolution.
 */
async function compileFixtureForTypecheck(fixture) {
    const contractPath = await findFixtureContract(fixture.fixtureDir);
    const outputDir = fixtureOutputDir(fixture.fixtureDir);

    await fs.rm(outputDir, {
        recursive: true,
        force: true,
    });
    await fs.mkdir(outputDir, {
        recursive: true,
    });

    const result = await compileContract(contractPath, outputDir, {
        skipZk: true,
    });

    if (result.exitCode !== 0) {
        throw new Error(
            `${contractPath} failed to compile while preparing lint artifacts:\n${result.stdout}\n${result.stderr}`,
        );
    }
}

/**
 * Resolves the single `.compact` source owned by a fixture directory.
 */
async function findFixtureContract(fixtureDir) {
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
 * Invokes the Compact compiler and captures stdout, stderr, and exit code.
 */
function compileContract(contractPath, outputDir, options = {}) {
    return new Promise((resolve, reject) => {
        const args = compilerArgs(contractPath, outputDir, options);
        const child = spawn(
            resolvedCompilerPath,
            args,
            {
                stdio: ['ignore', 'pipe', 'pipe'],
            },
        );
        let stdout = '';
        let stderr = '';

        child.stdout.on('data', (data) => {
            stdout += data.toString();
        });
        child.stderr.on('data', (data) => {
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
 * Builds argv for either the Nix `compactc` binary or a `compact` wrapper.
 */
function compilerArgs(contractPath, outputDir, options = {}) {
    const coreArgs = options.skipZk
        ? ['--skip-zk', contractPath, outputDir]
        : [contractPath, outputDir];

    return path.basename(resolvedCompilerPath) === 'compact'
        ? ['compile', ...coreArgs]
        : coreArgs;
}

/**
 * Builds the fixture-scoped output directory.
 */
function fixtureOutputDir(fixtureDir) {
    return path.join(fixtureDir, '.build');
}

/**
 * Checks whether a fixture path matches any CLI path filter.
 */
function matchesFilters(targetPath, selectedFilters) {
    const normalizedTarget = normalizePath(targetPath);
    const relativeTarget = normalizePath(path.relative(testRoot, targetPath));

    return selectedFilters.some((filter) => {
        const normalizedFilter = normalizePath(filter);
        const absoluteFilter = normalizePath(path.resolve(testRoot, filter));

        return relativeTarget.includes(normalizedFilter) ||
            normalizedTarget.includes(normalizedFilter) ||
            normalizedTarget.includes(absoluteFilter);
    });
}

/**
 * Normalizes path separators for stable substring matching.
 */
function normalizePath(value) {
    return value.split(path.sep).join('/');
}

/**
 * Resolves a command to its real executable path, or null when not found.
 */
async function resolveExecutable(binary) {
    const candidates = binary.includes(path.sep)
        ? [path.resolve(binary)]
        : (process.env.PATH ?? '')
            .split(path.delimiter)
            .filter(Boolean)
            .map((dir) => path.join(dir, binary));

    for (const candidate of candidates) {
        try {
            await fs.access(candidate, fsConstants.X_OK);
            return await fs.realpath(candidate);
        } catch {
            // Keep searching the remaining PATH entries.
        }
    }

    return null;
}

/**
 * Resolves the locally built Compact compiler from the Nix compiler shell.
 */
async function requireLocalCompactBinary() {
    const requested = process.env.COMPACT_BINARY ?? 'compactc';
    const compilerPath = await resolveExecutable(requested);

    if (compilerPath === null) {
        fail(
            `Compact compiler not available: no executable \`${requested}\` on PATH.\n` +
            '  The compiler comes from the Nix test-contracts shell. Run ./test-contracts/test.sh,\n' +
            '  or enter the shell first with `nix develop .#test-contracts`.',
        );
    }

    const nixStorePrefix = `${path.sep}nix${path.sep}store${path.sep}`;

    if (!compilerPath.startsWith(nixStorePrefix)) {
        fail(
            `Refusing to use the Compact compiler at:\n    ${compilerPath}\n` +
            `  Tests must use the Nix-built compiler under ${nixStorePrefix}, not a globally\n` +
            '  installed toolchain. Run ./test-contracts/test.sh, or enter\n' +
            '  `nix develop .#test-contracts` so `compactc` resolves into the Nix store.',
        );
    }

    return compilerPath;
}

/**
 * Ensures `@midnight-ntwrk/compact-runtime` is linked to a locally built
 * runtime: either the Nix package substituted from the cache (used by test.sh
 * and CI) or the working-tree build at ../runtime (local development).
 */
async function requireLocalRuntimeBuild() {
    const localRuntimeDir = path.join(path.dirname(testRoot), 'runtime');
    const packageDir = path.join(
        testRoot,
        'node_modules',
        '@midnight-ntwrk',
        'compact-runtime',
    );

    let resolvedDir;

    try {
        resolvedDir = await fs.realpath(packageDir);
    } catch {
        fail(
            'Compact runtime not linked: node_modules/@midnight-ntwrk/compact-runtime is\n' +
            '  absent. ./test-contracts/test.sh links the runtime the Nix shell pulled from\n' +
            '  the cache. To run by hand, point `.compact-runtime` at a runtime build\n' +
            '  (the Nix store package via $COMPACT_RUNTIME_PKG, or ../runtime) and run\n' +
            '  `yarn install`.',
        );
    }

    const nixStorePrefix = `${path.sep}nix${path.sep}store${path.sep}`;
    const localRuntimeReal = await fs.realpath(localRuntimeDir).catch(() => localRuntimeDir);
    const isNixRuntime = resolvedDir.startsWith(nixStorePrefix);
    const isLocalRuntime = resolvedDir === localRuntimeReal;

    if (!isNixRuntime && !isLocalRuntime) {
        fail(
            'Compact runtime is not a locally built runtime: it resolves to\n' +
            `    ${resolvedDir}\n` +
            '  but tests must use either the Nix-built package under\n' +
            `    ${nixStorePrefix}\n` +
            `  (substituted from the cache) or the working-tree runtime at\n    ${localRuntimeDir}\n` +
            '  Point `.compact-runtime` at one of those and reinstall with `yarn install`.',
        );
    }

    let manifest;

    try {
        manifest = JSON.parse(
            await fs.readFile(path.join(packageDir, 'package.json'), 'utf8'),
        );
    } catch {
        fail(
            'Compact runtime not linked: node_modules/@midnight-ntwrk/compact-runtime is\n' +
            '  missing its package.json. Reinstall with `yarn install`.',
        );
    }

    const mainPath = path.join(packageDir, manifest.main ?? 'index.js');

    try {
        await fs.access(mainPath);
    } catch {
        fail(
            `Compact runtime not built: expected ${path.relative(testRoot, mainPath)}.\n` +
            '  The Nix runtime package ships prebuilt; ./test-contracts/test.sh links it.\n' +
            '  When using ../runtime instead, build it first with `npm run build` there.',
        );
    }
}

/**
 * Prints an actionable setup failure and exits without a noisy stack trace.
 */
function fail(message) {
    console.error(`\nCannot run Compact tests:\n\n${message}\n`);
    process.exit(1);
}

/**
 * Spawns a process and resolves with its exit code.
 */
function spawnProcess(command, args, options) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, options);

        child.on('error', (error) => {
            reject(error);
        });
        child.on('close', (code) => {
            resolve(code ?? 1);
        });
    });
}
