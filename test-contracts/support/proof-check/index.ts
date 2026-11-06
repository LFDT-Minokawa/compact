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

/**
 * Checks a circuit call against the fixture's ZKIR, as a prover would.
 *
 * A runtime test only runs the generated JavaScript, which skips the side of a
 * branch that is not taken. The ZKIR circuit has no branches: it runs every
 * instruction on every call and selects the results afterwards. A ZKIR
 * instruction that fails on the side that is not taken therefore breaks
 * proving while the JavaScript still returns the right result, and only a
 * check like this one catches it.
 *
 * Imported by fixtures as `@test/proof-check`. It needs the fixture's
 * `.build/zkir/` output, so it only works for impure circuits.
 */

import { readFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
    proofDataIntoSerializedPreimage,
    type CallProofData,
} from '@midnight-ntwrk/compact-runtime';
import { check, jsonIrToBinary } from '@midnightntwrk/zkir-v3';

import { fixtureOutputDir } from '../../utils.ts';

/** The part of a circuit call's result that the check reads. */
export interface ProvableCallResult {
    readonly context: {
        readonly callProofDataTrace: readonly CallProofData[];
    };
}

/**
 * Runs `call`, a call of the exported circuit `circuitId`, through the
 * fixture's ZKIR with the inputs, outputs and transcripts the JavaScript
 * recorded, and throws if the ZKIR rejects them. `metaUrl` is the runtime
 * test's `import.meta.url`.
 *
 * The circuit is named here because `createTestContract` leaves the context's
 * circuit id at `constructor`, so the proof data does not carry the right one.
 */
export async function checkProof(
    metaUrl: string,
    circuitId: string,
    call: ProvableCallResult,
): Promise<void> {
    const proofData = call.context.callProofDataTrace.at(-1);

    if (proofData === undefined) {
        throw new Error('the circuit call recorded no proof data');
    }

    const zkirDir = path.join(
        fixtureOutputDir(path.dirname(fileURLToPath(metaUrl))),
        'zkir',
    );
    const zkirFile = path.join(zkirDir, `${circuitId}.zkir`);
    const json = await readFile(zkirFile, 'utf-8');
    const { major } = JSON.parse(json).version as { major: number };

    if (major !== 3) {
        throw new Error(
            `${zkirFile} is ZKIR v${major}, but the proof check only runs v3`,
        );
    }

    const ir = jsonIrToBinary(json);
    const preimage = proofDataIntoSerializedPreimage(
        proofData.input,
        proofData.output,
        proofData.publicTranscript,
        proofData.privateTranscriptOutputs,
        circuitId,
    );

    await check(preimage, {
        lookupKey: async (keyLocation) =>
            keyLocation === circuitId
                ? {
                      proverKey: new Uint8Array(0),
                      verifierKey: new Uint8Array(0),
                      ir,
                  }
                : undefined,
        // Checking runs the circuit without proving, so it needs no
        // parameters.
        getParams: async (k) => {
            throw new Error(
                `the proof check asked for proving parameters (k = ${k})`,
            );
        },
    });
}
