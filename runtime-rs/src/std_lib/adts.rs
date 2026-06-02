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
    aligned_bytes, AlignedValue, CompactError, ContractState, Fr, FromFieldRepr, StateValue, DB,
};

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

/// Decode an `AlignedValue` known to be a fixed-width unsigned integer
/// to a u128. Accepts variable-length atoms (upstream strips trailing
/// zero bytes) and zero-pads to the full target width. Internal helper
/// for the typed decoders below.
///
/// The base-crypto `ValueAtom` encoding for primitive integers is
/// little-endian with trailing zero bytes stripped via `normalize`
/// (see `midnight_base_crypto::fab::conversions`), so e.g. a u64 may
/// occupy 0..=8 bytes. We zero-pad and decode little-endian.
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

/// Decode an `AlignedValue` known to be a bool. Booleans encode as a
/// single byte (0 or 1); we accept anything via the u8 decoder and
/// coerce non-zero to true.
pub fn decode_bool(av: &AlignedValue) -> Result<bool, CompactError> {
    decode_u8(av).map(|n| n != 0)
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
/// AlignedValue produced by a `new_cell_array` write.
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

/// Decode an `AlignedValue` into a user type `T: FromFieldRepr` by
/// converting each atom in the value to `Fr` and feeding the resulting
/// slice into `T::from_field_repr`. Used by the codegen for tenum
/// ledger reads where the runtime call site expects the actual enum
/// variant (e.g. `pure_circuits::successor(state.read())` on
/// election's `PublicState`) rather than the raw u8 discriminant.
///
/// Returns `Err(AssertionFailed)` if any atom fails the
/// `Fr::try_from(&ValueAtom)` round-trip or if `T::from_field_repr`
/// rejects the resulting Fr slice (e.g. unknown enum discriminant).
pub fn decode_via_field_repr<T: FromFieldRepr>(av: &AlignedValue) -> Result<T, CompactError> {
    let mut frs: Vec<Fr> = Vec::with_capacity(av.value.0.len());
    for (i, atom) in av.value.0.iter().enumerate() {
        let fr = Fr::try_from(atom).map_err(|e| {
            CompactError::AssertionFailed(format!("decode_via_field_repr[{i}]: {e:?}"))
        })?;
        frs.push(fr);
    }
    T::from_field_repr(&frs).ok_or_else(|| {
        CompactError::AssertionFailed("decode_via_field_repr: from_field_repr returned None".into())
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
    use crate::AlignedValue;

    #[test]
    fn decode_fr_roundtrips_via_aligned_value() {
        // Encode an Fr → AlignedValue and recover it via decode_fr.
        let original = Fr::from(123456789u64);
        let av: AlignedValue = original.into();
        let decoded = decode_fr(&av).expect("decode_fr should succeed");
        assert_eq!(decoded, original);
    }
}
