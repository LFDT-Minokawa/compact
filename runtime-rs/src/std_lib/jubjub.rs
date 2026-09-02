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
// R2 — the Compact `JubjubPoint` type and the EC / transient natives.
//
// The compiler's `(rust "...")` annotations on `declare-native-entry` point
// at the free functions here. Upstream exposes the underlying primitives as
// methods on `EmbeddedGroupAffine` plus `Mul` / `Add` / `Neg` operator impls;
// the Compact natives spell them as bare functions, hence the wrappers.
//
// The type itself is this crate's own, rather than an alias for upstream's
// validated group element — see [`JubjubPoint`] for why that distinction is
// load-bearing rather than cosmetic.

use midnight_base_crypto::repr::MemWrite;
use midnight_circuits::ecc::curves::CircuitCurve;
use midnight_transient_crypto::curve::{embedded, EmbeddedGroupAffine};

use crate::base_crypto::hash::HashOutput;
use crate::transient_crypto::hash as transient_hash_mod;
use crate::{
    Aligned, Alignment, BinaryHashRepr, CompactError, FieldRepr, Fr, FromFieldRepr, JubjubScalar,
    Value, ValueAtom,
};

// ---------------------------------------------------------------------------
// The Compact `JubjubPoint` type.
// ---------------------------------------------------------------------------

/// Compact's `JubjubPoint`: a pair of field elements, and nothing more.
///
/// This mirrors the normative TypeScript runtime, where the type is literally
/// `{ x: bigint, y: bigint }` and its descriptor reads and writes two `field`
/// atoms with no validation at all:
///
/// ```ts
/// fromValue(value) {
///   const c = value.splice(0, 2);
///   return { x: valueToBigInt([c[0]]), y: valueToBigInt([c[1]]) };
/// },
/// toValue(value) {
///   return bigIntToValue(value.x).concat(bigIntToValue(value.y));
/// },
/// ```
///
/// # Why this is not an alias for a validated curve point
///
/// It used to be `pub use EmbeddedGroupAffine as JubjubPoint`, i.e. a point
/// proven to lie in the embedded curve's prime-order subgroup. That is a
/// strictly smaller set of values than Compact's type, and the gap was
/// reachable three separate ways:
///
/// * `constructJubjubPoint(1, 1)` is a value in TypeScript and was an error
///   here. The Compact builtin only packs two field elements; nothing in the
///   language or the circuit checks curve membership.
/// * A ledger cell can hold any two field elements — written by TypeScript,
///   by another implementation, or by a contract that never did curve
///   arithmetic. Decoding it here failed where TypeScript succeeds.
/// * Worse, it did not always *fail*. `EmbeddedGroupAffine::new` returns
///   `None` only for coordinates off the curve entirely; for a point that is
///   on the curve but outside the prime-order subgroup — `(1, 0)`, `(2, 3)` —
///   it panics inside `into_subgroup`. So an off-subgroup point arriving from
///   ledger state aborted the process rather than returning an error.
///
/// Validation now happens where it is actually needed: [`JubjubPoint::to_group`]
/// converts to a group element for arithmetic, and returns `None` rather than
/// panicking. Construction, decoding and the coordinate accessors do not
/// validate at all, because Compact does not.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash, PartialOrd, Ord)]
pub struct JubjubPoint {
    /// The affine `x` coordinate, as a bare field element.
    pub x: Fr,
    /// The affine `y` coordinate, as a bare field element.
    pub y: Fr,
}

impl JubjubPoint {
    /// The additive identity, `(0, 1)`.
    ///
    /// The embedded curve is a twisted Edwards curve, whose identity has a
    /// genuine affine representation — unlike a Weierstrass curve, where it is
    /// the point at infinity. `(0, 1)` satisfies the curve equation and is
    /// what `ecMulGenerator(0)` returns, which is also what Compact's
    /// `default<JubjubPoint>` evaluates to.
    #[inline]
    pub fn identity() -> Self {
        JubjubPoint {
            x: Fr::from(0u64),
            y: Fr::from(1u64),
        }
    }

    /// The curve's primary generator.
    #[inline]
    pub fn generator() -> Self {
        EmbeddedGroupAffine::generator().into()
    }

    /// Whether this is the additive identity.
    #[inline]
    pub fn is_identity(&self) -> bool {
        *self == Self::identity()
    }

    /// Convert to a validated group element, or `None` if the coordinates are
    /// not a point in the embedded curve's prime-order subgroup.
    ///
    /// This is the only place curve membership is checked, and it is
    /// deliberately total: it goes through `try_into_subgroup` rather than
    /// `EmbeddedGroupAffine::new`, which panics for a point that satisfies the
    /// curve equation but lies outside the subgroup. Anything reachable from
    /// ledger state must not be able to abort the process.
    pub fn to_group(&self) -> Option<EmbeddedGroupAffine> {
        embedded::AffineExtended::from_xy(self.x.0, self.y.0)
            .and_then(CircuitCurve::try_into_subgroup)
            .map(EmbeddedGroupAffine)
    }

    /// [`Self::to_group`], reported as a `CompactError` naming the operation
    /// that needed a real group element.
    fn require_group(&self, op: &str) -> Result<EmbeddedGroupAffine, CompactError> {
        self.to_group().ok_or_else(|| {
            CompactError::AssertionFailed(format!(
                "{op}: ({}, {}) is not a point in the embedded curve's \
                 prime-order subgroup",
                self.x, self.y
            ))
        })
    }
}

impl Default for JubjubPoint {
    /// The identity, matching Compact's `default<JubjubPoint>` — which the
    /// compiler's own test pins as equal to `ecMulGenerator(0)`.
    #[inline]
    fn default() -> Self {
        Self::identity()
    }
}

impl From<EmbeddedGroupAffine> for JubjubPoint {
    /// Total: every subgroup element has affine coordinates on this curve,
    /// the identity included.
    #[inline]
    fn from(p: EmbeddedGroupAffine) -> Self {
        JubjubPoint {
            x: p.x().unwrap_or_else(|| Fr::from(0u64)),
            y: p.y().unwrap_or_else(|| Fr::from(1u64)),
        }
    }
}

impl TryFrom<JubjubPoint> for EmbeddedGroupAffine {
    type Error = CompactError;

    #[inline]
    fn try_from(p: JubjubPoint) -> Result<Self, Self::Error> {
        p.require_group("JubjubPoint")
    }
}

impl Aligned for JubjubPoint {
    /// Two `field` atoms, matching `CompactTypeJubjubPoint.alignment()`.
    fn alignment() -> Alignment {
        Alignment::concat([&Fr::alignment(), &Fr::alignment()])
    }
}

impl FieldRepr for JubjubPoint {
    #[inline]
    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {
        writer.write(&[self.x, self.y]);
    }
    #[inline]
    fn field_size(&self) -> usize {
        JUBJUB_POINT_FIELD_SIZE
    }
}

impl FromFieldRepr for JubjubPoint {
    const FIELD_SIZE: usize = JUBJUB_POINT_FIELD_SIZE;

    /// Reads the two coordinates back verbatim.
    ///
    /// There is deliberately no `(0, 0) => identity` special case. The old
    /// implementation had one, copied from a branch in upstream's
    /// `TryFrom<&ValueSlice>` that is dead code — it is guarded by
    /// `HAS_INFINITY`, which is `false` for this curve. The effect was that a
    /// cell holding `(0, 0)` decoded as the identity `(0, 1)` here and as
    /// `{ x: 0, y: 0 }` in TypeScript: the same bytes, two different values.
    fn from_field_repr(r: &[Fr]) -> Option<Self> {
        if r.len() < JUBJUB_POINT_FIELD_SIZE {
            return None;
        }
        Some(JubjubPoint { x: r[0], y: r[1] })
    }
}

impl BinaryHashRepr for JubjubPoint {
    #[inline]
    fn binary_repr<W: MemWrite<u8>>(&self, writer: &mut W) {
        writer.write(&self.x.as_le_bytes());
        writer.write(&self.y.as_le_bytes());
    }
    #[inline]
    fn binary_len(&self) -> usize {
        JUBJUB_POINT_BINARY_LEN
    }
}

impl From<JubjubPoint> for Value {
    #[inline]
    fn from(p: JubjubPoint) -> Value {
        Value(vec![ValueAtom::from(p.x), ValueAtom::from(p.y)])
    }
}

// ---------------------------------------------------------------------------
// Representation helpers named the way the codegen calls them.
// ---------------------------------------------------------------------------
//
// These were free functions because Rust's orphan rules forbade implementing
// upstream traits on the upstream `EmbeddedGroupAffine`. Now that
// `JubjubPoint` is this crate's own type the trait impls above are the real
// implementation, and these remain only as the call shape generated code
// already uses. They are one-line delegations; prefer the traits in new code.

/// Compile-time `FIELD_SIZE` for `JubjubPoint` — two `field` atoms.
pub const JUBJUB_POINT_FIELD_SIZE: usize = 2;

/// Bytes written by `jubjub_point_binary_repr` — two 32-byte LE `Fr`
/// serialisations.
pub const JUBJUB_POINT_BINARY_LEN: usize = 64;

/// Delegates to `<JubjubPoint as FromFieldRepr>::from_field_repr`.
#[inline]
pub fn jubjub_point_from_field_repr(r: &[Fr]) -> Option<JubjubPoint> {
    <JubjubPoint as FromFieldRepr>::from_field_repr(r)
}

/// Delegates to `<JubjubPoint as FieldRepr>::field_repr`.
#[inline]
pub fn jubjub_point_field_repr<W: MemWrite<Fr>>(p: &JubjubPoint, writer: &mut W) {
    p.field_repr(writer);
}

/// Delegates to `<JubjubPoint as FieldRepr>::field_size`.
#[inline]
pub fn jubjub_point_field_size(p: &JubjubPoint) -> usize {
    p.field_size()
}

/// Delegates to `<JubjubPoint as BinaryHashRepr>::binary_repr`.
#[inline]
pub fn jubjub_point_binary_repr<W: MemWrite<u8>>(p: &JubjubPoint, writer: &mut W) {
    p.binary_repr(writer);
}

/// Delegates to `<JubjubPoint as BinaryHashRepr>::binary_len`.
#[inline]
pub fn jubjub_point_binary_len(p: &JubjubPoint) -> usize {
    p.binary_len()
}

// ---------------------------------------------------------------------------
// The Compact natives.
// ---------------------------------------------------------------------------

/// `jubjubPointX(p)` — the affine X coordinate, verbatim.
#[inline]
pub fn jubjub_point_x(p: JubjubPoint) -> Fr {
    p.x
}

/// `jubjubPointY(p)` — the affine Y coordinate, verbatim.
#[inline]
pub fn jubjub_point_y(p: JubjubPoint) -> Fr {
    p.y
}

/// `constructJubjubPoint(x, y)` — packs two field elements into a
/// `JubjubPoint`.
///
/// Total, and deliberately so. The TypeScript runtime documents the same:
///
/// ```text
/// // NOTE that it does not check that the coordinates represent a
/// // valid point on the Jubjub curve.
/// export function constructJubjubPoint(x: bigint, y: bigint): JubjubPoint {
///   return { x, y };
/// }
/// ```
///
/// Curve membership is checked by the operations that need it — [`ec_add`],
/// [`ec_mul`], [`ec_neg`] and the Schnorr verifiers — not here, because the
/// Compact builtin does not check it and neither does the circuit.
#[inline]
pub fn construct_jubjub_point(x: Fr, y: Fr) -> JubjubPoint {
    JubjubPoint { x, y }
}

/// `ecAdd(a, b)` — group addition.
///
/// Fallible because its arguments are Compact `JubjubPoint`s, which may hold
/// any two field elements. TypeScript reaches the same outcome by a different
/// route: `ocrt.ecAdd` decodes both arguments into curve points on the way
/// into WebAssembly and throws when that fails.
pub fn ec_add(a: JubjubPoint, b: JubjubPoint) -> Result<JubjubPoint, CompactError> {
    let (a, b) = (a.require_group("ecAdd")?, b.require_group("ecAdd")?);
    Ok((a + b).into())
}

/// `ecNeg(a)` — group negation. Fallible for the same reason as [`ec_add`].
pub fn ec_neg(a: JubjubPoint) -> Result<JubjubPoint, CompactError> {
    Ok((-a.require_group("ecNeg")?).into())
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

/// `ecMul(p, s)` — scalar multiplication. Fallible for the same reason as
/// [`ec_add`]; the scalar itself is always valid, having been reduced into
/// the embedded scalar field by the `as JubjubScalar` cast.
pub fn ec_mul(p: JubjubPoint, s: JubjubScalar) -> Result<JubjubPoint, CompactError> {
    Ok((p.require_group("ecMul")? * s).into())
}

/// `ecMulGenerator(s)` — `generator() * s`. Total: the generator is a curve
/// point by construction, so there is nothing here that can fail.
#[inline]
pub fn ec_mul_generator(s: JubjubScalar) -> JubjubPoint {
    (EmbeddedGroupAffine::generator() * s).into()
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
    /// in the subgroup without hard-coding coordinates.
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
        assert_eq!(ec_add(p, q).unwrap(), ec_add(q, p).unwrap());
        assert_eq!(ec_add(p, JubjubPoint::identity()).unwrap(), p);
    }

    #[test]
    fn negation_inverts_addition() {
        let p = point(7);
        let sum = ec_add(p, ec_neg(p).unwrap()).unwrap();
        assert_eq!(sum, JubjubPoint::identity());
        assert!(sum.is_identity());
    }

    /// `ec_mul` must agree with repeated addition. This is the one that would
    /// catch a scalar wired to the wrong field or a bad wide-reduction.
    #[test]
    fn scalar_multiplication_agrees_with_repeated_addition() {
        let g = JubjubPoint::generator();
        let three_g = ec_add(ec_add(g, g).unwrap(), g).unwrap();
        assert_eq!(
            ec_mul(g, jubjub_scalar_from_field(Fr::from(3u64))).unwrap(),
            three_g
        );
        assert_eq!(
            ec_mul_generator(jubjub_scalar_from_field(Fr::from(3u64))),
            three_g
        );
    }

    #[test]
    fn multiplying_by_zero_gives_the_identity() {
        assert!(ec_mul(point(9), jubjub_scalar_from_field(Fr::from(0u64)))
            .unwrap()
            .is_identity());
    }

    /// `default<JubjubPoint>` is the identity — the compiler's own test pins
    /// it as equal to `ecMulGenerator(0)`. The Schnorr identity guard compares
    /// against it, so the two must not drift apart.
    #[test]
    fn the_default_point_is_the_identity_and_equals_generator_times_zero() {
        assert!(JubjubPoint::default().is_identity());
        assert_eq!(
            JubjubPoint::default(),
            ec_mul_generator(jubjub_scalar_from_field(Fr::from(0u64)))
        );
    }

    // ---- what the type does and does not validate -------------------------

    /// The heart of the coordinate-pair change: construction is total,
    /// matching `constructJubjubPoint`, which the TypeScript runtime
    /// documents as performing no curve check.
    #[test]
    fn construction_preserves_an_arbitrary_coordinate_pair() {
        let p = construct_jubjub_point(Fr::from(1u64), Fr::from(1u64));
        assert_eq!(jubjub_point_x(p), Fr::from(1u64));
        assert_eq!(jubjub_point_y(p), Fr::from(1u64));
        assert_eq!(p.to_group(), None, "…and it is still not a curve point");
    }

    #[test]
    fn construction_round_trips_a_real_point() {
        let p = point(19);
        assert_eq!(construct_jubjub_point(p.x, p.y), p);
    }

    /// `to_group` is the one validating conversion, and it must be **total**.
    ///
    /// Upstream's `EmbeddedGroupAffine::new` is not: it returns `None` for a
    /// pair off the curve, but *panics* inside `into_subgroup` for one that
    /// satisfies the curve equation while lying outside the prime-order
    /// subgroup. `(1, 0)` and `(2, 3)` are such pairs. Since a `JubjubPoint`
    /// can come straight from a ledger cell, that panic was reachable from
    /// untrusted input — this test is the guard against reintroducing it.
    #[test]
    fn to_group_rejects_every_non_subgroup_pair_without_panicking() {
        for (x, y) in [(0u64, 0u64), (1, 0), (2, 3), (1, 1), (5, 7)] {
            let p = construct_jubjub_point(Fr::from(x), Fr::from(y));
            assert_eq!(p.to_group(), None, "({x}, {y}) must not convert");
        }
    }

    #[test]
    fn to_group_accepts_subgroup_points_including_the_identity() {
        assert!(point(23).to_group().is_some());
        assert!(JubjubPoint::identity().to_group().is_some());
        assert!(JubjubPoint::generator().to_group().is_some());
    }

    /// The arithmetic natives are where validation surfaces to the caller, as
    /// an error rather than a crash.
    #[test]
    fn arithmetic_reports_a_non_subgroup_argument_as_an_error() {
        let bad = construct_jubjub_point(Fr::from(2u64), Fr::from(3u64));
        let good = point(29);

        let err = ec_add(bad, good).expect_err("(2, 3) is not in the subgroup");
        assert!(
            err.to_string().contains("prime-order subgroup"),
            "message should say what was wrong, got: {err}"
        );
        assert!(ec_add(good, bad).is_err());
        assert!(ec_neg(bad).is_err());
        assert!(ec_mul(bad, jubjub_scalar_from_field(Fr::from(2u64))).is_err());
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

    /// Decoding preserves whatever two field elements are in the cell.
    ///
    /// This replaces a test that asserted `(0, 0)` decodes to the *identity*,
    /// on the stated belief that `(0, 0)` is "the encoding the ledger uses for
    /// the identity". It is not. `Value::from(identity)` is `(0, 1)`, and the
    /// `(0, 0) => identity` branch in upstream's `TryFrom<&ValueSlice>` is
    /// dead code — it is guarded by `HAS_INFINITY`, which is `false` for this
    /// curve. The old behaviour meant a cell holding `(0, 0)` read back as
    /// `(0, 1)` here and as `{ x: 0, y: 0 }` in TypeScript.
    #[test]
    fn decoding_preserves_the_coordinates_verbatim() {
        for (x, y) in [(0u64, 0u64), (1, 1), (2, 3), (7, 0)] {
            let decoded = jubjub_point_from_field_repr(&[Fr::from(x), Fr::from(y)]);
            assert_eq!(
                decoded,
                Some(construct_jubjub_point(Fr::from(x), Fr::from(y))),
                "({x}, {y}) must decode to itself"
            );
        }
    }

    /// The identity encodes as `(0, 1)`: this curve is a twisted Edwards
    /// curve, so its neutral element has genuine affine coordinates rather
    /// than being a point at infinity.
    #[test]
    fn the_identity_encodes_as_zero_one() {
        let id = JubjubPoint::identity();
        let mut buf: Vec<Fr> = Vec::new();
        jubjub_point_field_repr(&id, &mut buf);
        assert_eq!(buf, vec![Fr::from(0u64), Fr::from(1u64)]);
        assert_eq!(jubjub_point_from_field_repr(&buf), Some(id));
    }

    #[test]
    fn a_short_field_repr_is_rejected_rather_than_read_past() {
        assert_eq!(jubjub_point_from_field_repr(&[Fr::from(1u64)]), None);
        assert_eq!(jubjub_point_from_field_repr(&[]), None);
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
    /// accessors, because Compact's are.
    #[test]
    fn coordinate_accessors_are_total() {
        let p = point(17);
        assert_eq!(jubjub_point_x(p), p.x);
        assert_eq!(jubjub_point_y(p), p.y);

        let id = JubjubPoint::identity();
        assert_eq!(jubjub_point_x(id), Fr::from(0u64));
        assert_eq!(jubjub_point_y(id), Fr::from(1u64));
    }

    // ---- transient hash bridge -------------------------------------------

    #[test]
    fn degrade_and_upgrade_are_inverse_on_transient_values() {
        let f = degrade_to_transient([7u8; 32]);
        assert_eq!(degrade_to_transient(upgrade_from_transient(f)), f);
    }
}
