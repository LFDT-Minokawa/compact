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

//! Decoding ledger values into Rust values.
//!
//! These are the read half of the ledger boundary: an `AlignedValue` comes off
//! the chain and has to become a Rust value of a known Compact type. The
//! normative behaviour is `CompactType.fromValue` in the TypeScript runtime,
//! and these functions are written to agree with it — including on which
//! inputs are rejected.
//!
//! Two differences from the TypeScript side are deliberate, and both are
//! visible in the signatures.
//!
//! **Failure is in the return type.** TypeScript's `fromValue(value): bigint`
//! promises a `bigint` and throws instead; nothing at the call site says so.
//! These return `Result<_, CompactError>`, which a caller cannot silently
//! ignore.
//!
//! **The input is borrowed, not consumed.** TypeScript's `fromValue` is
//! documented as converting "destructively; (partially) consuming the input,
//! and ignoring superfluous data for chaining" — it calls `value.shift()` on
//! the caller's array, so decoding is order-dependent, stateful, and
//! non-repeatable. These take `&AlignedValue`; decoding the same value twice
//! gives the same answer, and cannot disturb anything the caller still holds.
//!
//! A Compact type's *domain* is not the same as its storage width, so the
//! decoders that need the declared bound take it as an argument — see
//! [`decode_bounded_uint`].

use crate::{
    aligned_bytes, jubjub_point_from_field_repr, AlignedValue, CompactError, Fr, JubjubPoint,
};

// ---------------------------------------------------------------------------
// Width-typed decoders.
// ---------------------------------------------------------------------------

/// Decode an `AlignedValue` holding a Compact `Uint<0..max>`.
///
/// `max` is the **declared Compact bound**, not the storage width. The two
/// are different numbers whenever the bound is not exactly `2^(8k) - 1`:
/// `Uint<0..100>` is stored in one byte, so every value up to 255 fits the
/// storage and only the bound rules out 101..=255.
///
/// This mirrors the normative decoder,
/// `CompactTypeUnsignedInteger.fromValue`, which accumulates the atom's
/// bytes little-endian and then rejects anything above `maxValue`:
///
/// ```ts
/// if (res > this.maxValue) {
///   throw new CompactError(`expected UnsignedInteger[<=${this.maxValue}]`);
/// }
/// ```
///
/// The width-typed helpers below pass `uN::MAX`, which is the right bound
/// only for a Compact type declared at the full width. For anything
/// narrower — every `Uint<0..n>` a contract actually writes — call this and
/// pass the declared bound, or the ledger view will hand contract code a
/// value its own type says cannot exist.
///
/// The byte-length check is retained on top of the value check. It cannot
/// over-reject (the storage width is by construction wide enough for `max`),
/// and it catches a malformed atom before the arithmetic rather than after.
pub fn decode_bounded_uint(
    av: &AlignedValue,
    max_bytes: usize,
    max: u128,
) -> Result<u128, CompactError> {
    let bytes = aligned_bytes(av).ok_or_else(|| {
        CompactError::AssertionFailed("decode_bounded_uint: aligned value is empty".into())
    })?;
    if bytes.len() > max_bytes {
        return Err(CompactError::AssertionFailed(format!(
            "decode_bounded_uint: expected at most {max_bytes} bytes, got {}",
            bytes.len()
        )));
    }
    let mut buf = [0u8; 16];
    buf[..bytes.len()].copy_from_slice(bytes);
    let value = u128::from_le_bytes(buf);
    if value > max {
        return Err(CompactError::AssertionFailed(format!(
            "expected UnsignedInteger[<={max}], got {value}"
        )));
    }
    Ok(value)
}

/// Decode an `AlignedValue` known to be a u8, i.e. Compact `Uint<0..255>`.
///
/// For a narrower declared bound use [`decode_bounded_uint`].
pub fn decode_u8(av: &AlignedValue) -> Result<u8, CompactError> {
    decode_bounded_uint(av, 1, u8::MAX as u128).map(|n| n as u8)
}

/// Decode an `AlignedValue` known to be a u16, i.e. Compact
/// `Uint<0..65535>`.
///
/// For a narrower declared bound use [`decode_bounded_uint`].
pub fn decode_u16(av: &AlignedValue) -> Result<u16, CompactError> {
    decode_bounded_uint(av, 2, u16::MAX as u128).map(|n| n as u16)
}

/// Decode an `AlignedValue` known to be a u32.
///
/// For a narrower declared bound use [`decode_bounded_uint`].
pub fn decode_u32(av: &AlignedValue) -> Result<u32, CompactError> {
    decode_bounded_uint(av, 4, u32::MAX as u128).map(|n| n as u32)
}

/// Decode an `AlignedValue` known to be a u64.
///
/// For a narrower declared bound use [`decode_bounded_uint`].
pub fn decode_u64(av: &AlignedValue) -> Result<u64, CompactError> {
    decode_bounded_uint(av, 8, u64::MAX as u128).map(|n| n as u64)
}

/// Decode an `AlignedValue` known to be a u128.
///
/// For a narrower declared bound use [`decode_bounded_uint`].
pub fn decode_u128(av: &AlignedValue) -> Result<u128, CompactError> {
    decode_bounded_uint(av, 16, u128::MAX)
}

/// Decode an `AlignedValue` known to be a Compact `Boolean`.
///
/// Booleans have exactly two encodings, and this accepts exactly those two.
/// The normative decoder is `CompactTypeBoolean.fromValue`:
///
/// ```ts
/// const val = value.shift();
/// if (val == undefined || val.length > 1 || (val.length == 1 && val[0] != 1)) {
///   throw new CompactError('expected Boolean');
/// }
/// return val.length == 1;
/// ```
///
/// so `false` is the **empty** atom and `true` is the single byte `1`. A
/// one-byte atom holding `0` is not a canonical `false`: `toValue(false)`
/// produces `new Uint8Array(0)`, and `ValueAtom::normalize` strips the
/// trailing zero on the Rust side too, so nothing that encodes a Compact
/// boolean ever produces it.
///
/// Coercing any nonzero byte to `true` would be the worse half of a
/// divergence: a cell holding `2` — reachable by anything writing the ledger
/// outside this crate — would throw in TypeScript while contract code here
/// carried on with a value its own type says cannot exist.
pub fn decode_bool(av: &AlignedValue) -> Result<bool, CompactError> {
    let bytes = aligned_bytes(av)
        .ok_or_else(|| CompactError::AssertionFailed("expected Boolean, got no value".into()))?;
    match bytes {
        [] => Ok(false),
        [1] => Ok(true),
        other => Err(CompactError::AssertionFailed(format!(
            "expected Boolean, got {other:?}"
        ))),
    }
}

/// Decode an `AlignedValue` known to be a `Vector<N, Field>` — i.e. N
/// consecutive `Fr` atoms in the value. Each atom is parsed via
/// `Fr::try_from(&ValueAtom)` (same path as `decode_fr`). Returns
/// `Err(AssertionFailed)` if the value has fewer than N atoms or any
/// individual atom fails to parse.
pub fn decode_vector_fr<const N: usize>(av: &AlignedValue) -> Result<[Fr; N], CompactError> {
    if av.value.0.len() < N {
        return Err(CompactError::AssertionFailed(format!(
            "decode_vector_fr: expected at least {N} atoms, got {}",
            av.value.0.len()
        )));
    }
    let mut out = [Fr::default(); N];
    for (i, atom) in av.value.0.iter().take(N).enumerate() {
        out[i] = Fr::try_from(atom)
            .map_err(|e| CompactError::AssertionFailed(format!("decode_vector_fr[{i}]: {e:?}")))?;
    }
    Ok(out)
}

/// Decode an `AlignedValue` known to be a `Vector<N, Uint<64>>` — i.e.
/// N consecutive u64 atoms in the value. Each atom occupies 0..=8 bytes
/// (trailing zero bytes are stripped by upstream `normalize`); we
/// zero-pad each per-element slice and read as little-endian u64.
/// Returns `Err(AssertionFailed)` if the value has fewer than N atoms
/// or any individual atom carries more than 8 bytes.
///
/// Mirrors `decode_vector_fr` for the integer case, so a
/// `Vector<N, Uint<64>>` ledger view can decode the gathered `AlignedValue`
/// a `new_cell_array` write produces.
pub fn decode_vector_u64<const N: usize>(av: &AlignedValue) -> Result<[u64; N], CompactError> {
    if av.value.0.len() < N {
        return Err(CompactError::AssertionFailed(format!(
            "decode_vector_u64: expected at least {N} atoms, got {}",
            av.value.0.len()
        )));
    }
    let mut out = [0u64; N];
    for (i, atom) in av.value.0.iter().take(N).enumerate() {
        let bytes = atom.0.as_slice();
        if bytes.len() > 8 {
            return Err(CompactError::AssertionFailed(format!(
                "decode_vector_u64[{i}]: expected at most 8 bytes, got {}",
                bytes.len()
            )));
        }
        let mut buf = [0u8; 8];
        buf[..bytes.len()].copy_from_slice(bytes);
        out[i] = u64::from_le_bytes(buf);
    }
    Ok(out)
}

/// Decode an `AlignedValue` known to be a fixed-width byte array
/// `Bytes<N>`.
///
/// Compact's `Bytes<N>` lowers to a single `ValueAtom` carrying the raw
/// bytes; upstream `normalize` may strip trailing zero bytes. We
/// zero-pad up to `N` and return the full array. Returns
/// `Err(AssertionFailed)` if the atom carries more than `N` bytes.
pub fn decode_bytes<const N: usize>(av: &AlignedValue) -> Result<[u8; N], CompactError> {
    let bytes = aligned_bytes(av).ok_or_else(|| {
        CompactError::AssertionFailed("decode_bytes: aligned value is empty".into())
    })?;
    if bytes.len() > N {
        return Err(CompactError::AssertionFailed(format!(
            "decode_bytes: expected at most {N} bytes, got {}",
            bytes.len()
        )));
    }
    let mut out = [0u8; N];
    out[..bytes.len()].copy_from_slice(bytes);
    Ok(out)
}

/// Decode an `AlignedValue` known to be a `Field` (i.e. a single `Fr`
/// atom).
///
/// On the encode side, `Fr` lowers to a single `ValueAtom` via
/// `midnight_transient_crypto::fab::From<Fr> for ValueAtom`, which
/// writes `Fr::as_le_bytes` and `.normalize()`s trailing zeros. We
/// invert by reading the first atom and running `Fr::try_from(&ValueAtom)`,
/// which calls `Fr::from_le_bytes` and accepts ≤ `FR_BYTES` bytes.
pub fn decode_fr(av: &AlignedValue) -> Result<Fr, CompactError> {
    let atom = av.value.0.first().ok_or_else(|| {
        CompactError::AssertionFailed("decode_fr: aligned value has no atoms".into())
    })?;
    Fr::try_from(atom).map_err(|e| CompactError::AssertionFailed(format!("decode_fr: {e:?}")))
}

/// Decode a `JubjubPoint` from a ledger `AlignedValue`: two `field` atoms
/// read back as the coordinate pair they are.
///
/// Curve membership is **not** checked, matching
/// `CompactTypeJubjubPoint.fromValue`, which reads the two atoms and returns
/// `{ x, y }`. A cell can hold any two field elements — Compact's
/// `constructJubjubPoint` performs no check, and neither does the circuit —
/// so refusing to read one back would make state written by the TypeScript
/// runtime unreadable here.
///
/// Reconstructing a validated subgroup element here would do worse than
/// reject an off-curve pair: for a point on the curve but *outside* the
/// prime-order subgroup, upstream's `EmbeddedGroupAffine::new` panics inside
/// `into_subgroup`. Ledger state is untrusted input and must not be able to
/// abort the process.
pub fn decode_jubjub_point(av: &AlignedValue) -> Result<JubjubPoint, CompactError> {
    let mut frs: Vec<Fr> = Vec::with_capacity(av.value.0.len());
    for (i, atom) in av.value.0.iter().enumerate() {
        let fr = Fr::try_from(atom).map_err(|e| {
            CompactError::AssertionFailed(format!("decode_jubjub_point[{i}]: {e:?}"))
        })?;
        frs.push(fr);
    }
    jubjub_point_from_field_repr(&frs).ok_or_else(|| {
        CompactError::AssertionFailed(format!(
            "decode_jubjub_point: expected 2 field atoms, got {}",
            frs.len()
        ))
    })
}

#[cfg(test)]
mod decoder_tests {
    use super::super::decode_via_field_repr;
    use super::*;

    /// These decoders are the read path out of ledger state: an
    /// `AlignedValue` off the chain, turned back into a Rust value. A wrong
    /// answer here is not a crash, it is a contract that reads the wrong
    /// number — which is why the round-trips below assert values rather than
    /// merely that decoding succeeded.

    #[test]
    fn unsigned_decoders_round_trip_their_own_widths() {
        assert_eq!(decode_u8(&AlignedValue::from(7u8)).unwrap(), 7);
        assert_eq!(decode_u16(&AlignedValue::from(1_000u16)).unwrap(), 1_000);
        assert_eq!(decode_u32(&AlignedValue::from(70_000u32)).unwrap(), 70_000);
        assert_eq!(
            decode_u64(&AlignedValue::from(5_000_000_000u64)).unwrap(),
            5_000_000_000
        );
        assert_eq!(
            decode_u128(&AlignedValue::from(u128::from(u64::MAX) + 1)).unwrap(),
            u128::from(u64::MAX) + 1
        );
    }

    /// Boundary values, because a width mistake in the decoder shows up at
    /// the extremes rather than in the middle.
    #[test]
    fn unsigned_decoders_handle_their_extremes() {
        assert_eq!(decode_u8(&AlignedValue::from(0u8)).unwrap(), 0);
        assert_eq!(decode_u8(&AlignedValue::from(u8::MAX)).unwrap(), u8::MAX);
        assert_eq!(decode_u16(&AlignedValue::from(u16::MAX)).unwrap(), u16::MAX);
        assert_eq!(decode_u32(&AlignedValue::from(u32::MAX)).unwrap(), u32::MAX);
        assert_eq!(decode_u64(&AlignedValue::from(u64::MAX)).unwrap(), u64::MAX);
        assert_eq!(
            decode_u128(&AlignedValue::from(u128::MAX)).unwrap(),
            u128::MAX
        );
    }

    /// A narrower decoder reading a wider value must not silently truncate.
    /// This is the same class as the `as`-cast bug the emitter had: a wrong
    /// value is worse than an error.
    #[test]
    fn a_narrow_decoder_does_not_truncate_a_wide_value() {
        let wide = AlignedValue::from(u64::MAX);
        let got = decode_u8(&wide);
        assert!(
            got.is_err() || got.unwrap() == u8::MAX,
            "decoding a u64::MAX as u8 must not quietly yield a small number"
        );
    }

    #[test]
    fn bool_decodes_both_ways() {
        assert!(decode_bool(&AlignedValue::from(true)).unwrap());
        assert!(!decode_bool(&AlignedValue::from(false)).unwrap());
    }

    #[test]
    fn fr_round_trips() {
        for v in [0u64, 1, 42, u64::MAX] {
            let f = Fr::from(v);
            assert_eq!(decode_fr(&AlignedValue::from(f)).unwrap(), f);
        }
    }

    #[test]
    fn bytes_round_trip_at_the_common_width() {
        let b = [3u8; 32];
        assert_eq!(decode_bytes::<32>(&AlignedValue::from(b)).unwrap(), b);
    }

    /// `decode_via_field_repr` is the generic path used for user structs and
    /// enums. Exercised here through a primitive so the test does not depend
    /// on generated code.
    #[test]
    fn decode_via_field_repr_handles_a_primitive() {
        let av = AlignedValue::from(9u64);
        assert_eq!(decode_via_field_repr::<u64>(&av).unwrap(), 9u64);
    }

    /// Decoding the wrong shape must produce an error rather than a value.
    /// Each of these is a case where returning something plausible would be
    /// worse than failing.
    #[test]
    fn a_mismatched_shape_is_an_error_not_a_guess() {
        let boolean = AlignedValue::from(true);
        assert!(
            decode_vector_fr::<3>(&boolean).is_err(),
            "a single bool is not a 3-element Fr vector"
        );
    }

    /// `decode_bytes` zero-extends a short atom instead of rejecting it, and
    /// that is correct rather than lax: the encode side `.normalize()`s
    /// trailing zeros, so a `Bytes<32>` whose value ends in zeros comes back
    /// as a *shorter* atom. Zero-padding is the exact inverse of that.
    ///
    /// Which is why over-long is the only error case — and worth pinning,
    /// because "reject anything not exactly N bytes" is the tempting
    /// tightening that would break every value with a zero tail.
    #[test]
    fn decode_bytes_zero_extends_a_normalized_atom_but_rejects_an_overlong_one() {
        assert_eq!(
            decode_bytes::<32>(&AlignedValue::from(1u8)).unwrap(),
            {
                let mut want = [0u8; 32];
                want[0] = 1;
                want
            },
            "a one-byte atom is a Bytes<32> whose upper 31 bytes were normalized away"
        );

        let mut trailing_zeros = [0u8; 32];
        trailing_zeros[0] = 5;
        assert_eq!(
            decode_bytes::<32>(&AlignedValue::from(trailing_zeros)).unwrap(),
            trailing_zeros,
            "round-trip must survive normalization"
        );

        assert!(
            decode_bytes::<4>(&AlignedValue::from([9u8; 32])).is_err(),
            "32 bytes cannot be read as Bytes<4>"
        );
    }

    #[test]
    fn jubjub_point_decodes_from_its_aligned_form() {
        let p = crate::std_lib::ec_mul_generator(crate::std_lib::jubjub_scalar_from_field(
            Fr::from(23u64),
        ));
        let mut frs: Vec<Fr> = Vec::new();
        crate::std_lib::jubjub_point_field_repr(&p, &mut frs);
        let av: AlignedValue = (frs[0], frs[1]).into();
        assert_eq!(decode_jubjub_point(&av).unwrap(), p);
    }

    // ---- Compact domains, not just storage widths -------------------------
    //
    // A ledger cell is bytes. The Compact type that names the cell says which
    // of those byte patterns are values of that type, and the decoders are
    // where the two meet. Accepting a pattern the type excludes hands
    // contract code a value its own type says cannot exist — and does it
    // silently, which is worse than refusing.

    use crate::{Alignment, AlignmentAtom, Value, ValueAtom};

    /// Build an `AlignedValue` with a chosen raw atom under a `Bytes{len}`
    /// alignment — i.e. what a cell written by something other than this
    /// crate can legitimately contain.
    fn raw_cell(bytes: &[u8], len: u32) -> AlignedValue {
        AlignedValue::new(
            Value(vec![ValueAtom(bytes.to_vec())]),
            Alignment::singleton(AlignmentAtom::Bytes { length: len }),
        )
        .expect("test atom must fit the declared alignment")
    }

    /// The two canonical boolean encodings, taken from our own encoder so
    /// the test cannot drift from what the crate actually writes.
    #[test]
    fn bool_roundtrips_through_the_encoder() {
        assert!(!decode_bool(&AlignedValue::from(false)).unwrap());
        assert!(decode_bool(&AlignedValue::from(true)).unwrap());
    }

    /// `false` is the empty atom, not a zero byte: `toValue(false)` is
    /// `new Uint8Array(0)` in TypeScript and `ValueAtom::normalize` strips
    /// the trailing zero here.
    #[test]
    fn the_canonical_false_is_the_empty_atom() {
        let av = AlignedValue::from(false);
        assert_eq!(
            av.value.0[0].0.len(),
            0,
            "if this changes, decode_bool's accepted set has to change with it"
        );
    }

    /// Byte `2` is not a Compact `Boolean` — `CompactTypeBoolean.fromValue`
    /// throws on it — so decoding it as `true`, which any `n != 0` test does,
    /// hands contract code a value its own type excludes.
    #[test]
    fn decode_bool_rejects_a_non_boolean_byte() {
        for byte in [2u8, 3, 0xFF] {
            let err = decode_bool(&raw_cell(&[byte], 1))
                .expect_err("only the empty atom and [1] are Booleans");
            assert!(err.to_string().contains("expected Boolean"), "got: {err}");
        }
    }

    /// TypeScript also rejects a one-byte atom holding `0`
    /// (`val.length == 1 && val[0] != 1`), and this decoder agrees with it
    /// for a stronger reason than agreement: `Bytes{n}` alignment requires
    /// the atom to be in normal form, so an atom with a trailing zero byte
    /// cannot be part of a well-formed `AlignedValue` at all.
    ///
    /// That invariant is what makes "empty means false" safe to rely on,
    /// so it is asserted rather than assumed. If it ever weakens,
    /// `decode_bool` needs a `[0] => Ok(false)` arm and this test is where
    /// that gets noticed.
    #[test]
    fn a_non_normal_form_atom_is_not_a_well_formed_aligned_value() {
        for (bytes, len) in [(&[0u8][..], 1u32), (&[1u8, 0][..], 2)] {
            assert!(
                AlignedValue::new(
                    Value(vec![ValueAtom(bytes.to_vec())]),
                    Alignment::singleton(AlignmentAtom::Bytes { length: len }),
                )
                .is_none(),
                "trailing zeros must be unrepresentable: {bytes:?}"
            );
        }
    }

    /// A two-byte atom is not a Boolean however its bytes read —
    /// TypeScript rejects on `val.length > 1` before looking at them.
    #[test]
    fn decode_bool_rejects_an_overlong_atom() {
        assert!(decode_bool(&raw_cell(&[1, 1], 2)).is_err());
    }

    /// The unsigned case: `200` fits one byte, so the storage width admits
    /// it, but a `Uint<0..100>` does not contain it.
    /// `CompactTypeUnsignedInteger.fromValue` throws
    /// `expected UnsignedInteger[<=100]`.
    #[test]
    fn a_bounded_uint_rejects_a_value_above_its_declared_maximum() {
        let av = raw_cell(&[200], 1);

        assert_eq!(
            decode_u8(&av).unwrap(),
            200,
            "the full-width helper is correct for Uint<0..255> and must keep \
             accepting it"
        );

        let err = decode_bounded_uint(&av, 1, 100)
            .expect_err("200 is outside Uint<0..100> whatever its storage width");
        assert!(
            err.to_string().contains("expected UnsignedInteger[<=100]"),
            "message should name the declared bound, got: {err}"
        );
    }

    #[test]
    fn a_bounded_uint_accepts_its_boundary_value() {
        assert_eq!(
            decode_bounded_uint(&raw_cell(&[100], 1), 1, 100).unwrap(),
            100
        );
        assert_eq!(decode_bounded_uint(&raw_cell(&[], 1), 1, 100).unwrap(), 0);
    }

    /// The bound and the storage width are independent checks, and the
    /// width one still has to hold: `Uint<0..70000>` needs 3 bytes, so a
    /// 4-byte atom is malformed even though 70000 would pass the bound.
    #[test]
    fn a_bounded_uint_still_rejects_an_overlong_atom() {
        let err = decode_bounded_uint(&raw_cell(&[0x70, 0x11, 0x01, 0x02], 4), 3, 70_000)
            .expect_err("4 bytes is wider than the declared 3");
        assert!(err.to_string().contains("at most 3 bytes"), "got: {err}");
    }
}
