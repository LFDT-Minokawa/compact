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
    query_for_verify, CircuitContext, CircuitResults, CompactError, DefaultDB, EmbeddedGroupAffine,
    JubjubPoint, OpProgramVerify,
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

/// The full, unreduced challenge: `transientHash(ann_x, ann_y, pk_x, pk_y,
/// ...msg)`.
///
/// Both circuits below hash exactly these field elements in exactly this
/// order. They differ only in how they reduce the result into the Jubjub
/// scalar field, so that reduction is the caller's choice — see
/// [`fr_to_embedded_fr`] (mod `r`) and [`truncate_challenge`] (mod 2^248).
fn challenge_hash(ann_x: Fr, ann_y: Fr, pk_x: Fr, pk_y: Fr, msg: &[Fr]) -> Fr {
    let mut hash_input = Vec::with_capacity(4 + msg.len());
    hash_input.push(ann_x);
    hash_input.push(ann_y);
    hash_input.push(pk_x);
    hash_input.push(pk_y);
    hash_input.extend_from_slice(msg);
    transient_hash(&hash_input)
}

/// Reduce a BLS12-381 scalar `Fr` modulo the Jubjub scalar field order,
/// i.e. `x mod r_jubjub`. Single implementation lives in
/// [`crate::std_lib::jubjub_scalar_from_field`], which is also what
/// Compact's `as JubjubScalar` cast lowers to.
///
/// This is the reduction the **0.33 standard library**'s
/// `jubjubSchnorrVerify` performs (`cNative as JubjubScalar`), so it is the
/// one [`jubjub_schnorr_verify`] and [`verify`] use. It is *not* the
/// vendored `schnorr.compact` module's reduction — see
/// [`truncate_challenge`].
fn fr_to_embedded_fr(fr: Fr) -> EmbeddedFr {
    crate::std_lib::jubjub_scalar_from_field(fr)
}

/// Reduce a challenge by **248-bit truncation**: `cFull mod 2^248`.
///
/// This is the reduction the vendored
/// `examples/did-05/jubjub-schnorr/src/schnorr.compact` module performs. It
/// spells it as a witness plus two asserts rather than an operator:
///
/// ```compact
/// const [q, cTruncated] = getSchnorrReduction(cFull);
/// assert(disclose(q) < 116, "Schnorr quotient out of range");
/// assert(disclose(q) * TWO_248 + (disclose(cTruncated) as Field) == cFull,
///        "Invalid challenge reduction");
/// const c: Field = disclose(cTruncated) as Field;
/// ```
///
/// Those two asserts constrain `cTruncated` to be exactly `cFull mod 2^248`
/// (the `q < 116` bound is implied by `cFull < r_bls ≈ 115.9 · 2^248`, so it
/// restricts the witness, not the input, and has nothing to reproduce here).
///
/// `2^248` is `31` whole bytes, so on the canonical little-endian
/// representation the reduction is simply "keep the low 31 bytes". The
/// result is `< 2^248 < r_jubjub`, so widening it into the embedded scalar
/// field is value-preserving — which is what the circuit's own
/// `c as JubjubScalar` cast relies on.
///
/// # Security note
///
/// A 248-bit challenge is the vendored circuit's design, not a choice made
/// here; reproducing it is what makes the off-circuit verifier agree with
/// the on-circuit one. It is ~4 bits weaker than the mod-`r` form.
fn truncate_challenge(c_full: Fr) -> EmbeddedFr {
    const TRUNCATED_BYTES: usize = 31; // 248 bits
    let le = c_full.as_le_bytes();
    let keep = TRUNCATED_BYTES.min(le.len());
    let mut wide = [0u8; 64];
    wide[..keep].copy_from_slice(&le[..keep]);
    // `from_bytes_wide` rather than the fallible `from_le_bytes`: the input
    // is `< 2^248 < r_jubjub`, so the wide reduction is the identity here and
    // this stays infallible rather than trading a panic for an `Option` that
    // can never be `None`.
    EmbeddedFr(midnight_transient_crypto::curve::embedded::Scalar::from_bytes_wide(&wide))
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
///
/// A `pk` or `announcement` that is not a point in the prime-order subgroup
/// yields `false` rather than reaching upstream. Both arrive as Compact
/// `JubjubPoint`s — coordinate pairs, typically straight off the ledger — and
/// converting one with `EmbeddedGroupAffine::new` would panic rather than
/// fail. There is no signature to accept in that case anyway.
pub fn verify(pk: JubjubPoint, msg: &[Fr], sig: &SchnorrSignature) -> bool {
    let (Some(pk), Some(announcement)) = (pk.to_group(), sig.announcement.to_group()) else {
        return false;
    };
    midnight_transient_crypto::schnorr::verify(
        pk,
        msg,
        &midnight_transient_crypto::schnorr::SchnorrSignature {
            announcement,
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
/// The identity contributes its own coordinates `(0, 1)` to the hash, with no
/// up-front identity rejection — exactly like the stdlib circuit. A point
/// outside the prime-order subgroup yields `false`: the group arithmetic
/// below is undefined for it, and the circuit's own `ecMul` cannot be
/// satisfied by one either.
pub fn jubjub_schnorr_verify<const N: usize>(
    msg: [Fr; N],
    signature: JubjubSchnorrSignature,
    pk: JubjubPoint,
) -> bool {
    let (Some(announcement), Some(pk_group)) = (signature.announcement.to_group(), pk.to_group())
    else {
        return false;
    };

    let c = fr_to_embedded_fr(challenge_hash(
        signature.announcement.x,
        signature.announcement.y,
        pk.x,
        pk.y,
        &msg,
    ));

    let lhs = EmbeddedGroupAffine::generator() * fr_to_embedded_fr(signature.response);
    let rhs = announcement + pk_group * c;
    lhs == rhs
}

/// Off-circuit verifier for the **vendored** `schnorr` module's
/// `schnorrVerify<#n>` circuit
/// (`examples/did-05/jubjub-schnorr/src/schnorr.compact`). Returns `true`
/// iff the signature satisfies that circuit's equation.
///
/// This is a different function from [`verify`], and deliberately so. The
/// two circuits derive the challenge from the same hash but reduce it
/// differently:
///
/// | | challenge reduction |
/// |---|---|
/// | 0.33 stdlib `jubjubSchnorrVerify` → [`verify`] | `cFull mod r_jubjub` |
/// | vendored `schnorrVerify` → this function | `cFull mod 2^248` |
///
/// Since `2^248 < r_jubjub`, the two disagree whenever `cFull >= 2^248` —
/// which is essentially every full-width hash. A verifier substituted for
/// the wrong one of these rejects valid signatures and, worse, is not the
/// predicate the on-chain proof actually enforces.
///
/// Beyond the reduction it reproduces the rest of the circuit body:
/// identity `pk` or `announcement` is rejected up front (the circuit's
/// `assert(pk != default<JubjubPoint> && announcement != …)`, which exists
/// because `ecMul(O, c) == O` collapses the check to `response·G ==
/// announcement` and drops the message entirely), then `response as
/// JubjubScalar` is the mod-`r` cast, and the equation is
/// `response·G == announcement + c·pk`.
pub fn verify_truncated_challenge(pk: JubjubPoint, msg: &[Fr], sig: &SchnorrSignature) -> bool {
    if pk.is_identity() || sig.announcement.is_identity() {
        return false;
    }
    // A key or announcement outside the prime-order subgroup is refused here
    // rather than converted. Both are Compact `JubjubPoint`s — coordinate
    // pairs an attacker can put in a ledger cell — and the group arithmetic
    // below is undefined for one, so there is nothing to accept.
    let (Some(pk_group), Some(announcement)) = (pk.to_group(), sig.announcement.to_group()) else {
        return false;
    };

    let c = truncate_challenge(challenge_hash(
        sig.announcement.x,
        sig.announcement.y,
        pk.x,
        pk.y,
        msg,
    ));

    let lhs = EmbeddedGroupAffine::generator() * fr_to_embedded_fr(sig.response);
    let rhs = announcement + pk_group * c;
    lhs == rhs
}

/// Circuit-shaped wrapper used by the compact codegen to replace
/// `self.schnorr_verify(ctx, msg, sig, pk)?` calls inside the
/// generated `schnorr_verify_digest` circuit body. Verifies the
/// signature, returns `Err(CompactError::AssertionFailed)` on
/// rejection, and otherwise threads `ctx` through a no-op
/// `query_for_verify` to produce a `CircuitResults<PS, ()>` shaped the
/// same way an inlined Compact assert body would.
///
/// The circuit it replaces is the vendored `schnorr` module's, so it
/// verifies with [`verify_truncated_challenge`], not [`verify`]. It used to
/// call [`verify`], which meant a signature the on-chain circuit accepts was
/// rejected here (and vice versa) for essentially every message — the
/// substitution did not compute the predicate it was substituted for.
pub fn schnorr_verify_jubjub<PS, const N: usize>(
    ctx: CircuitContext<PS>,
    msg: [Fr; N],
    sig: SchnorrSignature,
    pk: JubjubPoint,
) -> Result<CircuitResults<PS, ()>, CompactError>
where
    PS: Clone,
{
    if !verify_truncated_challenge(pk, &msg, &sig) {
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
        let announcement = crate::std_lib::ec_mul_generator(jubjub_scalar_from_field(response));
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
        let pk = crate::std_lib::ec_mul_generator(jubjub_scalar_from_field(Fr::from(99u64)));
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

    // ---- the vendored circuit's truncated challenge ------------------------

    /// Widen an embedded scalar into the outer field with the same integer
    /// value. `r_jubjub < r_bls`, so every canonical embedded scalar has an
    /// outer-field representative, and `fr_to_embedded_fr` maps it back
    /// unchanged — which is exactly what the circuit's `response as
    /// JubjubScalar` cast relies on.
    fn widen(s: EmbeddedFr) -> Fr {
        Fr::from_le_bytes(&s.as_le_bytes()).expect("r_jubjub < r_bls, so this always fits")
    }

    /// Produce a signature that satisfies the **vendored** circuit's
    /// equation: `s = k + c·sk` with `c = cFull mod 2^248`.
    fn sign_truncated(
        sk: EmbeddedFr,
        nonce: EmbeddedFr,
        msg: &[Fr],
    ) -> (JubjubPoint, SchnorrSignature) {
        let pk = crate::std_lib::ec_mul_generator(sk);
        let announcement = crate::std_lib::ec_mul_generator(nonce);
        let c = truncate_challenge(challenge_hash(
            announcement.x,
            announcement.y,
            pk.x,
            pk.y,
            msg,
        ));
        let response = widen(nonce + c * sk);
        (
            pk,
            SchnorrSignature {
                announcement,
                response,
            },
        )
    }

    /// The same, reduced mod `r_jubjub` — what the 0.33 stdlib circuit and
    /// upstream's `verify` expect.
    fn sign_mod_r(
        sk: EmbeddedFr,
        nonce: EmbeddedFr,
        msg: &[Fr],
    ) -> (JubjubPoint, SchnorrSignature) {
        let pk = crate::std_lib::ec_mul_generator(sk);
        let announcement = crate::std_lib::ec_mul_generator(nonce);
        let c = fr_to_embedded_fr(challenge_hash(
            announcement.x,
            announcement.y,
            pk.x,
            pk.y,
            msg,
        ));
        let response = widen(nonce + c * sk);
        (
            pk,
            SchnorrSignature {
                announcement,
                response,
            },
        )
    }

    fn keys() -> (EmbeddedFr, EmbeddedFr, [Fr; 4]) {
        (
            jubjub_scalar_from_field(Fr::from(0x00C0_FFEEu64)),
            jubjub_scalar_from_field(Fr::from(0x0000_BEEFu64)),
            [
                Fr::from(1u64),
                Fr::from(2u64),
                Fr::from(3u64),
                Fr::from(4u64),
            ],
        )
    }

    /// The reviewer's probe, as a test. A signature built against the
    /// vendored circuit's 248-bit truncated challenge must verify on the
    /// path that substitutes for that circuit — and must *not* verify under
    /// the mod-`r` reduction, which is what the code used to call.
    ///
    /// The second assertion is the one that would have caught the bug: it
    /// fails the moment `verify_truncated_challenge` is "simplified" back
    /// into `verify`, because then both assertions describe the same
    /// function and they cannot both hold.
    #[test]
    fn a_signature_for_the_vendored_circuit_verifies_only_under_truncation() {
        let (sk, nonce, msg) = keys();
        let (pk, sig) = sign_truncated(sk, nonce, &msg);

        assert!(
            verify_truncated_challenge(pk, &msg, &sig),
            "the off-circuit verifier must accept what the circuit it \
             replaces accepts"
        );
        assert!(
            !verify(pk, &msg, &sig),
            "…and the mod-r verifier must not: 2^248 < r_jubjub, so the two \
             reductions differ for every challenge at or above 2^248"
        );
    }

    /// The converse direction, so neither verifier can quietly become the
    /// other.
    #[test]
    fn a_stdlib_signature_does_not_verify_under_truncation() {
        let (sk, nonce, msg) = keys();
        let (pk, sig) = sign_mod_r(sk, nonce, &msg);

        assert!(verify(pk, &msg, &sig));
        assert!(!verify_truncated_challenge(pk, &msg, &sig));
    }

    /// The vendored circuit asserts `pk != default<JubjubPoint> &&
    /// announcement != default<JubjubPoint>`, so the off-circuit verifier
    /// must refuse the same universal forgery.
    #[test]
    fn the_truncated_verifier_rejects_identity() {
        let (sig, short_msg) = forgery_against_identity();
        assert!(!verify_truncated_challenge(
            JubjubPoint::identity(),
            &short_msg,
            &sig
        ));

        let (sk, _, msg) = keys();
        let pk = crate::std_lib::ec_mul_generator(sk);
        let identity_ann = SchnorrSignature {
            announcement: JubjubPoint::identity(),
            response: Fr::from(1u64),
        };
        assert!(!verify_truncated_challenge(pk, &msg, &identity_ann));
    }

    /// `schnorr_verify_jubjub` is what the codegen substitutes for the
    /// vendored circuit, so the predicate it applies is the thing that has
    /// to be right. Driving it end to end pins the wiring, not just the
    /// helper: re-pointing it at `verify` fails here even though every
    /// test above still passes.
    #[test]
    fn schnorr_verify_jubjub_applies_the_truncated_predicate() {
        use crate::{ChargedState, ContractAddress, QueryContext, StateValue, INITIAL_COST_MODEL};

        let ctx = || CircuitContext::<()> {
            current_private_state: (),
            current_query_context: QueryContext::new(
                ChargedState::new(StateValue::Null),
                ContractAddress::default(),
            ),
            current_zswap_local_state: Default::default(),
            cost_model: INITIAL_COST_MODEL,
            gas_limit: None,
        };

        let (sk, nonce, msg) = keys();

        let (pk, truncated) = sign_truncated(sk, nonce, &msg);
        assert!(
            schnorr_verify_jubjub(ctx(), msg, truncated, pk).is_ok(),
            "must accept a signature the vendored circuit accepts"
        );

        let (pk, mod_r) = sign_mod_r(sk, nonce, &msg);
        assert!(
            schnorr_verify_jubjub(ctx(), msg, mod_r, pk).is_err(),
            "must reject a signature the vendored circuit rejects"
        );
    }
}
