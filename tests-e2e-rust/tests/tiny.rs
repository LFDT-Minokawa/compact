// SPDX-License-Identifier: Apache-2.0

// `passing a unit value to a function` fires throughout these tests
// because some fixtures have `PS = ()` (no private state), so the
// CircuitContext::new(state, ()) call deliberately threads a unit.
// The lint can't see that and the alternative (a phantom newtype) would
// be more confusing than the suppression.
#![allow(clippy::unit_arg)]
//
// tiny.compact multi-step byte-parity tests (M2 + M2.1 of the M3 plan).
//
// Sequence mirrored against fixtures/capture-tiny.mjs:
//   1. initial_state(42)  → state=1/set, value=42, authority=H([7;32])
//   2. clear              → state=0/unset, value=0, authority=0
//   3. set(99)            → state=1/set, value=99, authority=H([7;32])
//   4. get                → Maybe::some(99)
//
// Each impure step is byte-checked against the captured TS fixture.

use compact_contract_tiny::{ledger, Contract, Witnesses};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::{TinyStepSnapshot, TinyTsReferenceState};

/// Deterministic witness implementation matching the TS driver:
/// `private$secret_key` always returns a 32-byte constant 0x07.
struct TinyWitnesses;

impl Witnesses<()> for TinyWitnesses {
    fn private_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<compact_contract_tiny::Ledger<'a>, ()>,
    ) -> ((), [u8; 32]) {
        ((), [7u8; 32])
    }
}

fn fixture() -> TinyTsReferenceState {
    TinyTsReferenceState::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/tiny-ts-state.json"
    ))
}

fn fresh_contract() -> Contract<(), TinyWitnesses> {
    Contract::new(TinyWitnesses)
}

fn ctor_ctx() -> ConstructorContext<()> {
    ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL.clone(),
        gas_limit: None,
    }
}

/// Build a ContractState envelope around a freshly mutated
/// ChargedState, matching what tiny.compact's TS path produces:
/// data plus the canonical `(get, set, clear)` operations plus the
/// default maintenance authority plus an empty balance.
/// `tagged_serialize` then produces a byte-identical encoding to the
/// TS `.serialize()`.
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(EntryPointBuf(b"get".to_vec()), ContractOperation::new(None));
    operations = operations.insert(EntryPointBuf(b"set".to_vec()), ContractOperation::new(None));
    operations = operations.insert(
        EntryPointBuf(b"clear".to_vec()),
        ContractOperation::new(None),
    );
    ContractState {
        data,
        operations,
        maintenance_authority: ContractMaintenanceAuthority::default(),
        balance: Default::default(),
    }
}

fn assert_step_bytes_eq(
    label: &str,
    state: &ContractState<midnight_storage::DefaultDB>,
    expected: &TinyStepSnapshot,
) {
    let mut buf = Vec::new();
    tagged_serialize(state, &mut buf).expect("tagged_serialize");
    let ts_bytes = expected.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "[{label}] Rust state bytes differ from TS reference\n\nRust ({} B): {}\n\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes),
    );
}

#[test]
fn tiny_init_byte_parity() {
    let ts_ref = fixture();
    let contract = fresh_contract();
    let result = contract
        .initial_state(ctor_ctx(), Fr::from(42u64))
        .expect("initial_state");
    let envelope = make_envelope(result.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);

    // Cross-check the decoded ledger.value matches the fixture.
    let ledger_view = ledger(&result.current_contract_state);
    let decoded_value = ledger_view.value().expect("ledger value");
    let decoded_u128: u128 = decoded_value.try_into().expect("fits in u128");
    assert_eq!(decoded_u128.to_string(), ts_ref.after_init.ledger.value);
}

#[test]
fn tiny_init_then_clear_byte_parity() {
    let ts_ref = fixture();
    let contract = fresh_contract();
    let init = contract
        .initial_state(ctor_ctx(), Fr::from(42u64))
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let cleared = contract.clear(circ_ctx).expect("clear");
    let envelope = make_envelope(cleared.context.current_query_context.state.clone());
    assert_step_bytes_eq("clear", &envelope, &ts_ref.after_clear);

    let ledger_view = ledger(&cleared.context.current_query_context.state);
    let decoded_value = ledger_view.value().expect("ledger value");
    let decoded_u128: u128 = decoded_value.try_into().expect("fits in u128");
    assert_eq!(decoded_u128.to_string(), ts_ref.after_clear.ledger.value);
}

#[test]
fn tiny_init_clear_set_byte_parity() {
    let ts_ref = fixture();
    let contract = fresh_contract();
    let init = contract
        .initial_state(ctor_ctx(), Fr::from(42u64))
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let cleared = contract.clear(circ_ctx).expect("clear");
    let after_set = contract.set(cleared.context, Fr::from(99u64)).expect("set");
    let envelope = make_envelope(after_set.context.current_query_context.state.clone());
    assert_step_bytes_eq("set99", &envelope, &ts_ref.after_set_99);

    let ledger_view = ledger(&after_set.context.current_query_context.state);
    let decoded_value = ledger_view.value().expect("ledger value");
    let decoded_u128: u128 = decoded_value.try_into().expect("fits in u128");
    assert_eq!(decoded_u128.to_string(), ts_ref.after_set_99.ledger.value);
}

#[test]
fn tiny_get_returns_maybe_some_99() {
    let ts_ref = fixture();
    let contract = fresh_contract();
    let init = contract
        .initial_state(ctor_ctx(), Fr::from(42u64))
        .expect("initial_state");
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let cleared = contract.clear(circ_ctx).expect("clear");
    let after_set = contract.set(cleared.context, Fr::from(99u64)).expect("set");
    let got = contract.get(after_set.context).expect("get");

    // The Rust Maybe<Fr> mirrors the TS {is_some, value} shape.
    assert_eq!(got.result.is_some, ts_ref.get_result.is_some);
    let decoded_u128: u128 = got.result.value.try_into().expect("fits in u128");
    assert_eq!(decoded_u128.to_string(), ts_ref.get_result.value);
}
