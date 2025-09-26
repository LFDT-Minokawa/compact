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
function pickRandomVersion() {
    const major = Math.floor(Math.random() * majorVersion);
    const minor = Math.floor(Math.random() * minorVersion);
    const patch = Math.floor(Math.random() * patchVersion);
    return `${major}.${minor}.${patch}`;
}

/*
 * Generator for string of different types and weights, currently we can generate:
 * - random - random string, from below presets
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
 * - bytes - malormed bytes
 */
function pickRandomString(type = 'random', options = {}) {
    const maxLength = options.length || 10;
    const length = options.exactLength ? maxLength : Math.floor(Math.random() * (maxLength + 1));

    const presets = {
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

    const weights = {
        normal: 74,
        digits: 2,
        symbols: 2,
        polish: 2,
        chinese: 2,
        japanese: 2,
        korean: 2,
        thai: 2,
        arabic: 2,
        hebrew: 2,
        emoji: 2,
        zalgo: 2,
        deseret: 2,
        bytes: 2,
        ...options.weights,
    };

    const activePresets = Object.entries(weights).filter(([_, w]) => w > 0);
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
        const preset = type === 'random' ? pickPreset() : type;
        const charset = presets[preset];
        const char = charset[Math.floor(Math.random() * charset.length)];
        result += char;
    }

    return result;
}

/*
 * Helper function to choose random type to return, based on weights we provide.
 */
function pickWeightedRandomType(weightedTypes) {
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
function generateBigInt(options, signed) {
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
 * - float: signed, unsigned
 * - bigint: signed, unsigned up to 2*1024.
 */
function pickRandomNumber(type = 'random', options = {}) {
    const weightTypes = [
        { type: 'zero', weight: 3 },
        { type: 'int', weight: 1 },
        { type: 'uint', weight: 50 },
        { type: 'float', weight: 1 },
        { type: 'ufloat', weight: 1 },
        { type: 'bigint', weight: 1 },
        { type: 'ubigint', weight: 43 },
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
 * Function to generate table for: for loop vector representation.
 */
function pickRandomTable(size = 100) {
    const array = [];

    for (let i = 1; i < Math.random() * size; i++) {
        array.push(`${i}`);
    }

    return array.toString();
}

/*
 * Function to generate nested for loops.
 */
function generateNestedFor(depth = 3) {
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
function generateNestedIf(depth = 3) {
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
function generateModules(depth = 3) {
    let result = '';
    for (let i = 0; i < depth; i++) {
        result += `module var_${i} {\n}\n`;
    }

    return result;
}

/*
 * Function to generate multiple module statements.
 */
function generateLargeEnum(depth = 3) {
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
function pickRandomNode(node) {
    return node[Math.floor(Math.random() * node.length)];
}

module.exports = {
    pickRandomVersion,
    pickRandomNumber,
    pickRandomString,
    pickRandomTable,
    pickRandomNode,
    generateNestedFor,
    generateNestedIf,
    generateModules,
    generateLargeEnum,
};
