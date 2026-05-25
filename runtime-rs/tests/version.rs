// SPDX-License-Identifier: Apache-2.0

#[test]
fn matching_version_compiles() {
    // The macro expands to a const assertion. If the expected string equals
    // compact_runtime::COMPACT_RUNTIME_VERSION, the assertion passes and the
    // test compiles. If not, compilation fails.
    compact_runtime::check_runtime_version!("0.1.0");
}

#[test]
fn version_constant_is_exposed() {
    assert_eq!(compact_runtime::COMPACT_RUNTIME_VERSION, "0.1.0");
}
