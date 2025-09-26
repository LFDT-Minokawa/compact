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
import * as contract from '../gen/contract/index.cjs';

// define witnesses and private state

type PrivateState = {
  maxAttempts: bigint;
};

const compute = (
  privateState: runtime.WitnessContext<contract.Ledger, PrivateState>,
  fst: boolean,
  snd: boolean,
): [PrivateState, boolean] => {
  if (fst) {
    return [privateState.privateState, snd];
  }
  return [privateState.privateState, snd && true];
};

// initialize smart contract

const contractAddress = runtime.sampleContractAddress();
const coinPublicKey = '0'.repeat(64);

const witnessSets = { [contract.contractId]: { compute } };
const exec = contract.executables(witnessSets);

const initialPrivateState = {
  maxAttempts: 10n,
};
const difficulty = 0n;
const { currentContractState, currentPrivateState } = exec.stateConstructor(
  runtime.createConstructorContext(coinPublicKey, initialPrivateState),
  difficulty,
);

export const createCircuitContext = (circuitId: string) =>
  runtime.createCircuitContext(
    contract.contractId,
    circuitId,
    contractAddress,
    coinPublicKey,
    { [contractAddress]: currentContractState },
    { [contractAddress]: currentPrivateState },
  );

export const runSmartContract = (flag: boolean) => {
  const result1 = exec.impureCircuits.nestedCall(createCircuitContext('nestedCall'), flag, false).result; // transition function (with nested call)
  const result2 = exec.impureCircuits.privateCall(createCircuitContext('privateCall'), flag, false).result; // witness (call private function)
  exec.impureCircuits.ledgerCalls(createCircuitContext('ledgerCalls'), 1n); // access ledger (public state)
  const result3 = exec.pureCircuits.stdLibCall(flag, false); // calls from standard library
  return {
    nestedCallResult: result1,
    privateCallResult: result2,
    stdLibCallResult: result3,
  };
};

const flag: boolean = true;
const results = runSmartContract(flag);

console.log(results.nestedCallResult);
console.log(results.privateCallResult);
console.log(results.stdLibCallResult);
