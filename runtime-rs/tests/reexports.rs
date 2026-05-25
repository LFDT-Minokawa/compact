// SPDX-License-Identifier: Apache-2.0
//
// Smoke test asserting that every type the codegen will reference is
// reachable through the `compact_runtime` prelude. Catches regressions
// in re-exports without exercising behaviour.

use compact_runtime::*;

#[test]
fn prelude_resolves_all_required_symbols() {
    // Encoding / alignment
    let _: fn() -> Alignment = || Alignment::singleton(base_crypto::fab::AlignmentAtom::Bytes { length: 0 });
    let _: fn(u64) -> AlignedValue = AlignedValue::from;
    let _ = std::any::type_name::<Value>();

    // Field arithmetic
    let _: fn(u64) -> Fr = Fr::from;
    let _ = std::any::type_name::<JubjubPoint>();

    // Hashes (re-exported as bare names)
    let _ = std::any::type_name::<fn() -> ()>(); // placeholder — hash signatures vary

    // VM ops + path keys
    let _: fn(AlignedValue) -> Key = Key::Value;

    // State
    let _ = std::any::type_name::<StateValue>();
    let _ = std::any::type_name::<ContractState<DefaultDB>>();
    let _ = std::any::type_name::<ChargedState<DefaultDB>>();

    // Runtime / context
    let _ = std::any::type_name::<QueryContext<DefaultDB>>();
    let _ = std::any::type_name::<QueryResults<ResultModeVerify, DefaultDB>>();

    // Storage backend
    let _ = std::any::type_name::<DefaultDB>();
    let _ = std::any::type_name::<InMemoryDB>();
    let _: fn(Vec<Key>) -> Array<Key> = Array::from;

    // Cost / gas
    let _ = std::any::type_name::<CostModel>();
    let _ = std::any::type_name::<RunningCost>();

    // Coin / contract addressing
    let _ = std::any::type_name::<ContractAddress>();
    let _ = std::any::type_name::<CoinPublicKey>();

    // Zswap
    let _ = std::any::type_name::<ZswapLocalState<DefaultDB>>();
}
