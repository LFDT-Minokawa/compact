// SPDX-License-Identifier: Apache-2.0

use compact_runtime::std_lib::Counter;
use compact_runtime::*;

#[test]
fn counter_decode_reads_u64_from_state_value() {
    let sv: StateValue = AlignedValue::from(42u64).into();
    let value = Counter::decode_from(&sv).expect("decode");
    assert_eq!(value, 42);
}

#[test]
fn counter_decode_errors_on_wrong_shape() {
    let sv = StateValue::Null;
    let err = Counter::decode_from(&sv).expect_err("should not decode");
    assert!(matches!(err, CompactError::AssertionFailed(_)));
}
