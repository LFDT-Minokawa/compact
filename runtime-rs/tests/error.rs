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

use compact_runtime::*;

#[test]
fn compact_error_constructs_assertion() {
    let e = CompactError::AssertionFailed("test".into());
    assert_eq!(e.to_string(), "assertion failed: test");
}

#[test]
fn transcript_rejected_converts_to_compact_error() {
    // The codegen will use `?` on QueryContext::query() results, relying
    // on a From<TranscriptRejected<D>> for CompactError impl. We can't
    // easily construct a TranscriptRejected, but we can verify the
    // conversion path exists at the type level.
    fn _conversion_exists<D: DB>(t: TranscriptRejected<D>) -> CompactError {
        t.into()
    }
}

#[test]
fn compact_assert_macro_passes_when_true() {
    fn check() -> Result<(), CompactError> {
        compact_runtime::compact_assert!(2 + 2 == 4, "math broken");
        Ok(())
    }
    check().unwrap();
}

#[test]
fn compact_assert_macro_errors_when_false() {
    fn check() -> Result<(), CompactError> {
        compact_runtime::compact_assert!(2 + 2 == 5, "nope");
        Ok(())
    }
    match check() {
        Err(CompactError::AssertionFailed(msg)) => assert_eq!(msg, "nope"),
        other => panic!("expected AssertionFailed, got {other:?}"),
    }
}
