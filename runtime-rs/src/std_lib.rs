// SPDX-License-Identifier: Apache-2.0
//
// Compact standard library types used by generated contract code.
//
// Each ledger ADT (Counter / Cell / Map / Set / MerkleTree / List) lives
// here as a newtype + a `decode_from(&StateValue)` helper. The compiler
// lowers mutating operations (e.g., `round.increment(1)`) directly to
// Op programs, so the wrappers don't need methods for those.

use crate::{aligned_bytes, AlignedValue, CompactError, ContractState, StateValue, DB};

/// Compact's `Counter` ledger ADT. Represented at runtime as
/// `StateValue::Cell` containing a u64 aligned-value.
pub struct Counter;

impl Counter {
    /// Decode the current counter value from a `StateValue::Cell`.
    /// Returns `Err(AssertionFailed)` if `sv` is not a Cell or its
    /// contents are not a u64-aligned value.
    pub fn decode_from(sv: &StateValue) -> Result<u64, CompactError> {
        let cell = match sv {
            StateValue::Cell(c) => c,
            _ => {
                return Err(CompactError::AssertionFailed(
                    "Counter::decode_from: expected StateValue::Cell".into(),
                ));
            }
        };
        decode_u64(cell)
    }
}

/// Decode an `AlignedValue` known to be a fixed-width unsigned integer to a
/// u128. Accepts variable-length atoms (upstream strips trailing zero bytes)
/// and zero-pads to the full target width. Internal helper for the typed
/// decoders below.
///
/// The base-crypto `ValueAtom` encoding for primitive integers is
/// little-endian with trailing zero bytes stripped via `normalize`
/// (see `midnight_base_crypto::fab::conversions`), so e.g. a u64 may occupy
/// 0..=8 bytes. We zero-pad and decode little-endian.
fn decode_unsigned(av: &AlignedValue, max_bytes: usize) -> Result<u128, CompactError> {
    let bytes = aligned_bytes(av).ok_or_else(|| {
        CompactError::AssertionFailed("decode_unsigned: aligned value is empty".into())
    })?;
    if bytes.len() > max_bytes {
        return Err(CompactError::AssertionFailed(format!(
            "decode_unsigned: expected at most {max_bytes} bytes, got {}",
            bytes.len()
        )));
    }
    let mut buf = [0u8; 16];
    buf[..bytes.len()].copy_from_slice(bytes);
    Ok(u128::from_le_bytes(buf))
}

/// Decode an `AlignedValue` known to be a u8.
pub fn decode_u8(av: &AlignedValue) -> Result<u8, CompactError> {
    decode_unsigned(av, 1).map(|n| n as u8)
}

/// Decode an `AlignedValue` known to be a u16.
pub fn decode_u16(av: &AlignedValue) -> Result<u16, CompactError> {
    decode_unsigned(av, 2).map(|n| n as u16)
}

/// Decode an `AlignedValue` known to be a u32.
pub fn decode_u32(av: &AlignedValue) -> Result<u32, CompactError> {
    decode_unsigned(av, 4).map(|n| n as u32)
}

/// Decode an `AlignedValue` known to be a u64.
pub fn decode_u64(av: &AlignedValue) -> Result<u64, CompactError> {
    decode_unsigned(av, 8).map(|n| n as u64)
}

/// Decode an `AlignedValue` known to be a u128.
pub fn decode_u128(av: &AlignedValue) -> Result<u128, CompactError> {
    decode_unsigned(av, 16)
}

/// Canonically serialise a `ContractState` to bytes via
/// `midnight_serialize::tagged_serialize` — this is the byte format the
/// TypeScript runtime's `cr.encode` produces. Use this for byte-parity tests
/// and on-chain submission.
pub fn serialize_contract_state<D: DB>(state: &ContractState<D>) -> Result<Vec<u8>, CompactError> {
    let mut buf = Vec::new();
    midnight_serialize::tagged_serialize(state, &mut buf)
        .map_err(|e| CompactError::AssertionFailed(format!("serialize_contract_state: {e}")))?;
    Ok(buf)
}

// -------------------------------------------------------------------------
// M3a universal helpers — Bytes<N>, Maybe<T>, pad, disclose
// -------------------------------------------------------------------------

/// Compact's `Bytes<N>` primitive maps directly to a fixed-width byte array.
/// Generated code uses this alias rather than spelling `[u8; N]` everywhere.
pub type Bytes<const N: usize> = [u8; N];

/// Compact's standard-library `Maybe<T>` ADT — equivalent to `Option<T>`
/// but kept as a distinct type so generated code matches the TS spelling.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Maybe<T> {
    Some(T),
    None,
}

impl<T> Maybe<T> {
    #[inline]
    pub fn is_some(&self) -> bool {
        matches!(self, Maybe::Some(_))
    }

    #[inline]
    pub fn unwrap(self) -> T {
        match self {
            Maybe::Some(v) => v,
            Maybe::None => panic!("Maybe::unwrap on None"),
        }
    }
}

#[inline]
pub fn some<T>(v: T) -> Maybe<T> {
    Maybe::Some(v)
}

#[inline]
pub fn none<T>() -> Maybe<T> {
    Maybe::None
}

/// Compact's `pad(width, s)` — return the bytes of `s` resized to exactly
/// `width` bytes. Truncates if `s` is longer; zero-extends if shorter.
pub fn pad(width: usize, s: &str) -> Vec<u8> {
    let mut v = s.as_bytes().to_vec();
    v.resize(width, 0);
    v
}

/// Compact's `disclose(x)` — identity in Rust. The compiler uses this to
/// mark a value as publicly revealed; the runtime side has no operational
/// difference.
#[inline]
pub fn disclose<T>(x: T) -> T {
    x
}

#[cfg(test)]
mod tests_m3a_helpers {
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
    fn pad_truncates_and_zero_extends() {
        assert_eq!(pad(5, "abc"), vec![b'a', b'b', b'c', 0, 0]);
    }

    #[test]
    fn disclose_is_identity() {
        let x = 42u64;
        assert_eq!(disclose(x), 42u64);
    }
}
