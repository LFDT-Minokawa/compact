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
// Witness execution context + a trivial `NoWitnesses` marker for contracts
// that declare zero witnesses.

//! Witness execution context for `compactc --rust`-generated contracts.
//!
//! # Witness privacy model
//!
//! Every generated `Witnesses<PS>::<method>` returns `(PS, T)`. `PS`
//! (private state) is a free generic parameter on `WitnessContext`,
//! `CircuitContext`, `ConstructorContext`, `CircuitResults`, and
//! `ConstructorResult`, with **no** `Aligned` / `FieldRepr` /
//! `BinaryHashRepr` / `From<…> for AlignedValue` bounds. The type
//! system therefore forbids pushing a `PS` value into a `StateValue`
//! or any other serialised on-chain representation — `PS` is
//! structurally confined to the four well-known fields that thread it
//! between constructor / circuit invocations, none of which feed the
//! `ChargedState` that becomes `ContractState.data`.
//!
//! The witness *value* `T` is a normal Rust type. Whether it is safe
//! to write to a public ledger field is the contract author's
//! responsibility — the codegen has no way to tell which `T` values
//! are private by intent.

use crate::{ContractAddress, DefaultDB, QueryContext, DB};

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

impl<L, PS, D> WitnessContext<L, PS, D>
where
    D: DB,
{
    /// Convenience constructor for the common case where the generated
    /// circuit code has just a `QueryContext` and a projected ledger view
    /// in hand. Pulls the contract address straight out of `qctx.address`
    /// and clones the query context for the witness's read-only view.
    pub fn new(ledger: L, private_state: PS, qctx: &QueryContext<D>) -> Self {
        Self {
            ledger,
            private_state,
            contract_address: qctx.address,
            query_context: qctx.clone(),
        }
    }
}

/// Marker for contracts that declare zero witnesses. The compiler uses
/// `NoWitnesses` as the default bound when a contract has no `witness`
/// declarations, so users don't have to write an empty trait impl.
#[derive(Clone, Copy, Default, Debug)]
pub struct NoWitnesses;
