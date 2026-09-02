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
use crate::{Fr, JubjubPoint, JubjubScalar};
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

/// `ecNeg(a)` — group negation (compiler 0.33's new `ecNeg` native).
/// Upstream `EmbeddedGroupAffine` impls `Neg` through
/// `wrap_group_arith!`.
#[inline]
pub fn ec_neg(a: JubjubPoint) -> JubjubPoint {
    -a
}

/// Compact's `Field as JubjubScalar` cast: reduce a native-field value
/// (BLS12-381 scalar `Fr`) modulo the JubJub scalar order. Mirrors the
/// TS runtime's `convertNumericToJubjubScalar` (`x mod r`). Values
/// already below the embedded order round-trip unchanged.
pub fn jubjub_scalar_from_field(f: Fr) -> JubjubScalar {
    let mut wide = [0u8; 64];
    wide[..32].copy_from_slice(&f.as_le_bytes());
    JubjubScalar(midnight_transient_crypto::curve::embedded::Scalar::from_bytes_wide(&wide))
}

/// `ecMul(p, s)` — scalar multiplication. Compiler 0.33 types the
/// scalar as `JubjubScalar` (the embedded curve's scalar field,
/// upstream `EmbeddedFr`); upstream impls
/// `Mul<EmbeddedFr> for EmbeddedGroupAffine` natively.
#[inline]
pub fn ec_mul(p: JubjubPoint, s: JubjubScalar) -> JubjubPoint {
    p * s
}

/// `ecMulGenerator(s)` — `generator() * s`.
#[inline]
pub fn ec_mul_generator(s: JubjubScalar) -> JubjubPoint {
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

#[cfg(test)]
mod tests {
    use super::*;

    /// A point with a known secret, so the tests below can rely on it being
    /// on the curve without hard-coding coordinates.
    fn point(k: u64) -> JubjubPoint {
        ec_mul_generator(jubjub_scalar_from_field(Fr::from(k)))
    }

    // ---- group laws -------------------------------------------------------
    //
    // These assert algebraic identities rather than fixed coordinates. A
    // transcription error in any of the wrappers below breaks at least one of
    // them, and none of them can be satisfied by an accidentally-correct
    // constant.

    #[test]
    fn addition_is_commutative_and_the_identity_is_neutral() {
        let (p, q) = (point(3), point(5));
        assert_eq!(ec_add(p, q), ec_add(q, p));
        assert_eq!(ec_add(p, JubjubPoint::identity()), p);
    }

    #[test]
    fn negation_inverts_addition() {
        let p = point(7);
        assert_eq!(ec_add(p, ec_neg(p)), JubjubPoint::identity());
        assert!(ec_add(p, ec_neg(p)).is_identity());
    }

    /// `ec_mul` must agree with repeated addition. This is the one that would
    /// catch a scalar wired to the wrong field or a bad wide-reduction.
    #[test]
    fn scalar_multiplication_agrees_with_repeated_addition() {
        let g = JubjubPoint::generator();
        let three_g = ec_add(ec_add(g, g), g);
        assert_eq!(ec_mul(g, jubjub_scalar_from_field(Fr::from(3u64))), three_g);
        assert_eq!(
            ec_mul_generator(jubjub_scalar_from_field(Fr::from(3u64))),
            three_g
        );
    }

    #[test]
    fn multiplying_by_zero_gives_the_identity() {
        assert!(ec_mul(point(9), jubjub_scalar_from_field(Fr::from(0u64))).is_identity());
    }

    // ---- field representation --------------------------------------------

    /// The round-trip that generated code depends on for every `JubjubPoint`
    /// read out of ledger state.
    #[test]
    fn field_repr_round_trips() {
        let p = point(11);
        let mut buf: Vec<Fr> = Vec::new();
        jubjub_point_field_repr(&p, &mut buf);
        assert_eq!(buf.len(), jubjub_point_field_size(&p));
        assert_eq!(jubjub_point_from_field_repr(&buf), Some(p));
    }

    /// `(0, 0)` is not a curve point; it is the encoding the ledger uses for
    /// the identity, and decoding must honour that rather than reject it.
    #[test]
    fn all_zero_field_repr_decodes_to_the_identity() {
        let zeros = [Fr::from(0u64), Fr::from(0u64)];
        assert_eq!(
            jubjub_point_from_field_repr(&zeros),
            Some(JubjubPoint::identity())
        );
    }

    /// The identity round-trips, but note *which* encoding it writes.
    ///
    /// This curve is a twisted Edwards curve, so its neutral element has real
    /// affine coordinates — `(0, 1)`, not `(0, 0)`. That is what
    /// `field_repr` emits. Decoding is deliberately more permissive than
    /// encoding: `(0, 0)` is *also* accepted as the identity, because that is
    /// the encoding upstream's `TryFrom<&ValueSlice>` produces for an unset
    /// cell. So the two directions are not symmetric, and both inputs have to
    /// keep working — an "obvious" tidy-up that made decoding reject `(0, 0)`
    /// would break reads of never-written ledger state.
    #[test]
    fn the_identity_round_trips_as_zero_one() {
        let id = JubjubPoint::identity();
        let mut buf: Vec<Fr> = Vec::new();
        jubjub_point_field_repr(&id, &mut buf);
        assert_eq!(
            buf,
            vec![Fr::from(0u64), Fr::from(1u64)],
            "the Edwards neutral element is (0, 1)"
        );
        assert_eq!(jubjub_point_from_field_repr(&buf), Some(id));
    }

    #[test]
    fn a_short_field_repr_is_rejected_rather_than_read_past() {
        assert_eq!(jubjub_point_from_field_repr(&[Fr::from(1u64)]), None);
        assert_eq!(jubjub_point_from_field_repr(&[]), None);
    }

    #[test]
    fn a_point_not_on_the_curve_is_rejected() {
        // (1, 1) does not satisfy the Edwards equation.
        assert_eq!(
            jubjub_point_from_field_repr(&[Fr::from(1u64), Fr::from(1u64)]),
            None
        );
    }

    #[test]
    fn binary_repr_writes_the_declared_length() {
        let p = point(13);
        let mut buf: Vec<u8> = Vec::new();
        jubjub_point_binary_repr(&p, &mut buf);
        assert_eq!(buf.len(), jubjub_point_binary_len(&p));
        assert_eq!(buf.len(), JUBJUB_POINT_BINARY_LEN);
    }

    // ---- coordinate accessors --------------------------------------------

    /// `jubjub_point_x/y` are total, unlike upstream's `Option`-returning
    /// accessors, because Compact's are. The identity is where that matters.
    #[test]
    fn coordinate_accessors_are_total() {
        let p = point(17);
        assert_eq!(jubjub_point_x(p), p.x().unwrap());
        assert_eq!(jubjub_point_y(p), p.y().unwrap());

        // The identity does have coordinates on an Edwards curve: (0, 1).
        let id = JubjubPoint::identity();
        assert_eq!(jubjub_point_x(id), Fr::from(0u64));
        assert_eq!(jubjub_point_y(id), Fr::from(1u64));
    }

    #[test]
    fn construct_jubjub_point_accepts_a_real_point() {
        let p = point(19);
        assert_eq!(construct_jubjub_point(p.x().unwrap(), p.y().unwrap()), p);
    }

    #[test]
    #[should_panic(expected = "not on the embedded curve")]
    fn construct_jubjub_point_panics_off_curve() {
        construct_jubjub_point(Fr::from(1u64), Fr::from(1u64));
    }

    // ---- transient hash bridge -------------------------------------------

    #[test]
    fn degrade_and_upgrade_are_inverse_on_transient_values() {
        let f = degrade_to_transient([7u8; 32]);
        assert_eq!(degrade_to_transient(upgrade_from_transient(f)), f);
    }
}
