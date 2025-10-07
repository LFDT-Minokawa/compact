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
 * Circuit statements related grammar.
 *
 * Description of output:
 * - circuit_declaration - will create more random circuit
 * - circuit_declaration_with_body - will try to more mimic "real" circuit definition
 */
const circuit = {
    circuit_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'optional_circuit', ' ', 'circuit_declaration'],
        ['optional_circuit', ' ', 'circuit_declaration'],
        ['import CompactStandardLibrary;', 'line_separator', 'valid_optional_circuit', 'circuit_declaration_with_body', 'circuit_body'],
    ],
    optional_circuit: [['random_keyword'], ['random_string'], ['optional_circuit']],
    valid_optional_circuit: [['export '], ['pure '], ['valid_optional_circuit']],
    circuit_declaration: [
        ['circuit ', 'random_string', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_keyword', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<#N, T>', '(x:', 'circuit_generic_value', '):', 'circuit_generic', 'end_line'],
        ['circuit ', 'random_string', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
    ],
    circuit_declaration_with_body: [
        ['circuit ', 'random_string', '(): ', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'circuit_params', '):', 'valid_types'],
        ['circuit ', 'random_string', '(', 'circuit_params', '):', 'valid_types'],
    ],
    circuit_body: [
        ['{\n ', 'circuit_assert_statements', 'circuit_return_statements', '\n}'], 
        ['{\n ', 'circuit_multi_const_statements', 'circuit_return_statements', '\n}'],
        ['{\n ', 'circuit_struct', 'circuit_multi_const_statements_struct', 'circuit_return_statements', '\n}'],
        ['{\n ', 'circuit_struct', 'circuit_spread_statements', 'circuit_return_statements', '\n}'],
        ['{\n ', 'circuit_struct', 'circuit_map_fold_statements', 'circuit_return_statements', '\n}'],
    ],
    circuit_assert_statements: [
        ['assert (', ' 1 < 2 ', ', ', '"Secret message"', ')', 'end_line']
    ],
    circuit_spread_statements: [
        ['const a', ' = [...slice<', 'random_number', '>(', 'valid_types' , ', ', 'random_number', ')]', 'end_line'],
        ['const [', 'valid_types', ', ', 'valid_types', '] = ', '[...', 'valid_types', ', ', '...', 'valid_types', ']', 'end_line' ],
        ['const a', ' = [...', 'random_string', ', ...', 'random_number', ']', 'end_line' ],
        ['const a', ' = [...[', 'random_string', '], ...[', 'random_number', ']]', 'end_line' ],
        ['const a', ' = [...', 'random_table', ', ...', 'random_mixed_table', ']', 'end_line' ],
        ['const a', ' = [...[', 'random_table', '], ...[', 'random_mixed_table', ']]', 'end_line' ],
    ],
    circuit_multi_const_statements: [
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ' = ', 'random_number', ', ', 'random_string', ' = ', 'random_mixed_table', 'end_line'],
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ' = ', 'small_random_number', ', ', 'random_string', ' = ', 'random_keyword', 'end_line'],
        ['const ', 'random_string', ':', 'valid_types', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ':', 'valid_types', ' = ', 'random_number', ', ', 'random_string', ':', 'valid_types', ' = ', 'random_keyword', 'end_line'],
    ],
    circuit_multi_const_statements_struct: [
        ['const ', 'random_string', ' = ', 'default<', 'var_struct', '>', ', ' , 'random_string', ' = ', 'random_string', ', ', 'random_string', ' = ', 'random_number', 'end_line'],
    ],
    circuit_map_fold_statements: [
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'valid_types' , ')', 'valid_end_line'],
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'default<', ', ', 'valid_types' , '>)', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'valid_types', ', ', 'valid_types' , ')', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'default<', 'valid_types', '>, default<', 'valid_types' , '>)', 'valid_end_line'],
    ],
    circuit_return_statements: [
        ['optional_end'],
        ['return', 'optional_end'],
        ['return', 'optional_end', 'circuit_return_statements'],
        ['return ', 'random_keyword', 'optional_end'],
        ['return ', 'random_string', 'optional_end'],
        ['return ', 'random_number', 'optional_end'],
    ],
    optional_end: [[''], ['end_line']],
    circuit_args: [['random_string'], ['random_string', ', ', 'circuit_args']],
    circuit_params: [
        ['random_string', ' : ', 'valid_types'],
        ['random_string', ' : ', 'valid_types', ', ', 'circuit_params'],
    ],
    contaminated_circuit_params: [
        ['random_string', ' : ', 'contaminated_compact_types'],
        ['random_keyword', ': ', 'contaminated_compact_types'],
        ['random_string', ' : ', 'contaminated_compact_types', ', ', 'circuit_params'],
    ],
    circuit_generic: [
        ['Uint<', 'circuit_generic_value', '>'],
        ['Uint<', 'circuit_generic_value', '..', 'circuit_generic_value', '>'],
        ['Bytes<', 'circuit_generic_value', '>'],
        ['Vector<', 'circuit_generic_value', ', ', 'circuit_generic_value', '>'],
        ['Maybe<', 'circuit_generic_value', '>'],
        ['Either<', 'circuit_generic_value', ',', 'circuit_generic_value', '>'],
        ['MerkleTreePath<', 'circuit_generic_value', ',', 'circuit_generic_value', '>'],
    ],
    circuit_generic_value: [
        ['N'],
        ['#N'],
        ['T']
    ],
    circuit_struct: [
        ['struct ', 'var_struct', ' {\n', 'circuit_struct_fields', '\n}', 'valid_end_line']
    ],
    circuit_struct_fields: [
        ['  ', 'random_string', ': ', 'valid_types'],
    ]
};

exports.circuit = circuit;
