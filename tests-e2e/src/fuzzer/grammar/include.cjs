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

/*
 * Include statements related grammar.
 */
const include = {
    include_statements: [
        ['include_statement'],
        // ['include_statement', 'include_statements']
    ],
    include_statement: [
        ['random_keyword', ' include ', 'include_file', 'end_line'],
        ['random_string', ' include ', 'include_file', 'end_line'],
        ['include ', 'include_file', 'end_line'],
    ],
    include_file: [
        ['CompactStandardLibrary'],
        ['path/to/file'],
        ['//path//to//file'],
        ['\\path\\to\\file'],
        ['\/path\/to\/file'],
        ['\path\to\file'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['valid_type'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
};

exports.include = include;
