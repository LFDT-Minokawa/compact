// SPDX-License-Identifier: Apache-2.0
//
// set_fixture.compact byte-parity test — validates F1.2/2 of the M3.5 plan.
//
// Drives the generated set-fixture crate through initial_state() and asserts
// the serialized ContractState matches the TS reference fixture captured by
// fixtures/capture-set-fixture.mjs.
//
// Purpose: provide a standalone Set<T> row in the M3.5 ADT matrix and
// exercise the F1.2/2 "ADT-read-with-arg" gather lowering end-to-end.
// The exported `check(x: Field)` circuit body invokes `s.member(x)`,
// which the rust-passes emitter lowers into an `OpProgramGather` chain
// (dup / idx / push / member / popeq) — this code path lit up by the
// `fb0c724` infrastructure work but previously had no purpose-built
// fixture covering it.
//
// The compile-time visibility into the emitted body comes from the
// fact that `compact_contract_set_fixture::Contract::check` must
// type-check; this asserts the F1.2/2 builder methods (`.push()`,
// `.member()`) resolve and that the surrounding ledger-read shape
// remains stable.

use compact_contract_set_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/set-fixture-ts-state.json"
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
/// set_fixture exports a single circuit `check`, so the operations map
/// must register one entry under that name to match the TS-side
/// initialState() output.
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"check".to_vec()),
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
fn set_fixture_init_byte_parity() {
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
