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

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v3';

/**
 * A user-provided interface for fetching the public state of a contract
 * at a given block hash. Used exclusively to retrieve the state of cross-contract
 * call targets at runtime. Assumes state returned is the post-block evaluation
 * contract state.
 *
 * The `parentBlockHash` value in {@link CircuitContext} is used for as the `blockHash` argument.
 */
export interface ContractStateProvider {
  getContractState(blockHash: string, address: ocrt.ContractAddress): Promise<ocrt.ContractState | undefined>;
}
