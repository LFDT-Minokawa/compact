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
 * Ledger statements related grammar.
 */
const ledger = {
    ledger_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'optional_modifier', ' ledger ', 'random_string', ': ', 'compact_types', 'end_line'],
        // ['optional_modifier', 'ledger ', 'random_string', ': ', 'compact_types', 'end_line', 'ledger_statements'],
    ],
    optional_modifier: [
        [''],
        ['export'],
        ['sealed'],
        ['export sealed'],
        ['sealed export'],
        ['random_keyword'],
        ['random_string'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
    ],
};

exports.ledger = ledger;
