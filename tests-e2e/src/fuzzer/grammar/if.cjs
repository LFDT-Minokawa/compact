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
 * If statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz ifs, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const if_grammar = {
    if_statements: [['import CompactStandardLibrary;', 'line_separator', 'if_declaration', 'if_body']],
    if_declaration: [['constructor()']],
    if_body: [
        ['{\n ', 'if_variable_a', 'if_variable_b', 'if_variable_c', 'if_body_statements', '\n}'],
        // ['{\n ', 'generate_nested_if', '\n}'],
    ],
    if_body_statements: [['if_statement']],
    if_variable_a: [
        ['const ', 'bob', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'bob', ' : ', 'valid_types', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'bob', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'bob', ' = ', 'random_number', 'end_line'],
        ['const ', 'bob', ' = ', 'random_string', 'end_line'],
        ['const ', 'bob', ' = ', 'slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')', 'end_line'],
        ['const ', 'bob', ' = ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')', 'end_line'],
    ],
    if_variable_b: [
        ['const ', 'tom', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'tom', ' : ', 'valid_types', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'tom', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'tom', ' = ', 'random_number', 'end_line'],
        ['const ', 'tom', ' = ', 'random_string', 'end_line'],
        ['const ', 'tom', ' = ', 'slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')', 'end_line'],
        ['const ', 'tom', ' = ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')', 'end_line'],
    ],
    if_variable_c: [
        ['const ', 'greg', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'greg', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'greg', ' : ', 'valid_types', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'greg', ' = ', 'random_number', 'end_line'],
        ['const ', 'greg', ' = ', 'random_string', 'end_line'],
        ['const ', 'greg', ' = ', 'slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')', 'end_line'],
        ['const ', 'greg', ' = ', 'slice<', 'random_number', '>([', 'random_mixed_table', '], ', 'random_number', ')', 'end_line'],
        ['const ', 'greg', ' = ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')', 'end_line'],
    ],
    if_statement: [
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line'],
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line', 'if_statement'],
    ],
    if_condition: [
        ['tom', 'random_operator', 'bob'],
        ['tom', 'random_keyword', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'greg'],
        ['tom', 'random_operator', 'bob', 'random_keyword', 'greg'],
        ['tom', 'random_operator', 'random_number'],
        ['tom', 'random_operator', '"', 'random_string', '"'],
        ['"', 'random_string', '"', 'random_operator', 'tom'],
        ['tom * bob', 'random_operator', 'random_number'],
        ['tom + bob', 'random_operator', 'random_number'],
        ['tom - bob', 'random_operator', 'random_number'],
        ['tom / bob', 'random_operator', 'random_number'],
        ['tom', ' as ', 'valid_types', 'random_operator', 'random_number'],
        ['tom', 'random_operator', 'bob', ' as ', 'valid_types'],
        ['random_number', 'random_operator', 'tom'],
        ['random_number', 'random_operator', 'tom * bob'],
        ['random_number', 'random_operator', 'tom + bob'],
        ['random_number', 'random_operator', 'tom - bob'],
        ['random_number', 'random_operator', 'tom / bob'],
        ['default<', 'valid_types', '>', 'random_operator', 'default<', 'valid_types', '>'],
    ],
};

exports.if_grammar = if_grammar;
