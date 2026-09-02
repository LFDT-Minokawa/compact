// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//! Module-1 (Schnorr) — Schnorr-on-Jubjub signature verification
//! exposed in a shape the compact codegen can call directly.
//!
//! This module used to vendor ~50 LOC of verifier because the pinned
//! `midnight-transient-crypto 2.1.0` did not expose a `schnorr` module.
//! On the ledger-9 line it does — this crate resolves transient-crypto
//! **3.0.0** — so [`verify`] now delegates upstream instead.
//!
//! Two things did *not* move upstream, and the reasons are worth keeping
//! next to the code:
//!
//! - **The signature type stays local.** Ours declares `response: Fr`
//!   because Compact declares that field `Field`; upstream's declares
//!   `response: EmbeddedFr`. Codegen constructs these values by field
//!   name and type, so the layout has to match the Compact struct. The
//!   reduction between the two is [`fr_to_embedded_fr`], applied at the
//!   call boundary in [`verify`].
//!
//! - **[`jubjub_schnorr_verify`] keeps its own body**, and must. It
//!   mirrors the 0.33 standard library's `jubjubSchnorrVerify` circuit,
//!   which performs **no up-front identity rejection** — identity points
//!   simply contribute zero coordinates to the hash. Upstream's `verify`
//!   *does* reject identity. Routing that function through upstream would
//!   make the Rust path refuse signatures the stdlib circuit accepts,
//!   which is a new divergence rather than a fix. So the challenge
//!   machinery below stays, serving that one caller.
//!
//! [`schnorr_verify_jubjub`] is the circuit-shaped wrapper codegen calls:
//! it takes a `CircuitContext`, threads it through a no-op
//! `query_for_verify`, and surfaces rejection as
//! `CompactError::AssertionFailed`.

use midnight_transient_crypto::curve::{EmbeddedFr, Fr};
use midnight_transient_crypto::hash::transient_hash;

use crate::{
    query_for_verify, CircuitContext, CircuitResults, CompactError, DefaultDB, JubjubPoint,
    OpProgramVerify,
};

/// A Schnorr signature over the embedded curve. Layout matches the
/// Compact-side `Schnorr.SchnorrSignature` struct exactly
/// (`announcement: JubjubPoint`, `response: Field`) so the codegen's
/// generated user-struct lines up by name + field types and the
/// `schnorr_verify_jubjub` wrapper accepts both. The `response` field
/// is stored as the outer scalar `Fr` (matching Compact's `Field`); the
/// off-circuit verifier reduces it to `EmbeddedFr` modulo the Jubjub
/// scalar order before the group-arithmetic check (`fr_to_embedded_fr`).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SchnorrSignature {
    /// The announcement point, `R = k * G`.
    pub announcement: JubjubPoint,
    /// The response scalar, encoded as an outer-curve `Fr`. The
    /// off-circuit verifier reduces this modulo the Jubjub scalar
    /// field order before use.
    pub response: Fr,
}

/// Hash `(ann_x, ann_y, pk_x, pk_y, ...msg)` with the Poseidon-based
/// transient hash and reduce modulo the Jubjub scalar field order.
fn compute_challenge(ann_x: Fr, ann_y: Fr, pk_x: Fr, pk_y: Fr, msg: &[Fr]) -> EmbeddedFr {
    let mut hash_input = Vec::with_capacity(4 + msg.len());
    hash_input.push(ann_x);
    hash_input.push(ann_y);
    hash_input.push(pk_x);
    hash_input.push(pk_y);
    hash_input.extend_from_slice(msg);
    let hash = transient_hash(&hash_input);
    fr_to_embedded_fr(hash)
}

/// Reduce a BLS12-381 scalar `Fr` modulo the Jubjub scalar field order,
/// i.e. `x mod r_jubjub`. Single implementation lives in
/// [`crate::std_lib::jubjub_scalar_from_field`], which is also what
/// Compact's `as JubjubScalar` cast lowers to.
///
/// # Warning: this is NOT the vendored circuit's challenge reduction
///
/// The doc comment this replaced claimed the function "mirrors what the
/// matching circuit does via the `getSchnorrReduction` witness". It does
/// not. The vendored `examples/did-05/jubjub-schnorr/src/schnorr.compact`
/// derives its challenge by **248-bit truncation** — `cFull = q·2^248 +
/// cTruncated` with `c = cTruncated`, i.e. `cFull mod 2^248` — whereas
/// this is `cFull mod r_jubjub`. Since `2^248 < r_jubjub` the two differ
/// whenever `cFull >= 2^248`, which is essentially always, so
/// [`schnorr_verify_jubjub`] and that circuit disagree. No test currently
/// covers the gap (`did-05`'s tests are constructor-scaffold/readback
/// only). The 0.33 standard library's `jubjubSchnorrVerify` uses the
/// mod-`r` form, so this function matches the STDLIB semantics and a
/// coordinated migration off the vendored module is the eventual fix.
/// Tracked on MediaNoxLabs/compact#17.
fn fr_to_embedded_fr(fr: Fr) -> EmbeddedFr {
    crate::std_lib::jubjub_scalar_from_field(fr)
}

/// Off-circuit Schnorr verifier. Returns `true` iff the signature is
/// valid for `(pk, msg)`. Identity public-key / announcement are
/// rejected, matching the circuit's identity guards.
///
/// This delegates to `midnight_transient_crypto::schnorr::verify` rather
/// than repeating it. The module header used to explain that the pinned
/// `midnight-transient-crypto 2.1.0` did not expose a `schnorr` module,
/// so ~50 lines of verifier were vendored here until it did. On the
/// ledger-9 line it does: this crate resolves transient-crypto **3.0.0**,
/// which exports `pub mod schnorr` with the same challenge derivation
/// (Poseidon over `[ann_x, ann_y, pk_x, pk_y, ..msg]`, reduced mod
/// `r_jubjub`), the same verification equation, and the same up-front
/// identity rejection this function documents.
///
/// So the stated precondition for deleting the vendored copy is met, and
/// the security-critical path is now upstream's implementation rather
/// than our transcription of it — which is the point. A copy that agrees
/// today is a copy that can silently stop agreeing.
///
/// The signature type still cannot be a re-export: ours carries
/// `response: Fr` because Compact declares that field `Field`, while
/// upstream's carries `response: EmbeddedFr`. The reduction between them
/// is exactly `fr_to_embedded_fr`, applied here at the boundary.
pub fn verify(pk: JubjubPoint, msg: &[Fr], sig: &SchnorrSignature) -> bool {
    midnight_transient_crypto::schnorr::verify(
        pk,
        msg,
        &midnight_transient_crypto::schnorr::SchnorrSignature {
            announcement: sig.announcement,
            response: fr_to_embedded_fr(sig.response),
        },
    )
}

/// A Schnorr signature over the JubJub curve — the Rust mirror of the
/// 0.33 standard library's `JubjubSchnorrSignature` struct
/// (`announcement: JubjubPoint`, `response: Field`). Field layout and
/// order match the Compact struct exactly so codegen-constructed
/// values line up; the codegen's stdlib-struct mapping routes the
/// Compact type here instead of emitting its own declaration.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct JubjubSchnorrSignature {
    /// The announcement point, `R = k * G`.
    pub announcement: JubjubPoint,
    /// The response scalar, encoded as an outer-curve `Fr` (Compact
    /// `Field`). Reduced modulo the JubJub scalar order before use,
    /// matching the stdlib circuit's `response as JubjubScalar` cast.
    pub response: Fr,
}

/// Pure-circuit-shaped verifier used by the compact codegen to replace
/// calls to the 0.33 standard library's `jubjubSchnorrVerify<#N>`
/// circuit. Mirrors the stdlib body exactly:
///
/// - challenge `c = transientHash(annX, annY, pkX, pkY, msg...)`
///   reduced into the JubJub scalar field (the stdlib's
///   `cNative as JubjubScalar` cast — plain mod-r reduction);
/// - `response as JubjubScalar` — same reduction;
/// - valid iff `s·G == R + c·pk`.
///
/// Identity points contribute zero coordinates to the hash (the
/// `jubjubPointX`/`jubjubPointY` semantics), with no up-front identity
/// rejection — exactly like the stdlib circuit.
pub fn jubjub_schnorr_verify<const N: usize>(
    msg: [Fr; N],
    signature: JubjubSchnorrSignature,
    pk: JubjubPoint,
) -> bool {
    let ann_x = signature.announcement.x().unwrap_or_else(|| Fr::from(0u64));
    let ann_y = signature.announcement.y().unwrap_or_else(|| Fr::from(0u64));
    let pk_x = pk.x().unwrap_or_else(|| Fr::from(0u64));
    let pk_y = pk.y().unwrap_or_else(|| Fr::from(0u64));

    let c = compute_challenge(ann_x, ann_y, pk_x, pk_y, &msg);

    let lhs = JubjubPoint::generator() * fr_to_embedded_fr(signature.response);
    let rhs = signature.announcement + pk * c;
    lhs == rhs
}

/// Circuit-shaped wrapper used by the compact codegen to replace
/// `self.schnorr_verify(ctx, msg, sig, pk)?` calls inside the
/// generated `schnorr_verify_digest` circuit body. Verifies the
/// signature, returns `Err(CompactError::AssertionFailed)` on
/// rejection, and otherwise threads `ctx` through a no-op
/// `query_for_verify` to produce a `CircuitResults<PS, ()>` shaped the
/// same way an inlined Compact assert body would.
pub fn schnorr_verify_jubjub<PS, const N: usize>(
    ctx: CircuitContext<PS>,
    msg: [Fr; N],
    sig: SchnorrSignature,
    pk: JubjubPoint,
) -> Result<CircuitResults<PS, ()>, CompactError>
where
    PS: Clone,
{
    if !verify(pk, &msg, &sig) {
        return Err(CompactError::AssertionFailed(
            "Schnorr signature verification failed".into(),
        ));
    }
    let ops = OpProgramVerify::<DefaultDB>::new().build();
    let results = query_for_verify(
        &ctx.current_query_context,
        &ops,
        ctx.gas_limit,
        &ctx.cost_model,
    )?;
    Ok(CircuitResults {
        result: (),
        context: CircuitContext {
            current_query_context: results.context,
            ..ctx
        },
        gas_cost: results.gas_cost,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::std_lib::jubjub_scalar_from_field;

    /// A signature whose response is `s` and whose announcement is `s·G`.
    ///
    /// Against an **identity** public key this is a universal forgery, and
    /// that is the whole point of the identity guard: with `pk = O`,
    /// `pk·c = O` for every challenge `c`, so the verification equation
    /// collapses from `s·G == R + pk·c` to `s·G == R` — which this pair
    /// satisfies by construction, for any message, with no secret key.
    fn forgery_against_identity() -> (SchnorrSignature, [Fr; 2]) {
        let response = Fr::from(12345u64);
        let announcement = JubjubPoint::generator() * jubjub_scalar_from_field(response);
        (
            SchnorrSignature {
                announcement,
                response,
            },
            [Fr::from(7u64), Fr::from(9u64)],
        )
    }

    /// The security property. `verify` now delegates to
    /// `midnight_transient_crypto::schnorr::verify`, so this asserts that
    /// upstream's guard is really in force on our path — a delegation that
    /// quietly dropped the check would leave every contract verifying
    /// against an unset key wide open, because a ledger cell holds its
    /// type's default until written and `JubjubPoint::default()` **is** the
    /// identity.
    #[test]
    fn identity_public_key_is_rejected() {
        let (sig, msg) = forgery_against_identity();
        assert!(
            !verify(JubjubPoint::identity(), &msg, &sig),
            "an identity public key must never verify: pk·c is O for every \
             challenge, so any (s, s·G) pair satisfies the equation"
        );
    }

    #[test]
    fn identity_announcement_is_rejected() {
        let sig = SchnorrSignature {
            announcement: JubjubPoint::identity(),
            response: Fr::from(1u64),
        };
        let pk = JubjubPoint::generator() * jubjub_scalar_from_field(Fr::from(99u64));
        assert!(!verify(pk, &[Fr::from(1u64)], &sig));
    }

    /// `JubjubPoint::default()` is the identity, which is why the guard is
    /// reachable rather than theoretical: an unwritten ledger key cell
    /// holds exactly this value.
    #[test]
    fn the_default_jubjub_point_is_the_identity() {
        assert!(JubjubPoint::default().is_identity());
        let (sig, msg) = forgery_against_identity();
        assert!(!verify(JubjubPoint::default(), &msg, &sig));
    }

    /// Pins the deliberate difference between the two verifiers, so that
    /// nobody later "tidies" `jubjub_schnorr_verify` into a call to
    /// upstream's `verify` and silently changes its meaning.
    ///
    /// `jubjub_schnorr_verify` mirrors the 0.33 standard library's
    /// `jubjubSchnorrVerify` circuit, which performs **no** identity
    /// rejection — identity points just contribute zero coordinates to the
    /// hash. So the same forgery that `verify` refuses is **accepted**
    /// here, exactly as the circuit accepts it.
    ///
    /// This asserts a weakness on purpose. It is not an endorsement of it:
    /// the Rust path matching the circuit is what makes the two comparable,
    /// and closing the hole belongs in the circuit, where the divergence
    /// would otherwise be invisible.
    #[test]
    fn the_stdlib_mirror_deliberately_does_not_reject_identity() {
        let (sig, msg) = forgery_against_identity();
        let stdlib_sig = JubjubSchnorrSignature {
            announcement: sig.announcement,
            response: sig.response,
        };

        assert!(
            jubjub_schnorr_verify(msg, stdlib_sig, JubjubPoint::identity()),
            "the stdlib mirror must accept what the stdlib circuit accepts; \
             if this fails, it has been routed through a guarded verifier and \
             now disagrees with the circuit it exists to match"
        );
        assert!(
            !verify(JubjubPoint::identity(), &msg, &sig),
            "…while the guarded verifier refuses the same pair"
        );
    }
}
