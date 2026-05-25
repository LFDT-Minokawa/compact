// SPDX-License-Identifier: Apache-2.0
//
// Facade aggregates for circuit / constructor execution. Bundles existing upstream
// state types into the shape generated code expects.

use crate::{ChargedState, CostModel, QueryContext, RunningCost, DefaultDB};
use midnight_storage::db::DB;

/// Context passed into each impure / provable circuit invocation.
///
/// Mirrors the TS `CircuitContext<PS>` shape from @midnight-ntwrk/compact-runtime.
#[derive(Clone)]
pub struct CircuitContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_private_state: PS,
    pub current_query_context: QueryContext<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
    // current_zswap_local_state: omitted in the spike — only added when zswap
    // operations are actually emitted.
}

/// Context passed into the contract constructor.
#[derive(Clone)]
pub struct ConstructorContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub initial_private_state: PS,
    // empty_zswap_local_state: omitted in spike — see above.
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
    _phantom: std::marker::PhantomData<D>,
}

/// Return of a provable / impure circuit. Mirrors the TS `CircuitResults<PS, R>`.
#[derive(Clone)]
pub struct CircuitResults<PS, R, D = DefaultDB>
where
    D: DB,
{
    pub result: R,
    pub context: CircuitContext<PS, D>,
    pub gas_cost: RunningCost,
}

/// Return of the constructor.
#[derive(Clone)]
pub struct ConstructorResult<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_contract_state: ChargedState<D>,
    pub current_private_state: PS,
}

impl<PS, D> ConstructorContext<PS, D>
where
    D: DB,
{
    pub fn new(initial_private_state: PS, cost_model: CostModel) -> Self {
        Self {
            initial_private_state,
            cost_model,
            gas_limit: None,
            _phantom: std::marker::PhantomData,
        }
    }
}
