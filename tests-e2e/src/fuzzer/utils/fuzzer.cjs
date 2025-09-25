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

const fs = require('fs');
const path = require('node:path');
const {
    pickRandomNode,
    pickRandomVersion,
    pickRandomString,
    pickRandomNumber,
    pickRandomTable,
    randomMixedTable,
    generateNestedFor,
    generateNestedIf,
    generateModules, generateLargeEnum,
} = require('./generators.cjs');

class Fuzzer {
    constructor(config) {
        this.startNode = config.startNode;
        this.grammar = config.grammar;
        this.outputName = config.outputName;
        this.contractAmount = config.contractAmount;
        this.outputDir = config.outputDir;
        this.numberPower = config.numberPower;
        this.stringLength = config.stringLength;
        this.tableLength = config.tableLength;
        this.MAX_DEPTH = 100;
    }

    #generate(node, depth = 0) {
        if (depth > this.MAX_DEPTH) return '';

        if (!this.grammar[node]) {
            // TODO: how to configure that ?
            if (node === 'random_version') return pickRandomVersion();
            if (node === 'random_string') return pickRandomString('random', { length: this.stringLength, exactLength: false });
            if (node === 'random_number') return pickRandomNumber('random', { bigIntSize: this.numberPower });
            if (node === 'small_random_number') return pickRandomNumber('random', { bigIntSize: 16 });
            if (node === 'random_table') return pickRandomTable(this.tableLength);
            if (node === 'random_mixed_table') return randomMixedTable(this.tableLength);
            if (node === 'generate_nested_for') return generateNestedFor(8);
            if (node === 'generate_nested_if') return generateNestedIf(1000);
            if (node === 'generate_modules') return generateModules(10000);
            if (node === 'generate_large_enum') return generateLargeEnum(10000);
            return node;
        }

        // handle terminal nodes differently, do not run recursion there
        const terminal_nodes = ['javascript_keywords', 'compact_keywords', 'other_keywords'];
        if (terminal_nodes.includes(node)) {
            return pickRandomNode(this.grammar[node]);
        }

        const selected = pickRandomNode(this.grammar[node]);
        return selected.map((subNode) => this.#generate(subNode, depth + 1)).join('');
    }

    generate(node = this.startNode) {
        return this.#generate(node);
    }

    saveContracts() {
        if (!fs.existsSync(this.outputDir)) {
            fs.mkdirSync(this.outputDir);

            console.log(`directory: '${this.outputDir}' created.`);
        } else {
            console.log(`directory: '${this.outputDir}' already exists.`);
        }

        for (let i = 0; i < this.contractAmount; i++) {
            const contract = this.generate();
            fs.writeFileSync(path.join(this.outputDir, `${this.outputName}_contract_${i}.compact`), contract);
            console.log(`generated contract: ${i} for: ${this.outputName}`);
        }

        return fs.readdirSync(this.outputDir);
    }
}

module.exports = Fuzzer;
