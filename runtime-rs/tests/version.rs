// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

#[test]
fn matching_version_compiles() {
    // The macro expands to a const assertion. If the expected string equals
    // compact_runtime::COMPACT_RUNTIME_VERSION, the assertion passes and the
    // test compiles. If not, compilation fails.
    compact_runtime::check_runtime_version!("0.16.100");
}

#[test]
fn version_constant_is_exposed() {
    assert_eq!(compact_runtime::COMPACT_RUNTIME_VERSION, "0.16.100");
}
