import { logger } from './logger-utils';
import fs from 'fs';
import path from 'path';
import { isRelease } from './test-utils';
import { execa, Result } from 'execa';
import { expectCompilerResult } from './result-assertions';
import { expectFiles } from './files-assertions';

export enum Arguments {
    SKIP_ZK = '--skip-zk',
    TRACE_PASSES = '--trace-passes',
    HELP = '--help',
    VERSION = '--version',
    LANGUAGE_VERSION = '--language-version',
    VSCODE = '--vscode',
}

export function getCompactcBinary(): string {
    const local = '../result/bin/compactc';
    const system = 'compactc';

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

export function getFormatterBinary(): string {
    return '../result/bin/format-compact';
}

export function getFixupBinary(): string {
    return '../result/bin/fixup-compact';
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

/*
 * Compile, format and fixup
 */
export function compile(args: string[], folderPath?: string): Promise<Result> {
    return execa(getCompactcBinary(), args, {
        reject: false,
        ...(folderPath !== undefined && folderPath.length > 0 && { cwd: folderPath }),
    });
}

export function compileWithContractName(contractName: string, contractsDir: string): Promise<Result> {
    return compile([Arguments.SKIP_ZK, contractsDir + `${contractName}.compact`, contractsDir + `${contractName}`]);
}

export function compileWithContractPath(path: string, outputDirName: string, contractsDir: string): Promise<Result> {
    return compile([Arguments.VSCODE, Arguments.SKIP_ZK, `${path}`, `${contractsDir}${outputDirName}`]);
}

export async function compileQueue(contractsDir: string, contractNames: string[]) {
    for (const contractName of contractNames) {
        expectCompilerResult(await compileWithContractName(contractName, contractsDir)).toCompileWithoutErrors();
        expectFiles(`${contractsDir}${contractName}`).thatGeneratedJSCodeIsValid();
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
