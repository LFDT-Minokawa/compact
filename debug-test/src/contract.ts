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
  dummyContractAddress,
  HostInterfaceProvider,
} from '@midnight-ntwrk/compact-runtime';
import { Contract, Maybe } from '../gen/contract/index.js';

// answer the host interface the contract declares

const COMPUTE = 'test:oracle/compute@1.0.0';

function compute(fst: boolean, snd: boolean): boolean {
  if (fst) {
    return snd;
  }
  return snd && true;
}

const hostInterfaceProvider: HostInterfaceProvider = {
  resolve: (id) => (id === COMPUTE ? { compute: (_context, fst: boolean, snd: boolean) => compute(fst, snd) } : undefined),
};

// initialize smart contract

const sc: Contract = new Contract();
const difficulty = 0n;
const { currentContractState } = await sc.initialState(createConstructorContext('0'.repeat(64)), difficulty);

export const execCtx = (circuitId: string) =>
  createCircuitContext({
    circuitId,
    contractAddress: dummyContractAddress(),
    coinPublicKeyOrZswapState: '0'.repeat(64),
    contractState: currentContractState,
    hostInterfaceProvider,
  });

// helper types

type AllResults = {
  nested: Maybe<bigint>;
  priv: Maybe<bigint>;
  stdLib: Maybe<Uint8Array>;
};

// run smart contract from TypeScript

export async function runSmartContract(flag: boolean): Promise<AllResults> {
  const result1 = await sc.circuits.nestedCall(execCtx('nestedCall'), flag, false); // transition function (with nested call)
  const result2 = await sc.circuits.privateCall(execCtx('privateCall'), flag, false); // host function (call private function)
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
