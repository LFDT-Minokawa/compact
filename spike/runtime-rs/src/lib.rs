// SPDX-License-Identifier: Apache-2.0
//
// Spike `compact-runtime` — native Rust facade matching @midnight-ntwrk/compact-runtime.
//
// Strictly minimal: only what the validation spike (counter-contract) needs.
// Everything else is either a curated re-export of an upstream Midnight crate or
// a small facade aggregate / helper.
//
// NOT FOR PRODUCTION. This proves the design from Section 2 of the Rust-codegen brief
// compiles end-to-end against published crates.

// ---------------------------------------------------------------------------
// Curated re-exports — the things generated code references directly.
// ---------------------------------------------------------------------------

// Encoding / alignment / value bus.
pub use midnight_base_crypto::fab::{Aligned, AlignedValue, Alignment, Value};

// Field arithmetic + proof-system primitives.
pub use midnight_transient_crypto::curve::Fr;
pub use midnight_transient_crypto::repr::{FieldRepr, FromFieldRepr};

// Cost / gas.
pub use midnight_base_crypto::cost_model::RunningCost;
pub use midnight_onchain_vm::cost_model::CostModel;

// VM ops.
pub use midnight_onchain_vm::ops::{Key, Op};
pub use midnight_onchain_vm::result_mode::{ResultMode, ResultModeGather, ResultModeVerify};

// Storage primitives that generated code needs to construct paths.
pub use midnight_storage::storage::Array;

// On-chain state.
pub use midnight_onchain_state::state::{ChargedState, ContractState, StateValue};

// Runtime / context.
pub use midnight_onchain_runtime::context::{QueryContext, QueryResults};
pub use midnight_onchain_runtime::error::TranscriptRejected;

// Coin / contract addressing.
pub use midnight_coin_structure::contract::ContractAddress;

// Storage backend.
pub use midnight_storage::db::{InMemoryDB, DB};
pub use midnight_storage::DefaultDB;

// ---------------------------------------------------------------------------
// Facade aggregates — the small set of types that don't exist upstream.
// ---------------------------------------------------------------------------

pub mod context;
pub mod witness;
pub mod version;

pub use context::{CircuitContext, CircuitResults, ConstructorContext, ConstructorResult};
pub use witness::{NoWitnesses, WitnessContext};
