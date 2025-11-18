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

describe('Default contract values', () => {
    const witnessSets = {} as const;

    const contractConfigs: Record<string, util.ContractConfig> = {
        A: {
            module: contractCodeA,
            witnessSets: {}
        },
        B: {
            module: contractCodeB,
            witnessSets: {}
        },
        C: {
            module: contractCodeC,
            constructorArgs: (deployed: Record<string, runtime.ContractAddress>) => [
                util.toEncodedContractAddress(deployed.A),
                util.toEncodedContractAddress(deployed.B),
            ],
            witnessSets: {}
        }
    };

    const env = util.multiContractEnv(contractConfigs, witnessSets);

    test('Default complex struct with contract values has expected shape', () => {
        const cDeployed = env.deployedContracts.C;
        const cLedgerState = contractCodeC.ledger(cDeployed.constructorResult.currentContractState.data);
        const defaultEither = { is_left: false, left: { bytes: new Uint8Array(32) }, right: { bytes: new Uint8Array(32) }};
        const expectedS = { a: defaultEither, b: defaultEither };
        expect(cLedgerState.s).toEqual(expectedS);
    });

    test('Runtime should throw when a contract with default address is called', () => {
        const context = util.createInitialContext('C', 'baz', env);
        expect(() => env.deployedContracts.C.exec.impureCircuits.sumS(context)).toThrow(runtime.CompactError);
    });

    test('Should succeed when sumAB is called after setS', () => {
        const context0 = util.createInitialContext('C', 'setS', env);
        const circuitResult0 = env.deployedContracts.C.exec.impureCircuits.setS(context0);
        const circuitResult1 = env.deployedContracts.C.exec.impureCircuits.sumAB(circuitResult0.context);
        expect(circuitResult1.result).toEqual(7);
    });
});
