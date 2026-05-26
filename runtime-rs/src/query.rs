// SPDX-License-Identifier: Apache-2.0
//
// Purpose-named wrappers around `QueryContext::query` that force the correct
// `ResultMode` for read vs verify paths. Reading from ledger state (e.g. via
// `ledger().round()`) needs `ResultModeGather` to actually emit events; using
// `ResultModeVerify` silently produces empty events and reads come back
// missing.

use crate::{
    CostModel, Op, QueryContext, QueryResults, ResultModeGather, ResultModeVerify, RunningCost,
    TranscriptRejected, DB,
};

/// Run an Op program that should produce read events (e.g. `popeq`). Use this
/// for ledger view accessors. The returned `QueryResults` carries the
/// `GatherEvent::Read(...)` entries the caller decodes.
pub fn query_for_read<D: DB>(
    ctx: &QueryContext<D>,
    ops: &[Op<ResultModeGather, D>],
    gas_limit: Option<RunningCost>,
    cost_model: &CostModel,
) -> Result<QueryResults<ResultModeGather, D>, TranscriptRejected<D>> {
    ctx.query(ops, gas_limit, cost_model)
}

/// Run an Op program in verification-only mode — no events emitted, used for
/// state-mutation paths (e.g. circuits whose return value is `()`). Use this
/// for impure / provable circuit emissions where only the resulting
/// transcript / state matters.
pub fn query_for_verify<D: DB>(
    ctx: &QueryContext<D>,
    ops: &[Op<ResultModeVerify, D>],
    gas_limit: Option<RunningCost>,
    cost_model: &CostModel,
) -> Result<QueryResults<ResultModeVerify, D>, TranscriptRejected<D>> {
    ctx.query(ops, gas_limit, cost_model)
}
