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
// M3.5 helpers for codegen of `[u8; N]`, `Vec<u8>`, and `[T; N]`
// fields.
//
// Upstream `midnight-transient-crypto` provides only a partial set of
// `FieldRepr` / `FromFieldRepr` impls for byte arrays and vectors, and
// Rust's orphan rules forbid us from supplying the missing ones
// directly (the trait + the foreign type are both upstream). To
// sidestep the orphan rule, we expose plain functions in
// `midnight_compact_runtime` that the codegen calls from inside generated
// struct `FromFieldRepr` bodies. The local struct's own impl is OK by
// orphan rules; the per-field deserialiser doesn't need to go through
// `<T as FromFieldRepr>` for problematic T.

use crate::{Fr, FromFieldRepr};

/// `FIELD_SIZE` for a `[u8; N]` field-repr — 31-byte chunks plus a stray
/// Fr for the remainder, matching `bytes_from_field_repr`'s packing.
pub const fn bytes_field_size(n: usize) -> usize {
    let stray = n % 31;
    let chunks = n / 31;
    chunks + if stray == 0 { 0 } else { 1 }
}

/// Parse a `[u8; N]` from an Fr-slice using upstream's packing layout.
/// Codegen calls this in generated `FromFieldRepr` bodies when N != 32
/// (the only size upstream's blanket impl covers).
pub fn bytes_from_field_repr<const N: usize>(r: &[Fr]) -> Option<[u8; N]> {
    let size = bytes_field_size(N);
    if r.len() < size {
        return None;
    }
    let v = midnight_transient_crypto::repr::bytes_from_field_repr(&mut &r[..size], N)?;
    let mut out = [0u8; N];
    out.copy_from_slice(&v);
    Some(out)
}

/// Parse a `Vec<u8>` from an Fr-slice — packs all remaining elements
/// into bytes (no length prefix). Codegen calls this for `Vec<u8>`
/// fields where upstream provides no `FromFieldRepr`.
pub fn vec_u8_from_field_repr(r: &[Fr]) -> Option<Vec<u8>> {
    if r.is_empty() {
        return Some(Vec::new());
    }
    midnight_transient_crypto::repr::bytes_from_field_repr(&mut &r[..], r.len() * 31)
}

/// Parse a `[T; N]` of user-typed elements from an Fr-slice. Codegen
/// calls this for struct/enum array fields where neither upstream nor
/// orphan rules let us write the impl directly. Returns `None` if any
/// element parse fails or the slice is too short.
pub fn array_from_field_repr<T, const N: usize>(r: &[Fr], elt_size: usize) -> Option<[T; N]>
where
    T: FromFieldRepr,
{
    if r.len() < elt_size * N {
        return None;
    }
    let mut v: Vec<T> = Vec::with_capacity(N);
    for i in 0..N {
        v.push(T::from_field_repr(&r[i * elt_size..(i + 1) * elt_size])?);
    }
    v.try_into().ok()
}

#[cfg(test)]
mod tests {
    use super::*;

    /// The packing is 31 bytes per `Fr`, because an `Fr` cannot hold a full
    /// 32 bytes. Every size below is a boundary of that: exact multiples,
    /// one past, and one short.
    #[test]
    fn bytes_field_size_counts_31_byte_chunks() {
        assert_eq!(bytes_field_size(0), 0);
        assert_eq!(bytes_field_size(1), 1);
        assert_eq!(bytes_field_size(30), 1);
        assert_eq!(bytes_field_size(31), 1, "exactly one full chunk");
        assert_eq!(bytes_field_size(32), 2, "one past a chunk needs a stray");
        assert_eq!(bytes_field_size(62), 2);
        assert_eq!(bytes_field_size(63), 3);
    }

    /// A slice shorter than the declared size must be refused rather than
    /// read past — this is the guard that keeps a truncated ledger value from
    /// decoding into a plausible-looking array.
    #[test]
    fn a_short_slice_is_rejected() {
        assert_eq!(bytes_from_field_repr::<32>(&[]), None);
        assert_eq!(
            bytes_from_field_repr::<32>(&[Fr::from(0u64)]),
            None,
            "32 bytes needs 2 Fr, not 1"
        );
        assert_eq!(
            bytes_from_field_repr::<64>(&[Fr::from(0u64); 2]),
            None,
            "64 bytes needs 3 Fr, not 2"
        );
    }

    /// Exactly-sized and over-sized inputs both work: the decoder takes the
    /// prefix it needs and ignores the rest, because a field is decoded from
    /// the middle of a larger struct repr.
    #[test]
    fn an_exact_or_longer_slice_is_accepted() {
        let two = [Fr::from(0u64); 2];
        assert!(bytes_from_field_repr::<32>(&two).is_some());

        let many = [Fr::from(0u64); 8];
        assert!(
            bytes_from_field_repr::<32>(&many).is_some(),
            "trailing elements belong to the next field, not to this one"
        );
    }

    #[test]
    fn an_empty_vec_repr_decodes_to_an_empty_vec() {
        assert_eq!(vec_u8_from_field_repr(&[]), Some(Vec::new()));
    }

    /// `vec_u8_from_field_repr` consumes the whole slice, so its output
    /// length follows the 31-byte packing rather than the caller's intent.
    #[test]
    fn vec_u8_repr_length_follows_the_packing() {
        let one = vec_u8_from_field_repr(&[Fr::from(0u64)]).expect("one Fr decodes");
        assert_eq!(one.len(), 31);

        let three = vec_u8_from_field_repr(&[Fr::from(0u64); 3]).expect("three Fr decode");
        assert_eq!(three.len(), 93);
    }

    /// `array_from_field_repr` must reject when the slice cannot hold `N`
    /// elements of `elt_size`, and must not silently return a short array.
    #[test]
    fn array_repr_rejects_a_slice_too_short_for_n_elements() {
        // u64 has FIELD_SIZE 1 upstream, so 3 elements need 3 Fr.
        let two = [Fr::from(1u64); 2];
        assert_eq!(array_from_field_repr::<u64, 3>(&two, 1), None);

        let three = [Fr::from(1u64); 3];
        let got = array_from_field_repr::<u64, 3>(&three, 1);
        assert_eq!(got, Some([1u64, 1, 1]));
    }

    #[test]
    fn array_repr_reads_each_element_from_its_own_window() {
        let src = [Fr::from(7u64), Fr::from(8u64), Fr::from(9u64)];
        assert_eq!(
            array_from_field_repr::<u64, 3>(&src, 1),
            Some([7u64, 8, 9]),
            "element i must come from window i, not from a repeated read"
        );
    }
}
