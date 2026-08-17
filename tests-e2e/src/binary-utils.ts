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

import { logger } from './logger-utils';
import fs from 'fs';
import path from 'path';
import { isRelease } from './test-utils';
import { execa, Result } from 'execa';
import { expectCompilerResult } from './result-assertions';
import { expectFiles } from './files-assertions';
import { Compilation, CompilationPaths } from './types';

export enum Arguments {
    SKIP_ZK = '--skip-zk',
    FEATURE_V3 = '--feature-zkir-v3',
    NO_COMMUNICATIONS_COMMITMENT = '--no-communications-commitment',
    TRACE_PASSES = '--trace-passes',
    HELP = '--help',
    VERSION = '--version',
    LANGUAGE_VERSION = '--language-version',
    LEDGER_VERSION = '--ledger-version',
    RUNTIME_VERSION = '--runtime-version',
    VSCODE = '--vscode',
    LINES_LENGTH = '--line-length',
}

type FailedContract = {
    stderr: string;
    stdout: string;
    exitCode: number;
    contract: string;
};

function getBinary(local: string, system: string): string {
    if (isRelease()) {
        logger.info(`Using system compiler: ${system}`);
        return system;
    } else {
        if (!fs.existsSync(local)) {
            throw new Error(`No compactc binary found at: ${local}`);
        }
        logger.info(`Using local compiler: ${local}`);
        return path.resolve(local);
    }
}

// wrappers for binaries
export function getCompactcBinary(): string {
    return getBinary('../result/bin/compactc', 'compactc');
}

export function getFormatterBinary(): string {
    return getBinary('../result/bin/format-compact', 'format-compact');
}

export function getFixupBinary(): string {
    return getBinary('../result/bin/fixup-compact', 'fixup-compact');
}

export function extractCompilerVersion(): string {
    const filePath = '../compiler/compiler-version.ss';
    const content = fs.readFileSync(filePath, 'utf-8');
    const versionMatch = content.match(/\(make-version 'compiler (\d+) (\d+) (\d+)\)/);

    if (versionMatch) {
        const [, major, minor, patch] = versionMatch;
        return `${major}.${minor}.${patch}`;
    }
    throw new Error(`Could not extract compiler version from: ${filePath}`);
}

export async function getCompilerVersion(): Promise<string> {
    const result = await execa(getCompactcBinary(), [Arguments.VERSION], { reject: false });
    if (result.exitCode !== 0) {
        throw new Error(`Failed to get compiler version: ${result.stderr}`);
    }
    return result.stdout.trim();
}

export async function getLanguageVersion(): Promise<string> {
    const result = await execa(getCompactcBinary(), [Arguments.LANGUAGE_VERSION], { reject: false });
    if (result.exitCode !== 0) {
        throw new Error(`Failed to get language version: ${result.stderr}`);
    }
    return result.stdout.trim();
}

export function withContractPath(compilation: Compilation, contractPath: string): Compilation {
    return { ...compilation, contractPath };
}

function compiledPaths(args: string[], cwd: string | undefined): CompilationPaths {
    // filter out flags
    const values = args.filter((argument) => !argument.startsWith('-'));
    if (values.length < 2) {
        return {};
    }

    const base = cwd ?? process.cwd();
    return {
        contractPath: path.resolve(base, values[values.length - 2]),
        outputDir: path.resolve(base, values[values.length - 1]),
    };
}

export async function compile(args: string[], folderPath?: string): Promise<Compilation> {
    const cwd = folderPath !== undefined && folderPath.length > 0 ? folderPath : undefined;

    const result = await execa(getCompactcBinary(), args, {
        reject: false,
        ...(cwd !== undefined && { cwd }),
    });

    return { ...result, ...compiledPaths(args, cwd) };
}

export function compileWithContractName(
    contractName: string,
    contractsDir: string,
    formatErrors: boolean = false,
): Promise<Compilation> {
    const args = [Arguments.SKIP_ZK, contractsDir + `${contractName}.compact`, contractsDir + `${contractName}`];

    if (formatErrors) {
        args.unshift(Arguments.VSCODE);
    }
    return compile(args);
}

export function compileWithContractPath(path: string, outputDirName: string, contractsDir: string): Promise<Compilation> {
    return compile([Arguments.VSCODE, Arguments.SKIP_ZK, `${path}`, `${contractsDir}${outputDirName}`]);
}

export async function compileQueue(contractsDir: string, contractNames: string[]): Promise<void> {
    for (const contractName of contractNames) {
        const compilation = await compileWithContractName(contractName, contractsDir);

        expectCompilerResult(compilation).toCompileWithoutErrors();
        expectFiles(compilation).thatGeneratedJSCodeIsValid();
    }
}

export async function compileQueueWithFailures(
    contractsDir: string,
    contractNames: string[],
    failed: FailedContract[],
    formatErrors: boolean = false,
): Promise<void> {
    for (const contractName of contractNames) {
        const match = failed.find((item) => item.contract === contractName);
        if (match !== undefined) {
            logger.info(`found failed contract: ${contractName}`);
            const compilation = await compileWithContractName(contractName, contractsDir, formatErrors);

            expectCompilerResult(compilation).toReturn(match.stderr, match.stdout, match.exitCode);
            expectFiles(compilation).thatNoFilesAreGenerated();
        } else {
            logger.info(`performing default check: ${contractName}`);
            const compilation = await compileWithContractName(contractName, contractsDir);

            expectCompilerResult(compilation).toCompileWithoutErrors();
            expectFiles(compilation).thatGeneratedJSCodeIsValid();
        }
    }
}

export function format(args: string[]): Promise<Result> {
    return execa(getFormatterBinary(), args, {
        reject: false,
    });
}

export function fixup(args: string[]): Promise<Result> {
    return execa(getFixupBinary(), args, {
        reject: false,
    });
}
