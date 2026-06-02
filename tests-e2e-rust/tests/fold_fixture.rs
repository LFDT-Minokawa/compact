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
// fold_fixture.compact byte-parity test — validates Iter 6 of the
// rust-codegen polish work (fold with loop-var substitution).
//
// Drives the generated fold-fixture crate through initial_state()
// and asserts the serialized ContractState matches the TS reference
// fixture captured by fixtures/capture-fold-fixture.mjs.
//
// Purpose: validate the fold body's per-iteration loop-variable
// substitution. The Compact source constructor iterates a literal
// `Uint<16>[3]` array of `[1, 2, 3]` and calls `c.increment(x)` on
// each iteration; the emitter must materialise the i-th literal as
// the addi-immediate at each unroll step, so the OpProgramVerify
// chain is `addi(1) … addi(2) … addi(3)` (NOT three identical
// `addi(1)` calls as Iter 5 would have produced). The TS-side
// `_folder_0` runs the equivalent semantics and the captured
// `currentContractState.serialize()` reflects a Counter value of 6.
//
// The `ping` circuit is a no-op `.increment(0)` placeholder
// satisfying the at-least-one-exported-circuit invariant.

use compact_contract_fold_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use tests_e2e_rust::SmallFixtureTsReference;

fn fixture() -> SmallFixtureTsReference {
    SmallFixtureTsReference::load(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/fold-fixture-ts-state.json"
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
/// fold_fixture exports a single circuit `ping`, so the operations map
/// must register one entry under that name to match the TS-side
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
fn fold_fixture_init_byte_parity() {
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
