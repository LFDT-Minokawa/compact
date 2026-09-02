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
// `midnight-compact-runtime` standard library.
//
// Submodules carry the surface area generated contract code reaches
// into via the `midnight_compact_runtime::std_lib::*` path. The flat re-export
// below preserves that path — adding a new helper means adding it to
// one of the submodules and re-exporting it here.
//
// See ../README.md for the submodule responsibility table.

mod adts;
mod bytes_pad_disclose;
mod field_repr;
mod jubjub;
mod maybe;
mod merkle_path;
mod narrowing;
mod opaque;
mod schnorr;

pub use adts::{
    decode_bool, decode_bounded_uint, decode_bytes, decode_fr, decode_jubjub_point, decode_u128,
    decode_u16, decode_u32, decode_u64, decode_u8, decode_vector_fr, decode_vector_u64,
    decode_via_field_repr, serialize_contract_state, Counter,
};
pub use bytes_pad_disclose::{
    disclose, pad, persistent_hash_aligned, transient_hash_aligned, Bytes,
};
pub use field_repr::{
    array_from_field_repr, bytes_field_size, bytes_from_field_repr, vec_u8_from_field_repr,
};
pub use jubjub::{
    construct_jubjub_point,
    degrade_to_transient,
    ec_add,
    ec_mul,
    ec_mul_generator,
    ec_neg,
    // R5a: orphan-safe repr helpers used by codegen for JubjubPoint-typed
    // struct fields. Re-exported into `midnight_compact_runtime::std_lib::` so
    // generated code can avoid `<JubjubPoint as FromFieldRepr>::*`
    // syntax (which the orphan rule forbids us from impl'ing).
    jubjub_point_binary_len,
    jubjub_point_binary_repr,
    jubjub_point_field_repr,
    jubjub_point_field_size,
    jubjub_point_from_field_repr,
    jubjub_point_x,
    jubjub_point_y,
    jubjub_scalar_from_field,
    upgrade_from_transient,
    JUBJUB_POINT_BINARY_LEN,
    JUBJUB_POINT_FIELD_SIZE,
};
pub use maybe::{none, some, Maybe};
pub use merkle_path::{
    default_merkle_path, merkle_tree_path_root, merkle_tree_path_root_no_leaf_hash,
};
pub use narrowing::narrow;
pub use opaque::OpaqueString;
// Two off-circuit Schnorr verifiers, exported under names that say which
// circuit each one agrees with. They are not interchangeable: the challenge
// reductions differ (mod `r_jubjub` vs mod 2^248), so a signature valid
// under one is not generally valid under the other. Exporting only the
// first — which is what this did — left the second reachable by no name at
// all while `schnorr_verify` looked like *the* verifier.
pub use schnorr::{
    jubjub_schnorr_verify, schnorr_verify_jubjub, verify as schnorr_verify,
    verify_truncated_challenge as schnorr_verify_truncated, JubjubSchnorrSignature,
    SchnorrSignature,
};
