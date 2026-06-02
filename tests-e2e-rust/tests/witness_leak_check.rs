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

// `passing a unit value to a function` fires throughout these tests
// because tiny.compact has `PS = ()` (no private state), so the
// CircuitContext::new(state, ()) call deliberately threads a unit.
#![allow(clippy::unit_arg)]
//
// Prod-11: negative witness-threading regression test.
//
// The Prod-8 audit (docs/superpowers/research/2026-06-02-witness-threading-audit.md)
// verified by code review that private state (PS) values cannot leak
// into the serialised `ContractState` bytes. This test pins that
// invariant down operationally: the tiny.compact witness returns the
// sentinel secret key `[0x07; 32]`, and we assert that this 32-byte
// pattern (and a less-strict 16-byte prefix) never appears as a
// contiguous subsequence in the serialised state after any step.
//
// If a future codegen change ever pushed a witness return value into
// an `OpProgramVerify`/`new_cell(...)` op, this test would fail with
// the leaked offset, making the regression easy to bisect.

use compact_contract_tiny::{Contract, Witnesses};
use compact_runtime::*;
use midnight_serialize::tagged_serialize;
use midnight_storage::storage::HashMap;

const SK_SENTINEL_32: [u8; 32] = [0x07; 32];
const SK_SENTINEL_16: [u8; 16] = [0x07; 16];

struct TinyWitnesses;

impl Witnesses<()> for TinyWitnesses {
    fn private_secret_key<'a>(
        &self,
        _ctx: &WitnessContext<compact_contract_tiny::Ledger<'a>, ()>,
    ) -> ((), [u8; 32]) {
        ((), SK_SENTINEL_32)
    }
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

fn assert_no_sentinel(label: &str, bytes: &[u8], sentinel: &[u8]) {
    let found = bytes.windows(sentinel.len()).any(|w| w == sentinel);
    assert!(
        !found,
        "[{label}] witness sentinel ({} bytes of 0x07) found in serialized ContractState — \
         private data leaked!\n\nstate ({} B): {}",
        sentinel.len(),
        bytes.len(),
        hex::encode(bytes),
    );
}

fn serialize_envelope(state: &ContractState<midnight_storage::DefaultDB>) -> Vec<u8> {
    let mut buf = Vec::new();
    tagged_serialize(state, &mut buf).expect("tagged_serialize");
    buf
}

fn check_step(label: &str, state: &ContractState<midnight_storage::DefaultDB>) {
    let buf = serialize_envelope(state);
    // Strict: full 32-byte sentinel must not appear.
    assert_no_sentinel(label, &buf, &SK_SENTINEL_32);
    // Less-strict: even a 16-byte run of 0x07 would be highly suspicious
    // — a partial leak or a corrupted hash preimage.
    assert_no_sentinel(label, &buf, &SK_SENTINEL_16);
}

#[test]
fn tiny_witness_secret_key_does_not_leak_into_serialised_state() {
    let contract = fresh_contract();

    // 1. initial_state(42) — authority is H([7;32]), preimage must not appear.
    let init = contract
        .initial_state(ctor_ctx(), Fr::from(42u64))
        .expect("initial_state");
    let init_env = make_envelope(init.current_contract_state.clone());
    check_step("init", &init_env);

    // 2. clear — authority cleared to zero, sentinel must still be absent.
    let circ_ctx = CircuitContext::new(init.current_contract_state, init.current_private_state);
    let cleared = contract.clear(circ_ctx).expect("clear");
    let clear_env = make_envelope(cleared.context.current_query_context.state.clone());
    check_step("clear", &clear_env);

    // 3. set(99) — re-derives the authority hash; preimage still must not appear.
    let after_set = contract.set(cleared.context, Fr::from(99u64)).expect("set");
    let set_env = make_envelope(after_set.context.current_query_context.state.clone());
    check_step("set", &set_env);

    // 4. get — pure read; state unchanged, but re-serialise and re-check.
    let got = contract.get(after_set.context).expect("get");
    let get_env = make_envelope(got.context.current_query_context.state.clone());
    check_step("get", &get_env);

    // Sanity: serialised state is non-trivial in size — guards against the
    // assertion vacuously passing on an empty buffer if the API ever changes.
    assert!(
        serialize_envelope(&set_env).len() > SK_SENTINEL_32.len(),
        "serialised state shorter than the sentinel — check is vacuous"
    );
}
