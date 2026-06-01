// SPDX-License-Identifier: Apache-2.0
//
// list_fixture.compact byte-parity test — validates Iter 3 of the
// rust-codegen polish work.
//
// Drives the generated list-fixture crate through initial_state() and asserts
// the serialized ContractState matches the TS reference fixture captured by
// fixtures/capture-list-fixture.mjs.
//
// Purpose: provide a standalone List<T> row in the ADT matrix. The List<T>
// ADT's initial value is a 3-slot array `[Null, Null, Cell(0u64)]` — i.e.
// an empty linked-list cell where the first two slots hold head / tail
// references (or Null when empty) and the third holds the u64 length.
// See compiler/midnight-ledger.ss:798 for the canonical spec.
//
// The exported `ping` circuit body is intentionally trivial (writes
// `true` into a Boolean flag); pushFront / popFront / head / length /
// isEmpty method emission lands in a follow-up iteration.

use compact_contract_list_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/list-fixture-ts-state.json"
    ))
}

fn ctor_ctx() -> ConstructorContext<()> {
    ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL.clone(),
        gas_limit: None,
    }
}

/// Build a ContractState envelope around a freshly minted ChargedState.
/// list_fixture exports a single circuit `ping`, so the operations map
/// must register one entry under that name to match the TS-side
/// initialState() output.
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"ping".to_vec()),
        ContractOperation::new(None),
    );
    ContractState {
        data,
        operations,
        maintenance_authority: ContractMaintenanceAuthority::default(),
        balance: Default::default(),
    }
}

#[test]
fn list_fixture_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), NoWitnesses> = Contract::new(NoWitnesses);
    let result = contract.initial_state(ctor_ctx()).expect("initial_state");

    let envelope = make_envelope(result.current_contract_state.clone());
    let mut buf = Vec::new();
    tagged_serialize(&envelope, &mut buf).expect("tagged_serialize");

    let ts_bytes = ts_ref.after_init.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "Rust state bytes differ from TS reference\n\nRust ({} B): {}\n\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes),
    );
}
