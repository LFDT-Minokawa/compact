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
// Prod-5a: sealed_ledger_fixture.compact byte-parity test.
//
// Compact's `sealed ledger NAME: T;` declares a ledger field that is
// writable only from the constructor (or `pure` setup circuits) — it
// is type-checked write-protected for non-pure circuits. At the
// StateValue / AlignedValue layer it serializes identically to a
// regular ledger field; the frontend enforces the no-write rule.
//
// This test locks in two invariants:
//   1. The constructor writes the sealed fields (Field admin = 42,
//      Bytes<32> contract_id = pad(32, "lares:sealed:demo"),
//      Uint<64> created_at = 12345) and the resulting ContractState
//      bytes match the TS reference. The Bytes<32> case is the Prod-15
//      regression — a prior diagnostic had claimed an on-wire
//      Bytes<L>-from-pad encoding divergence; byte-parity here pins
//      the disposition that the encoding actually matches.
//   2. A non-sealed `flag` field declared alongside the sealed fields
//      is still writable end-to-end via the `ping` circuit.
//
// Two byte-parity steps mirrored against
// fixtures/capture-sealed-ledger-fixture.mjs:
//   - afterInit: ContractState after initial_state()
//   - afterPing: ContractState after ping()

use compact_contract_sealed_ledger_fixture::Contract;
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
struct SealedLedgerTsReference {
    #[serde(rename = "afterInit")]
    after_init: StepSnapshot,
    #[serde(rename = "afterPing")]
    after_ping: StepSnapshot,
}

fn fixture() -> SealedLedgerTsReference {
    let path = concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/fixtures/sealed-ledger-fixture-ts-state.json"
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

/// sealed_ledger_fixture exports one circuit `ping`.
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
fn sealed_ledger_fixture_init_then_ping_byte_parity() {
    let ts_ref = fixture();
    let contract: Contract<(), NoWitnesses> = Contract::new(NoWitnesses);

    // Step 1: initial_state — constructor writes the sealed `admin` field.
    let init = contract.initial_state(ctor_ctx()).expect("initial_state");
    let envelope = make_envelope(init.current_contract_state.clone());
    assert_step_bytes_eq("init", &envelope, &ts_ref.after_init);

    // Step 2: ping — writes the regular `flag` field next to the
    // already-initialized sealed field.
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let after_ping = contract.ping(circ_ctx).expect("ping");
    let envelope = make_envelope(after_ping.context.current_query_context.state.clone());
    assert_step_bytes_eq("ping", &envelope, &ts_ref.after_ping);
}
