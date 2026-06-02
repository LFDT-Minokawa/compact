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
// `compact-runtime` standard library.
//
// Submodules carry the surface area generated contract code reaches
// into via the `compact_runtime::std_lib::*` path. The flat re-export
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
mod opaque;

pub use adts::{
    decode_bool, decode_bytes, decode_fr, decode_u128, decode_u16, decode_u32, decode_u64,
    decode_u8, decode_vector_fr, decode_vector_u64, decode_via_field_repr,
    serialize_contract_state, Counter,
};
pub use bytes_pad_disclose::{disclose, pad, persistent_hash_aligned, Bytes};
pub use field_repr::{
    array_from_field_repr, bytes_field_size, bytes_from_field_repr, vec_u8_from_field_repr,
};
pub use jubjub::{
    construct_jubjub_point, degrade_to_transient, ec_add, ec_mul, ec_mul_generator, jubjub_point_x,
    jubjub_point_y, upgrade_from_transient,
};
pub use maybe::{none, some, Maybe};
pub use merkle_path::{
    default_merkle_path, merkle_tree_path_root, merkle_tree_path_root_no_leaf_hash,
};
pub use opaque::OpaqueString;
