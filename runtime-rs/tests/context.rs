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

use compact_runtime::*;

// Upstream API gotchas vs. the plan's test body:
//   - `ChargedState` has no `Default` impl — only `ChargedState::new(StateValue)`.
//     We pass `StateValue::Null` (which is `StateValue`'s default variant).
//   - `CostModel` has no `initial()` associated function — upstream exposes
//     a `pub const INITIAL_COST_MODEL: CostModel` in
//     `midnight_onchain_vm::cost_model`. We reach for it via the
//     `onchain_vm` re-export of the parent crate.

#[test]
fn circuit_context_can_be_constructed() {
    let qctx = QueryContext::new(
        ChargedState::new(StateValue::Null),
        ContractAddress::default(),
    );
    let ctx: CircuitContext<()> = CircuitContext {
        current_private_state: (),
        current_query_context: qctx,
        current_zswap_local_state: ZswapLocalState::default(),
        cost_model: onchain_vm::cost_model::INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _ = ctx.cost_model;
}

#[test]
fn constructor_context_can_be_constructed() {
    let cctx: ConstructorContext<()> = ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: onchain_vm::cost_model::INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _ = cctx.cost_model;
}

#[test]
fn circuit_results_can_be_constructed() {
    let qctx = QueryContext::new(
        ChargedState::new(StateValue::Null),
        ContractAddress::default(),
    );
    let ctx: CircuitContext<()> = CircuitContext {
        current_private_state: (),
        current_query_context: qctx,
        current_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _: CircuitResults<(), ()> = CircuitResults {
        result: (),
        context: ctx,
        gas_cost: RunningCost::default(),
    };
}

#[test]
fn constructor_result_can_be_constructed() {
    let _: ConstructorResult<()> = ConstructorResult {
        current_contract_state: ChargedState::new(StateValue::Null),
        current_private_state: (),
        current_zswap_local_state: ZswapLocalState::default(),
    };
}
