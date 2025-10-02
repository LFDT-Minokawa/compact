// This file is part of Compact.
// Copyright (C) 2025 Midnight Foundation
// SPDX-License-Identifier: Apache-2.0
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// 	http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import * as ocrt from '@midnight-ntwrk/onchain-runtime-v1';

/**
 * The external information accessible from within a Compact witness call
 */
export interface WitnessContext<L = any, PS = any> {
  /**
   * The projected ledger state, if the transaction were to run against the
   * ledger state as you locally see it currently
   */
  readonly ledger: L;
  /**
   * The current private state for the contract
   */
  readonly privateState: PS;
  /**
   * The address of the contract being called
   */
  readonly contractAddress: ocrt.ContractAddress;
}

/**
 * Internal constructor for {@link WitnessContext}.
 * @internal
 */
export function createWitnessContext<L, PS>(
  ledger: L,
  privateState: PS,
  contractAddress: ocrt.ContractAddress,
): WitnessContext<L, PS> {
  return {
    ledger,
    privateState,
    contractAddress,
  };
}
