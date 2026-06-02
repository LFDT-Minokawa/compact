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

// SPDX-License-Identifier: Apache-2.0
//
// Generated Rust contracts call `check_runtime_version!("x.y.z")` at module load to
// assert that the runtime they were compiled against is ABI-compatible with the one
// linked at build time. Mirrors the TS path's `__compactRuntime.checkRuntimeVersion(...)`.

/// Stub version constant. In the real runtime-rs, this is wired through
/// from `onchain_runtime::transcript::Transcript::VERSION`. For the spike we
/// just hard-code so the macro compiles.
pub const COMPACT_RUNTIME_VERSION: &str = "0.1.0-spike";

#[macro_export]
macro_rules! check_runtime_version {
    ($expected:literal) => {
        // In a real impl this would do a semver-compatible check at startup.
        // Spike just asserts string equality.
        const _: () = assert!(
            $crate::version::const_str_eq($expected, $crate::version::COMPACT_RUNTIME_VERSION),
            "compact-runtime version mismatch"
        );
    };
}

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
