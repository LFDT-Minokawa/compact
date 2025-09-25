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

import {
  type CircuitContext,
  type ContractState,
  QueryContext,
  sampleContractAddress,
} from '@midnight-ntwrk/compact-runtime';
import * as crypto from 'node:crypto';
import { Contract, type Ledger, ledger, type Witnesses } from './managed/counter/contract/index.cjs';

class PrivateState {
  constructor(
    public readonly secretKey: Uint8Array,
    public readonly round: bigint
  ) {}

  static random(): PrivateState {
    const outArray = new Uint8Array(32);
    const secretKey = crypto.getRandomValues(outArray);

    return new PrivateState(secretKey, 0n);
  }
}

export class SimpleWallet {
  readonly contract: Contract<PrivateState>;
  readonly privateState: PrivateState;
  readonly contractState: ContractState;

  constructor() {
    const witnesses: Witnesses<PrivateState> = {};
    this.contract = new Contract<PrivateState>(witnesses);
    const privateState = PrivateState.random();

    const [initPrivState, contractState] = this.contract.initialState(privateState);
    this.contractState = contractState;
    this.privateState = initPrivState;
  }

  public getLedger(): Ledger {
    return ledger(this.contractState.data);
  }

  public increment(): Ledger {
    const address = sampleContractAddress();
    const ctx: CircuitContext<PrivateState> = {
      currentPrivateState: this.privateState,
      originalState: this.contractState,
      transactionContext: new QueryContext(this.contractState.data, address),
    };
    const circuitResults = this.contract.impureCircuits.increment(ctx);

    return ledger(circuitResults.context.transactionContext.state);
  }
}
