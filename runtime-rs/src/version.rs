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

//
// Generated contracts call `check_runtime_version!("x.y.z")` at module
// load to assert that the runtime they were compiled against is
// ABI-compatible with the one they're being linked with. Mirrors the
// TS path's `__compactRuntime.checkRuntimeVersion(...)`.

/// The published version of this crate, expanded at build time.
pub const COMPACT_RUNTIME_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Compile-time string equality, used by `check_runtime_version!`.
#[doc(hidden)]
pub const fn const_str_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

/// Fail the build if the linked compact-runtime doesn't match the
/// version the contract was compiled against.
#[macro_export]
macro_rules! check_runtime_version {
    ($expected:literal) => {
        const _: () = assert!(
            $crate::version::const_str_eq($expected, $crate::version::COMPACT_RUNTIME_VERSION),
            "compact-runtime version mismatch"
        );
    };
}
