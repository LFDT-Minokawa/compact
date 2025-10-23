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

import * as runtime from '@midnight-ntwrk/compact-runtime';
import * as contract from '../gen/contract/index.js';

// handle private state

type PrivateState = {
  maxAttempts: bigint;
};

function compute(
  privateState: runtime.WitnessContext<contract.Ledger, PrivateState>,
  fst: boolean,
  snd: boolean,
): [PrivateState, boolean] {
  if (fst) {
    return [privateState.privateState, snd];
  }
  return [privateState.privateState, snd && true];
}

const witnessSets = { [contract.contractId]: { compute } };

// initialize smart contract

const exec = contract.executables(witnessSets);
const difficulty = 0n;
const initPS = {
  maxAttempts: 10n,
};
const { currentContractState, currentPrivateState } = exec.initialState(
  runtime.createConstructorContext('0'.repeat(64), initPS),
  difficulty,
);

const address = runtime.sampleContractAddress();
const coinPubKey = '0'.repeat(64);

export const circuitContext = (circuitId: string) =>
  runtime.createCircuitContext(
    contract.contractId,
    circuitId,
    address,
    coinPubKey,
    { [address]: currentContractState.data },
    { [address]: currentPrivateState },
  );

// helper types

type AllResults = {
  nested: contract.Maybe<bigint>;
  priv: contract.Maybe<bigint>;
  stdLib: contract.Maybe<Uint8Array>;
};

// run smart contract from TypeScript

export function runSmartContract(flag: boolean): AllResults {
  const result1 = exec.circuits.nestedCall(circuitContext('nestedCall'), flag, false); // transition function (with nested call)
  const result2 = exec.circuits.privateCall(circuitContext('privateCall'), flag, false); // witness (call private function)
  exec.circuits.ledgerCalls(circuitContext('ledgerCalls'), 1n); // access ledger (public state)
  const result3 = exec.circuits.stdLibCall(circuitContext('stdLibCall'), flag, false); // calls from standard library

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
