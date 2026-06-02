// SPDX-License-Identifier: Apache-2.0
//
// if_stmt_fixture.compact byte-parity test (F8 of the M3.5 plan).
//
// Drives the generated if-stmt-fixture crate through initial_state() and
// asserts the serialized ContractState matches the TS reference fixture
// captured by fixtures/capture-if-stmt-fixture.mjs.
//
// The fixture exists to exercise E6's statement-position if-then-else
// emission via an exported `pure circuit classify(b: Boolean): Boolean`
// whose body is `if (b) { return false; } else { return true; }`. The
// byte-parity assertion below only checks the initial_state seed; the
// classify body is emitted (and compiled) but not invoked here.
//
// The contract has one exported circuit (`classify`), but it is pure, so
// it lives in `pure_circuits` and is not part of the dispatch operations
// map — that map stays empty.

use compact_contract_if_stmt_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/if-stmt-fixture-ts-state.json"
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

fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    ContractState {
        data,
        operations,
        maintenance_authority: ContractMaintenanceAuthority::default(),
        balance: Default::default(),
    }
}

#[test]
fn if_stmt_fixture_init_byte_parity() {
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

#[test]
fn if_stmt_fixture_classify_body_compiles() {
    // Sanity-check that the E6-emitted classify body compiles and behaves
    // as expected. This invokes the pure circuit directly; it does not
    // touch the byte-parity machinery.
    use compact_contract_if_stmt_fixture::pure_circuits::classify;
    // assert_eq!(_, true/false) is the literal `is X equal to true/false?`
    // here, deliberately mirroring the Compact `classify` circuit's
    // boolean negation contract; `assert!` / `assert!(!_)` would lose
    // the symmetry. Suppress clippy's nudge to switch.
    #[allow(clippy::bool_assert_comparison)]
    {
        assert_eq!(classify(true), false);
        assert_eq!(classify(false), true);
    }
}
