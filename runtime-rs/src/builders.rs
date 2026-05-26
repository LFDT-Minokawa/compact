// SPDX-License-Identifier: Apache-2.0
//
// Ergonomic constructors and accessors that wrap upstream Midnight crate APIs
// the generated Compact contract code uses pervasively. Each helper here
// eliminates a specific friction point captured in the original codegen plan's
// "upstream-API findings" section.
//
// These wrappers are zero-cost (single function call / re-export); the goal is
// readability of generated code, not performance.

use crate::{
    AlignedValue, Array, ChargedState, ContractState, CostModel, QueryResults, ResultMode,
    StateValue, INITIAL_COST_MODEL, DB,
};
use midnight_onchain_state::state::{
    ContractMaintenanceAuthority, ContractOperation, EntryPointBuf,
};
use midnight_storage::storage::HashMap;

/// Returns a fresh `CostModel` initialised to upstream's `INITIAL_COST_MODEL`
/// constant. Method-shaped for natural reading: `let cm = initial_cost_model();`.
pub fn initial_cost_model() -> CostModel {
    INITIAL_COST_MODEL.clone()
}

/// Returns a `ChargedState<D>` wrapping `StateValue::Null`. Useful as a seed
/// when constructing fresh contract state from generated code.
pub fn empty_charged_state<D: DB>() -> ChargedState<D> {
    ChargedState::new(StateValue::Null)
}

/// Builds a `StateValue::Cell(...)` from anything convertible to an
/// `AlignedValue`. Mirrors the TypeScript `StateValue.newCell` factory.
pub fn new_cell<D: DB, T: Into<AlignedValue>>(v: T) -> StateValue<D> {
    StateValue::from(v.into())
}

/// Builds a `StateValue::Array(...)` from a vector of nested `StateValue`s.
/// Mirrors the TypeScript `StateValue.newArray().arrayPush(...)` chain.
pub fn new_array<D: DB>(items: Vec<StateValue<D>>) -> StateValue<D> {
    let arr = items
        .into_iter()
        .fold(Array::new(), |acc, s| acc.push(s));
    StateValue::Array(arr)
}

/// Builds an empty `StateValue::Array(...)`. Useful for the codegen's
/// `initial_state` template before fields are pushed.
pub fn new_empty_array<D: DB>() -> StateValue<D> {
    StateValue::Array(Array::new())
}

/// Returns the raw byte slice of the first atom in an `AlignedValue`'s
/// `Value(Vec<ValueAtom>)`, hiding the two-step accessor.
pub fn aligned_bytes(av: &AlignedValue) -> Option<&[u8]> {
    av.value.0.first().map(|a| a.0.as_slice())
}

/// Wraps `EntryPointBuf` construction. Generated code references operation
/// names as string literals (e.g. `"increment"`) — this helper converts them
/// without exposing the `Vec<u8>` ceremony.
pub fn entry_point(name: &str) -> EntryPointBuf {
    EntryPointBuf(name.as_bytes().to_vec())
}

/// Constructs a `ContractState<D>` with the given state value and a set of
/// operation names (commonly the contract's circuit names). The maintenance
/// authority defaults to `ContractMaintenanceAuthority::default()` (empty
/// committee, threshold 1, counter 0).
pub fn new_contract_state<D: DB>(data: StateValue<D>, operations: &[&str]) -> ContractState<D> {
    let mut ops: HashMap<EntryPointBuf, ContractOperation, D> = HashMap::new();
    for name in operations {
        ops = ops.insert(entry_point(name), ContractOperation::new(None));
    }
    ContractState::new(data, ops, ContractMaintenanceAuthority::default())
}

/// Returns a reference to the inner `StateValue<D>` from a `QueryResults`
/// without the user remembering `.context.state.get_ref()`.
pub fn query_result_state<M, D>(r: &QueryResults<M, D>) -> &StateValue<D>
where
    M: ResultMode<D>,
    D: DB,
{
    r.context.state.get_ref()
}
