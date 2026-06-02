// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//  	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

//
// Iter-9: pure_circuit_fixture.compact byte-parity + direct-invocation
// test for the standalone pure-circuit fixture.
//
// The fixture exists to exercise the `pure circuit` modifier across
// shapes that the existing if_stmt_fixture (single-arg `classify`)
// doesn't already cover:
//   - multi-argument pure circuit returning Boolean (`and_b`)
//   - pure circuit returning a non-Boolean primitive (`which_u32` →
//     Uint<32>) via an if-expression
//
// Three assertions:
//   1. `initial_state()` produces a ContractState whose serialized
//      bytes match the TS reference. The state has one Boolean ledger
//      slot (`flag`) and one operations-map entry (`ping`); the pure
//      circuits live in `pure_circuits` and contribute NOTHING to the
//      on-chain state shape.
//   2. `and_b(a, b)` direct-invocation truth table matches Boolean AND.
//   3. `which_u32(b)` direct-invocation maps true → 1u32, false → 0u32.

use compact_contract_pure_circuit_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/pure-circuit-fixture-ts-state.json"
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
fn pure_circuit_fixture_init_byte_parity() {
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
fn pure_circuit_fixture_and_b_truth_table() {
    // Multi-argument pure circuit returning Boolean. Body is `if (a)
    // return b; else return false;` — i.e. logical AND. The direct
    // invocation goes through the emitted `pure_circuits::and_b` fn
    // (no contract context, no ledger access).
    use compact_contract_pure_circuit_fixture::pure_circuits::and_b;
    #[allow(clippy::bool_assert_comparison)]
    {
        assert_eq!(and_b(true, true), true);
        assert_eq!(and_b(true, false), false);
        assert_eq!(and_b(false, true), false);
        assert_eq!(and_b(false, false), false);
    }
}

#[test]
fn pure_circuit_fixture_which_u32_branches() {
    // Pure circuit returning Uint<32> via an if-expression with
    // integer-literal branch values. Confirms that the integer-typed
    // pure-circuit return path round-trips through compactc --rust
    // for both branches.
    use compact_contract_pure_circuit_fixture::pure_circuits::which_u32;
    assert_eq!(which_u32(true), 1u32);
    assert_eq!(which_u32(false), 0u32);
}
