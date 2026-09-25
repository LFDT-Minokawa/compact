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

/** One set of names read from a single compiler declaration site. */
interface NameGroup {
    title: string;
    source: string;
    /** The `declare-*` form these come from; absent when they are not macro-generated. */
    macro?: string;
    names: string[];
    /** Names are `Adt.operation` rather than bare, so a receiver is needed to match them. */
    qualified?: boolean;
}

interface ContractFile {
    path: string;
    absolutePath: string;
}

/** A repo-relative path and 1-based line, used to build the report link. */
interface UsageSite {
    path: string;
    line: number;
}

/** Usage sites per name. Absent means no fixture uses it. */
type UsageIndex = Map<string, UsageSite[]>;

export type { ContractFile, NameGroup, UsageIndex, UsageSite };
