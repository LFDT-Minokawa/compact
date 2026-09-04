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
 * Assert statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz assert, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const asserts = {
    assert_statements: [['import CompactStandardLibrary;', 'line_separator', 'assert_declaration', 'assert_body']],
    assert_declaration: [['constructor()']],
    assert_body: [['{\n ', 'assert_variable_a', 'assert_variable_b', 'assert_body_statements', '\n}']],
    assert_body_statements: [['assert_statement']],
    assert_variable_a: [
        ['const ', 'bob', ' = ', 'default<', 'valid_types', '>', 'valid_end_line'],
        ['const ', 'bob', ' = ', 'pad(', 'random_number', ', "', 'random_string', '")', 'valid_end_line'],
        ['const ', 'bob', ' = ', '[...slice<', 'random_number', '>(', 'valid_types' , ', ', 'random_number', ')]', 'end_line'],
        ['const ', 'bob', ' = ', 'slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')', 'end_line'],
        ['const ', 'bob', ' = ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')', 'end_line'],
    ],
    assert_variable_b: [
        ['const ', 'tom', ' = ', 'default<', 'valid_types', '>', 'valid_end_line'],
        ['const ', 'tom', ' = ', 'pad(', 'random_number', ', "', 'random_string', '")', 'valid_end_line'],
        ['const ', 'tom', ' = ', '[...slice<', 'random_number', '>(', 'valid_types' , ', ', 'random_number', ')]', 'end_line'],
        ['const ', 'tom', ' = ', 'slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')', 'end_line'],
        ['const ', 'tom', ' = ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')', 'end_line'],
    ],
    assert_statement: [
        ['assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'random_keyword', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'assert_condition', ' ', 'random_keyword', '")', 'end_line'],
        ['assert (', 'assert_condition', 'random_keyword', 'random_string', '")', 'end_line'],
        ['random_keyword', ' ', 'assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
    ],
    assert_condition: [
        ['tom', 'random_string', 'bob'],
        ['tom', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'random_mixed_table'],
        ['tom', ' ', 'random_keyword', ' ', 'bob'],
        ['bob', 'random_operator', 'tom'],
        ['bob', 'random_operator', 'tom', 'random_operator', 'tom'],
        ['bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'tom'],
        ['tom', 'random_operator', 'tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'random_keyword'],
        ['random_keyword', 'random_operator', 'bob'],
    ],
};

exports.asserts = asserts;
