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
// `Maybe<T>` — Compact's standard-library option type.
//
// Mirrors the on-chain wire format (1-byte is_some + T's repr) used by
// `standard-library.compact`:
//
//   export struct Maybe<T> { is_some: Boolean; value: T; }
//
// Generated code references `Maybe<T>` directly; the `some(v)` /
// `none()` helpers below construct values in the same shape Compact's
// circuits do.

use crate::{Aligned, Alignment, CompactError, FieldRepr, Fr, FromFieldRepr, MemWrite, Value};

/// `Copy` is implemented when `T: Copy` so the struct composes cheaply
/// with primitive payloads (e.g. `Maybe<Field>`, `Maybe<u64>`).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Maybe<T> {
    pub is_some: bool,
    pub value: T,
}

impl<T> Maybe<T> {
    /// Returns the `is_some` discriminant. Provided as a method for
    /// ergonomic parity with `Option::is_some` even though the field
    /// itself is public.
    #[inline]
    pub fn is_some(&self) -> bool {
        self.is_some
    }

    /// Returns the inner `value`, or an error if `is_some` is false.
    ///
    /// This is the form generated code and library code should use: an
    /// absent value is data, so it travels on the same `Result` as every
    /// other contract-level failure rather than unwinding.
    #[inline]
    pub fn try_unwrap(self) -> Result<T, CompactError> {
        if !self.is_some {
            return Err(CompactError::AssertionFailed(
                "Maybe::unwrap on a None value".into(),
            ));
        }
        Ok(self.value)
    }

    /// Returns the inner `value`, panicking if `is_some` is false.
    ///
    /// Deliberately the `Option::unwrap` idiom: the caller asserts it has
    /// already established `is_some`, and a panic here means that assertion
    /// was wrong — a bug in the calling code, not a contract-level failure.
    /// Use [`Maybe::try_unwrap`] where the discriminant is not already
    /// known. Generated code uses neither; the emitter reads `is_some` and
    /// `value` directly.
    #[inline]
    pub fn unwrap(self) -> T {
        if !self.is_some {
            panic!("Maybe::unwrap on None");
        }
        self.value
    }
}

impl<T: Aligned> Aligned for Maybe<T> {
    fn alignment() -> Alignment {
        Alignment::concat([&bool::alignment(), &T::alignment()])
    }
}

impl<T: FieldRepr> FieldRepr for Maybe<T> {
    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {
        self.is_some.field_repr(writer);
        self.value.field_repr(writer);
    }
    fn field_size(&self) -> usize {
        self.is_some.field_size() + self.value.field_size()
    }
}

impl<T: FromFieldRepr> FromFieldRepr for Maybe<T> {
    const FIELD_SIZE: usize = 1 + T::FIELD_SIZE;
    fn from_field_repr(r: &[Fr]) -> Option<Self> {
        if r.len() < Self::FIELD_SIZE {
            return None;
        }
        let is_some = bool::from_field_repr(&r[..bool::FIELD_SIZE])?;
        let value = T::from_field_repr(&r[bool::FIELD_SIZE..Self::FIELD_SIZE])?;
        Some(Maybe { is_some, value })
    }
}

/// `From<Maybe<T>> for Value` so `Maybe<T>: DynAligned` lifts to
/// `AlignedValue: From<Maybe<T>>` through the upstream blanket impl,
/// which in turn satisfies `new_cell(Maybe::<T>::default())` at the
/// codegen seeding site. Parallels upstream `From<Option<T>> for Value`
/// (midnight-base-crypto/src/fab/conversions.rs:262).
impl<T: Into<Value>> From<Maybe<T>> for Value {
    fn from(inp: Maybe<T>) -> Value {
        Value::concat([Value::from(inp.is_some), inp.value.into()].iter())
    }
}

/// Construct a `Maybe<T>` in the "some" state. Mirrors Compact's
/// `some<T>(value: T): Maybe<T>` circuit from `standard-library.compact`.
#[inline]
pub fn some<T>(v: T) -> Maybe<T> {
    Maybe {
        is_some: true,
        value: v,
    }
}

/// Construct a `Maybe<T>` in the "none" state. The caller supplies a
/// default-shaped value for the inert `value` field; Compact's
/// `none<T>(): Maybe<T>` uses `default<T>` for this, which Rust can
/// mirror via `T::default()` at the call site.
#[inline]
pub fn none<T: Default>() -> Maybe<T> {
    Maybe {
        is_some: false,
        value: T::default(),
    }
}

#[cfg(test)]
mod tests {

    /// The field-repr round-trip is what generated code depends on for every
    /// optional read out of ledger state. `is_some` is part of that
    /// encoding, so a `None` must come back as a `None` rather than as a
    /// `Some` holding a default — which is the failure this pins.
    #[test]
    fn field_repr_round_trips_both_states() {
        let s = some(42u64);
        let mut buf: Vec<Fr> = Vec::new();
        s.field_repr(&mut buf);
        assert_eq!(Maybe::<u64>::from_field_repr(&buf), Some(s));

        let n: Maybe<u64> = none();
        let mut buf: Vec<Fr> = Vec::new();
        n.field_repr(&mut buf);
        let decoded = Maybe::<u64>::from_field_repr(&buf).expect("none decodes");
        assert!(!decoded.is_some(), "a None must not decode as Some");
        assert_eq!(decoded, n);
    }

    /// `Some` and `None` must not encode identically, even when the payload
    /// is the default value — otherwise the discriminant carries no
    /// information and every `None` reads back as `Some(default)`.
    #[test]
    fn some_of_the_default_is_distinguishable_from_none() {
        let s = some(0u64);
        let n: Maybe<u64> = none();
        assert_eq!(s.value, n.value, "same payload, by construction");

        let mut a: Vec<Fr> = Vec::new();
        let mut b: Vec<Fr> = Vec::new();
        s.field_repr(&mut a);
        n.field_repr(&mut b);
        assert_ne!(a, b, "the discriminant has to survive encoding");
    }

    #[test]
    fn field_size_matches_what_field_repr_writes() {
        let s = some(7u64);
        let mut buf: Vec<Fr> = Vec::new();
        s.field_repr(&mut buf);
        assert_eq!(buf.len(), s.field_size());
    }

    #[test]
    fn a_truncated_repr_is_rejected() {
        assert_eq!(Maybe::<u64>::from_field_repr(&[]), None);
    }

    #[test]
    #[should_panic(expected = "Maybe::unwrap on None")]
    fn unwrap_panics_on_none() {
        let n: Maybe<u64> = none();
        let _ = n.unwrap();
    }

    #[test]
    fn unwrap_returns_the_payload_on_some() {
        assert_eq!(some(5u64).unwrap(), 5);
    }
    use super::*;

    #[test]
    fn maybe_some_unwraps() {
        let m: Maybe<u32> = some(7);
        assert!(m.is_some());
        assert_eq!(m.unwrap(), 7);
    }

    #[test]
    fn maybe_none_is_none() {
        let m: Maybe<u32> = none();
        assert!(!m.is_some());
    }

    #[test]
    fn maybe_some_some_roundtrip() {
        // Sanity check: field_size of `Maybe<u8>` is 1 (is_some) + 1 (u8) = 2.
        let m: Maybe<u8> = Maybe {
            is_some: true,
            value: 42,
        };
        assert_eq!(m.field_size(), 1 + 42_u8.field_size());
        // FIELD_SIZE associated const matches.
        assert_eq!(
            <Maybe<u8> as FromFieldRepr>::FIELD_SIZE,
            1 + <u8 as FromFieldRepr>::FIELD_SIZE
        );
    }

    #[test]
    fn try_unwrap_reports_a_none_rather_than_unwinding() {
        let some: Maybe<u32> = Maybe {
            is_some: true,
            value: 7,
        };
        assert_eq!(some.try_unwrap().unwrap(), 7);

        let err = none::<u32>()
            .try_unwrap()
            .expect_err("a None must not yield a value");
        assert!(err.to_string().contains("Maybe::unwrap on a None value"));
    }
}
