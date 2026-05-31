// SPDX-License-Identifier: Apache-2.0
//
// witnesses_fixture.compact byte-parity test (F7 of the M3.5 plan).
//
// Drives the generated witnesses-fixture crate through initial_state() and
// asserts the serialized ContractState matches the TS reference fixture
// captured by fixtures/capture-witnesses-fixture.mjs.
//
// Exercises witness trait emission. The fixture declares three witnesses:
//   - witness fetch_field(): Field;
//   - witness fetch_maybe(): Maybe<Field>;
//   - witness echo(x: Field): Field;
// but only `fetch_field` is referenced from an export circuit; the frontend
// drops the other two from the emitted Witnesses<PS> trait. We assert the
// init-state byte shape matches TS, since initial_state() doesn't invoke any
// witnesses regardless.

use compact_contract_witnesses_fixture::{Contract, Ledger, Witnesses};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

/// Deterministic Witnesses impl. fetch_field is the only witness in the
/// emitted trait (Maybe-return and arg-taking declarations were
/// dead-code-eliminated by the frontend since they're never called).
struct FixtureWitnesses;

impl Witnesses<()> for FixtureWitnesses {
    fn fetch_field<'a>(&self, _ctx: &WitnessContext<Ledger<'a>, ()>) -> ((), Fr) {
        ((), Fr::from(42u64))
    }
}

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/witnesses-fixture-ts-state.json"
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

/// witnesses_fixture exports a single circuit `pull`.
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"pull".to_vec()),
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
fn witnesses_fixture_init_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), FixtureWitnesses> = Contract::new(FixtureWitnesses);
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
