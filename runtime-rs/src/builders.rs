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
    AlignedValue, Alignment, AlignmentAtom, Array, ChargedState, ContractState, CostModel,
    QueryResults, ResultMode, StateValue, Value, ValueAtom, INITIAL_COST_MODEL, DB,
};
use midnight_onchain_state::state::{
    ContractMaintenanceAuthority, ContractOperation, EntryPointBuf,
};
use midnight_storage::storage::HashMap;
use midnight_transient_crypto::merkle_tree::MerkleTree;

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

/// Builds a `StateValue::Cell(...)` for a bounded-range unsigned integer
/// `Uint<L..U>`. The bit-width of the type is `ceil(log2(U+1))` and the
/// on-state byte-width is `ceil(bits/8)`, which does **not** always match
/// the underlying Rust integer width (e.g. `Uint<0..70000>` needs 17 bits =
/// 3 bytes, but is held in a `u32`). Mirrors TS's
/// `CompactTypeUnsignedInteger(maxValue, length).alignment()` path:
/// emits a single `AlignmentAtom::Bytes { length: byte_len }` atom with
/// the value's little-endian bytes, normalised (trailing zeros stripped)
/// by `ValueAtom::from(u128)`. Used by codegen for `Uint<L..U>` ledger
/// fields and call-site cell values where the byte-width diverges from
/// the Rust integer width.
pub fn new_cell_bounded_uint<D: DB>(value: u128, byte_len: usize) -> StateValue<D> {
    let atom = ValueAtom::from(value);
    let alignment = Alignment::singleton(AlignmentAtom::Bytes {
        length: byte_len as u32,
    });
    let av = AlignedValue::new(Value(vec![atom]), alignment)
        .expect("new_cell_bounded_uint: value exceeds declared byte_len");
    StateValue::from(av)
}

/// Builds a `StateValue::Cell(...)` from a fixed-size array `[T; N]` of
/// values each convertible to `AlignedValue`. Concatenates each element's
/// AlignedValue into one. Used by codegen for Vector<N, T> ledger fields
/// where `[T; N]: Into<AlignedValue>` isn't impl'd upstream — orphan rules
/// block us from adding that impl directly, so we provide this helper.
pub fn new_cell_array<T, D, const N: usize>(v: [T; N]) -> StateValue<D>
where
    D: DB,
    T: Into<AlignedValue> + Copy,
{
    let avs: Vec<AlignedValue> = v.iter().copied().map(Into::into).collect();
    let av = AlignedValue::concat(avs.iter());
    StateValue::from(av)
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

/// Builds an empty `StateValue::Map(...)` — the initial state for the
/// Compact `Map` and `Set` ADTs (see compiler/midnight-ledger.ss:
/// `(initial-value (state-value 'map ()))` for both).
pub fn new_map<D: DB>() -> StateValue<D> {
    StateValue::Map(HashMap::new())
}

/// Builds the initial `StateValue` for the Compact `List<T>` ADT: a 3-slot
/// array `[Null, Null, Cell(0u64)]` — i.e. an empty linked-list cell where
/// the first slot holds the head value (or Null when empty), the second
/// holds the tail-list (or Null), and the third holds the u64 length.
///
/// See compiler/midnight-ledger.ss:
///   (declare-ledger-adt List ([Type value_type])
///     (initial-value (state-value 'array ((state-value 'null)
///                                         (state-value 'null)
///                                         (state-value 'cell (align 0 8))))) ...)
pub fn new_list<D: DB>() -> StateValue<D> {
    new_array(vec![
        StateValue::Null,
        StateValue::Null,
        new_cell(0u64),
    ])
}

/// Builds an empty `StateValue::Array([BoundedMerkleTree(blank), Cell(0u64)])`
/// — the initial state for the Compact `MerkleTree<height, T>` ADT.
/// See compiler/midnight-ledger.ss:
///   (initial-value (state-value 'array ((state-value 'merkle-tree nat ())
///                                       (state-value 'cell (align 0 8)))))
pub fn new_merkle_tree<D: DB>(height: u8) -> StateValue<D> {
    let mt: MerkleTree<(), D> = MerkleTree::blank(height);
    new_array(vec![
        StateValue::BoundedMerkleTree(mt),
        new_cell(0u64),
    ])
}

/// Builds the initial `StateValue` for the Compact `HistoricMerkleTree<h, T>`
/// ADT: a 3-slot array containing `[BoundedMerkleTree(blank), Cell(0u64),
/// Map { root_of_blank_tree -> Null }]`.
///
/// Note: the TS frontend lowers `HistoricMerkleTree<h, T>` initial-state via
/// the on-chain VM by first creating the 3-slot array (with an *empty* history
/// map) and then explicitly inserting the blank tree's root into the history.
/// We do that final step here so the seeded `StateValue` is byte-identical to
/// what TS produces — see `examples/zerocash.compact` byte-parity test.
pub fn new_historic_merkle_tree<D: DB>(height: u8) -> StateValue<D> {
    let mt: MerkleTree<(), D> = MerkleTree::blank(height);
    let rehashed = mt.rehash();
    let root_digest = rehashed
        .root()
        .expect("blank merkle tree should have a root after rehash");
    // The on-chain ledger keys the history map by the digest's AlignedValue
    // encoding (one Fr cell, alignment derived from MerkleTreeDigest).
    let key: AlignedValue = AlignedValue::from(root_digest);
    let mut history: HashMap<AlignedValue, StateValue<D>, D> = HashMap::new();
    history = history.insert(key, StateValue::Null);
    new_array(vec![
        StateValue::BoundedMerkleTree(rehashed),
        new_cell(0u64),
        StateValue::Map(history),
    ])
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

#[cfg(test)]
mod tests {
    use super::*;
    use midnight_storage::db::InMemoryDB;

    #[test]
    fn new_map_is_empty_state_value_map() {
        let sv: StateValue<InMemoryDB> = new_map();
        match &sv {
            StateValue::Map(m) => assert_eq!(m.size(), 0),
            other => panic!("expected StateValue::Map, got {:?}", other),
        }
    }

    #[test]
    fn new_merkle_tree_has_blank_tree_and_zero_cursor() {
        let sv: StateValue<InMemoryDB> = new_merkle_tree(32);
        match &sv {
            StateValue::Array(arr) => {
                assert_eq!(arr.len(), 2);
            }
            other => panic!("expected StateValue::Array, got {:?}", other),
        }
    }

    #[test]
    fn new_list_has_three_slots_null_null_zero() {
        let sv: StateValue<InMemoryDB> = new_list();
        match &sv {
            StateValue::Array(arr) => {
                assert_eq!(arr.len(), 3);
                // slot 0 and 1 are Null, slot 2 is Cell(0u64)
                match arr.get(0) {
                    Some(StateValue::Null) => {}
                    other => panic!("expected slot 0 Null, got {:?}", other),
                }
                match arr.get(1) {
                    Some(StateValue::Null) => {}
                    other => panic!("expected slot 1 Null, got {:?}", other),
                }
                match arr.get(2) {
                    Some(StateValue::Cell(_)) => {}
                    other => panic!("expected slot 2 Cell, got {:?}", other),
                }
            }
            other => panic!("expected StateValue::Array, got {:?}", other),
        }
    }

    #[test]
    fn new_historic_merkle_tree_has_three_slots() {
        let sv: StateValue<InMemoryDB> = new_historic_merkle_tree(10);
        match &sv {
            StateValue::Array(arr) => {
                assert_eq!(arr.len(), 3);
            }
            other => panic!("expected StateValue::Array, got {:?}", other),
        }
    }
}
