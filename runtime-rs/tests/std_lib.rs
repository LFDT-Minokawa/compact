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
