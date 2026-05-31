// SPDX-License-Identifier: Apache-2.0
//
// compact-runtime — native Rust facade. See lib doc comment in Task B1.

#![forbid(unsafe_code)]

// Re-export the foundational crates so generated code can write
// `base_crypto::*` etc. when needed for less-common types.
pub use midnight_base_crypto as base_crypto;
pub use midnight_transient_crypto as transient_crypto;
pub use midnight_onchain_state as onchain_state;
pub use midnight_onchain_vm as onchain_vm;
pub use midnight_onchain_runtime as onchain_runtime;
pub use midnight_coin_structure as coin_structure;
pub use midnight_storage as storage;
pub use midnight_zswap as zswap;

pub use compact_runtime_macros::witnesses;

// ---------------------------------------------------------------------------
// Curated prelude — the symbols the codegen references directly.
// ---------------------------------------------------------------------------

// Encoding / alignment / value bus.
pub use midnight_base_crypto::fab::{Aligned, AlignedValue, Alignment, Value};

// Field arithmetic + proof-system primitives.
pub use midnight_transient_crypto::curve::{EmbeddedGroupAffine as JubjubPoint, Fr};
pub use midnight_base_crypto::repr::MemWrite;
pub use midnight_transient_crypto::repr::{FieldRepr, FromFieldRepr};
pub use midnight_transient_crypto::merkle_tree::{
    MerklePath, MerklePathEntry, MerkleTreeDigest, leaf_hash,
};
pub use midnight_transient_crypto::fab::ValueReprAlignedValue;

// Cost / gas.
pub use midnight_base_crypto::cost_model::RunningCost;
pub use midnight_onchain_vm::cost_model::{CostModel, INITIAL_COST_MODEL};

// VM ops + path keys.
pub use midnight_onchain_vm::ops::{Key, Op};
pub use midnight_onchain_vm::result_mode::{ResultMode, ResultModeGather, ResultModeVerify};

// On-chain state.
pub use midnight_onchain_state::state::{
    ChargedState, ContractMaintenanceAuthority, ContractOperation, ContractState, EntryPointBuf,
    StateValue,
};

// Runtime / context.
pub use midnight_onchain_runtime::context::{QueryContext, QueryResults};
pub use midnight_onchain_runtime::error::TranscriptRejected;
pub use midnight_onchain_runtime::transcript::Transcript;

// Coin / contract addressing.
pub use midnight_coin_structure::coin::{
    Info as CoinInfo, PublicKey as CoinPublicKey, QualifiedInfo as QualifiedShieldedCoinInfo,
};
pub use midnight_coin_structure::contract::ContractAddress;
pub use midnight_coin_structure::transfer::Recipient;

// Storage backend.
pub use midnight_storage::db::{InMemoryDB, DB};
pub use midnight_storage::storage::Array;
pub use midnight_storage::DefaultDB;

// Compact ADT types — re-exports of upstream Midnight types under the
// Compact-level names that the codegen references.
//
// - Map<K, V> ← midnight_storage::storage::HashMap (the upstream
//   "map from key hashes to values"). The Compact `Map` ADT seeds its
//   initial StateValue as `state-value 'map ()`, i.e. an empty
//   `StateValue::Map(HashMap::new())`.
// - Set<T>: the Compact ADT also lowers to `state-value 'map ()` at the
//   StateValue level (a set is a map of values → null). For Rust-side
//   typing, we surface it as the same HashMap type with a unit value;
//   construction at the StateValue level is via `new_map()`.
// - MerkleTree / HistoricMerkleTree: the on-chain Compact ADTs lower to
//   StateValue::BoundedMerkleTree wrapped in an Array, see
//   compiler/midnight-ledger.ss `(declare-ledger-adt MerkleTree ...)`.
//   Construction goes through `new_merkle_tree(height)` /
//   `new_historic_merkle_tree(height)`. The Rust-side `MerkleTree<A, D>`
//   re-export is the cryptographic tree from midnight-transient-crypto;
//   it's exposed mainly so generated code (E4 onwards) can name leaf /
//   path types in method signatures.
pub use midnight_storage::storage::HashMap as Map;
pub use midnight_transient_crypto::merkle_tree::MerkleTree;

// Hashes (re-exported as bare names — usability over fully-qualified paths).
pub use midnight_base_crypto::hash::{persistent_commit, persistent_hash};
pub use midnight_transient_crypto::hash::{hash_to_curve, transient_commit, transient_hash};

// Zswap local state.
pub use midnight_zswap::local::State as ZswapLocalState;

// ---------------------------------------------------------------------------
// Facade aggregates.
// ---------------------------------------------------------------------------

mod context;
pub use context::{CircuitContext, ConstructorContext};

mod results;
pub use results::{CircuitResults, ConstructorResult};

mod witness;
pub use witness::{NoWitnesses, WitnessContext};

mod error;
pub use error::CompactError;

pub mod version;
pub use version::COMPACT_RUNTIME_VERSION;

pub mod std_lib;
pub use std_lib::{
    array_from_field_repr, bytes_from_field_repr, bytes_field_size, construct_jubjub_point,
    degrade_to_transient, disclose, ec_add, ec_mul, ec_mul_generator, jubjub_point_x,
    jubjub_point_y, none, pad, some, upgrade_from_transient, vec_u8_from_field_repr, Bytes,
    Maybe,
};

pub mod builders;
pub use builders::{
    aligned_bytes, empty_charged_state, entry_point, initial_cost_model, new_array, new_cell,
    new_contract_state, new_empty_array, new_historic_merkle_tree, new_map, new_merkle_tree,
    query_result_state,
};

pub mod query;
pub use query::{query_for_read, query_for_verify};

pub mod op_builder;
pub use op_builder::{OpProgramGather, OpProgramVerify};
