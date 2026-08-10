// This file is part of Compact.
// Copyright (C) 2026 Midnight Foundation
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

// The runtime rejects a callee whose fingerprints disagree with the chain, so `expectedVk` has to be
// right. The composable suite checks harness fingerprints against harness keys, so it cannot see a
// wrong one. Here the keys are really `compactc`'s, so here the compiler's arithmetic is checked.

import { beforeAll, describe, expect, test } from 'vitest';
import { buildPathTo, compile, createTempFolder, ExitCodes, expectCompilerResult } from '@';
import { ContractOperation } from '@midnightntwrk/onchain-runtime-v4';
import * as acorn from 'acorn';
import { createHash } from 'node:crypto';
import fs from 'fs';
import path from 'path';

/**
 * Everything downstream is keyed by external name, so a contract whose two names coincide proves
 * nothing. `module_wpp` exports `$brad` — `M.brad` under `import M prefix $` — so they differ.
 */
const CONTRACT = buildPathTo('/wpp/module_wpp.compact');

/** The external name, and the internal one the table must not be keyed by. */
const EXTERNAL_NAME = '$brad';
const INTERNAL_NAME = 'brad';

/**
 * The `expectedVk` object literal, read out of the AST rather than matched by pattern.
 *
 * An unrecognized emission means the emitter moved, but an empty table would pass everything below
 * vacuously, so this throws.
 */
const readExpectedVk = (outputDir: string): Record<string, string> => {
    const file = path.join(outputDir, 'contract', 'index.js');
    const program = acorn.parse(fs.readFileSync(file, 'utf-8'), { ecmaVersion: 'latest', sourceType: 'module' });
    for (const node of program.body) {
        const declaration = node.type === 'ExportNamedDeclaration' ? node.declaration : undefined;
        if (declaration?.type !== 'VariableDeclaration') continue;
        for (const declarator of declaration.declarations) {
            if (declarator.id.type !== 'Identifier' || declarator.id.name !== 'expectedVk') continue;
            if (declarator.init?.type !== 'ObjectExpression') {
                throw new Error(`'expectedVk' in ${file} is a ${String(declarator.init?.type)}, not an object literal`);
            }
            return Object.fromEntries(
                declarator.init.properties.map((property) => {
                    if (property.type !== 'Property' || property.key.type !== 'Literal' || property.value.type !== 'Literal') {
                        throw new Error(`unrecognized entry in 'expectedVk' in ${file}: ${property.type}`);
                    }
                    return [String(property.key.value), String(property.value.value)];
                }),
            );
        }
    }
    throw new Error(`no 'expectedVk' export in ${file}`);
};

const sha256Hex = (bytes: Uint8Array): string => createHash('sha256').update(bytes).digest('hex');

const verifierKeyFile = (outputDir: string, circuitName: string): string =>
    path.join(outputDir, 'keys', `${circuitName}.verifier`);

describe('[Expected verifier keys] Compiler', () => {
    let outputDir: string;
    let expectedVk: Record<string, string>;
    let generatedKeys: string[];

    beforeAll(async () => {
        outputDir = createTempFolder();
        expectCompilerResult(await compile([CONTRACT, outputDir])).toMatchExitCode(ExitCodes.Success);

        expectedVk = readExpectedVk(outputDir);
        generatedKeys = fs
            .readdirSync(path.join(outputDir, 'keys'))
            .filter((name) => name.endsWith('.verifier'))
            .map((name) => name.slice(0, -'.verifier'.length));
    }, 300_000);

    test('keys were generated at all', () => {
        // A missing `zkir` is a warning, not an error, so the compiler emits `expectedVk = {}`.
        // We need to ensure that all keys are actually generated or every test below would hold vacuously.
        expect(generatedKeys.length).toBeGreaterThan(0);
        expect(Object.keys(expectedVk).length).toBeGreaterThan(0);
    });

    test('every fingerprint is the SHA-256 of the key the compiler wrote', () => {
        for (const [circuitName, fingerprint] of Object.entries(expectedVk)) {
            const keyFile = verifierKeyFile(outputDir, circuitName);
            expect(fs.existsSync(keyFile), `${keyFile} missing`).toBe(true);
            expect(fingerprint, `fingerprint for '${circuitName}'`).toEqual(sha256Hex(fs.readFileSync(keyFile)));
        }
    });

    test('the table covers exactly the circuits keys were generated for', () => {
        // A subset leaves a circuit with nothing to check a callee against, a superset names a key
        // that was never written.
        expect(Object.keys(expectedVk).sort()).toEqual(generatedKeys.sort());
    });

    test('fingerprints are keyed by external circuit name', () => {
        expect(Object.keys(expectedVk)).toContain(EXTERNAL_NAME);
        expect(Object.keys(expectedVk)).not.toContain(INTERNAL_NAME);
    });

    test('the ledger accepts the keys those fingerprints are taken over', () => {
        // These bytes are the ones a deployment installs on an operation, so the ledger's own setter
        // has to accept them.
        for (const circuitName of Object.keys(expectedVk)) {
            const key = new Uint8Array(fs.readFileSync(verifierKeyFile(outputDir, circuitName)));
            const operation = new ContractOperation();
            operation.verifierKey = key;
            expect(sha256Hex(operation.verifierKey), `round trip for '${circuitName}'`).toEqual(expectedVk[circuitName]);
        }
    });
});
