import { isRelease } from './test-utils';
import { extractCompilerVersion } from './binary-utils';
import { getFileContent } from './file-utils';

/**
 * The default output of the compiler.
 * Depends on the way compiler is launched.
 * - Script returns a header version
 * - Binary does not return any header
 */
export function compilerDefaultOutput(): string {
    if (isRelease()) {
        return `Compactc version: ${extractCompilerVersion()}`;
    } else {
        return '';
    }
}

export function compilerUsageMessageHeader(): string {
    if (isRelease()) {
        return 'Usage: compactc.bin';
    } else {
        return `Usage: compactc`;
    }
}

export function compilerManualPage(): string {
    return `${compilerDefaultOutput()}
${getFileContent('src/resources/compiler_man_page.txt')}`
        .replaceAll('USAGE_HEADER', compilerUsageMessageHeader())
        .trim();
}

export function formatterManualPage(): string {
    return getFileContent('src/resources/formatter_man_page.txt').trim();
}

export function fixupManualPage(): string {
    return getFileContent('src/resources/fixup_man_page.txt').trim();
}
