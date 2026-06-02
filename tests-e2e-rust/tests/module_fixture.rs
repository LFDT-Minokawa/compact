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

#![allow(clippy::unit_arg)]
//
// Iter 10: module_fixture.compact byte-parity test.
//
// Compact's frontend pass `expand-modules-and-types` (at
// compiler/analysis-passes.ss:43) inlines a module's exported
// declarations into the importing program before the IR reaches
// Ltypescript. The `Lexpanded` language definition at
// compiler/langs.ss:529-535 strips the `(module ...)` and
// `(import ...)` nonterminals — so by the time the Rust codegen runs,
// every `module M { ... }` and `import M;` form has been desugared
// away into flat top-level declarations. There is no module-specific
// codegen code path: the emitter sees only flat circuits and ledger
// fields.
//
// This test locks the invariant in via byte-parity:
//   1. afterInit:      ContractState after initial_state() — proves
//                      the module's `inner_count` field lands at the
//                      same flat slot index as a top-level field.
//   2. afterBumpInner: ContractState after bump_inner() — proves a
//                      circuit defined inside the module is emitted
//                      as a flat method on `Contract` and mutates the
//                      shared ledger correctly.
//
// Mirrors Iter 11's analogous finding for generic circuits, where the
// same frontend pass monomorphises type parameters before codegen.

use compact_contract_module_fixture::Contract;
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;
use serde::Deserialize;

#[derive(Deserialize, Debug)]
struct StepSnapshot {
    #[serde(rename = "stateHex")]
    state_hex: String,
}

impl StepSnapshot {
    fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}

#[derive(Deserialize, Debug)]
struct ModuleFixtureTsReference {
    #[serde(rename = "afterInit")]
    after_init: StepSnapshot,
    #[serde(rename = "afterBumpInner")]
    after_bump_inner: StepSnapshot,
}

fn fixture() -> ModuleFixtureTsReference {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/module-fixture-ts-state.json"
    );
    let raw = std::fs::read_to_string(path).expect("read fixture");
    serde_json::from_str(&raw).expect("parse fixture")
}

fn ctor_ctx() -> ConstructorContext<()> {
    ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL.clone(),
        gas_limit: None,
    }
}

/// module_fixture exports one circuit `bump_inner` (re-exported from
/// `module M`).
fn make_envelope(
    data: ChargedState<midnight_storage::DefaultDB>,
) -> ContractState<midnight_storage::DefaultDB> {
    let mut operations: HashMap<EntryPointBuf, ContractOperation, midnight_storage::DefaultDB> =
        HashMap::new();
    operations = operations.insert(
        EntryPointBuf(b"bump_inner".to_vec()),
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
    expected: &StepSnapshot,
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
fn module_fixture_init_then_bump_inner_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), NoWitnesses> = Contract::new(NoWitnesses);

    // Step 1: initial_state — constructor sets the top-level
    // `outer_flag = true`. The module's `inner_count` field is the
    // default `Counter` value (0). Both fields share a flat layout.
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let envelope = make_envelope(init.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);

    // Step 2: bump_inner — mutates the module-declared `inner_count`
    // through a flat method on `Contract`. The module boundary is
    // invisible at this layer.
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_bump = contract.bump_inner(circ_ctx).expect("bump_inner");
    let envelope = make_envelope(after_bump.context.current_query_context.state.clone());
    assert_step_bytes_eq("bump_inner", &envelope, &ts_ref.after_bump_inner);
}
