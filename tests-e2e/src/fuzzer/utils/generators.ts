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

/*
 * Terminal generators: the parts of the output that are produced rather than
 * derived from a production. Everything structural lives in grammar/compact.ts.
 */

import { Alternative, Production, Token } from '../grammar/types';
import { Terminal } from '../grammar/compact';

export type StringPreset =
    | 'normal' | 'digits' | 'symbols' | 'polish' | 'chinese' | 'japanese' | 'korean'
    | 'thai' | 'arabic' | 'hebrew' | 'emoji' | 'zalgo' | 'deseret' | 'bytes';

export type NumberKind =
    | 'zero' | 'int' | 'uint' | 'hex' | 'binary' | 'octal' | 'float' | 'ufloat' | 'bigint' | 'ubigint';

export interface StringOptions {
    length?: number;
    exactLength?: boolean;
    weights?: Partial<Record<StringPreset, number>>;
}

export interface NumberOptions {
    bigIntSize?: number;
}

const majorVersion = 5;
const minorVersion = 10;
const patchVersion = 20;
const alphabet = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ';
const digits = '0123456789';
const signs = '§!@£$%^&*()_+{}:"|?><±! ±~`.,/;][-=#';
const polish = 'ąćęłńóśźżĄĆĘŁŃÓŚŹŻ';

/*
 * Simple generator for proper version of language or compiler.
 * Generates data in form of: major.minor.patch version.
 */
export function pickRandomVersion(): string {
    const major = Math.floor(Math.random() * majorVersion);
    const minor = Math.floor(Math.random() * minorVersion);
    const patch = Math.floor(Math.random() * patchVersion);
    return `${major}.${minor}.${patch}`;
}

/*
 * The character sets, built once. These were rebuilt on every call, which cost
 * around 30us a call -- fourteen strings, six of them assembled a character at a
 * time -- and made string generation the bulk of the time spent generating a
 * contract. They are constant, so there is nothing to rebuild.
 */
const PRESETS: Record<StringPreset, string> = {
    normal: alphabet,
    digits: alphabet + digits,
    symbols: alphabet + signs,
    polish: alphabet + polish,
    chinese: Array.from({ length: 200 }, (_, i) => String.fromCharCode(0x4e00 + i)).join(''),
    japanese: Array.from({ length: 200 }, (_, i) => String.fromCharCode(0x3040 + i)).join(''),
    korean: Array.from({ length: 200 }, (_, i) => String.fromCharCode(0xac00 + i)).join(''),
    thai: Array.from({ length: 100 }, (_, i) => String.fromCharCode(0x0e00 + i)).join(''),
    arabic: Array.from({ length: 100 }, (_, i) => String.fromCharCode(0x0600 + i)).join(''),
    hebrew: Array.from({ length: 50 }, (_, i) => String.fromCharCode(0x0590 + i)).join(''),
    emoji: ['😀', '🤖', '❤️', '🔥', '💀', '👻', '🎉', '😎', '🧠', '🍕', '🪐', '🐉'].join(''),
    zalgo: 'H̶E̷L̷L̸O̴W̵O̴R̷L̶D̸',
    deseret: Array.from({ length: 50 }, (_, i) => String.fromCharCode(0x10400 + i)).join(''),
    bytes: Array.from({ length: 128 }, (_, i) => String.fromCharCode(i)).join(''),
};

/* Mostly ordinary identifiers, with a long tail of everything else. */
const DEFAULT_WEIGHTS: Record<StringPreset, number> = {
    normal: 1000,
    digits: 1,
    symbols: 1,
    polish: 1,
    chinese: 1,
    japanese: 1,
    korean: 1,
    thai: 1,
    arabic: 1,
    hebrew: 1,
    emoji: 1,
    zalgo: 1,
    deseret: 1,
    bytes: 1,
};

/*
 * Generator for string of different types and weights, currently we can generate:
 * - random - random string, from the presets above
 * - normal - normal alphabet
 * - digits - normal alphabet + digits
 * - symbols - normal alphabet + symbols
 * - polish - normal alphabet + Polish diacritic characters
 * - chinese - chinese symbols
 * - japanse - japanese symbols
 * - korean - korean symbols
 * - thai - thai symbols
 * - arabic - arabic symbols
 * - hebrew - hebrew symbols
 * - emoji - emoji examples
 * - zalgo - zalgo examples
 * - deseret - rare alphabets like gothic
 * - bytes - malformed bytes
 */
export function pickRandomString(type: StringPreset | 'random' = 'random', options: StringOptions = {}): string {
    const maxLength = options.length || 10;
    const length = options.exactLength ? maxLength : Math.floor(Math.random() * (maxLength + 1));

    const weights = options.weights ? { ...DEFAULT_WEIGHTS, ...options.weights } : DEFAULT_WEIGHTS;

    const activePresets = (Object.entries(weights) as [StringPreset, number][]).filter(([, w]) => w > 0);
    const totalWeight = activePresets.reduce((sum, [_, w]) => sum + w, 0);

    const pickPreset = () => {
        let rand = Math.random() * totalWeight;
        for (const [preset, weight] of activePresets) {
            if (rand < weight) return preset;
            rand -= weight;
        }

        return activePresets[activePresets.length - 1][0];
    };

    let result = '';

    for (let i = 0; i < length; i++) {
        const preset: StringPreset = type === 'random' ? pickPreset() : type;
        const charset = PRESETS[preset];
        const char = charset[Math.floor(Math.random() * charset.length)];
        result += char;
    }

    return result;
}

/*
 * Helper function to choose random type to return, based on weights we provide.
 */
function pickWeightedRandomType(weightedTypes: { type: NumberKind; weight: number }[]): NumberKind {
    const totalWeight = weightedTypes.reduce((sum, entry) => sum + entry.weight, 0);
    const rand = Math.random() * totalWeight;

    let cumulative = 0;

    for (const entry of weightedTypes) {
        cumulative += entry.weight;
        if (rand < cumulative) {
            return entry.type;
        }
    }

    return weightedTypes[weightedTypes.length - 1].type;
}

/*
 * Generator for bigint numbers, with sign switching
 */
function generateBigInt(options: NumberOptions, signed: boolean): bigint {
    const bits = options.bigIntSize || 1024;
    const sign = signed ? -1n : 1n;

    let value = 0n;
    for (let i = 0n; i < BigInt(bits); i++) {
        if (Math.random() < 0.5) {
            value |= 1n << i;
        }
    }

    return sign * value;
}

/*
 * Generator for numbers of different types and weights, currently we can generate:
 * - zero: just zero
 * - int: signed, unsigned
 * - hex: hexadecimal (based on uint)
 * - binary: binary (based on uint)
 * - octal: binary (based on uint)
 * - float: signed, unsigned
 * - bigint: signed, unsigned up to 2*1024.
 */
export function pickRandomNumber(type: NumberKind | 'random' = 'random', options: NumberOptions = {}): string | number | bigint {
    const weightTypes: { type: NumberKind; weight: number }[] = [
        { type: 'zero', weight: 3 },
        { type: 'int', weight: 1 },
        { type: 'uint', weight: 50 },
        { type: 'hex', weight: 5 },
        { type: 'binary', weight: 5 },
        { type: 'octal', weight: 5 },
        { type: 'float', weight: 1 },
        { type: 'ufloat', weight: 1 },
        { type: 'bigint', weight: 1 },
        { type: 'ubigint', weight: 28 },
    ];

    if (type === 'random') {
        type = pickWeightedRandomType(weightTypes);
    }

    switch (type) {
        case 'zero':
            return 0;
        case 'int':
            return Math.floor(Math.random() * 2 ** 32) - 2 ** 32;
        case 'uint':
            return Math.floor(Math.random() * 2 ** 32);
        case 'hex':
            return "0x" + (Math.floor(Math.random() * 2 ** 32)).toString(16);
        case 'binary':
            return "0b" + (Math.floor(Math.random() * 2 ** 32)).toString(2);
        case 'octal':
            return "0o" + (Math.floor(Math.random() * 2 ** 32)).toString(8);
        case 'float':
            return Math.random() * 2e6 - 1e6;
        case 'ufloat':
            return Math.random() * 1e6;
        case 'bigint':
            return generateBigInt(options, true);
        case 'ubigint':
            return generateBigInt(options, false);
        default:
            throw new Error(`Unknown type: ${type}`);
    }
}

/*
 * Function to generate table for - for loop vector representation.
 */
export function pickRandomTable(size = 100): string {
    const array: string[] = [];

    for (let i = 1; i < Math.random() * size; i++) {
        array.push(`${i}`);
    }

    return array.toString();
}

/*
 * Function to generate table with mixed data.
 */
export function randomMixedTable(size = 10): (string | number | bigint | boolean | undefined)[] {
    return Array.from( {length: size }, () => {
       const choice = Math.floor(Math.random() * 4);
       const number = pickRandomNumber('random', { bigIntSize: 128 });
       
       switch (choice) {
           case 0:
               return number;
           case 1:
               return true;
           case 2: 
               return false;
           case 3:
               return `"${Array.from({ length: 10 }, () => alphabet[Math.floor(Math.random() * alphabet.length)]).join('')}"`;
       }
    });
}

/*
 * Function to generate nested for loops.
 */
export function generateNestedFor(depth = 3): string {
    let result = '';
    for (let i = 0; i < depth; i++) {
        result += 'for(const bob of 1..10) {\n';
    }
    result += 'assert 1 != 2 "Secret message"; \n';

    for (let i = 1; i <= depth; i++) {
        result += '}\n';
    }

    return result;
}

/*
 * Function to generate nested if statements.
 */
export function generateNestedIf(depth = 3): string {
    let result = '';
    for (let i = 0; i < depth; i++) {
        result += 'if (true != false) {\n';
    }
    result += 'assert 1 != 2 "Secret message"; \n';

    for (let i = 1; i <= depth; i++) {
        result += '}\n';
    }

    return result;
}

/*
 * Function to generate multiple module statements.
 */
export function generateModules(depth = 3): string {
    let result = '';
    for (let i = 0; i < depth; i++) {
        result += `module var_${i} {\n}\n`;
    }

    return result;
}

/*
 * Function to generate multiple module statements.
 */
export function generateLargeEnum(depth = 3): string {
    let result = 'export enum bob {';

    for (let i = 0; i < depth; i++) {
        result += `var_${i}, `;
    }

    result += '};\n';
    return result;
}

/*
 * Function to pick random node from existing grammar.
 */
export function pickRandomNode(node: Production): Alternative | Token {
    return node[Math.floor(Math.random() * node.length)];
}

/** How much the generators above are allowed to produce. */
export interface TerminalLimits {
    stringLength: number;
    numberPower: number;
    tableLength: number;
}

export const TERMINAL_LIMITS: TerminalLimits = {
    stringLength: 32,
    numberPower: 128,
    tableLength: 200,
};

/*
 * One generator per terminal the grammar declares. Typing this as
 * `Record<Terminal, ...>` is what keeps the two in step: a name in `TERMINALS`
 * with no generator here, or a generator here for a name the grammar does not
 * declare, is a compile error. Previously this was a chain of `if (node === ...)`
 * in the Fuzzer and a separate hand-written list in the grammar, and nothing
 * checked that they matched -- a terminal missing from the chain is not an error,
 * it is silently emitted into the contract as its own name.
 */
export const TERMINAL_GENERATORS: Record<Terminal, (limits: TerminalLimits) => string> = {
    random_version: () => pickRandomVersion(),
    random_string: (l) => pickRandomString('random', { length: l.stringLength, exactLength: false }),
    random_number: (l) => String(pickRandomNumber('random', { bigIntSize: l.numberPower })),
    // bigIntSize 10 guarantees a value <= 2^10
    very_small_random_number: () => String(pickRandomNumber('ubigint', { bigIntSize: 10 })),
    small_random_number: () => String(pickRandomNumber('random', { bigIntSize: 16 })),
    random_table: (l) => pickRandomTable(l.tableLength),
    random_mixed_table: (l) => String(randomMixedTable(l.tableLength)),
    generate_nested_for: () => generateNestedFor(8),
    generate_nested_if: () => generateNestedIf(1000),
    generate_modules: () => generateModules(10000),
    generate_large_enum: () => generateLargeEnum(10000),
};
