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
// Unified error type for generated contract code. Encompasses
// assertion failures (from `assert(cond, msg)` in Compact source) and
// VM-level transcript rejections.

use crate::{TranscriptRejected, DB};
use std::fmt;

/// Unified error type returned from every generated circuit and
/// constructor. Wraps both Compact-level assertion failures (from
/// `assert(cond, "msg")` in source) and VM-level transcript rejections
/// (gas exhaustion, type mismatches, invalid path keys, …).
#[derive(Debug)]
pub enum CompactError {
    /// A Compact `assert(cond, "msg")` evaluated to false. The string
    /// carries the user-supplied message.
    AssertionFailed(String),
    /// The VM rejected the assembled op program. Carries a debug-format
    /// rendering of the upstream `TranscriptRejected<D>`.
    TranscriptRejected(String),
}

impl fmt::Display for CompactError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AssertionFailed(msg) => write!(f, "assertion failed: {msg}"),
            Self::TranscriptRejected(msg) => write!(f, "transcript rejected: {msg}"),
        }
    }
}

impl std::error::Error for CompactError {}

impl<D: DB> From<TranscriptRejected<D>> for CompactError {
    fn from(t: TranscriptRejected<D>) -> Self {
        Self::TranscriptRejected(format!("{t:?}"))
    }
}

/// `compact_assert!(cond, "msg")` — returns `Err(CompactError::AssertionFailed)`
/// from the enclosing function (which must return `Result<_, CompactError>`)
/// if `cond` is false. Mirrors Compact's `assert(cond, "msg")`.
#[macro_export]
macro_rules! compact_assert {
    ($cond:expr, $msg:expr) => {
        if !($cond) {
            return Err($crate::CompactError::AssertionFailed($msg.into()));
        }
    };
    ($cond:expr) => {
        if !($cond) {
            return Err($crate::CompactError::AssertionFailed(
                concat!("at ", file!(), ":", line!()).into(),
            ));
        }
    };
}
