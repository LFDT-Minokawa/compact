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
 * Module statements related grammar.
 */
const module_grammar = {
    module_statements: [
        // ['generate_modules'],
        ['module_statement'],
    ],
    module_statement: [
        ['module ', 'module_name', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '<', 'module_params', '>', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '<', 'module_generic_value', ',', 'module_generic_value', '>', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '[', 'module_params', ']', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '(', 'module_params', ')', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '{', 'module_params', '}', ' {', 'line_separator', '}', 'line_separator'],
    ],
    module_params: [
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
        ['random_string', ', ', 'module_params'],
    ],
    module_name: [
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
    module_generic_value: [
        ['N'],
        ['#N'],
        ['T'],
        ['#T'],
        ['random_string'],
        ['A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, U, P, Q, R, S, T, U, V, W, X'],
        ['#A, #B, #C, #D, #E, #F, #G, #H, #I, #J, #K, #L, #M, #N, #O, #U, #P, #Q, #R, #S, #T, #U, #V, #W, #X'],
    ]
};

exports.module_grammar = module_grammar;
