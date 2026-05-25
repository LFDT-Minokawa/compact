// SPDX-License-Identifier: Apache-2.0
//
// HAND-TRANSLATED Rust port of examples/counter.compact:
//
//   import CompactStandardLibrary;
//   export ledger round: Counter;
//   export circuit increment(): [] { round.increment(1); }
//
// This is what `compactc --rust counter.compact` SHOULD produce. The goal of
// the spike is to confirm the shape compiles against the real compact-runtime
// crate and the published Midnight Rust ecosystem. The exact Op-program bytes
// emitted by the lowering pass are validated separately (the IR is documented
// at compiler/midnight-ledger.ss:587-606 — Counter ADT).
//
// NOT a runtime-correctness check: we do not assert this produces identical
// state transitions to the TS path. That's the next spike (cross-language byte
// parity), to be performed once compactc is built and the Rust emitter exists.

use compact_runtime::*;
use std::marker::PhantomData;

compact_runtime::check_runtime_version!("0.1.0-spike");

// ---------------------------------------------------------------------------
// Witnesses trait
// counter.compact has zero witness declarations, so the trait is empty and we
// default the Contract's witness generic to `NoWitnesses`.
// (For contracts WITH witnesses the compiler would emit one method per witness.)
// ---------------------------------------------------------------------------
pub trait Witnesses<PS> {}
impl<PS> Witnesses<PS> for NoWitnesses {}

// ---------------------------------------------------------------------------
// Contract
// ---------------------------------------------------------------------------

/// Generated contract. `PS` is the user's private-state type (unit `()` for
/// contracts with no witnesses). `W` is the user-supplied witnesses impl.
pub struct Contract<PS, W = NoWitnesses>
where
    W: Witnesses<PS>,
{
    pub witnesses: W,
    _ps: PhantomData<PS>,
}

impl<PS, W> Contract<PS, W>
where
    W: Witnesses<PS>,
{
    pub fn new(witnesses: W) -> Self {
        Self {
            witnesses,
            _ps: PhantomData,
        }
    }

    /// Generated circuit: `increment()`.
    ///
    /// Compact source: `circuit increment(): [] { round.increment(1); }`
    ///
    /// Lowered Op program (from compiler/midnight-ledger.ss:602-606):
    ///   idx  [cached: f-cached, push_path: true, path: f]
    ///   addi [immediate: 1]
    ///   ins  [cached: true, n: length(f)]
    ///
    /// For a single-field contract (`round` only), the path `f` resolves
    /// to `[Key::Value(AlignedValue::from(0u64))]` and `length(f) == 1`.
    pub fn increment(
        &self,
        ctx: CircuitContext<PS>,
    ) -> Result<CircuitResults<PS, ()>, TranscriptRejected<DefaultDB>> {
        // Build the Op program. Concrete result mode is Verify for non-proving callers.
        let ops: Vec<Op<ResultModeVerify>> = vec![
            Op::Idx {
                cached: false,
                push_path: true,
                path: Array::from(vec![Key::Value(AlignedValue::from(0u64))]),
            },
            Op::Addi { immediate: 1 },
            Op::Ins {
                cached: true,
                n: 1,
            },
        ];

        // Run the program against the on-chain VM.
        let results = ctx
            .current_query_context
            .query(&ops, ctx.gas_limit.clone(), &ctx.cost_model)?;

        Ok(CircuitResults {
            result: (),
            context: CircuitContext {
                current_private_state: ctx.current_private_state,
                current_query_context: results.context,
                cost_model: ctx.cost_model,
                gas_limit: ctx.gas_limit,
            },
            gas_cost: results.gas_cost,
        })
    }
}

// ---------------------------------------------------------------------------
// Ledger view
//
// `ledger(state)` returns a typed view exposing each ledger field by name.
// For `round: Counter`, the view exposes `.round()` returning a u64 read of
// the counter's current value. (Spike stops short of decoding the value out
// of StateValue — that's mechanical and not on the critical path of this
// validation.)
// ---------------------------------------------------------------------------

pub struct Ledger<'a, D: DB = DefaultDB> {
    state: &'a ChargedState<D>,
}

pub fn ledger<D: DB>(state: &ChargedState<D>) -> Ledger<'_, D> {
    Ledger { state }
}

impl<'a, D: DB> Ledger<'a, D> {
    /// Read the `round` counter value.
    ///
    /// Real generated code: decode `StateValue::Cell(AlignedValue(u64))` at
    /// path `[0]`. Out of scope for this minimal spike.
    pub fn round(&self) -> u64 {
        let _ = &self.state;
        todo!("decode round counter from contract state — out of spike scope")
    }
}
