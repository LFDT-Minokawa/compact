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
  createCircuitContext,
  createConstructorContext,
  WitnessContext,
  dummyContractAddress,
} from '@midnight-ntwrk/compact-runtime';
import { Contract, Witnesses, Maybe, Ledger } from '../gen/contract/index.js';

// handle private state

type PrivateState = {
  maxAttempts: bigint;
};

function compute(privateState: WitnessContext<Ledger, PrivateState>, fst: boolean, snd: boolean): [PrivateState, boolean] {
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
const { currentContractState, currentPrivateState } = await sc.initialState(
  createConstructorContext(initPS, '0'.repeat(64)),
  difficulty,
);

export const execCtx = (circuitId: string) =>
  createCircuitContext(circuitId, dummyContractAddress(), '0'.repeat(64), currentContractState, currentPrivateState);

// helper types

type AllResults = {
  nested: Maybe<bigint>;
  priv: Maybe<bigint>;
  stdLib: Maybe<Uint8Array>;
};

// run smart contract from TypeScript

export async function runSmartContract(flag: boolean): Promise<AllResults> {
  const result1 = await sc.circuits.nestedCall(execCtx('nestedCall'), flag, false); // transition function (with nested call)
  const result2 = await sc.circuits.privateCall(execCtx('privateCall'), flag, false); // witness (call private function)
  await sc.circuits.ledgerCalls(execCtx('ledgerCalls'), 1n); // access ledger (public state)
  const result3 = await sc.circuits.stdLibCall(execCtx('stdLibCall'), flag, false); // calls from standard library

  return {
    nested: result1.result,
    priv: result2.result,
    stdLib: result3.result,
  };
}

const flag: boolean = true;
const results = await runSmartContract(flag);

console.log(results.nested);
console.log(results.priv);
console.log(results.stdLib);
