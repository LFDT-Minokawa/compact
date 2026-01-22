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

export interface CircuitInfo {
    name: string;
    type: 'pure' | 'impure' | 'unknown';
    hasProver: boolean;
    hasVerifier: boolean;
    hasZkir: boolean;
    hasBzkir: boolean;
}

export class AssertCircuits {
    private folderPath: string = '';
    private pureCircuits: string[] = [];
    private impureCircuits: string[] = [];
    private circuitsWithKeys: string[] = [];
    private circuitsWithZkir: string[] = [];

    /** Initialize with contract folder path, scans directories immediately */
    expect(folder: string): AssertCircuits {
        this.folderPath = folder.endsWith('/') ? folder : folder + '/';
        this.pureCircuits = [];
        this.impureCircuits = [];
        this.circuitsWithKeys = [];
        this.circuitsWithZkir = [];

        this.parseTypesFromDts();
        this.scanKeysDirectory();
        this.scanZkirDirectory();

        return this;
    }

    private parseTypesFromDts(): void {
        const dtsPath = this.folderPath + 'contract/index.d.ts';
        if (!fs.existsSync(dtsPath)) return;

        const content = fs.readFileSync(dtsPath, 'utf-8');
        this.pureCircuits = this.parseCircuitType(content, 'PureCircuits');
        this.impureCircuits = this.parseCircuitType(content, 'ImpureCircuits');
    }

    private parseCircuitType(content: string, typeName: string): string[] {
        const regex = new RegExp(`export\\s+type\\s+${typeName}(?:<[^>]*>)?\\s*=\\s*\\{([^}]*)\\}`, 's');
        const match = content.match(regex);
        if (!match || !match[1]) return [];

        const body = match[1];
        const methodRegex = /^\s*(\w+)\s*[(<]/gm;
        const methods: string[] = [];
        let methodMatch;
        while ((methodMatch = methodRegex.exec(body)) !== null) {
            methods.push(methodMatch[1]);
        }
        return methods;
    }

    private scanKeysDirectory(): void {
        const keysDir = this.folderPath + 'keys';
        if (!fs.existsSync(keysDir)) return;

        const files = fs.readdirSync(keysDir);
        const circuits = new Set<string>();
        for (const file of files) {
            if (file.endsWith('.prover') || file.endsWith('.verifier')) {
                circuits.add(file.replace(/\.(prover|verifier)$/, ''));
            }
        }
        this.circuitsWithKeys = [...circuits];
    }

    private scanZkirDirectory(): void {
        const zkirDir = this.folderPath + 'zkir';
        if (!fs.existsSync(zkirDir)) return;

        const files = fs.readdirSync(zkirDir);
        const circuits = new Set<string>();
        for (const file of files) {
            if (file.endsWith('.zkir') || file.endsWith('.bzkir')) {
                circuits.add(file.replace(/\.(b?zkir)$/, ''));
            }
        }
        this.circuitsWithZkir = [...circuits];
    }

    /** Get circuits from PureCircuits type in index.d.ts */
    getPureCircuits(): string[] {
        return [...this.pureCircuits];
    }

    /** Get circuits from ImpureCircuits type in index.d.ts */
    getImpureCircuits(): string[] {
        return [...this.impureCircuits];
    }

    /** Get all circuits defined in index.d.ts (pure + impure) */
    getAllCircuits(): string[] {
        return [...new Set([...this.pureCircuits, ...this.impureCircuits])];
    }

    /** Get circuits that have .prover/.verifier files in keys/ */
    getCircuitsWithKeys(): string[] {
        return [...this.circuitsWithKeys];
    }

    /** Get circuits that have .zkir/.bzkir files in zkir/ */
    getCircuitsWithZkir(): string[] {
        return [...this.circuitsWithZkir];
    }

    /** Get detailed info for a specific circuit */
    getCircuitInfo(circuitName: string): CircuitInfo {
        const isPure = this.pureCircuits.includes(circuitName);
        const isImpure = this.impureCircuits.includes(circuitName);

        let type: 'pure' | 'impure' | 'unknown';
        if (isImpure) type = 'impure';
        else if (isPure) type = 'pure';
        else type = 'unknown';

        return {
            name: circuitName,
            type,
            hasProver: fs.existsSync(this.folderPath + `keys/${circuitName}.prover`),
            hasVerifier: fs.existsSync(this.folderPath + `keys/${circuitName}.verifier`),
            hasZkir: fs.existsSync(this.folderPath + `zkir/${circuitName}.zkir`),
            hasBzkir: fs.existsSync(this.folderPath + `zkir/${circuitName}.bzkir`),
        };
    }

    /** Assert circuit is pure (in PureCircuits, not in ImpureCircuits) */
    thatCircuitIsPure(circuitName: string): AssertCircuits {
        expect(this.pureCircuits.includes(circuitName), `'${circuitName}' should be pure`).toBe(true);
        expect(this.impureCircuits.includes(circuitName), `'${circuitName}' should NOT be impure`).toBe(false);
        return this;
    }

    /** Assert circuit is impure (in ImpureCircuits) */
    thatCircuitIsImpure(circuitName: string): AssertCircuits {
        expect(this.impureCircuits.includes(circuitName), `'${circuitName}' should be impure`).toBe(true);
        return this;
    }

    /** Assert circuit exists in index.d.ts (pure or impure) */
    thatCircuitExists(circuitName: string): AssertCircuits {
        const all = this.getAllCircuits();
        expect(all.includes(circuitName), `'${circuitName}' should exist in index.d.ts`).toBe(true);
        return this;
    }

    /** Assert circuit does NOT exist in index.d.ts */
    thatCircuitNotExists(circuitName: string): AssertCircuits {
        const all = this.getAllCircuits();
        expect(all.includes(circuitName), `'${circuitName}' should NOT exist`).toBe(false);
        return this;
    }

    /** Assert .prover and .verifier files exist */
    thatCircuitHasKeys(circuitName: string): AssertCircuits {
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.prover`), `${circuitName}.prover missing`).toBe(true);
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.verifier`), `${circuitName}.verifier missing`).toBe(true);
        return this;
    }

    /** Assert .prover and .verifier files do NOT exist */
    thatCircuitHasNoKeys(circuitName: string): AssertCircuits {
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.prover`), `${circuitName}.prover should NOT exist`).toBe(
            false,
        );
        expect(fs.existsSync(this.folderPath + `keys/${circuitName}.verifier`), `${circuitName}.verifier should NOT exist`).toBe(
            false,
        );
        return this;
    }

    /** Assert .zkir and .bzkir files exist */
    thatCircuitHasZkir(circuitName: string): AssertCircuits {
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.zkir`), `${circuitName}.zkir missing`).toBe(true);
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.bzkir`), `${circuitName}.bzkir missing`).toBe(true);
        return this;
    }

    /** Assert .zkir and .bzkir files do NOT exist */
    thatCircuitHasNoZkir(circuitName: string): AssertCircuits {
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.zkir`), `${circuitName}.zkir should NOT exist`).toBe(false);
        expect(fs.existsSync(this.folderPath + `zkir/${circuitName}.bzkir`), `${circuitName}.bzkir should NOT exist`).toBe(false);
        return this;
    }

    /** Assert impure circuit with all files (keys + zkir) */
    thatImpureCircuitIsComplete(circuitName: string): AssertCircuits {
        return this.thatCircuitIsImpure(circuitName).thatCircuitHasKeys(circuitName).thatCircuitHasZkir(circuitName);
    }

    /** Assert pure circuit with NO files (no keys, no zkir) */
    thatPureCircuitIsComplete(circuitName: string): AssertCircuits {
        return this.thatCircuitIsPure(circuitName).thatCircuitHasNoKeys(circuitName).thatCircuitHasNoZkir(circuitName);
    }

    /** Assert all impure circuits have keys generated */
    thatAllImpureCircuitsHaveKeys(): AssertCircuits {
        for (const circuit of this.impureCircuits) {
            this.thatCircuitHasKeys(circuit);
        }
        return this;
    }

    /** Assert all pure circuits have NO keys */
    thatNoPureCircuitsHaveKeys(): AssertCircuits {
        for (const circuit of this.pureCircuits) {
            this.thatCircuitHasNoKeys(circuit);
        }
        return this;
    }

    /** Assert circuits with keys match impure circuits (no extra, no missing) */
    thatKeysMatchImpureCircuits(): AssertCircuits {
        const impureSet = new Set(this.impureCircuits);
        const keysSet = new Set(this.circuitsWithKeys);

        // Check no extra keys
        for (const circuit of this.circuitsWithKeys) {
            expect(impureSet.has(circuit), `'${circuit}' has keys but is not impure`).toBe(true);
        }
        // Check no missing keys
        for (const circuit of this.impureCircuits) {
            expect(keysSet.has(circuit), `'${circuit}' is impure but has no keys`).toBe(true);
        }
        return this;
    }
}
