// SPDX-License-Identifier: Apache-2.0
//
// for_iter_fixture.compact byte-parity test — validates Iter 5 of the
// rust-codegen polish work.
//
// Drives the generated for-iter-fixture crate through initial_state()
// and asserts the serialized ContractState matches the TS reference
// fixture captured by fixtures/capture-for-iter-fixture.mjs.
//
// Purpose: validate the for-iterable loop emission MVP. The Compact
// source constructor seeds a Counter ledger field to 5 via a literal
// `for (const _ of [1, 2, 3, 4, 5]) { c.increment(1); }` loop; the
// frontend desugars the iteration to a `(fold ...)` IR node whose
// body's accumulator is threaded through unchanged. The emitter
// compile-time unrolls the body's builder lines (.idx_at_index/.addi/
// .ins) five times into a single OpProgramVerify chain, which mirrors
// the VM state mutation the TS-side _folder_0 helper produces.

use compact_contract_for_iter_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/for-iter-fixture-ts-state.json"
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
/// for_iter_fixture exports a single circuit `ping`, so the operations
/// map must register one entry under that name to match the TS-side
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
fn for_iter_fixture_init_byte_parity() {
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
