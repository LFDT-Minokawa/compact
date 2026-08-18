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
 * binding returns `undefined` rather than throwing, so the runtime classifies every failure and an
 * application sees one vocabulary rather than one per provider.
 */
export interface ContractModuleProvider {
  resolve(calleeAddress: ocrt.ContractAddress): ModuleThunk | undefined;
}
