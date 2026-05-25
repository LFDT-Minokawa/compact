// SPDX-License-Identifier: Apache-2.0
//
// Facade aggregates bundling existing upstream state types into the shapes
// the compiler emits references to. Mirror TS `CircuitContext<PS>`,
// `ConstructorContext<PS>` from @midnight-ntwrk/compact-runtime.

use crate::{CostModel, DefaultDB, QueryContext, RunningCost, ZswapLocalState, DB};

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
