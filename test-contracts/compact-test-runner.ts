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

import { spawn, type SpawnOptions } from 'node:child_process';
import { constants as fsConstants } from 'node:fs';
import fs from 'node:fs/promises';
import { registerHooks } from 'node:module';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import type { DiscoveredFixture } from './types.ts';
import {
    compileContract,
    discoverFixtures,
    findFixtureContract,
    fixtureOutputDir,
    loadCompileDefinition,
    matchesFilters,
    testRoot,
} from './utils.ts';

type RunnerArgs = {
    filters: string[];
    prepareArtifacts: boolean;
    vitestArgs: string[];
};

type RuntimeManifest = {
    main?: string;
};

const prepareArtifactsFlag = '--prepare-artifacts';
const compactTestAlias = '@test/compact-test';
const skipZkArg = '--skip-zk';
const compactTestModuleUrl = pathToFileURL(
    path.join(testRoot, 'compact-test.ts'),
).href;
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

// Fixture tests reach the shared helpers through the `@test/compact-test`
// alias that vitest.config.ts resolves. Node needs the same mapping so this
// runner can import fixture compile metadata, such as fixture-declared
// compiler flags, while preparing lint artifacts.
registerHooks({
    resolve(specifier, context, nextResolve) {
        return specifier === compactTestAlias
            ? {
                  url: compactTestModuleUrl,
                  shortCircuit: true,
              }
            : nextResolve(specifier, context);
    },
});

const { filters, prepareArtifacts, vitestArgs } = parseRunnerArgs(
    process.argv.slice(2),
);

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
function parseRunnerArgs(args: string[]): RunnerArgs {
    const filters: string[] = [];
    const vitestArgs: string[] = [];
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
async function runVitest(
    filters: string[],
    vitestArgs: string[],
): Promise<void> {
    await cleanSelectedFixtureArtifacts(filters);

    const vitestEntry = path.join(
        testRoot,
        'node_modules',
        'vitest',
        'vitest.mjs',
    );
    const code = await spawnProcess(
        process.execPath,
        [vitestEntry, 'run', '--config', 'vitest.config.ts', ...vitestArgs],
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
async function cleanSelectedFixtureArtifacts(filters: string[]): Promise<void> {
    const fixtures = await discoverFixtures(testRoot);
    const selectedFixtures = fixtures.filter(
        (fixture) =>
            filters.length === 0 ||
            matchesFilters(fixture.fixtureDir, filters) ||
            (fixture.compile !== undefined &&
                matchesFilters(fixture.compile.filePath, filters)) ||
            (fixture.runtime !== undefined &&
                matchesFilters(fixture.runtime.filePath, filters)),
    );

    await Promise.all(
        selectedFixtures.map((fixture) =>
            fs.rm(fixtureOutputDir(fixture.fixtureDir), {
                recursive: true,
                force: true,
            }),
        ),
    );
}

/**
 * Compiles runtime fixture prerequisites so static generated imports typecheck.
 */
async function prepareRuntimeArtifacts(): Promise<void> {
    const fixtures = await discoverFixtures(testRoot);
    const runtimeFixtures = fixtures.filter(
        (fixture) => fixture.runtime !== undefined,
    );

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
 * Compiles one fixture for TypeScript static import resolution.
 */
async function compileFixtureForTypecheck(
    fixture: DiscoveredFixture,
): Promise<void> {
    const contractPath = await findFixtureContract(fixture.fixtureDir);
    const outputDir = fixtureOutputDir(fixture.fixtureDir);
    const compileDefinition = await loadCompileDefinition(
        fixture.compile!.filePath,
    );

    await fs.rm(outputDir, {
        recursive: true,
        force: true,
    });
    await fs.mkdir(outputDir, {
        recursive: true,
    });

    const result = await compileContract(
        resolvedCompilerPath,
        contractPath,
        outputDir,
        [...(compileDefinition.options.compilerArgs ?? []), skipZkArg],
    );

    if (result.exitCode !== 0) {
        throw new Error(
            `${contractPath} failed to compile while preparing lint artifacts:\n${result.stdout}\n${result.stderr}`,
        );
    }
}

/**
 * Resolves a command to its real executable path, or null when not found.
 */
async function resolveExecutable(binary: string): Promise<string | null> {
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
async function requireLocalCompactBinary(): Promise<string> {
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
async function requireLocalRuntimeBuild(): Promise<void> {
    const localRuntimeDir = path.join(path.dirname(testRoot), 'runtime');
    const packageDir = path.join(
        testRoot,
        'node_modules',
        '@midnight-ntwrk',
        'compact-runtime',
    );

    let resolvedDir: string;

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
    const localRuntimeReal = await fs
        .realpath(localRuntimeDir)
        .catch(() => localRuntimeDir);
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

    let manifest: RuntimeManifest;

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
function fail(message: string): never {
    console.error(`\nCannot run Compact tests:\n\n${message}\n`);
    process.exit(1);
}

/**
 * Spawns a process and resolves with its exit code.
 */
function spawnProcess(
    command: string,
    args: string[],
    options: SpawnOptions,
): Promise<number> {
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
