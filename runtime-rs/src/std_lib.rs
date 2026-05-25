// SPDX-License-Identifier: Apache-2.0
//
// Compact standard library types used by generated contract code.
//
// Each ledger ADT (Counter / Cell / Map / Set / MerkleTree / List) lives
// here as a newtype + a `decode_from(&StateValue)` helper. The compiler
// lowers mutating operations (e.g., `round.increment(1)`) directly to
// Op programs, so the wrappers don't need methods for those.

use crate::{AlignedValue, CompactError, StateValue};

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

/// Decode an `AlignedValue` known to be a u64 value into a u64.
///
/// The base-crypto `ValueAtom` encoding for primitive integers is
/// little-endian with trailing zero bytes stripped via `normalize`
/// (see `midnight_base_crypto::fab::conversions`), so a u64 may occupy
/// 0..=8 bytes. We left-pad with zeros and decode little-endian.
pub fn decode_u64(av: &AlignedValue) -> Result<u64, CompactError> {
    let atom = av.value.0.first().ok_or_else(|| {
        CompactError::AssertionFailed("decode_u64: aligned value is empty".into())
    })?;
    let bytes: &[u8] = &atom.0;
    if bytes.len() > 8 {
        return Err(CompactError::AssertionFailed(format!(
            "decode_u64: expected at most 8 bytes, got {}",
            bytes.len()
        )));
    }
    let mut buf = [0u8; 8];
    buf[..bytes.len()].copy_from_slice(bytes);
    Ok(u64::from_le_bytes(buf))
}
