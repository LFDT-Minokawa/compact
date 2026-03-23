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

import fs from 'fs';
import { expect } from 'vitest';
import { ContractInfo, ContractInfoCircuit } from './types';

export class AssertContract {
    private folderPath: string = '';
    private pureCircuits: string[] = [];
    private impureCircuits: string[] = [];
    private contractInfo: ContractInfo | null = null;

    /** Initialize with contract folder path, scans directories immediately */
    expect(folder: string): AssertContract {
        this.folderPath = folder.endsWith('/') ? folder : folder + '/';
        this.pureCircuits = [];
        this.impureCircuits = [];

        this.parseTypesFromDts();
        this.parseContractInfo();

        return this;
    }

    private parseTypesFromDts(): void {
        const dtsPath = this.folderPath + 'contract/index.d.ts';
        if (!fs.existsSync(dtsPath)) return;

        const content = fs.readFileSync(dtsPath, 'utf-8');
        const regex = (typeName: string) => new RegExp(`export\\s+type\\s+${typeName}(?:<[^>]*>)?\\s*=\\s*\\{([^}]*)\\}`, 's');

        for (const [type, arr] of [
            ['PureCircuits', this.pureCircuits],
            ['ImpureCircuits', this.impureCircuits],
        ] as const) {
            const match = content.match(regex(type));
            if (match?.[1]) {
                const methodRegex = /^\s*(\w+)\s*[(<]/gm;
                let m;
                while ((m = methodRegex.exec(match[1])) !== null) {
                    arr.push(m[1]);
                }
            }
        }
    }

    private parseContractInfo(): void {
        const contractInfoPath = this.folderPath + 'compiler/contract-info.json';
        if (!fs.existsSync(contractInfoPath)) return;

        try {
            this.contractInfo = JSON.parse(fs.readFileSync(contractInfoPath, 'utf-8')) as ContractInfo;
        } catch {
            // Ignore parse errors
        }
    }

    private getCircuitFromJson(circuitName: string): ContractInfoCircuit | undefined {
        return this.contractInfo?.circuits.find((c) => c.name === circuitName);
    }

    getPureCircuits(): string[] {
        return [...this.pureCircuits];
    }

    getImpureCircuits(): string[] {
        return [...this.impureCircuits];
    }

    getCompilerVersion(): string | undefined {
        return this.contractInfo?.['compiler-version'];
    }

    getLanguageVersion(): string | undefined {
        return this.contractInfo?.['language-version'];
    }

    getContractInfoCircuits(): ContractInfoCircuit[] | undefined {
        return this.contractInfo?.circuits;
    }

    thatCompilerVersionIs(expectedVersion: string): AssertContract {
        expect(this.contractInfo?.['compiler-version'], 'compiler-version mismatch in contract-info.json').toBe(expectedVersion);
        return this;
    }

    thatLanguageVersionIs(expectedVersion: string): AssertContract {
        expect(this.contractInfo?.['language-version'], 'language-version mismatch in contract-info.json').toBe(expectedVersion);
        return this;
    }

    thatCircuitHasKeys(circuitName: string): AssertContract {
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.prover`), `${circuitName}.prover missing`).toBe(true);
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.verifier`), `${circuitName}.verifier missing`).toBe(true);
        return this;
    }

    thatCircuitHasNoKeys(circuitName: string): AssertContract {
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.prover`), `${circuitName}.prover should NOT exist`).toBe(
            false,
        );
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.verifier`), `${circuitName}.verifier should NOT exist`).toBe(
            false,
        );
        return this;
    }

    thatCircuitHasZkir(circuitName: string): AssertContract {
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.zkir`), `${circuitName}.zkir missing`).toBe(true);
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.bzkir`), `${circuitName}.bzkir missing`).toBe(true);
        return this;
    }

    thatCircuitHasNoZkir(circuitName: string): AssertContract {
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.zkir`), `${circuitName}.zkir should NOT exist`).toBe(false);
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.bzkir`), `${circuitName}.bzkir should NOT exist`).toBe(false);
        return this;
    }

    thatCircuitNotInJson(circuitName: string): AssertContract {
        const circuit = this.getCircuitFromJson(circuitName);
        expect(circuit, `'${circuitName}' should NOT be in contract-info.json`).toBeUndefined();
        return this;
    }

    thatCircuitIsJsonPure(circuitName: string): AssertContract {
        const circuit = this.getCircuitFromJson(circuitName);
        expect(circuit, `'${circuitName}' not found in contract-info.json`).toBeDefined();
        expect(circuit?.pure, `'${circuitName}' should be pure in contract-info.json`).toBe(true);
        return this;
    }

    thatCircuitIsJsonImpure(circuitName: string): AssertContract {
        const circuit = this.getCircuitFromJson(circuitName);
        expect(circuit, `'${circuitName}' not found in contract-info.json`).toBeDefined();
        expect(circuit?.pure, `'${circuitName}' should be impure in contract-info.json`).toBe(false);
        return this;
    }

    thatCircuitRequiresProof(circuitName: string): AssertContract {
        const circuit = this.getCircuitFromJson(circuitName);
        expect(circuit, `'${circuitName}' not found in contract-info.json`).toBeDefined();
        expect(circuit?.proof, `'${circuitName}' should require proof`).toBe(true);
        return this;
    }

    thatCircuitNoProof(circuitName: string): AssertContract {
        const circuit = this.getCircuitFromJson(circuitName);
        expect(circuit, `'${circuitName}' not found in contract-info.json`).toBeDefined();
        expect(circuit?.proof, `'${circuitName}' should NOT require proof`).toBe(false);
        return this;
    }

    /** Non-exported circuit: no keys, no zkir, not in contract-info.json */
    thatCircuitIsNotExported(circuitName: string): AssertContract {
        return this.thatCircuitHasNoKeys(circuitName).thatCircuitHasNoZkir(circuitName).thatCircuitNotInJson(circuitName);
    }

    /** Pure exported circuit: no keys, no zkir, no proof, marked pure in JSON */
    thatCircuitIsPureExported(circuitName: string): AssertContract {
        return this.thatCircuitHasNoKeys(circuitName)
            .thatCircuitHasNoZkir(circuitName)
            .thatCircuitNoProof(circuitName)
            .thatCircuitIsJsonPure(circuitName);
    }

    /** Impure exported circuit: has keys, has zkir, requires proof, marked impure in JSON */
    thatCircuitIsImpureExported(circuitName: string): AssertContract {
        return this.thatCircuitHasKeys(circuitName)
            .thatCircuitHasZkir(circuitName)
            .thatCircuitRequiresProof(circuitName)
            .thatCircuitIsJsonImpure(circuitName);
    }

    /** Impure exported circuit WITHOUT proof: no keys, no zkir, no proof, marked impure in JSON */
    thatCircuitIsImpureNoProofExported(circuitName: string): AssertContract {
        return this.thatCircuitHasNoKeys(circuitName)
            .thatCircuitHasNoZkir(circuitName)
            .thatCircuitNoProof(circuitName)
            .thatCircuitIsJsonImpure(circuitName);
    }
}
