// SPDX-License-Identifier: Apache-2.0
//
// Counter.compact byte-parity test.
//
// 1. Drive the Rust runtime through the same Op sequence the emitter
//    produces for counter.compact (init + one increment).
// 2. Build a full ContractState containing the post-increment StateValue
//    (matching what TS `cr.encode(currentQueryContext.state)` serializes).
// 3. Compare byte-for-byte against the TS reference
//    (fixtures/counter-ts-state.json), using `tagged_serialize` (the TS
//    `encode()` writes a tag-prefixed canonical envelope).
// 4. Cross-check the decoded Counter value matches the TS counterValue.
//
// This is the v1 correctness signal. If it stays green, the Rust path
// reproduces TS state transitions for counter.compact.

use compact_runtime::std_lib::Counter;
use compact_runtime::*;
use midnight_onchain_state::state::{
    ContractMaintenanceAuthority, ContractOperation, EntryPointBuf,
};
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::TsReferenceState;

#[test]
fn counter_init_plus_increment_byte_parity() {
    // Step 1: reproduce the TS init+increment sequence in Rust.
    // initialState builds StateValue::Array with a single Cell(0u64) at idx 0.
    let initial = StateValue::Array(
        Array::<StateValue, _>::new().push(StateValue::from(AlignedValue::from(0u64))),
    );
    let state = ChargedState::new(initial);
    let qctx = QueryContext::new(state, ContractAddress::default());

    // Op sequence for `round.increment(1)` (matches runtime-rs integration test).
    let ops: Vec<Op<ResultModeVerify>> = vec![
        Op::Idx {
            cached: false,
            push_path: true,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Addi { immediate: 1 },
        Op::Ins { cached: true, n: 1 },
    ];
    let results = qctx.query(&ops, None, &INITIAL_COST_MODEL).expect("query");
    let post_state = results.context.state; // ChargedState<DefaultDB>
    let post_state_value = post_state.get_ref().clone();

    // Step 2: build the full ContractState envelope that TS encodes.
    // TS path: c.initialState() registers operations for each circuit; the
    // counter.compact contract has one circuit "increment". The maintenance
    // authority defaults to empty.
    let mut operations: HashMap<EntryPointBuf, ContractOperation, DefaultDB> = HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"increment".to_vec()),
        ContractOperation::new(None),
    );
    let contract_state: ContractState<DefaultDB> = ContractState::new(
        post_state_value.clone(),
        operations,
        ContractMaintenanceAuthority::default(),
    );

    // Step 3: serialize via tagged_serialize (matches TS cr.encode envelope).
    let mut buf = Vec::new();
    tagged_serialize(&contract_state, &mut buf).expect("tagged_serialize");

    // Step 4: load TS reference + compare.
    let fixture_path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/counter-ts-state.json"
    );
    let ts_ref = TsReferenceState::load(fixture_path);
    let ts_bytes = ts_ref.state_bytes();
    assert_eq!(
        buf,
        ts_bytes,
        "Rust state bytes differ from TS reference.\nRust ({} B): {}\nTS   ({} B): {}",
        buf.len(),
        hex::encode(&buf),
        ts_bytes.len(),
        hex::encode(&ts_bytes)
    );

    // Step 5: cross-check counter value matches what TS reported.
    let arr = match &post_state_value {
        StateValue::Array(a) => a,
        _ => panic!("expected Array"),
    };
    let cell = arr.get(0).expect("first elem");
    let val = Counter::decode_from(cell).expect("decode");
    let ts_val: u64 = ts_ref.counter_value.parse().expect("parse u64");
    assert_eq!(val, ts_val);
}
