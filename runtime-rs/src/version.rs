// SPDX-License-Identifier: Apache-2.0
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
