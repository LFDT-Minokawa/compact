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
// Facade aggregates bundling existing upstream state types into the shapes
// the compiler emits references to. Mirror TS `CircuitContext<PS>`,
// `ConstructorContext<PS>` from @midnight-ntwrk/compact-runtime.

use crate::{
    ChargedState, ContractAddress, CostModel, DefaultDB, QueryContext, RunningCost,
    ZswapLocalState, DB, INITIAL_COST_MODEL,
};

/// Context passed into each impure / provable circuit invocation.
#[derive(Clone)]
pub struct CircuitContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_private_state: PS,
    pub current_query_context: QueryContext<D>,
    pub current_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}

impl<PS, D> CircuitContext<PS, D>
where
    D: DB,
{
    /// Build a fresh `CircuitContext` from a contract state and a
    /// private state. Mirrors the TS `createCircuitContext` helper:
    /// instantiates a `QueryContext` against the dummy contract
    /// address, an empty `ZswapLocalState`, the default
    /// `INITIAL_COST_MODEL`, and no gas limit.
    pub fn new(state: ChargedState<D>, private_state: PS) -> Self {
        Self {
            current_private_state: private_state,
            current_query_context: QueryContext::new(state, ContractAddress::default()),
            current_zswap_local_state: ZswapLocalState::default(),
            cost_model: INITIAL_COST_MODEL.clone(),
            gas_limit: None,
        }
    }
}

/// Context passed into the contract constructor.
#[derive(Clone)]
pub struct ConstructorContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub initial_private_state: PS,
    pub empty_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}
