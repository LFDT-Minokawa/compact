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
// Range-checked narrowing for `x as Uint<N>`.
//
// The TypeScript backend lowers a narrowing cast to a bounds check that
// throws:
//
//     ((t1) => {
//       if (t1 > 99n) {
//         throw new CompactError('<src>: cast from Field or Uint value to \
//                                 smaller Uint value failed: ' + t1 +
//                                ' is greater than 99');
//       }
//       return t1;
//     })(expr)
//
// The Rust backend used to lower the same cast to Rust's `as`, which does
// not check anything. The two disagreed on every out-of-range value, in two
// separate ways (MediaNoxLabs/compact#51):
//
//   * `as` widens the accepted range to the *Rust* type's bound rather than
//     the Compact one. `Uint<0..100>` becomes `u8`, so 100..=255 was
//     accepted unchanged — a value outside the declared type, with no
//     truncation to make it visible.
//   * past that, `as` truncates. `300 as u8` is 44, so an out-of-range value
//     silently became a different, in-range-looking one.
//
// TypeScript is normative, so both were Rust bugs. This helper restores
// parity: same bound, same message, an error instead of a wrong value.

use crate::error::CompactError;

/// Narrow `value` to `T`, failing if it exceeds `max`.
///
/// `max` is the Compact type's upper bound, not the Rust type's — those
/// differ whenever the declared bound is not exactly `uN::MAX`, which is the
/// case that made the old lowering silently permissive.
///
/// `src` is the Compact source location, rendered into the message so a
/// failure points at the cast rather than at generated code.
pub fn narrow<T>(value: u128, max: u128, src: &str) -> Result<T, CompactError>
where
    T: TryFrom<u128>,
{
    if value > max {
        return Err(CompactError::CastFailed(format!(
            "{src}: cast from Field or Uint value to smaller Uint value failed: \
             {value} is greater than {max}"
        )));
    }
    // Unreachable while `max <= T::MAX`, which the emitter guarantees by
    // choosing T as the smallest Rust width holding `max`. Reported rather
    // than unwrapped so a future emitter change cannot turn it into a panic
    // inside generated code.
    T::try_from(value).map_err(|_| {
        CompactError::CastFailed(format!(
            "{src}: cast from Field or Uint value to smaller Uint value failed: \
             {value} does not fit the target Rust type"
        ))
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn in_range_passes_through() {
        let v: u8 = narrow(50, 99, "probe.compact line 1 char 1").unwrap();
        assert_eq!(v, 50);
    }

    #[test]
    fn boundary_value_is_accepted() {
        let v: u8 = narrow(99, 99, "probe.compact line 1 char 1").unwrap();
        assert_eq!(v, 99);
    }

    /// The case Rust's `as` got wrong without truncating: 100..=255 fits `u8`
    /// but is outside `Uint<0..100>`, so `as` returned it unchanged.
    #[test]
    fn above_compact_bound_but_inside_rust_type_is_rejected() {
        let r: Result<u8, _> = narrow(200, 99, "probe.compact line 2 char 64");
        let msg = r.unwrap_err().to_string();
        assert!(
            msg.contains("200 is greater than 99"),
            "message should name the value and the bound, got: {msg}"
        );
        assert!(
            msg.starts_with("probe.compact line 2 char 64:"),
            "message should lead with the Compact source location, got: {msg}"
        );
    }

    /// The case Rust's `as` corrupted: 300 truncates to 44.
    #[test]
    fn above_rust_type_is_rejected_rather_than_truncated() {
        let r: Result<u8, _> = narrow(300, 99, "probe.compact line 2 char 64");
        assert!(r.is_err(), "300 must not become 44");
        assert!(r
            .unwrap_err()
            .to_string()
            .contains("300 is greater than 99"));
    }

    /// The message is the TypeScript one verbatim, so the two backends report
    /// the same failure. Compare against the string TS emits, which is
    /// `'<src>: cast from Field or Uint value to smaller Uint value failed: '
    /// + t1 + ' is greater than <max>'`.
    #[test]
    fn message_matches_the_typescript_text() {
        let r: Result<u8, _> = narrow(300, 99, "narrow.compact line 2 char 64");
        assert_eq!(
            r.unwrap_err().to_string(),
            "narrow.compact line 2 char 64: cast from Field or Uint value to \
             smaller Uint value failed: 300 is greater than 99"
        );
    }

    #[test]
    fn wider_targets_work_too() {
        let v: u64 = narrow(4_294_967_296, u64::MAX as u128, "src").unwrap();
        assert_eq!(v, 4_294_967_296);
    }
}
