// SPDX-License-Identifier: Apache-2.0
//
// tiny.compact byte-parity test (M2 of the M3 plan).
//
// 1. Drive the generated tiny.compact Rust crate through
//    `initial_state(ctx, 42)` with a deterministic
//    `private_secret_key` witness that returns [7u8; 32] — matching
//    the TS driver in fixtures/capture-tiny.mjs.
// 2. Wrap the resulting `ChargedState` into a full `ContractState`
//    envelope with operations entries for each impure circuit
//    (`set`, `get`, `clear`) — same shape TS produces.
// 3. `tagged_serialize` and assert byte-equality against the TS
//    reference fixture captured in M1.
// 4. Cross-check the decoded `ledger().value()` matches the
//    fixture's `ledger.value` string.

use compact_contract_tiny::{ledger, Contract, Witnesses};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::TinyTsReferenceState;

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

#[test]
fn tiny_init_byte_parity() {
    let ts_ref = TinyTsReferenceState::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/tiny-ts-state.json"
    ));

    // 1. Build the Contract with the deterministic witness.
    let contract: Contract<(), TinyWitnesses> = Contract::new(TinyWitnesses);

    // 2. Build the ConstructorContext — empty private state + a
    //    default-initialised empty Zswap local state.
    let ctx: ConstructorContext<()> = ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL.clone(),
        gas_limit: None,
    };

    // 3. Run initial_state with v=42 (matches TS `42n`).
    let v = Fr::from(42u64);
    let result = contract.initial_state(ctx, v).expect("initial_state");

    // 4. The post-state is in result.current_contract_state.
    let post_state = &result.current_contract_state;
    let post_state_value = post_state.get().clone();

    // 5. Build the ContractState envelope. tiny.compact registers
    //    operations for each impure circuit: set, get, clear. The
    //    order in the fixture matters because HashMap iteration
    //    order is hash-bucket order, not insertion order — but
    //    `ContractState::serialize` (TS) and `tagged_serialize`
    //    (Rust) iterate in canonical key order, so any insertion
    //    order works.
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"get".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"set".to_vec()),
        ContractOperation::new(None),
    );
    operations = operations.insert(
        EntryPointBuf(b"clear".to_vec()),
        ContractOperation::new(None),
    );

    let contract_state: ContractState<midnight_storage::DefaultDB> = ContractState {
        data: post_state.clone(),
        operations,
        maintenance_authority: ContractMaintenanceAuthority::default(),
        balance: Default::default(),
    };

    // 6. Serialize via tagged_serialize (matches TS .serialize()).
    let mut buf = Vec::new();
    tagged_serialize(&contract_state, &mut buf).expect("tagged_serialize");

    let ts_bytes = ts_ref.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "Rust state bytes differ from TS reference\n\nRust ({} B): {}\n\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes),
    );

    // 7. Cross-check the decoded ledger.value matches the fixture.
    //    Fr's `Display` formats as hex, but the TS BigInt.toString()
    //    in the fixture is decimal — so convert via u128 (42 fits
    //    trivially; this is a sanity check, not a parity claim).
    let ledger_view = ledger(post_state);
    let decoded_value = ledger_view.value().expect("ledger value");
    let decoded_u128: u128 = decoded_value
        .try_into()
        .expect("ledger.value should fit in u128 for this fixture");
    assert_eq!(decoded_u128.to_string(), ts_ref.ledger.value);
    let _ = post_state_value; // silence unused warning when assertions short-circuit
}
