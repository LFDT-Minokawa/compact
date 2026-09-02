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

import fs from 'node:fs';

/**
 * Collect the distinct `parse error: ...` messages from a compiler log.
 *
 * Was a top-level script that read `build_parse.txt` on import and wrote
 * `output.txt`; nothing in the repo produces that file or imports this module, so
 * it is exposed as a function rather than run as a side effect.
 */
export function extractErrorMessages(filePath: string): Set<string> {
    const fileContent = fs.readFileSync(filePath, 'utf8');
    const messages = new Set<string>();
    for (const match of fileContent.matchAll(/parse error:([^\n]+)/g)) {
        messages.add(match[1].trim());
    }
    return messages;
}
