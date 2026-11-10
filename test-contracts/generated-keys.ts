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

import { createHash } from 'node:crypto';
import fs from 'node:fs/promises';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

import { ContractOperation } from '@midnightntwrk/onchain-runtime-v4';

type KeyKind = 'prover' | 'verifier';

type ManifestFile = {
    size?: unknown;
    hash?: unknown;
};

// The version is left open so that a zkir upgrade does not fail every fixture.
const keyHeaders: Record<KeyKind, RegExp> = {
    prover: /^midnight:prover-key\[v\d+\](?:\([^)]*\))?:/,
    verifier: /^midnight:verifier-key\[v\d+\]:/,
};

/**
 * Checks the prover and verifier keys of a successful compile and returns one
 * message per problem. These checks only read the files: no proof is made, so
 * a key whose data is wrong but well formed still passes.
 */
export async function checkGeneratedKeys(outputDir: string): Promise<string[]> {
    const problems: string[] = [];
    const circuits = await readProofCircuits(outputDir);
    const keyFiles = await listKeyFiles(outputDir);
    const expectedFiles = circuits.flatMap((circuit) => [
        keyFileName(circuit, 'prover'),
        keyFileName(circuit, 'verifier'),
    ]);

    for (const name of expectedFiles) {
        if (!keyFiles.includes(name)) {
            problems.push(`keys/${name} is missing`);
        }
    }

    for (const name of keyFiles) {
        if (!expectedFiles.includes(name)) {
            problems.push(
                `keys/${name} has no matching proof circuit in contract-info.json`,
            );
        }
    }

    const manifest = await readKeyManifest(outputDir);
    const expectedVk = await readExpectedVk(outputDir);

    for (const name of Object.keys(manifest)) {
        if (!keyFiles.includes(name)) {
            problems.push(
                `contract-manifest.json lists keys/${name}, which does not exist`,
            );
        }
    }

    for (const circuit of Object.keys(expectedVk)) {
        if (!circuits.includes(circuit)) {
            problems.push(
                `expectedVk has an entry for '${circuit}', which is not a proof circuit`,
            );
        }
    }

    for (const circuit of circuits) {
        for (const kind of ['prover', 'verifier'] as const) {
            const name = keyFileName(circuit, kind);

            if (!keyFiles.includes(name)) {
                continue;
            }

            const bytes = await fs.readFile(path.join(outputDir, 'keys', name));
            const hash = sha256Hex(bytes);

            problems.push(...checkKeyBytes(name, kind, bytes));
            problems.push(
                ...checkManifestEntry(name, manifest[name], bytes, hash),
            );

            if (kind === 'verifier' && expectedVk[circuit] !== hash) {
                problems.push(
                    `expectedVk['${circuit}'] is ${String(expectedVk[circuit])}, but keys/${name} hashes to ${hash}`,
                );
            }
        }
    }

    return problems;
}

/**
 * Checks one key file's header and, for a verifier key, that the ledger can
 * read it the way it does when a contract is deployed.
 */
function checkKeyBytes(name: string, kind: KeyKind, bytes: Buffer): string[] {
    const header = keyHeaders[kind].exec(
        bytes.subarray(0, 128).toString('latin1'),
    );

    if (header === null) {
        return [
            `keys/${name} does not start with a midnight:${kind}-key header`,
        ];
    }

    if (bytes.length <= header[0].length) {
        return [`keys/${name} has no data after its header`];
    }

    if (kind === 'verifier') {
        try {
            new ContractOperation().verifierKey = new Uint8Array(bytes);
        } catch (error) {
            return [
                `the ledger cannot read keys/${name}: ${error instanceof Error ? error.message : String(error)}`,
            ];
        }
    }

    return [];
}

/**
 * Compares one key file with its size and hash in contract-manifest.json.
 */
function checkManifestEntry(
    name: string,
    entry: ManifestFile | undefined,
    bytes: Buffer,
    hash: string,
): string[] {
    if (entry === undefined) {
        return [`contract-manifest.json does not list keys/${name}`];
    }

    if (entry.size !== bytes.length || entry.hash !== hash) {
        return [
            `contract-manifest.json lists keys/${name} as ${String(entry.size)} bytes with hash ${String(entry.hash)}, but the file is ${bytes.length} bytes with hash ${hash}`,
        ];
    }

    return [];
}

/**
 * Reads the names of the circuits that need a proof, and so need keys.
 */
async function readProofCircuits(outputDir: string): Promise<string[]> {
    const info = JSON.parse(
        await fs.readFile(
            path.join(outputDir, 'compiler', 'contract-info.json'),
            'utf8',
        ),
    ) as { circuits?: Array<{ name: string; proof?: boolean }> };

    return (info.circuits ?? [])
        .filter((circuit) => circuit.proof === true)
        .map((circuit) => circuit.name);
}

/**
 * Lists the files in keys/. A contract with no proof circuits has no keys/.
 */
async function listKeyFiles(outputDir: string): Promise<string[]> {
    try {
        return await fs.readdir(path.join(outputDir, 'keys'));
    } catch (error) {
        if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
            return [];
        }

        throw error;
    }
}

/**
 * Reads the keys entries of contract-manifest.json.
 */
async function readKeyManifest(
    outputDir: string,
): Promise<Record<string, ManifestFile>> {
    const manifest = JSON.parse(
        await fs.readFile(
            path.join(outputDir, 'compiler', 'contract-manifest.json'),
            'utf8',
        ),
    ) as { keys?: Record<string, unknown> };
    const entries: Record<string, ManifestFile> = {};

    for (const [name, entry] of Object.entries(manifest.keys ?? {})) {
        if (typeof entry === 'object' && entry !== null) {
            entries[name] = entry as ManifestFile;
        }
    }

    return entries;
}

/**
 * Reads the verifier key hashes the compiler embedded in the contract module.
 */
async function readExpectedVk(
    outputDir: string,
): Promise<Record<string, unknown>> {
    const module = (await import(
        pathToFileURL(path.join(outputDir, 'contract', 'index.js')).href
    )) as { expectedVk?: unknown };

    if (typeof module.expectedVk !== 'object' || module.expectedVk === null) {
        throw new Error(
            `${outputDir}/contract/index.js does not export expectedVk`,
        );
    }

    return module.expectedVk as Record<string, unknown>;
}

function keyFileName(circuit: string, kind: KeyKind) {
    return `${circuit}.${kind}`;
}

function sha256Hex(bytes: Buffer) {
    return createHash('sha256').update(bytes).digest('hex');
}
