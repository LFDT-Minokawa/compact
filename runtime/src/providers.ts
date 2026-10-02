// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
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

import * as ocrt from '@midnightntwrk/onchain-runtime-v4';
import { Module } from './module.js';

/**
 * A user-provided fetch of a contract's public state at a block hash, used only for cross-contract
 * call targets. The state returned must be post-block-evaluation; `blockHash` is the
 * `parentBlockHash` from the circuit context.
 */
export interface ContractStateProvider {
  getContractState(blockHash: string, address: ocrt.ContractAddress): Promise<ocrt.ContractState | undefined>;
}

/** A deferred load of a generated contract module: evaluated only when a call resolves to it. */
export type ModuleThunk = () => Promise<Module>;

/**
 * A user-provided lookup from a cross-contract callee's address to the module implementing the
 * contract deployed there.
 *
 * `resolve` is synchronous and total: loading is deferred into the thunk, and an address with no
 * binding returns `undefined` rather than throwing, so the runtime classifies every failure of this
 * seam and an application sees one vocabulary rather than one per provider. Calling a circuit the
 * contract type never declared is not one of them — that is the caller's own source disagreeing
 * with itself, which compilation should have refused, and it throws a plain `CompactError`.
 */
export interface ContractModuleProvider {
  resolve(calleeAddress: ocrt.ContractAddress): ModuleThunk | undefined;
}

/**
 * A user-provided lookup of this account's local state for a cross-contract callee: the capsule
 * `(account, callee)` as folded from the account's landed transactions, or `undefined` when the
 * account has never touched the contract, which the runtime takes as the capsule's first touch and
 * seeds with the callee's declaration defaults.
 *
 * Local state is the account's own and not a chain read, therefore there is no block hash: one
 * current value per callee rather than one per block. The runtime only reads through it (what a
 * call did comes back in its records, and folding them is the application's), and asks once per
 * callee per transaction, since a second sequential call must see what the first left behind.
 */
export interface LocalStateProvider {
  getLocalState(calleeAddress: ocrt.ContractAddress): Promise<ocrt.StateValue | undefined>;
}
