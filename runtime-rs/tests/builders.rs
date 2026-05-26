// SPDX-License-Identifier: Apache-2.0
//
// Smoke tests for the ergonomic helpers in compact-runtime::builders and
// compact-runtime::query. One happy-path test per helper.

use compact_runtime::std_lib::{
    decode_u128, decode_u16, decode_u32, decode_u64, decode_u8, serialize_contract_state,
};
use compact_runtime::*;

#[test]
fn initial_cost_model_matches_constant() {
    let cm = initial_cost_model();
    // Comparing against the constant via debug equality.
    assert_eq!(format!("{cm:?}"), format!("{:?}", INITIAL_COST_MODEL));
}

#[test]
fn empty_charged_state_wraps_null() {
    let cs: ChargedState<DefaultDB> = empty_charged_state();
    assert!(matches!(cs.get_ref(), StateValue::Null));
}

#[test]
fn new_cell_builds_state_value_cell() {
    let sv: StateValue<DefaultDB> = new_cell(42u64);
    assert!(matches!(sv, StateValue::Cell(_)));
}

#[test]
fn new_array_builds_state_value_array_with_items() {
    let sv: StateValue<DefaultDB> = new_array(vec![new_cell(1u64), new_cell(2u64)]);
    match &sv {
        StateValue::Array(a) => assert_eq!(a.len(), 2),
        _ => panic!("expected StateValue::Array"),
    }
}

#[test]
fn new_empty_array_is_empty() {
    let sv: StateValue<DefaultDB> = new_empty_array();
    match &sv {
        StateValue::Array(a) => assert_eq!(a.len(), 0),
        _ => panic!("expected StateValue::Array"),
    }
}

#[test]
fn aligned_bytes_returns_first_atom_bytes() {
    let av = AlignedValue::from(0x42u64);
    let bytes = aligned_bytes(&av).expect("non-empty atom");
    assert_eq!(bytes[0], 0x42);
}

#[test]
fn entry_point_encodes_name_bytes() {
    let ep = entry_point("increment");
    assert_eq!(ep.0, b"increment".to_vec());
}

#[test]
fn new_contract_state_includes_operations() {
    let data: StateValue<DefaultDB> = new_array(vec![new_cell(0u64)]);
    let cs: ContractState<DefaultDB> = new_contract_state(data, &["increment"]);
    assert_eq!(cs.operations.size(), 1);
    let serialized = serialize_contract_state(&cs).expect("serialize");
    assert!(!serialized.is_empty());
}

#[test]
fn query_for_read_emits_read_events_for_popeq() {
    // Build a single-cell state then read via dup+popeq.
    let sv: StateValue = new_cell(7u64);
    let qctx: QueryContext<DefaultDB> =
        QueryContext::new(ChargedState::new(sv), ContractAddress::default());
    let ops: Vec<Op<ResultModeGather>> = vec![
        Op::Dup { n: 0 },
        Op::Popeq {
            cached: true,
            result: (),
        },
    ];
    let res = query_for_read(&qctx, &ops, None, &initial_cost_model()).expect("query ok");
    // events should carry one Read with our value.
    let av = match res.events.last() {
        Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av.clone(),
        other => panic!("expected Read event, got {other:?}"),
    };
    assert_eq!(decode_u64(&av).unwrap(), 7);
}

#[test]
fn query_for_verify_runs_noop() {
    // Verify mode on a single-cell state with a noop (dup+pop) — this won't
    // emit events; we just exercise the wrapper.
    let sv: StateValue = new_cell(0u64);
    let qctx: QueryContext<DefaultDB> =
        QueryContext::new(ChargedState::new(sv), ContractAddress::default());
    let ops: Vec<Op<ResultModeVerify>> = vec![Op::Noop { n: 0 }];
    let res = query_for_verify(&qctx, &ops, None, &initial_cost_model()).expect("query ok");
    let _state_ref: &StateValue = query_result_state(&res);
}

#[test]
fn decode_family_handles_all_widths() {
    assert_eq!(decode_u8(&AlignedValue::from(0xABu8)).unwrap(), 0xAB);
    assert_eq!(decode_u16(&AlignedValue::from(0xABCDu16)).unwrap(), 0xABCD);
    assert_eq!(
        decode_u32(&AlignedValue::from(0xDEADBEEFu32)).unwrap(),
        0xDEADBEEF
    );
    assert_eq!(
        decode_u64(&AlignedValue::from(0xDEADBEEFCAFEBABEu64)).unwrap(),
        0xDEADBEEFCAFEBABE
    );
    assert_eq!(
        decode_u128(&AlignedValue::from(0x0123456789ABCDEFu128)).unwrap(),
        0x0123456789ABCDEF
    );
}
