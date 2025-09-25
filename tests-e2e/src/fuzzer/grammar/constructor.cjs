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
 * Constructor statements related grammar.
 */
const constructor = {
    constructor_statements: [['import CompactStandardLibrary;', 'line_separator', 'constructor_declaration', 'constructor_body']],
    constructor_declaration: [
        ['random_keyword', ' ', 'constructor()'],
        ['random_string', ' ', 'constructor()'],
        ['constructor()'],
        ['constructor(', 'constructor_params', ')'],
    ],
    constructor_body: [['{\n ', 'constructor_assert_statements', 'constructor_return_statements', '\n}']],
    constructor_assert_statements: [['assert (', ' 1 < 2 ', ', ', '"Secret message"', ')', 'end_line']],
    constructor_return_statements: [
        ['optional_end'],
        ['return', 'optional_end'],
        ['return', 'optional_end', 'constructor_return_statements'],
        ['return ', 'random_keyword', 'optional_end'],
        ['return ', 'random_string', 'optional_end'],
        ['return ', 'random_number', 'optional_end'],
    ],
    optional_end: [[''], ['end_line']],
    constructor_params: [
        ['random_string', ' : ', 'constructor_param_types'],
        ['random_keyword', ' : ', 'constructor_param_types'],
        ['random_string', ' : ', 'constructor_param_types', ', ', 'constructor_params'],
    ],
    constructor_param_types: [['random_keyword'], ['random_string'], ['random_table'], ['random_version'], ['compact_types']],
};

exports.constructor = constructor;
