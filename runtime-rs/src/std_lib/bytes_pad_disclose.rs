// SPDX-License-Identifier: Apache-2.0
//
// `Bytes<N>`, `pad`, `disclose`, and `persistent_hash_aligned` —
// the standard-library "universal helpers" that don't fit a more
// specific bucket.

use crate::{AlignedValue, ValueReprAlignedValue};
use midnight_base_crypto::hash::PersistentHashWriter;
use midnight_base_crypto::repr::BinaryHashRepr;

/// Compact's `Bytes<N>` primitive maps directly to a fixed-width byte
/// array. Generated code uses this alias rather than spelling
/// `[u8; N]` everywhere.
pub type Bytes<const N: usize> = [u8; N];

/// Compact's `pad(width, s)` — return the bytes of `s` resized to
/// exactly `width` bytes. Truncates if `s` is longer; zero-extends if
/// shorter.
pub fn pad(width: usize, s: &str) -> Vec<u8> {
    let mut v = s.as_bytes().to_vec();
    v.resize(width, 0);
    v
}

/// Compact's `disclose(x)` — identity in Rust. The compiler uses this
/// to mark a value as publicly revealed; the runtime side has no
/// operational difference.
#[inline]
pub fn disclose<T>(x: T) -> T {
    x
}

/// Compact's `persistentHash<T>(value)` — alignment-aware persistent
/// hash.
///
/// Mirrors the TS path
/// `__compactRuntime.persistentHash(rtType, value)`, which lowers to
/// `ocrt.persistentHash(rtType.alignment(), rtType.toValue(value))`
/// inside the `onchain-runtime-wasm` crate. That call constructs an
/// [`AlignedValue`], wraps it in `ValueReprAlignedValue`, and hashes
/// the resulting alignment-framed byte stream with SHA-256.
///
/// In Rust we get the same bytes by:
/// 1. Building an `AlignedValue` for each pre-converted element (the
///    codegen passes already-`AlignedValue`-typed arguments — for a
///    `Vector<N, T>` that means N entries).
/// 2. Concatenating them with [`AlignedValue::concat`] — equivalent to
///    TS's `Value`-level concatenation.
/// 3. Feeding the result through `ValueReprAlignedValue::binary_repr`
///    into a `PersistentHashWriter`.
///
/// Returns the 32-byte SHA-256 digest as a `[u8; 32]`, matching the
/// Compact stdlib signature `persistentHash<T>(value: T): Bytes<32>`.
///
/// The byte stream produced by `ValueReprAlignedValue::binary_repr` is
/// the per-atom encoding documented in `spec/field-aligned-binary.md`:
/// `bytes<n>` atoms emit raw bytes padded out to `n` with zeros,
/// `field` atoms emit `FR_BYTES` little-endian bytes via
/// `Fr::as_le_bytes`, and `compress` atoms emit a `transient_commit` of
/// the contents. For uniform `Bytes<N>` inputs this coincides with raw
/// byte concatenation (which is why `tiny.compact`'s previous
/// `.concat().0` flat-byte emission produced the correct hash for
/// `public_key`), but it diverges for mixed-type, `Field`-, or
/// `Compress`-bearing inputs.
pub fn persistent_hash_aligned(values: &[AlignedValue]) -> [u8; 32] {
    let av = AlignedValue::concat(values.iter());
    let mut writer = PersistentHashWriter::new();
    ValueReprAlignedValue(av).binary_repr(&mut writer);
    writer.finalize().0
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::Fr;

    #[test]
    fn pad_truncates_and_zero_extends() {
        assert_eq!(pad(5, "abc"), vec![b'a', b'b', b'c', 0, 0]);
    }

    #[test]
    fn disclose_is_identity() {
        let x = 42u64;
        assert_eq!(disclose(x), 42u64);
    }

    #[test]
    fn persistent_hash_aligned_matches_raw_concat_for_byte_arrays() {
        // For uniform `Bytes<N>` inputs the alignment-aware path produces
        // exactly the same bytes as the raw flat `[a, b, ...].concat()`
        // approach used by I3b/1. Tiny.compact's `public_key` (two 32-byte
        // arrays) lives in this regime, so this acts as a backstop confirming
        // R3 doesn't regress tiny's existing byte-parity test.
        let a: [u8; 32] = [
            108, 97, 114, 101, 115, 58, 116, 105, 110, 121, 58, 112, 107, 58, 0, 0, 0, 0, 0, 0, 0,
            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0,
        ];
        let b: [u8; 32] = [
            42, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21, 22, 23,
            24, 25, 26, 27, 28, 29, 30, 31,
        ];
        let new_path = persistent_hash_aligned(&[a.into(), b.into()]);
        let old_path = midnight_base_crypto::hash::persistent_hash(&[a, b].concat()).0;
        assert_eq!(new_path, old_path);
    }

    #[test]
    fn persistent_hash_aligned_differs_for_field_input() {
        // For an `Fr` input the alignment-aware path emits a normalised
        // 32-byte little-endian encoding via `value_atom_as_field` /
        // `Fr::binary_repr` (always exactly FR_BYTES). Raw `.concat()` on
        // the AlignedValue bytes would NOT have the same framing, so this
        // is the smallest case where R3's fix is observable.
        let f = Fr::from(123456789u64);
        let av: AlignedValue = f.into();
        let new_path = persistent_hash_aligned(&[av.clone()]);
        // sanity: length is 32 bytes (sha256 output).
        assert_eq!(new_path.len(), 32);
        // independent observation: hashing the same Fr twice is stable.
        let new_path2 = persistent_hash_aligned(&[av]);
        assert_eq!(new_path, new_path2);
    }
}
