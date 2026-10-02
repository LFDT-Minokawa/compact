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

import { bytesToHex, hexToBytes } from '@noble/hashes/utils.js';

// Digest vectors over a range of `Bytes<N>` widths, shared by the keccak256
// and sha256 fixtures.
//
// `computed` digests come from @noble/hashes, which is a second implementation
// for persistentHash but not for keccak256, since the runtime computes keccak
// with that same library. Use `pinned` published digests for keccak.

/** A `Bytes<N>` input paired with its expected digest. */
export type LengthVector = {
    /** Input bytes as hex; the length picks which circuit runs. */
    input: string;
    /** The digest `input` should hash to, as hex. */
    digest: string;
    /** Optional note shown in failure messages. */
    label?: string;
};

/** A hash function over raw bytes. */
export type DigestFn = (input: Uint8Array) => Uint8Array;

/** Widths on and around the 31-byte field packing boundaries. */
export const packingWidths: readonly number[] = [
    1,
    ...Array.from({ length: 32 }, (_unused, index) => 32 + index),
    93,
    94,
];

/** A real-world size and a large multi-block input. */
export const largeWidths: readonly number[] = [376, 1024];

/** Every width the `multi_length` contracts export. */
export const sweepWidths: readonly number[] = [
    ...packingWidths,
    ...largeWidths,
];

/** Repeatable filler bytes, none of them zero. */
export function fillerBytes(length: number): Uint8Array {
    return Uint8Array.from({ length }, (_unused, index) => (index % 255) + 1);
}

/** A vector whose digest is computed by `digest`. */
export function computed(
    digest: DigestFn,
    input: Uint8Array,
    label?: string,
): LengthVector {
    const vector: LengthVector = {
        input: bytesToHex(input),
        digest: bytesToHex(digest(input)),
    };

    if (label !== undefined) {
        vector.label = label;
    }

    return vector;
}

/** A vector whose digest is a published constant, so it checks the hash itself. */
export function pinned(
    input: Uint8Array | string,
    digest: string,
    label?: string,
): LengthVector {
    const bytes = typeof input === 'string' ? hexToBytes(input) : input;
    const vector: LengthVector = { input: bytesToHex(bytes), digest };

    if (label !== undefined) {
        vector.label = label;
    }

    return vector;
}

/** One filler vector per width. */
export function sweepVectors(
    digest: DigestFn,
    widths: readonly number[] = sweepWidths,
): LengthVector[] {
    return widths.map((width) => computed(digest, fillerBytes(width)));
}

/** The `Bytes<N>` width of a vector. */
export function vectorWidth(vector: LengthVector): number {
    return vector.input.length / 2;
}

/** A short name for failure messages, such as `Bytes<62>`. */
export function vectorLabel(vector: LengthVector): string {
    const width = `Bytes<${vectorWidth(vector)}>`;

    return vector.label === undefined ? width : `${width} (${vector.label})`;
}

/** Finds the `hashBytes{N}` circuit, naming the width if it is missing. */
export function widthCircuit(
    pureCircuits: Record<string, unknown>,
    width: number,
): (value: Uint8Array) => Uint8Array {
    const name = `hashBytes${width}`;
    const circuit = pureCircuits[name];

    if (typeof circuit !== 'function') {
        throw new Error(
            `contract exposes no ${name} circuit; add it to the fixture contract or drop Bytes<${width}> from the sweep`,
        );
    }

    return circuit as (value: Uint8Array) => Uint8Array;
}

/** Hashes one vector through its circuit and compares the digest. */
export function checkWidthVector(
    pureCircuits: Record<string, unknown>,
    vector: LengthVector,
): void {
    const width = vectorWidth(vector);
    const circuit = widthCircuit(pureCircuits, width);
    const actual = circuit(hexToBytes(vector.input));

    if (!(actual instanceof Uint8Array)) {
        throw new Error(
            `hashBytes${width} did not return Uint8Array (got ${String(actual)})`,
        );
    }

    if (bytesToHex(actual) !== vector.digest) {
        throw new Error(
            `hashBytes${width} = 0x${bytesToHex(actual)}, expected 0x${vector.digest}`,
        );
    }
}
