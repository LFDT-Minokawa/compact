import { Result } from 'execa';
import { describe, test } from 'vitest';
import path from 'node:path';
import {
    Arguments,
    compilerDefaultOutput,
    createTempFolder,
    expectCommandResult,
    format,
    formatterManualPage,
    isMacOS,
    isRelease,
} from '..';

const CONTRACT_WITH_ERRORS_FILE_PATH = '../examples/errors/multiSource.compact';
const CONTRACT_NO_ERRORS = '../examples/adt/exports/counter.compact';

function matchError(): string {
    if (isMacOS()) {
        return 'operation not permitted';
    }

    return 'is a directory';
}

describe.skipIf(isRelease())('[Smoke] Formatter', () => {
    const HELP_REGEX =
        /Usage: format-compact <flag> ... <source-pathname> \[ <target-pathname> ]\n.*--help displays detailed usage information/;

    const VERSION_REGEX = /(\d+)\.(\d+).(\d+)/;

    test('should show help option', async () => {
        const result: Result = await format([]);

        expectCommandResult(result).toReturn(HELP_REGEX, '', 1);
    });

    test('should get man page', async () => {
        const result: Result = await format([Arguments.HELP]);

        expectCommandResult(result).toReturn('', formatterManualPage(), 0);
    });

    test('should get compiler version', async () => {
        const result: Result = await format([Arguments.VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get language version', async () => {
        const result: Result = await format([Arguments.LANGUAGE_VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    // TODO: need to check if it is right
    test('should not return any errors with --vscode', async () => {
        const outputFile = path.join(createTempFolder(), 'formatted.compact');
        const result: Result = await format([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputFile]);

        expectCommandResult(result).toReturn('', compilerDefaultOutput(), 0);
    });

    test('should throw an error when output is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, CONTRACT_NO_ERRORS, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error creating output file: failed for ${outputDir}: ${matchError()}`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when input is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, outputDir, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: ${outputDir} is a directory`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when file does not exist', async () => {
        const outputDir = createTempFolder();
        const result: Result = await format([Arguments.VSCODE, 'bob.compact', outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: failed for bob.compact: no such file or directory`,
            compilerDefaultOutput(),
            255,
        );
    });
});
