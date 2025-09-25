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
  CircuitContext,
  WitnessContext,
  QueryContext,
  emptyZswapLocalState,
  constructorContext,
  dummyContractAddress,
} from '@midnight-ntwrk/compact-runtime';
import { Contract, Witnesses, Maybe, Ledger } from '../gen/contract/index.cjs';

// handle private state

type PrivateState = {
  maxAttempts: bigint;
};

function compute(
  privateState: WitnessContext<Ledger, PrivateState>,
  fst: boolean,
  snd: boolean,
): [PrivateState, boolean] {
  if (fst) {
    return [privateState.privateState, snd];
  }
  return [privateState.privateState, snd && true];
}

const myWitness: Witnesses<PrivateState> = { compute };

// initialize smart contract

const sc: Contract<PrivateState, Witnesses<PrivateState>> = new Contract(myWitness);
const difficulty = 0n;
const initPS: PrivateState = {
  maxAttempts: 10n,
};
const { currentContractState, currentPrivateState } = sc.initialState(
  constructorContext(initPS, '0'.repeat(64)),
  difficulty,
);

export const execCtx: CircuitContext<PrivateState> = {
  originalState: currentContractState,
  currentPrivateState,
  currentZswapLocalState: emptyZswapLocalState('0'.repeat(64)),
  transactionContext: new QueryContext(currentContractState.data, dummyContractAddress()),
};

// helper types

type AllResults = {
  nested: Maybe<bigint>;
  priv: Maybe<bigint>;
  stdLib: Maybe<Uint8Array>;
};

// run smart contract from TypeScript

export function runSmartContract(flag: boolean): AllResults {
  const result1 = sc.circuits.nestedCall(execCtx, flag, false); // transition function (with nested call)
  const result2 = sc.circuits.privateCall(execCtx, flag, false); // witness (call private function)
  sc.circuits.ledgerCalls(execCtx, 1n); // access ledger (public state)
  const result3 = sc.circuits.stdLibCall(execCtx, flag, false); // calls from standard library

  return {
    nested: result1.result,
    priv: result2.result,
    stdLib: result3.result,
  };
}

const flag: boolean = true;
const results = runSmartContract(flag);

console.log(results.nested);
console.log(results.priv);
console.log(results.stdLib);
