// SPDX-License-Identifier: Apache-2.0
//
// M3.5 helpers for codegen of `[u8; N]`, `Vec<u8>`, and `[T; N]`
// fields.
//
// Upstream `midnight-transient-crypto` provides only a partial set of
// `FieldRepr` / `FromFieldRepr` impls for byte arrays and vectors, and
// Rust's orphan rules forbid us from supplying the missing ones
// directly (the trait + the foreign type are both upstream). To
// sidestep the orphan rule, we expose plain functions in
// `compact_runtime` that the codegen calls from inside generated
// struct `FromFieldRepr` bodies. The local struct's own impl is OK by
// orphan rules; the per-field deserialiser doesn't need to go through
// `<T as FromFieldRepr>` for problematic T.

use crate::{FromFieldRepr, Fr};

/// FIELD_SIZE for a `[u8; N]` field-repr — 31-byte chunks plus a stray
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
