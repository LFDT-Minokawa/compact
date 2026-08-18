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
import { expect } from 'vitest';
import { Compilation } from './types';
import { displayPath } from './file-utils';

export enum ExitCodes {
    Success = 0,
    Failure = 255,
    Error = 1,
}

export type AssertOptions = {
    contract: string;
    ignoreStdOut: boolean;
    ignoreStdErr: boolean;
};

export class AssertResult {
    private result: Compilation;

    expect(result: Compilation): AssertResult {
        this.result = result;

        return this;
    }

    private get context(): string {
        const { command, contractPath, outputDir } = this.result;

        if (contractPath === undefined || outputDir === undefined) {
            return `[command: ${command}]`;
        }

        return `[contract: ${displayPath(contractPath)}] [output: ${displayPath(outputDir)}]`;
    }

    toReturn(stderr: string | RegExp, stdout: string | RegExp, exitCode: number): void {
        this.toMatchStdError(stderr).toMatchStdOut(stdout).toMatchExitCode(exitCode);
    }

    toBeSuccess(stderr: string | RegExp, stdout: string | RegExp): AssertResult {
        this.toReturn(stderr, stdout, ExitCodes.Success);

        return this;
    }

    toBeError(stderr: string | RegExp, stdout: string | RegExp): void {
        this.toReturn(stderr, stdout, ExitCodes.Error);
    }

    toBeFailure(stderr: string | RegExp, stdout: string | RegExp): void {
        this.toReturn(stderr, stdout, ExitCodes.Failure);
    }

    toMatchStdOut(stdout: string | RegExp) {
        if (stdout instanceof RegExp) {
            expect(this.result.stdout, this.context).toMatch(stdout);
        } else {
            expect(this.result.stdout, this.context).toBe(stdout);
        }

        return this;
    }

    stdOutToContain(stdout: (string | RegExp)[]): AssertResult {
        for (const word of stdout) {
            expect(this.result.stdout, this.context).toContain(word);
        }

        return this;
    }

    stdOutToNotContain(stdout: (string | RegExp)[]): AssertResult {
        for (const word of stdout) {
            expect(this.result.stdout, this.context).not.toContain(word);
        }

        return this;
    }

    toMatchStdError(stderr: string | RegExp): AssertResult {
        if (stderr instanceof RegExp) {
            expect(this.result.stderr, this.context).toMatch(stderr);
        } else {
            expect(this.result.stderr, this.context).toBe(stderr);
        }

        return this;
    }

    stdErrToContain(stderr: (string | RegExp)[]): AssertResult {
        for (const word of stderr) {
            expect(this.result.stderr, this.context).toContain(word);
        }

        return this;
    }

    stdErrToNotContain(stderr: (string | RegExp)[]): AssertResult {
        for (const word of stderr) {
            expect(this.result.stderr, this.context).not.toContain(word);
        }

        return this;
    }

    toMatchExitCode(exitCode: number): AssertResult {
        expect(this.result.exitCode, this.context).toEqual(exitCode);

        return this;
    }

    toCompileWithoutErrors(): AssertResult {
        this.toMatchExitCode(0);

        return this;
    }
}

const logChoice = (choice: boolean, message: string) => {
    // eslint-disable-next-line @typescript-eslint/no-unused-expressions
    choice ? logger.debug(message) : logger.info(message);
};

export function expectCommandResult(result: Compilation): AssertResult {
    logger.info(`---- Result ----`);
    logger.info(`command: ${result.command}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stdout: ${result.stdout}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stderr: ${result.stderr}`);
    logger.info(`exit code: ${result.exitCode}`);
    logger.info(`---- End ----`);
    return new AssertResult().expect(result);
}

export function expectCompilerResult(
    result: Compilation,
    options: AssertOptions = { contract: '', ignoreStdOut: false, ignoreStdErr: false },
): AssertResult {
    logger.info(`---- Result ----`);
    if (options.contract.length > 0) logger.info(`contract: ${options.contract}`);
    logger.info(`command: ${result.command}`);

    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logChoice(options.ignoreStdOut, `stdout: ${result.stdout}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logChoice(options.ignoreStdErr, `stderr: ${result.stderr}`);

    logger.info(`exit code: ${result.exitCode}`);
    logger.info(`---- End ----`);

    return new AssertResult().expect(result);
}
