// SPDX-License-Identifier: Apache-2.0
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
