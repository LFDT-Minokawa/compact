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
 * For statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz for, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const for_grammar = {
    for_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'for_declaration', 'for_body'],
        ['import CompactStandardLibrary;', 'line_separator', 'counter_declaration', 'for_declaration', 'for_body'],
    ],
    counter_declaration: [
        ['export ledger counter: Counter', 'end_line']
    ],
    counter_operation: [
        ['counter', 'random_operator', 'random_number'],
        ['counter', 'random_operator', 'small_random_number'],
        ['counter', 'random_operator', 'random_number', 'counter_operation'],
    ],
    for_declaration: [['constructor()']],
    for_body: [
        ['{\n', 'for_loop_range', '\n}'],
        // ['{\n', 'generate_nested_for', '\n}'],
    ],
    for_loop_range: [
        ['for (const ', 'bob', ' of ', 'random_number', '..', 'random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'counter_operation', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'small_random_number', '..', 'small_random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_table', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'valid_types', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'default<', 'valid_types', '>]) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_keyword', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '(', 'random_table', ')) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '{', 'random_table', '}) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '<', 'random_table', '>) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_table', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_keyword', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_version', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'valid_types', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'default<', 'valid_types', '>) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_number', ' as Uint<455>', '..', 'random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_number', '..', 'random_number', ' as Uint<455>', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_string', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_mixed_table', ']', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(', 'random_table', ', ', 'random_number', ')) {\n', '}\n'],
    ],
};

exports.for_grammar = for_grammar;
