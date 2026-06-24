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
// R2 — native function wrappers (Jubjub / EC + transient bridges).
//
// Thin shims over upstream symbols that the compiler's `(rust "...")`
// annotations on `declare-native-entry` point at. Upstream exposes
// Jubjub primitives as methods on `EmbeddedGroupAffine` (re-exported
// as `JubjubPoint`) plus `Mul<Fr>` / `+` operator impls; the Compact
// natives spell them as bare functions, hence the wrappers.

use crate::base_crypto::hash::HashOutput;
use crate::transient_crypto::hash as transient_hash_mod;
use crate::{Fr, JubjubPoint};
use midnight_base_crypto::repr::MemWrite;

// R5a (2026-06-24): orphan-safe helpers for codegen of struct fields
// whose type is `JubjubPoint` (alias for upstream
// `midnight_transient_crypto::curve::EmbeddedGroupAffine`).
//
// Upstream provides `Aligned` for EmbeddedGroupAffine (two field atoms
// — x and y) plus `From<EmbeddedGroupAffine> for Value` /
// `TryFrom<&ValueSlice> for EmbeddedGroupAffine`, but no `FieldRepr`,
// `FromFieldRepr`, or `BinaryHashRepr` impl. Rust's orphan rules forbid
// us from impl'ing them downstream (both type and trait are upstream).
//
// To sidestep the rule, codegen routes `JubjubPoint`-typed struct
// fields through the free functions below — mirroring the
// `field_repr.rs` pattern used for `[u8; N]` (N != 32) and `Vec<u8>`.
//
// Layout matches upstream's `From<EmbeddedGroupAffine> for Value` /
// `TryFrom<&ValueSlice> for EmbeddedGroupAffine`:
//   - field repr: two Fr values (x, y); identity → (0, 0)
//   - binary repr: two 32-byte LE Fr serialisations (64 bytes total)

/// Compile-time `FIELD_SIZE` for `JubjubPoint` (matches the two-atom
/// `Aligned::alignment()` upstream provides).
pub const JUBJUB_POINT_FIELD_SIZE: usize = 2;

/// Bytes written by `jubjub_point_binary_repr` per call — two 32-byte
/// LE Fr serialisations.
pub const JUBJUB_POINT_BINARY_LEN: usize = 64;

/// `<JubjubPoint as FromFieldRepr>::from_field_repr` replacement.
/// Reads two `Fr` values and reconstructs the curve point via
/// `EmbeddedGroupAffine::new(x, y)`. The `(0, 0)` reading maps to
/// identity (matches upstream's `TryFrom<&ValueSlice>` semantics).
pub fn jubjub_point_from_field_repr(r: &[Fr]) -> Option<JubjubPoint> {
    if r.len() < JUBJUB_POINT_FIELD_SIZE {
        return None;
    }
    let x = r[0];
    let y = r[1];
    if x == Fr::from(0u64) && y == Fr::from(0u64) {
        Some(JubjubPoint::identity())
    } else {
        JubjubPoint::new(x, y)
    }
}

/// `<JubjubPoint as FieldRepr>::field_repr` replacement.
/// Writes `x()` then `y()` (or `0` for the identity element's missing
/// coordinates).
pub fn jubjub_point_field_repr<W: MemWrite<Fr>>(p: &JubjubPoint, writer: &mut W) {
    let x = p.x().unwrap_or_else(|| Fr::from(0u64));
    let y = p.y().unwrap_or_else(|| Fr::from(0u64));
    writer.write(&[x]);
    writer.write(&[y]);
}

/// `<JubjubPoint as FieldRepr>::field_size` replacement.
#[inline]
pub fn jubjub_point_field_size(_p: &JubjubPoint) -> usize {
    JUBJUB_POINT_FIELD_SIZE
}

/// `<JubjubPoint as BinaryHashRepr>::binary_repr` replacement.
/// Writes the two coordinate `Fr` values' little-endian byte encodings
/// back to back (`FR_BYTES * 2 = 64`).
pub fn jubjub_point_binary_repr<W: MemWrite<u8>>(p: &JubjubPoint, writer: &mut W) {
    let x = p.x().unwrap_or_else(|| Fr::from(0u64));
    let y = p.y().unwrap_or_else(|| Fr::from(0u64));
    writer.write(&x.as_le_bytes());
    writer.write(&y.as_le_bytes());
}

/// `<JubjubPoint as BinaryHashRepr>::binary_len` replacement.
#[inline]
pub fn jubjub_point_binary_len(_p: &JubjubPoint) -> usize {
    JUBJUB_POINT_BINARY_LEN
}

/// `jubjubPointX(p)` — affine X coordinate, or zero if `p` is
/// identity. The Compact native returns `Field`, treating identity as
/// the zero coordinate (matches the TS `__compactRuntime.jubjubPointX`
/// behavior).
#[inline]
pub fn jubjub_point_x(p: JubjubPoint) -> Fr {
    p.x().unwrap_or(Fr::from(0u64))
}

/// `jubjubPointY(p)` — affine Y coordinate, or zero if `p` is identity.
#[inline]
pub fn jubjub_point_y(p: JubjubPoint) -> Fr {
    p.y().unwrap_or(Fr::from(0u64))
}

/// `ecAdd(a, b)` — group addition. Upstream `EmbeddedGroupAffine`
/// impls `Add` through the `wrap_group_arith!` macro, so we just defer
/// to `+`.
#[inline]
pub fn ec_add(a: JubjubPoint, b: JubjubPoint) -> JubjubPoint {
    a + b
}

/// `ecMul(p, s)` — scalar multiplication. Upstream impls
/// `Mul<Fr> for EmbeddedGroupAffine`.
#[inline]
pub fn ec_mul(p: JubjubPoint, s: Fr) -> JubjubPoint {
    p * s
}

/// `ecMulGenerator(s)` — `generator() * s`.
#[inline]
pub fn ec_mul_generator(s: Fr) -> JubjubPoint {
    JubjubPoint::generator() * s
}

/// `constructJubjubPoint(x, y)` — checked affine constructor. Panics
/// if `(x, y)` isn't on the curve, mirroring the TS runtime's
/// assertion-style failure mode.
#[inline]
pub fn construct_jubjub_point(x: Fr, y: Fr) -> JubjubPoint {
    JubjubPoint::new(x, y).expect("constructJubjubPoint: (x, y) not on the embedded curve")
}

/// `degradeToTransient(b)` — `(Bytes 32) -> Field`. Wraps the upstream
/// `transient_crypto::hash::degrade_to_transient(HashOutput) -> Fr`.
#[inline]
pub fn degrade_to_transient(b: [u8; 32]) -> Fr {
    transient_hash_mod::degrade_to_transient(HashOutput(b))
}

/// `upgradeFromTransient(f)` — `Field -> (Bytes 32)`. Wraps the
/// upstream `transient_crypto::hash::upgrade_from_transient(Fr) ->
/// HashOutput`.
#[inline]
pub fn upgrade_from_transient(f: Fr) -> [u8; 32] {
    transient_hash_mod::upgrade_from_transient(f).0
}
