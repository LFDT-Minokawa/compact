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

<<<<<<< HEAD
import * as runtime from '@midnight-ntwrk/compact-runtime';
import * as contract from '../gen/contract/index.cjs';

// define witnesses and private state
=======
import {
  createCircuitContext,
  createConstructorContext,
  WitnessContext,
  dummyContractAddress,
} from '@midnight-ntwrk/compact-runtime';
import { Contract, Witnesses, Maybe, Ledger } from '../gen/contract/index.js';

// handle private state
>>>>>>> main

type PrivateState = {
  maxAttempts: bigint;
};

<<<<<<< HEAD
const compute = (
  privateState: runtime.WitnessContext<contract.Ledger, PrivateState>,
  fst: boolean,
  snd: boolean,
): [PrivateState, boolean] => {
=======
function compute(
  privateState: WitnessContext<Ledger, PrivateState>,
  fst: boolean,
  snd: boolean,
): [PrivateState, boolean] {
>>>>>>> main
  if (fst) {
    return [privateState.privateState, snd];
  }
  return [privateState.privateState, snd && true];
<<<<<<< HEAD
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
=======
}

const myWitness: Witnesses<PrivateState> = { compute };

// initialize smart contract

const sc: Contract<PrivateState, Witnesses<PrivateState>> = new Contract(myWitness);
const difficulty = 0n;
const initPS: PrivateState = {
  maxAttempts: 10n,
};
const { currentContractState, currentPrivateState } = sc.initialState(
  createConstructorContext(initPS, '0'.repeat(64)),
  difficulty,
);

export const execCtx = createCircuitContext(dummyContractAddress(), '0'.repeat(64), currentContractState.data, currentPrivateState);

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
>>>>>>> main
