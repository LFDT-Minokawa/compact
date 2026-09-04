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

const { asserts } = require('./grammar/assert.cjs');
const { circuit } = require('./grammar/circuit.cjs');
const { constructor } = require('./grammar/constructor.cjs');
const { enums } = require('./grammar/enum.cjs');
const { for_grammar } = require('./grammar/for.cjs');
const { if_grammar } = require('./grammar/if.cjs');
const { imports } = require('./grammar/imports.cjs');
const { include } = require('./grammar/include.cjs');
const { ledger } = require('./grammar/ledger.cjs');
const { module_grammar } = require('./grammar/module.cjs');
const { pragma } = require('./grammar/pragma.cjs');
const { struct } = require('./grammar/struct.cjs');
const { std_grammar } = require('./grammar/std.cjs');
const { witness } = require('./grammar/witness.cjs');
const { buildConfig } = require('./utils/config.cjs');
const Fuzzer = require('./utils/fuzzer.cjs');

function generate(outputDir, amount) {
    const assert_fuzzer = new Fuzzer(buildConfig(asserts, 'assert_statements', outputDir, 'assert', amount));
    assert_fuzzer.saveContracts();

    const circuit_fuzzer = new Fuzzer(buildConfig(circuit, 'circuit_statements', outputDir, 'circuit', amount));
    circuit_fuzzer.saveContracts();

    const constructor_fuzzer = new Fuzzer(buildConfig(constructor, 'constructor_statements', outputDir, 'constructor', amount));
    constructor_fuzzer.saveContracts();

    const enum_fuzzer = new Fuzzer(buildConfig(enums, 'enum_definitions', outputDir, 'enum', amount));
    enum_fuzzer.saveContracts();

    const for_fuzzer = new Fuzzer(buildConfig(for_grammar, 'for_statements', outputDir, 'for', amount));
    for_fuzzer.saveContracts();

    const if_fuzzer = new Fuzzer(buildConfig(if_grammar, 'if_statements', outputDir, 'if', amount));
    if_fuzzer.saveContracts();

    const import_fuzzer = new Fuzzer(buildConfig(imports, 'import_statements', outputDir, 'import', amount));
    import_fuzzer.saveContracts();

    const include_fuzzer = new Fuzzer(buildConfig(include, 'include_statements', outputDir, 'include', amount));
    include_fuzzer.saveContracts();

    const ledger_fuzzer = new Fuzzer(buildConfig(ledger, 'ledger_statements', outputDir, 'ledger', amount));
    ledger_fuzzer.saveContracts();

    const module_fuzzer = new Fuzzer(buildConfig(module_grammar, 'module_statements', outputDir, 'module', amount));
    module_fuzzer.saveContracts();

    const pragma_fuzzer = new Fuzzer(buildConfig(pragma, 'pragma_statements', outputDir, 'pragma', amount));
    pragma_fuzzer.saveContracts();

    const std_fuzzer = new Fuzzer(buildConfig(std_grammar, 'statements', outputDir, 'std', amount));
    std_fuzzer.saveContracts();
    
    const single_fuzzer = new Fuzzer(buildConfig(std_grammar, 'single_statements', outputDir, 'single', amount));
    single_fuzzer.saveContracts();

    const struct_fuzzer = new Fuzzer(buildConfig(struct, 'struct_definitions', outputDir, 'struct', amount));
    struct_fuzzer.saveContracts();

    const witness_fuzzer = new Fuzzer(buildConfig(witness, 'witness_statements', outputDir, 'witness', amount));
    witness_fuzzer.saveContracts();
}

exports.generate = generate;
