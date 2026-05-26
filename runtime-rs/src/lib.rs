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

// ---------------------------------------------------------------------------
// Curated prelude — the symbols the codegen references directly.
// ---------------------------------------------------------------------------

// Encoding / alignment / value bus.
pub use midnight_base_crypto::fab::{Aligned, AlignedValue, Alignment, Value};

// Field arithmetic + proof-system primitives.
pub use midnight_transient_crypto::curve::{EmbeddedGroupAffine as JubjubPoint, Fr};
pub use midnight_transient_crypto::repr::{FieldRepr, FromFieldRepr};
pub use midnight_transient_crypto::merkle_tree::{MerklePath, MerklePathEntry, MerkleTreeDigest};

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

pub mod builders;
pub use builders::{
    aligned_bytes, empty_charged_state, entry_point, initial_cost_model, new_array, new_cell,
    new_contract_state, new_empty_array, query_result_state,
};

pub mod query;
pub use query::{query_for_read, query_for_verify};
