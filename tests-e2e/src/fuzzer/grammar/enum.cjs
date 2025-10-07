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
 * Enum definition related grammar.
 */
const enums = {
    enum_definitions: [['import CompactStandardLibrary;', 'line_separator', 'enum_definition']],
    enum_definition: [
        ['enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        ['export enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        // ['generate_large_enum'],
    ],
    enum_name: [['random_string'], ['random_keyword'], ['random_number'], ['random_table'], ['random_version']],
    enum_values: [
        ['  ', 'random_string', 'line_separator'],
        ['  ', 'random_number', 'line_separator'],
        ['  ', 'random_table', 'line_separator'],
        ['  ', 'random_version', 'line_separator'],
        ['  ', 'random_keyword', 'line_separator'],
        ['  ', 'random_string', ',', 'line_separator', 'enum_values'],
    ],
};

exports.enums = enums;
