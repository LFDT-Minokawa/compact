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
//! The pinned `midnight-transient-crypto 2.1.0` does not yet expose the
//! `schnorr` module that midnight-ledger ships locally (the impl was
//! added post-2.1.0). To keep compact-runtime self-contained we vendor
//! ~50 LOC of the verifier here, then expose a circuit-shaped wrapper
//! (`schnorr_verify_jubjub`) that takes a `CircuitContext`, threads it
//! through a no-op `query_for_verify`, and surfaces the verification
//! result as a `CompactError::AssertionFailed` on rejection.
//!
//! When upstream `midnight-transient-crypto` exposes `schnorr` in a
//! future release the vendored bits can be deleted in favour of
//! `pub use midnight_transient_crypto::schnorr::*` and the wrapper
//! unchanged.
//!
//! Algorithm matches `jubjub-schnorr/src/schnorr.compact`'s
//! `schnorrVerify` exactly: Poseidon over
//! `[ann_x, ann_y, pk_x, pk_y, ...msg]` then reduce modulo the Jubjub
//! scalar order → check `g^s == announcement + pk^c`.

use midnight_transient_crypto::curve::{embedded, EmbeddedFr, Fr};
use midnight_transient_crypto::hash::transient_hash;

use crate::{
    query_for_verify, CircuitContext, CircuitResults, CompactError, DefaultDB, JubjubPoint,
    OpProgramVerify,
};

/// A Schnorr signature over the embedded curve. Layout matches the
/// Compact-side `Schnorr.SchnorrSignature` struct
/// (`announcement: JubjubPoint`, `response: Field`) so codegen-generated
/// struct conversions line up.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct SchnorrSignature {
    /// The announcement point, `R = k * G`.
    pub announcement: JubjubPoint,
    /// The response scalar, `s = k + c * sk`.
    pub response: EmbeddedFr,
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

/// Reduce a BLS12-381 scalar `Fr` modulo the Jubjub scalar field order.
/// `from_uniform_bytes` interprets a 64-byte buffer as a big integer
/// and reduces — feeding the low 32 bytes mirrors what the matching
/// circuit does via the `getSchnorrReduction` witness (the circuit
/// must use a witness to expose the reduction as a constraint-friendly
/// quotient/remainder pair; off-circuit we just take the modular
/// reduction directly).
fn fr_to_embedded_fr(fr: Fr) -> EmbeddedFr {
    let mut wide = [0u8; 64];
    wide[..32].copy_from_slice(&fr.as_le_bytes());
    EmbeddedFr(embedded::Scalar::from_bytes_wide(&wide))
}

/// Off-circuit Schnorr verifier. Returns `true` iff the signature is
/// valid for `(pk, msg)`. Identity public-key / announcement are
/// rejected up front, matching the circuit's identity guards.
pub fn verify(pk: JubjubPoint, msg: &[Fr], sig: &SchnorrSignature) -> bool {
    if pk.is_identity() || sig.announcement.is_identity() {
        return false;
    }
    let pk_x = match pk.x() {
        Some(x) => x,
        None => return false,
    };
    let pk_y = match pk.y() {
        Some(y) => y,
        None => return false,
    };
    let ann_x = match sig.announcement.x() {
        Some(x) => x,
        None => return false,
    };
    let ann_y = match sig.announcement.y() {
        Some(y) => y,
        None => return false,
    };

    let challenge = compute_challenge(ann_x, ann_y, pk_x, pk_y, msg);

    let lhs = JubjubPoint::generator() * sig.response;
    let rhs = sig.announcement + pk * challenge;
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
        ctx.gas_limit.clone(),
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
