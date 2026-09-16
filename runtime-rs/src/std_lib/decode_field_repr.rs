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

//! Decoding composite Compact types through their field representation.
//!
//! A struct, tuple or enum reaches the ledger as a sequence of `ValueAtom`s
//! described by an `Alignment`. Recovering the Rust value means walking the
//! two in lockstep and expanding each leaf into the `Fr` elements its field
//! representation occupies, then handing that `Fr` slice to the type's own
//! `FromFieldRepr` impl.
//!
//! The expansion is not one `Fr` per atom. A `Bytes<n>` leaf occupies
//! `ceil(n / 31)` field elements, because upstream packs bytes into 31-byte
//! (`FR_BYTES_STORED`) chunks — so a 32-byte address is two elements, not one,
//! and the chunks are emitted in reverse order with the stray tail first. Any
//! decoder that assumed one element per atom would read the wrong values for
//! every type with a leaf wider than 31 bytes.
//!
//! [`expand_segments`] mirrors upstream's `Value::repr_traverse`, including
//! the `Option` segment rule: a two-byte discriminant selects a variant and
//! the stream is padded with zero elements out to the widest variant's length.

use crate::{AlignedValue, AlignmentAtom, CompactError, Fr, FromFieldRepr, ValueAtom};
use midnight_base_crypto::fab::AlignmentSegment;
use midnight_transient_crypto::curve::FR_BYTES_STORED;
use midnight_transient_crypto::fab::AlignmentExt;

/// Expand the raw bytes of one leaf atom into the `Fr` chunks its
/// field-repr occupies, mirroring upstream `impl FieldRepr for [u8]`
/// (`midnight-transient-crypto/src/repr.rs`): the bytes are packed into
/// 31-byte (`FR_BYTES_STORED`) little-endian chunks with the boundaries
/// counted from the START of the buffer, and emitted in REVERSE chunk
/// order — the stray (`len % 31`) tail chunk first, the leading full
/// chunk last.
///
/// `declared_len` is the leaf's full byte width from its alignment
/// (`AlignmentAtom::Bytes { length }`). Stored atoms are normalised
/// (trailing zero bytes stripped by upstream `ValueAtom::normalize`),
/// and because `[u8]::field_repr` packs from the END, the stripped
/// trailing bytes occupy the FIRST repr positions — so the missing
/// `ceil(declared_len/31) - ceil(len/31)` chunks are re-emitted here as
/// leading zero `Fr`s (same rule as upstream
/// `ValueAtom::field_repr_unchecked` for `Bytes`).
fn push_atom_byte_chunks(
    bytes: &[u8],
    declared_len: usize,
    atom_index: usize,
    out: &mut Vec<Fr>,
) -> Result<(), CompactError> {
    if bytes.len() > declared_len {
        return Err(CompactError::AssertionFailed(format!(
            "decode_via_field_repr[{atom_index}]: atom carries {} bytes but its \
             alignment declares {declared_len}",
            bytes.len()
        )));
    }
    let total_chunks = declared_len.div_ceil(FR_BYTES_STORED);
    let present_chunks = bytes.len().div_ceil(FR_BYTES_STORED);
    out.resize(out.len() + (total_chunks - present_chunks), Fr::default());
    let mut chunks: Vec<Fr> = Vec::with_capacity(present_chunks);
    for chunk in bytes.chunks(FR_BYTES_STORED) {
        let fr = Fr::from_le_bytes(chunk).ok_or_else(|| {
            CompactError::AssertionFailed(format!(
                "decode_via_field_repr[{atom_index}]: byte chunk does not fit in Fr"
            ))
        })?;
        chunks.push(fr);
    }
    out.extend(chunks.into_iter().rev());
    Ok(())
}

/// Expand a single (alignment atom, value atom) pair into the `Fr`s the
/// leaf occupies in this runtime's field-repr convention:
///
/// - `Field` — one `Fr`, via `Fr::try_from(&ValueAtom)` (inverse of the
///   upstream `From<Fr> for ValueAtom` encoding).
/// - `Bytes { length }` — `ceil(length/31)` `Fr`s of 31-byte chunks
///   (matches upstream `[u8; N]::field_repr` / `[u8; 32]::from_field_repr`
///   and the integer impls: an integer atom is <= 16 bytes, one chunk).
/// - `Compress` — a variable-length byte leaf (`Opaque<"string">` /
///   `Vec<u8>`). This runtime's `OpaqueString`/`Vec<u8>` `FieldRepr`
///   packs the RAW bytes in 31-byte chunks (not upstream's
///   transient-commit hash, which is not invertible), so the decode side
///   expands the atom the same way: `ceil(n/31)` `Fr`s for an n-byte
///   atom, and NO `Fr`s at all for the empty value (`[u8]::field_repr`
///   of `[]` emits nothing — `OpaqueString::FIELD_SIZE == 0` relies on
///   exactly this for empty-string leaves).
fn expand_atom(
    align: &AlignmentAtom,
    atom: &ValueAtom,
    atom_index: usize,
    out: &mut Vec<Fr>,
) -> Result<(), CompactError> {
    match align {
        AlignmentAtom::Field => {
            let fr = Fr::try_from(atom).map_err(|e| {
                CompactError::AssertionFailed(format!("decode_via_field_repr[{atom_index}]: {e:?}"))
            })?;
            out.push(fr);
        }
        AlignmentAtom::Bytes { length } => {
            push_atom_byte_chunks(&atom.0, *length as usize, atom_index, out)?;
        }
        AlignmentAtom::Compress => {
            push_atom_byte_chunks(&atom.0, atom.0.len(), atom_index, out)?;
        }
    }
    Ok(())
}

/// Walk alignment segments in lockstep with the value's atoms, expanding
/// each leaf via [`expand_atom`]. `AlignmentSegment::Option` mirrors
/// upstream `Value::repr_traverse`: a 2-byte discriminant atom selects
/// the variant alignment, and the stream is padded with zero `Fr`s to
/// the widest variant's `field_len` (note upstream `field_len` counts a
/// `Compress` leaf as one hash `Fr`; the Compact codegen never nests
/// variable-length leaves inside `Option` segments — `Maybe<T>` lowers
/// to a plain struct — so the two conventions cannot disagree here).
fn expand_segments(
    segments: &[AlignmentSegment],
    atoms: &mut &[ValueAtom],
    consumed: &mut usize,
    out: &mut Vec<Fr>,
) -> Result<(), CompactError> {
    let next_atom =
        |atoms: &mut &[ValueAtom], consumed: &mut usize| -> Result<ValueAtom, CompactError> {
            let atom = atoms.first().cloned().ok_or_else(|| {
                CompactError::AssertionFailed(format!(
                    "decode_via_field_repr: alignment expects more atoms than the \
                 value carries ({} consumed)",
                    *consumed
                ))
            })?;
            *atoms = &atoms[1..];
            *consumed += 1;
            Ok(atom)
        };
    for segment in segments {
        match segment {
            AlignmentSegment::Atom(align) => {
                let atom = next_atom(atoms, consumed)?;
                expand_atom(align, &atom, *consumed - 1, out)?;
            }
            AlignmentSegment::Option(options) => {
                let atom = next_atom(atoms, consumed)?;
                let discriminant = u16::try_from(&atom).map_err(|e| {
                    CompactError::AssertionFailed(format!(
                        "decode_via_field_repr[{}]: option discriminant: {e:?}",
                        *consumed - 1
                    ))
                })? as usize;
                expand_atom(
                    &AlignmentAtom::Bytes { length: 2 },
                    &atom,
                    *consumed - 1,
                    out,
                )?;
                let choice = options.get(discriminant).ok_or_else(|| {
                    CompactError::AssertionFailed(format!(
                        "decode_via_field_repr[{}]: option discriminant {discriminant} \
                         out of range ({} variants)",
                        *consumed - 1,
                        options.len()
                    ))
                })?;
                expand_segments(&choice.0, atoms, consumed, out)?;
                let padding = options
                    .iter()
                    .map(AlignmentExt::field_len)
                    .max()
                    .unwrap_or(0)
                    - choice.field_len();
                out.resize(out.len() + padding, Fr::default());
            }
        }
    }
    Ok(())
}

/// Decode an `AlignedValue` into a user type `T: FromFieldRepr` by
/// expanding the value's atoms into the `Fr` stream `T::field_repr`
/// would have produced, then feeding that slice into
/// `T::from_field_repr`. Used by the codegen for tenum ledger reads
/// (e.g. election's `PublicState`), `ContractAddress` reads
/// (`kernel.self()` / `ledger().id()`), and struct-typed cell / map
/// reads (e.g. did-05's `VerificationMethod` lookups).
///
/// Cells are ALIGNMENT-encoded — one atom per leaf value — while
/// `from_field_repr` consumes the field-repr layout, where a single
/// leaf may span multiple `Fr`s (a 32-byte address atom is TWO `Fr`s:
/// a 1-byte stray chunk plus a 31-byte chunk). Converting atoms to `Fr`s
/// 1:1 would therefore fail on any leaf wider than 31 bytes, and on any
/// multi-leaf struct containing one. This walks `av.alignment` to expand
/// each atom into exactly the chunks its leaf occupies (see `expand_atom`
/// for the per-alignment rules).
///
/// For fixed-size targets (`T::FIELD_SIZE > 0`) the expanded stream
/// must have exactly `T::FIELD_SIZE` elements. A longer stream means
/// the value contains a non-empty variable-length leaf (e.g. a
/// non-empty `Opaque<"string">` struct field): the generated
/// `from_field_repr` slices such fields at `OpaqueString::FIELD_SIZE
/// == 0` and would silently mis-slice every following field, so this
/// fails loudly instead — variable-length struct leaves round-trip
/// only while empty (tracked as a codegen follow-up).
///
/// Returns `Err(AssertionFailed)` on atom/alignment mismatch, on the
/// size check above, or if `T::from_field_repr` rejects the stream
/// (e.g. unknown enum discriminant).
pub fn decode_via_field_repr<T: FromFieldRepr>(av: &AlignedValue) -> Result<T, CompactError> {
    let mut frs: Vec<Fr> = Vec::with_capacity(av.value.0.len());
    let mut atoms: &[ValueAtom] = &av.value.0;
    let mut consumed = 0usize;
    expand_segments(&av.alignment.0, &mut atoms, &mut consumed, &mut frs)?;
    if !atoms.is_empty() {
        return Err(CompactError::AssertionFailed(format!(
            "decode_via_field_repr: value carries {} atoms but its alignment \
             describes only {consumed}",
            av.value.0.len()
        )));
    }
    if T::FIELD_SIZE > 0 && frs.len() != T::FIELD_SIZE {
        return Err(CompactError::AssertionFailed(format!(
            "decode_via_field_repr: expanded {} field elements but the target \
             type expects {} — a non-empty variable-length leaf (e.g. a \
             non-empty string field) cannot round-trip through from_field_repr",
            frs.len(),
            T::FIELD_SIZE
        )));
    }
    T::from_field_repr(&frs).ok_or_else(|| {
        CompactError::AssertionFailed("decode_via_field_repr: from_field_repr returned None".into())
    })
}
#[cfg(test)]
mod tests {
    use super::super::{decode_fr, decode_jubjub_point};
    use super::*;
    use crate::std_lib::OpaqueString;
    use crate::{
        new_cell, Aligned, AlignedValue, Alignment, ContractAddress, DefaultDB, StateValue, Value,
    };
    use midnight_base_crypto::hash::HashOutput;

    /// The invariant under test: for every `T` generated code stores in a
    /// cell, `decode_via_field_repr::<T>` must invert `new_cell(T)`'s
    /// `AlignedValue`.
    fn cell_av<T: Into<AlignedValue>>(v: T) -> AlignedValue {
        match new_cell::<DefaultDB, _>(v) {
            StateValue::Cell(ref c) => (**c).clone(),
            ref other => panic!("new_cell did not build a Cell: {other:?}"),
        }
    }

    #[test]
    fn decode_fr_roundtrips_via_aligned_value() {
        // Encode an Fr → AlignedValue and recover it via decode_fr.
        let original = Fr::from(123456789u64);
        let av: AlignedValue = original.into();
        let decoded = decode_fr(&av).expect("decode_fr should succeed");
        assert_eq!(decoded, original);
    }

    #[test]
    fn via_field_repr_roundtrips_u64() {
        for v in [0u64, 1, 0xDEAD_BEEF, u64::MAX] {
            let got = decode_via_field_repr::<u64>(&cell_av(v)).expect("u64 decode");
            assert_eq!(got, v);
        }
    }

    #[test]
    fn via_field_repr_roundtrips_small_scalars() {
        assert_eq!(
            decode_via_field_repr::<u8>(&cell_av(200u8)).expect("u8"),
            200u8
        );
        assert_eq!(
            decode_via_field_repr::<u32>(&cell_av(70_000u32)).expect("u32"),
            70_000u32
        );
        assert!(decode_via_field_repr::<bool>(&cell_av(true)).expect("bool"));
        assert!(!decode_via_field_repr::<bool>(&cell_av(false)).expect("bool"));
    }

    #[test]
    fn via_field_repr_roundtrips_fr() {
        let v = Fr::from(987654321u64);
        assert_eq!(decode_via_field_repr::<Fr>(&cell_av(v)).expect("Fr"), v);
    }

    /// The case that makes the expansion necessary: a `ContractAddress`
    /// cell is ONE 32-byte atom, but `[u8; 32]`'s field representation is TWO
    /// `Fr`s (a 1-byte stray chunk plus a 31-byte chunk). A 1:1 atom-to-`Fr`
    /// decode can never return `Ok` here, and this is the shape behind every
    /// `ledger().id()` / `kernel.self()` read.
    #[test]
    fn via_field_repr_roundtrips_contract_address() {
        let mut bytes = [0u8; 32];
        for (i, b) in bytes.iter_mut().enumerate() {
            *b = (i as u8) + 1; // 1..=32, nonzero last byte
        }
        for addr in [
            ContractAddress(HashOutput(bytes)),
            // All-zero address: the atom normalises to ZERO bytes and the
            // decode must re-pad from the declared Bytes{32} alignment.
            ContractAddress::default(),
            // Trailing-zero tail: atom normalises to a single byte.
            ContractAddress(HashOutput({
                let mut b = [0u8; 32];
                b[0] = 7;
                b
            })),
        ] {
            let got =
                decode_via_field_repr::<ContractAddress>(&cell_av(addr)).expect("address decode");
            assert_eq!(got, addr);
        }
    }

    #[test]
    fn via_field_repr_roundtrips_bytes32() {
        let mut bytes = [0u8; 32];
        bytes[0] = 0xAA;
        bytes[31] = 0xBB;
        let got = decode_via_field_repr::<[u8; 32]>(&cell_av(bytes)).expect("bytes32 decode");
        assert_eq!(got, bytes);
    }

    /// Mimics a codegen'd tenum: `Aligned` = u8, `Value` = discriminant
    /// byte, `FromFieldRepr` via u8. Variant 0's atom normalises to the
    /// EMPTY atom — the decode must still emit the one zero Fr the
    /// `Bytes{1}` alignment declares.
    #[derive(Clone, Copy, Debug, PartialEq, Eq)]
    #[repr(u8)]
    enum TestEnum {
        A = 0,
        B = 1,
        C = 2,
    }
    impl Aligned for TestEnum {
        fn alignment() -> Alignment {
            u8::alignment()
        }
    }
    impl FromFieldRepr for TestEnum {
        const FIELD_SIZE: usize = 1;
        fn from_field_repr(r: &[Fr]) -> Option<Self> {
            match u8::from_field_repr(r)? {
                0 => Some(Self::A),
                1 => Some(Self::B),
                2 => Some(Self::C),
                _ => None,
            }
        }
    }
    impl From<TestEnum> for Value {
        fn from(v: TestEnum) -> Value {
            Value::from(v as u8)
        }
    }

    #[test]
    fn via_field_repr_roundtrips_plain_enum() {
        for v in [TestEnum::A, TestEnum::B, TestEnum::C] {
            let got = decode_via_field_repr::<TestEnum>(&cell_av(v)).expect("enum decode");
            assert_eq!(got, v);
        }
    }

    #[test]
    fn via_field_repr_roundtrips_opaque_string() {
        for s in [
            "",                                            // empty: ZERO Frs
            "y",                                           // 1 byte
            "hello",                                       // < 31 bytes: one chunk
            "0123456789012345678901234567890",             // exactly 31
            "did:midnight:0123456789abcdef0123456789abcd", // > 31: two chunks
        ] {
            let v = OpaqueString::from(s);
            let got =
                decode_via_field_repr::<OpaqueString>(&cell_av(v.clone())).expect("string decode");
            assert_eq!(got, v, "string {s:?} must round-trip");
        }
    }

    /// Mimics a codegen'd struct with a 32-byte leaf: `{ addr: Bytes<32>,
    /// tag: Uint<8> }`. The cell is TWO atoms; the field-repr is THREE
    /// `Fr`s (two for the address plus one for the tag) — the arity mismatch
    /// that a 1:1 decode gets wrong for every struct with a wide leaf.
    #[derive(Clone, Debug, PartialEq, Eq)]
    struct AddrTag {
        addr: [u8; 32],
        tag: u8,
    }
    impl Aligned for AddrTag {
        fn alignment() -> Alignment {
            Alignment::concat([&<[u8; 32]>::alignment(), &u8::alignment()])
        }
    }
    impl FromFieldRepr for AddrTag {
        const FIELD_SIZE: usize =
            <[u8; 32] as FromFieldRepr>::FIELD_SIZE + <u8 as FromFieldRepr>::FIELD_SIZE;
        fn from_field_repr(r: &[Fr]) -> Option<Self> {
            if r.len() < Self::FIELD_SIZE {
                return None;
            }
            let n = <[u8; 32] as FromFieldRepr>::FIELD_SIZE;
            let addr = <[u8; 32] as FromFieldRepr>::from_field_repr(&r[..n])?;
            let tag = u8::from_field_repr(&r[n..n + 1])?;
            Some(AddrTag { addr, tag })
        }
    }
    impl From<AddrTag> for Value {
        fn from(s: AddrTag) -> Value {
            Value::concat([&Value::from(s.addr), &Value::from(s.tag)])
        }
    }

    #[test]
    fn via_field_repr_roundtrips_bytes32_bearing_struct() {
        let mut addr = [0u8; 32];
        addr[..4].copy_from_slice(&[9, 8, 7, 6]); // trailing zeros: normalisation edge
        let v = AddrTag { addr, tag: 42 };
        let got = decode_via_field_repr::<AddrTag>(&cell_av(v.clone())).expect("struct decode");
        assert_eq!(got, v);
    }

    /// Mimics a codegen'd struct with string leaves AFTER scalar leaves
    /// (PublicKeyJwk shape: `{ kty, crv, x: Opaque<"string">,
    /// y: Opaque<"string"> }`). Empty string leaves occupy ZERO Frs —
    /// matching `OpaqueString::FIELD_SIZE == 0` — so the struct
    /// round-trips exactly.
    #[derive(Clone, Debug, PartialEq, Eq)]
    struct JwkShape {
        kty: u8,
        crv: u8,
        x: OpaqueString,
        y: OpaqueString,
    }
    impl Aligned for JwkShape {
        fn alignment() -> Alignment {
            Alignment::concat([
                &u8::alignment(),
                &u8::alignment(),
                &OpaqueString::alignment(),
                &OpaqueString::alignment(),
            ])
        }
    }
    impl FromFieldRepr for JwkShape {
        const FIELD_SIZE: usize = <u8 as FromFieldRepr>::FIELD_SIZE
            + <u8 as FromFieldRepr>::FIELD_SIZE
            + <OpaqueString as FromFieldRepr>::FIELD_SIZE
            + <OpaqueString as FromFieldRepr>::FIELD_SIZE;
        fn from_field_repr(r: &[Fr]) -> Option<Self> {
            if r.len() < Self::FIELD_SIZE {
                return None;
            }
            // Same static-offset slicing the codegen emits.
            let mut off = 0usize;
            let kty = u8::from_field_repr(&r[off..off + 1])?;
            off += 1;
            let crv = u8::from_field_repr(&r[off..off + 1])?;
            off += 1;
            let x = OpaqueString::from_field_repr(&r[off..off])?;
            let y = OpaqueString::from_field_repr(&r[off..off])?;
            Some(JwkShape { kty, crv, x, y })
        }
    }
    impl From<JwkShape> for Value {
        fn from(s: JwkShape) -> Value {
            Value::concat([
                &Value::from(s.kty),
                &Value::from(s.crv),
                &Value::from(s.x),
                &Value::from(s.y),
            ])
        }
    }

    #[test]
    fn via_field_repr_roundtrips_multi_leaf_struct_with_empty_string_leaves() {
        let v = JwkShape {
            kty: 1,
            crv: 3,
            x: OpaqueString::from(""),
            y: OpaqueString::from(""), // did-05's JWK y="" case
        };
        let got = decode_via_field_repr::<JwkShape>(&cell_av(v.clone())).expect("struct decode");
        assert_eq!(got, v);
    }

    /// KNOWN LIMITATION (see decode_via_field_repr docs): a NON-empty
    /// variable-length leaf inside a fixed-slicing struct cannot
    /// round-trip — `OpaqueString::FIELD_SIZE == 0` gives the generated
    /// `from_field_repr` no slot to carry the bytes. The decode must
    /// fail LOUDLY (size check), never silently mis-slice or drop data.
    #[test]
    fn via_field_repr_rejects_struct_with_nonempty_string_leaf() {
        let v = JwkShape {
            kty: 1,
            crv: 3,
            x: OpaqueString::from("nonempty"),
            y: OpaqueString::from(""),
        };
        let err = decode_via_field_repr::<JwkShape>(&cell_av(v)).expect_err("must fail loudly");
        let msg = format!("{err:?}");
        assert!(
            msg.contains("variable-length leaf"),
            "expected the loud size-check error, got: {msg}"
        );
    }

    #[test]
    fn via_field_repr_roundtrips_tuple() {
        let v = (7u64, true);
        let got = decode_via_field_repr::<(u64, bool)>(&cell_av(v)).expect("tuple decode");
        assert_eq!(got, v);
    }

    #[test]
    fn decode_jubjub_point_roundtrips_via_cell() {
        let p = crate::hash_to_curve(Fr::from(5u64));
        let got = decode_jubjub_point(&cell_av(p)).expect("jubjub decode");
        assert_eq!(got, p);
    }

    // ---- agreement with upstream's own expansion --------------------------

    /// What upstream produces for the same aligned value, via
    /// `ValueReprAlignedValue`'s `FieldRepr` impl — the expansion the chain
    /// uses when hashing.
    fn upstream_expansion(av: &AlignedValue) -> Vec<Fr> {
        use midnight_transient_crypto::repr::FieldRepr as _;
        let mut frs: Vec<Fr> = Vec::new();
        crate::ValueReprAlignedValue(av.clone()).field_repr(&mut frs);
        frs
    }

    /// The walk in this module is not an independent invention: for every
    /// alignment it can invert, it must produce exactly what upstream's own
    /// expansion produces. Asserting that turns a reimplementation into a
    /// checked invariant — if upstream changes the packing, this fails here
    /// rather than as a wrong ledger read.
    #[test]
    fn the_walk_agrees_with_upstream_on_every_invertible_alignment() {
        fn same<T: Into<AlignedValue> + Clone + midnight_transient_crypto::repr::FieldRepr>(
            v: T,
            what: &str,
        ) {
            let mut ours: Vec<Fr> = Vec::new();
            v.clone().field_repr(&mut ours);
            assert_eq!(upstream_expansion(&cell_av(v)), ours, "{what}");
        }

        let mut bytes = [0u8; 32];
        for (i, b) in bytes.iter_mut().enumerate() {
            *b = (i as u8) + 1;
        }
        same(bytes, "Bytes<32> — one atom, two field elements");
        same(Fr::from(123_456_789u64), "Field");
        same(7u64, "Uint<64>");
        same(true, "Boolean");
    }

    /// …and the one alignment where it deliberately does not agree.
    ///
    /// Upstream expands a `Compress` leaf as `transient_commit(bytes, len)` —
    /// a one-way commitment, which is right for hashing and useless for
    /// decoding, because nothing can invert it. This module packs the bytes
    /// instead, so the value can be recovered. The divergence is the reason
    /// the walk exists at all rather than delegating wholesale.
    #[test]
    fn the_walk_deliberately_differs_from_upstream_on_compress_leaves() {
        use midnight_transient_crypto::repr::FieldRepr as _;

        let s = OpaqueString::from("hello");
        let mut ours: Vec<Fr> = Vec::new();
        s.field_repr(&mut ours);

        assert_ne!(
            upstream_expansion(&cell_av(s.clone())),
            ours,
            "if these ever agree, upstream's Compress expansion has become \
             invertible and this walk can delegate to it"
        );
        // …and ours is the one that round-trips.
        assert_eq!(
            decode_via_field_repr::<OpaqueString>(&cell_av(s.clone())).unwrap(),
            s
        );
    }
}
