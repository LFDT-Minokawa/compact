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

import fs from 'node:fs';
import path from 'node:path';
import { pickRandomNode, TERMINAL_GENERATORS, TERMINAL_LIMITS, type TerminalLimits } from './generators';
import { ENTRY_POINTS, grammar, type FuzzerName, type Terminal } from '../grammar';
import { Grammar } from '../grammar/types';

/**
 * Expands the grammar into contracts.
 *
 * Every fuzzer shares the one grammar table and the one set of limits; a fuzzer is
 * just an entry nonterminal into that table plus a name for its output files.
 */
export class Fuzzer {
    private readonly startNode: string;
    private readonly grammar: Grammar;
    private readonly limits: TerminalLimits;
    private readonly MAX_DEPTH = 100;

    constructor(
        private readonly name: FuzzerName,
        private readonly outputDir: string,
        private readonly contractAmount: number,
        options: { grammar?: Grammar; limits?: TerminalLimits } = {},
    ) {
        this.startNode = ENTRY_POINTS[name];
        this.grammar = options.grammar ?? grammar;
        this.limits = options.limits ?? TERMINAL_LIMITS;
    }

    #generate(node: string, depth = 0): string {
        if (depth > this.MAX_DEPTH) return '';

        const alternatives = this.grammar[node];
        if (!alternatives) {
            const terminal = TERMINAL_GENERATORS[node as Terminal];
            // an unknown node is emitted as its own name, which is how the grammar
            // spells the handful of identifiers it means literally
            return terminal ? terminal(this.limits) : node;
        }

        const selected = pickRandomNode(alternatives);
        // a keyword list holds bare strings rather than sequences: nothing to expand
        if (!Array.isArray(selected)) return selected;
        return selected.map((subNode) => this.#generate(subNode, depth + 1)).join('');
    }

    generate(node: string = this.startNode): string {
        return this.#generate(node);
    }

    /** Writes this fuzzer's contracts and returns the paths written. */
    saveContracts(): string[] {
        fs.mkdirSync(this.outputDir, { recursive: true });

        const written: string[] = [];
        for (let i = 0; i < this.contractAmount; i++) {
            const filePath = path.join(this.outputDir, `${this.name}_contract_${i}.compact`);
            fs.writeFileSync(filePath, this.generate());
            written.push(filePath);
        }

        console.log(`generated ${written.length} contracts for '${this.name}' in ${this.outputDir}`);
        return written;
    }
}
