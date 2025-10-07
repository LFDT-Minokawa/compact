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

import { isRelease } from './test-utils';
import { getFileContent } from './file-utils';

export const VERSION_REGEX = /(\d+)\.(\d+).(\d+)/;

export const HELP_REGEX = new RegExp(
    `${compilerUsageMessageHeader()} <flag> ... <source-pathname> <target-directory-pathname>\n.*--help displays detailed usage information`,
);

export const FIXUP_HELP_REGEX =
    /Usage: fixup-compact <flag> ... <source-pathname> \[ <target-pathname> ]\n.*--help displays detailed usage information/;

export const FORMATTER_HELP_REGEX =
    /Usage: format-compact <flag> ... <source-pathname> \[ <target-pathname> ]\n.*--help displays detailed usage information/;

/**
 * The default output of the compiler for both the binary and the script returns no headers,
 */
export function compilerDefaultOutput(): string {
    return '';
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
