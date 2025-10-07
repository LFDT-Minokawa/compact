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
 * Witness statements related grammar.
 */
const witness = {
    witness_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'export ', 'witness_declaration'],
        ['import CompactStandardLibrary;', 'line_separator', 'witness_declaration'],
    ],
    witness_declaration: [
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '():', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '(', 'witness_params', '):', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<#N, T>', '(x:', 'witness_generic_value', '):', 'witness_generic', 'end_line'],
        ['witness ', 'random_string', '(', 'witness_params', '):', 'compact_types', 'end_line'],
    ],
    witness_args: [['random_string'], ['random_keyword'], ['random_string', ', ', 'witness_args']],
    witness_params: [
        ['random_string', ' : ', 'compact_types'],
        ['random_keyword', ' : ', 'compact_types'],
        ['random_number', ' : ', 'compact_types'],
        ['random_table', ' : ', 'compact_types'],
        ['random_version', ' : ', 'compact_types'],
        ['random_string', ' : ', 'compact_types', ', ', 'witness_params'],
    ],
    witness_generic: [
        ['Uint<', 'witness_generic_value', '>'],
        ['Uint<', 'witness_generic_value', '..', 'witness_generic_value', '>'],
        ['Bytes<', 'witness_generic_value', '>'],
        ['Vector<', 'witness_generic_value', ', ', 'witness_generic_value', '>'],
        ['Maybe<', 'witness_generic_value', '>'],
        ['Either<', 'witness_generic_value', ',', 'witness_generic_value', '>'],
        ['MerkleTreePath<', 'witness_generic_value', ',', 'witness_generic_value', '>'],
    ],
    witness_generic_value: [
        ['N'],
        ['#N'],
        ['T']
    ]
};

exports.witness = witness;
