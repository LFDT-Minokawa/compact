import { Result } from 'execa';
import { describe, test } from 'vitest';
import {
    Arguments,
    compilerDefaultOutput,
    createTempFolder,
    expectCommandResult,
    expectFiles,
    fixup,
    fixupManualPage,
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

describe.skipIf(isRelease())('[Smoke] Fixup', () => {
    const HELP_REGEX =
        /Usage: fixup-compact <flag> ... <source-pathname> \[ <target-pathname> ]\n.*--help displays detailed usage information/;

    const VERSION_REGEX = /(\d+)\.(\d+).(\d+)/;

    test('should show help option', async () => {
        const result: Result = await fixup([]);

        expectCommandResult(result).toReturn(HELP_REGEX, '', 1);
    });

    test('should get man page', async () => {
        const result: Result = await fixup([Arguments.HELP]);

        expectCommandResult(result).toReturn('', fixupManualPage(), 0);
    });

    test('should get compiler version', async () => {
        const result: Result = await fixup([Arguments.VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should get language version', async () => {
        const result: Result = await fixup([Arguments.LANGUAGE_VERSION]);

        expectCommandResult(result).toReturn('', VERSION_REGEX, 0);
    });

    test('should throw single line error with --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCommandResult(result).toReturn(
            'Exception: multiSource.compact line 28 char 10: no compatible function named enabledPower is in scope at this call; one function is incompatible with the supplied argument types; supplied argument types: (Uint<0..0>, Field); declared argument types for function at line 19 char 1: (Boolean, Field)',
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('should throw multi line error without --vscode', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([CONTRACT_WITH_ERRORS_FILE_PATH, outputDir]);

        expectCommandResult(result).toReturn(
            'Exception: multiSource.compact line 28 char 10:\n' +
                '  no compatible function named enabledPower is in scope at this call\n' +
                '    one function is incompatible with the supplied argument types\n' +
                '      supplied argument types:\n' +
                '        (Uint<0..0>, Field)\n' +
                '      declared argument types for function at line 19 char 1:\n' +
                '        (Boolean, Field)',
            compilerDefaultOutput(),
            255,
        );
        expectFiles(outputDir).thatFilesAreGenerated(false, false);
    });

    test('should throw an error when output is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, CONTRACT_NO_ERRORS, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error creating output file: failed for ${outputDir}: ${matchError()}`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when input is directory', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, outputDir, outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: ${outputDir} is a directory`,
            compilerDefaultOutput(),
            255,
        );
    });

    test('should throw an error when file does not exist', async () => {
        const outputDir = createTempFolder();
        const result: Result = await fixup([Arguments.VSCODE, 'bob.compact', outputDir]);

        expectCommandResult(result).toReturn(
            `Exception: error opening source file: failed for bob.compact: no such file or directory`,
            compilerDefaultOutput(),
            255,
        );
    });
});
