// SPDX-License-Identifier: Apache-2.0
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

use crate::{Aligned, Alignment, FieldRepr, Fr, FromFieldRepr, MemWrite, Value};

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

    /// Returns the inner `value`, panicking if `is_some` is false.
    /// Matches the Compact `Maybe::unwrap` circuit's runtime check
    /// semantics.
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
}
