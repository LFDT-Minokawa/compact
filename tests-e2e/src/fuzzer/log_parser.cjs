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

const fs = require('fs');

function extractErrorMessages(filePath) {

    const fileContent = fs.readFileSync(filePath, 'utf8');
    const regex = /parse error:([^\n]+)/g;

    let errorMessages = new Set;
    let match;

    while ((match = regex.exec(fileContent)) !== null) {
        errorMessages.add(match[1].trim());
    }
    return errorMessages;
}

const filePath = 'build_parse.txt';
const errors = extractErrorMessages(filePath);

console.log(errors);

fs.writeFileSync('output.txt', Array.from(errors).join('\n'));
