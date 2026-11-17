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
import type { HostInterface } from './host.js';
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

/**
 * A user-provided resolution of the host interfaces a contract's `host` blocks declare: the
 * wallet's (eventually the capsule runtime's) answer for the account that is transacting. One per
 * execution, inherited by every cross-contract callee in the call tree, so a callee's host calls
 * are answered by the same party as the root's.
 *
 * `resolve` is synchronous and total, like {@link ContractModuleProvider.resolve}: an id with no
 * implementation returns `undefined` rather than throwing, so the runtime classifies the gap
 * (before a callee is entered, at the entry of a root circuit, or at the call as the backstop).
 * Synchronous because local functions run as synchronous code, so a host function they call
 * cannot be awaited; an implementation that must do asynchronous work has to have done it before
 * the call. The runtime resolves nothing by itself: the coin operations the standard library
 * declares (`zswapHostInterface`) are an implementation a provider may serve, not a default.
 */
export interface HostInterfaceProvider {
  resolve(interfaceId: string): HostInterface | undefined;
}
