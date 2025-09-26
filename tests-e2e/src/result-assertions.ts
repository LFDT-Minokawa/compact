import { logger } from './logger-utils';
import { expect } from 'vitest';
import { Result } from 'execa';

export class AssertResult {
    private result: Result;

    expect(result: Result): AssertResult {
        this.result = result;

        return this;
    }

    toReturn(stderr: string | RegExp, stdout: string | RegExp, exitCode: number): void {
        if (stderr instanceof RegExp) {
            expect(this.result.stderr).toMatch(stderr);
        } else {
            expect(this.result.stderr).toMatch(stderr);
        }

        if (stderr instanceof RegExp) {
            expect(this.result.stdout).toMatch(stdout);
        } else {
            expect(this.result.stdout).toMatch(stdout);
        }

        expect(this.result.exitCode).toEqual(exitCode);
    }

    toCompileWithoutErrors() {
        expect(this.result.exitCode).toEqual(0);
    }

    toContainSpecificError(error: string) {
        expect(this.result.stderr).toContain(error);
    }

    toNotContainSpecificError(error: string) {
        expect(this.result.stderr).not.toContain(error);
    }
}

const assertResult = new AssertResult();

export function expectCommandResult(returnValue: Result): AssertResult {
    logger.info(`---- Result ----`);
    logger.info(`command: ${returnValue.command}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stdout: ${returnValue.stdout}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stderr: ${returnValue.stderr}`);
    logger.info(`exit code: ${returnValue.exitCode}`);
    logger.info(`---- End ----`);

    return assertResult.expect(returnValue);
}

export function expectCompilerResult(returnValue: Result, contract: string = ''): AssertResult {
    logger.info(`---- Result ----`);
    if (contract.length > 0) logger.info(`contract: ${contract}`);
    logger.info(`command: ${returnValue.command}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stdout: ${returnValue.stdout}`);
    // eslint-disable-next-line @typescript-eslint/restrict-template-expressions
    logger.info(`stderr: ${returnValue.stderr}`);
    logger.info(`exit code: ${returnValue.exitCode}`);
    logger.info(`---- End ----`);

    return assertResult.expect(returnValue);
}
