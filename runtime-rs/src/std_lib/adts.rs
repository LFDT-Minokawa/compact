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
// Ledger ADT wrappers + AlignedValue decoders.
//
// Each Compact ledger ADT (Counter / Cell / Map / Set / MerkleTree / List)
// lives at runtime as a `StateValue` shape; mutating ops are lowered by
// the compiler directly to VM op programs, so the wrappers below only
// carry decoders for reading the current value back out.
//
// The width-typed decoders (`decode_u8`/`u16`/`u32`/`u64`/`u128`/`bool`/
// `fr`/`bytes`/`vector_fr`/`via_field_repr`) work on raw `AlignedValue`
// — the codegen's ledger-view emitter uses them when rendering
// `Ledger::field()` accessors.

use crate::{
    aligned_bytes, jubjub_point_from_field_repr, AlignedValue, AlignmentAtom, CompactError,
    ContractState, Fr, FromFieldRepr, JubjubPoint, StateValue, ValueAtom, DB,
};
use midnight_base_crypto::fab::AlignmentSegment;
use midnight_transient_crypto::curve::FR_BYTES_STORED;
use midnight_transient_crypto::fab::AlignmentExt;

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
/// This used to be `decode_u8(av).map(|n| n != 0)`, which turned every
/// nonzero byte into `true`. A cell holding `2` — reachable by anything
/// writing the ledger outside this crate — decoded as `true` here and threw
/// in TypeScript, which is the worse half of a divergence: contract code
/// carried on with a value the type system says is impossible instead of
/// stopping.
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
/// Mirrors `decode_vector_fr` for the integer case — Iter 7 adds this
/// so `Vector<N, Uint<64>>` ledger views can decode the gathered
/// `AlignedValue` produced by a `new_cell_array` write.
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
/// a 1-byte stray chunk plus a 31-byte chunk). The pre-A30 decoder
/// converted atoms to `Fr`s 1:1, so any leaf wider than 31 bytes (and
/// any multi-leaf struct containing one) could never decode. This
/// walks `av.alignment` to expand each atom into exactly the chunks
/// its leaf occupies (see `expand_atom` for the per-alignment rules).
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

/// Decode a `JubjubPoint` from a ledger `AlignedValue`.
///
/// `JubjubPoint` (`EmbeddedGroupAffine`) has no `FromFieldRepr` impl —
/// orphan rules forbid one downstream — so it cannot go through
/// `decode_via_field_repr`. This mirrors that decoder (AlignedValue atoms
/// → `Fr` slice) but reconstructs the point via the orphan-safe
/// `jubjub_point_from_field_repr` helper. Used by the codegen for
/// JubjubPoint-typed ledger reads (e.g. did.compact 0.5.0's
/// `controllerPublicKey` / `recoveryAuthorityPublicKey`).
pub fn decode_jubjub_point(av: &AlignedValue) -> Result<JubjubPoint, CompactError> {
    let mut frs: Vec<Fr> = Vec::with_capacity(av.value.0.len());
    for (i, atom) in av.value.0.iter().enumerate() {
        let fr = Fr::try_from(atom).map_err(|e| {
            CompactError::AssertionFailed(format!("decode_jubjub_point[{i}]: {e:?}"))
        })?;
        frs.push(fr);
    }
    jubjub_point_from_field_repr(&frs).ok_or_else(|| {
        CompactError::AssertionFailed(
            "decode_jubjub_point: jubjub_point_from_field_repr returned None".into(),
        )
    })
}

// ---------------------------------------------------------------------------
// ContractState serialisation.
// ---------------------------------------------------------------------------

/// Canonically serialise a `ContractState` to bytes via
/// `midnight_serialize::tagged_serialize` — this is the byte format the
/// TypeScript runtime's `cr.encode` produces. Use this for byte-parity
/// tests and on-chain submission.
pub fn serialize_contract_state<D: DB>(state: &ContractState<D>) -> Result<Vec<u8>, CompactError> {
    let mut buf = Vec::new();
    midnight_serialize::tagged_serialize(state, &mut buf)
        .map_err(|e| CompactError::AssertionFailed(format!("serialize_contract_state: {e}")))?;
    Ok(buf)
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::std_lib::OpaqueString;
    use crate::{new_cell, Aligned, AlignedValue, Alignment, ContractAddress, DefaultDB, Value};
    use midnight_base_crypto::hash::HashOutput;

    /// The A30 invariant under test: for every T the generated code
    /// stores in a cell, `decode_via_field_repr::<T>` must invert
    /// `new_cell(T)`'s AlignedValue.
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

    /// The A30 headline: a `ContractAddress` cell is ONE 32-byte atom,
    /// but `[u8; 32]`'s field-repr is TWO Frs (1-byte stray chunk +
    /// 31-byte chunk). The pre-A30 1:1 atom→Fr decode could never
    /// return `Ok` here (`ledger().id()` / `kernel.self()` readback).
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
    /// Frs (2 for the address + 1 for the tag) — the arity mismatch that
    /// broke every multi-Fr-leaf struct before A30.
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
}

#[cfg(test)]
mod decoder_tests {
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
    /// Every one of these would previously have been a candidate for the
    /// "emit something plausible" failure mode.
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

    /// The reviewer's probe. Byte `2` is not a Compact `Boolean`;
    /// `CompactTypeBoolean.fromValue` throws on it. It used to decode as
    /// `true` here, because the old body was `decode_u8(av).map(|n| n != 0)`.
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
