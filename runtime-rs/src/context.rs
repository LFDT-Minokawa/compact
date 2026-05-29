// SPDX-License-Identifier: Apache-2.0
//
// Facade aggregates bundling existing upstream state types into the shapes
// the compiler emits references to. Mirror TS `CircuitContext<PS>`,
// `ConstructorContext<PS>` from @midnight-ntwrk/compact-runtime.

use crate::{
    ChargedState, ContractAddress, CostModel, DefaultDB, QueryContext, RunningCost,
    ZswapLocalState, INITIAL_COST_MODEL, DB,
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
