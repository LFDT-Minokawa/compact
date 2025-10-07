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
 * Pragma statements related grammar.
 */
const pragma = {
    pragma_statements: [
        ['pragma ', 'pragma_constraints', 'end_line'],
        // ['pragma ', 'pragma_constraints', 'end_line', 'pragma_statements'],
    ],
    pragma_constraints: [['pragma_constraint'], ['pragma_constraints', ' ', 'random_operator', ' ', 'pragma_constraint']],
    pragma_constraint: [['pragma_type', ' ', 'random_operator', ' ', 'version_number']],
    pragma_type: [
        ['language_version'],
        ['compiler_version'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
    version_number: [
        ['random_version'],
        ['random_version', 'random_version'],
        ['random_keyword'],
        ['(', 'random_version', ')'],
        ['[', 'random_version', ']'],
        ['{', 'random_version', '}'],
        ['<', 'random_version', '>'],
        ['random_string'],
        [''],
    ],
};

exports.pragma = pragma;
