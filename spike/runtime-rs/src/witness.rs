// SPDX-License-Identifier: Apache-2.0
//
// Witness execution context + a trivial `NoWitnesses` marker for contracts
// without any witness declarations.

use crate::{ContractAddress, DefaultDB, QueryContext};
use midnight_storage::db::DB;

/// Read-only context handed to a witness implementation.
///
/// `L` is the projected ledger view that the compiler emits per-contract.
/// `PS` is the private state.
#[derive(Clone)]
pub struct WitnessContext<L, PS, D = DefaultDB>
where
    D: DB,
{
    pub ledger: L,
    pub private_state: PS,
    pub contract_address: ContractAddress,
    pub query_context: QueryContext<D>,
}

/// Marker impl for contracts that declare zero witnesses. The compiler
/// uses this as the default bound when a contract has no `witness ...`
/// declarations, so users don't have to write an empty trait impl.
#[derive(Clone, Default)]
pub struct NoWitnesses;
