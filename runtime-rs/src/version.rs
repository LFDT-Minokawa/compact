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

/// Fail the build if the linked midnight-compact-runtime doesn't match the
/// version the contract was compiled against.
#[macro_export]
macro_rules! check_runtime_version {
    ($expected:literal) => {
        const _: () = assert!(
            $crate::version::const_str_eq($expected, $crate::version::COMPACT_RUNTIME_VERSION),
            "midnight-compact-runtime version mismatch"
        );
    };
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The version the crate reports must be the version Cargo.toml declares,
    /// because generated code pins it: every emitted `lib.rs` opens with
    /// `check_runtime_version!("X.Y.Z")`, and that is the whole mechanism
    /// stopping a contract from linking against a runtime it was not
    /// compiled for.
    #[test]
    fn reported_version_is_the_package_version() {
        assert_eq!(COMPACT_RUNTIME_VERSION, env!("CARGO_PKG_VERSION"));
        assert!(
            COMPACT_RUNTIME_VERSION.split('.').count() == 3,
            "expected semver-shaped version, got {COMPACT_RUNTIME_VERSION}"
        );
    }

    /// `const_str_eq` runs in const context, where the usual `==` is not
    /// available, so it is hand-written and therefore worth testing directly
    /// rather than only through the macro.
    #[test]
    fn const_str_eq_matches_string_equality() {
        assert!(const_str_eq("", ""));
        assert!(const_str_eq("0.19.100", "0.19.100"));

        assert!(
            !const_str_eq("0.19.100", "0.19.101"),
            "differs in last char"
        );
        assert!(!const_str_eq("0.19.10", "0.19.100"), "prefix, shorter");
        assert!(!const_str_eq("0.19.100", "0.19.10"), "prefix, longer");
        assert!(!const_str_eq("", "0"), "empty vs non-empty");
        assert!(!const_str_eq("a", "b"), "same length, differs at 0");
    }

    /// It is `const`, so this has to hold at compile time and not merely at
    /// run time — an implementation that only worked at run time would pass
    /// the assertions above and still fail to guard anything.
    #[test]
    fn const_str_eq_is_usable_in_const_context() {
        // Asserted inside `const` blocks on purpose: these fail at *compile*
        // time if const evaluation is wrong, which is the property being
        // tested. A runtime `assert!` on a `const` would prove nothing —
        // clippy's `assertions_on_constants` is right to reject it.
        const { assert!(const_str_eq("x.y.z", "x.y.z")) };
        const { assert!(!const_str_eq("x.y.z", "x.y.q")) };
    }

    /// The macro accepts the crate's own version.
    ///
    /// Two things this cannot do, both deliberate. It cannot test the failing
    /// direction, because a mismatch is a *compile* error by design — which is
    /// why the `const_str_eq` cases above carry the real weight. And it cannot
    /// write `env!("CARGO_PKG_VERSION")` here, because the macro matches
    /// `$expected:literal` and `env!` is a macro call rather than a literal
    /// token. That restriction is correct — generated code always passes a
    /// literal — so the version below is spelled out on purpose: a version
    /// bump is meant to surface here and be acknowledged, not slip through.
    #[test]
    fn check_runtime_version_accepts_the_current_version() {
        crate::check_runtime_version!("0.19.100");
        assert_eq!(COMPACT_RUNTIME_VERSION, "0.19.100");
    }
}
