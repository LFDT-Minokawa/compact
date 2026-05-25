// SPDX-License-Identifier: Apache-2.0
//
// Unified error type for generated contract code. Encompasses
// assertion failures (from `assert(cond, msg)` in Compact source) and
// VM-level transcript rejections.

use crate::{DefaultDB, TranscriptRejected, DB};
use std::fmt;

#[derive(Debug)]
pub enum CompactError {
    AssertionFailed(String),
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
