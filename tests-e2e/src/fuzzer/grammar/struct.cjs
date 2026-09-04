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
 * Struct definition related grammar.
 */
const struct = {
    struct_definitions: [
        ['import CompactStandardLibrary;', 'line_separator', 'base_struct', 'struct_definition']
    ],
    base_struct: [
      ['struct ', 'var_struct', ' {\n', 'valid_struct_fields', '\n}', 'valid_end_line']  
    ],
    struct_definition: [
        ['struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
        ['random_keyword', ' struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
    ],
    struct_fields: [['struct_field'], ['struct_field', ',', 'line_separator', 'struct_fields']],
    struct_field: [
        ['  ', 'random_string', ': ', 'valid_types'],
        ['  ', 'random_string', ': ', 'var_struct'],
        ['  ', 'random_keyword', ': ', 'valid_types'],
        ['  ', 'random_string', ': ', 'compact_types'],
    ],
    valid_struct_fields: [
        ['  ', 'random_string', ': ', 'valid_types'],
    ]
};

exports.struct = struct;
