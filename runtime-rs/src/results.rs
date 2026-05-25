// SPDX-License-Identifier: Apache-2.0

use crate::{ChargedState, CircuitContext, DefaultDB, RunningCost, ZswapLocalState, DB};

/// Return of a provable / impure circuit. Mirrors the TS
/// `CircuitResults<PS, R>` from @midnight-ntwrk/compact-runtime.
#[derive(Clone)]
pub struct CircuitResults<PS, R, D = DefaultDB>
where
    D: DB,
{
    pub result: R,
    pub context: CircuitContext<PS, D>,
    pub gas_cost: RunningCost,
}

/// Return of the contract constructor.
#[derive(Clone)]
pub struct ConstructorResult<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_contract_state: ChargedState<D>,
    pub current_private_state: PS,
    pub current_zswap_local_state: ZswapLocalState<D>,
}
