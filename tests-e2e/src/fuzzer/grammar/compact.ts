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
 * The Compact fuzzer grammar. One table, one file, grouped by language category.
 *
 * Every production and every literal Compact token lives here. Nothing else
 * spells Compact syntax: shapes.ts is list combinators with no Compact in them,
 * index.ts assembles and checks, utils/ generates the terminals. The grammar used
 * to be spread over fifteen modules plus the helpers and the entry-point map, and
 * it drifted.
 *
 *   TERMINALS      produced by utils/generators.ts; declared here so they can be checked
 *   ENTRY_POINTS   which nonterminal each fuzzer starts from
 *   constructors   the syntax shapes the language repeats (calls, bindings, ...)
 *   harness        the contract each fuzzer wraps around what it is testing
 *   lexical        terminators, separators, keywords, operators
 *   types          std and ledger types, generics
 *   declarations   pragma, import, include, module, ledger, witness, struct, enum,
 *                  constructor, circuit
 *   statements     bindings, if, for, return, assert
 *   expressions    conditions and operands
 *   ledgerAdts     Kernel, Counter, Set, Map, List, MerkleTree, HistoricMerkleTree
 *   stdlib         standard library and native circuits
 *
 */

import { Alternative, Token, Grammar } from './types';
import { join } from './shapes';

/* ================================================================== *
 * Terminals and entry points
 * ================================================================== */

/*
 * Produced by a generator in utils/generators.ts rather than by a production here.
 * This list is the single source of truth: `TERMINAL_GENERATORS` there is typed as
 * `Record<Terminal, ...>`, so adding a name here without writing its generator (or
 * the reverse) is a compile error rather than a token emitted as literal text.
 */
export const TERMINALS = [
    'random_version', 'random_string', 'random_number', 'very_small_random_number',
    'small_random_number', 'random_table', 'random_mixed_table',
    'generate_nested_for', 'generate_nested_if', 'generate_modules', 'generate_large_enum',
] as const;

export type Terminal = (typeof TERMINALS)[number];

export const ENTRY_POINTS = {
    assert: 'assert_statements',
    circuit: 'circuit_statements',
    constructor: 'constructor_statements',
    enum: 'enum_definitions',
    for: 'for_statements',
    if: 'if_statements',
    import: 'import_statements',
    include: 'include_statements',
    ledger: 'ledger_statements',
    module: 'module_statements',
    pragma: 'pragma_statements',
    std: 'statements',
    single: 'single_statements',
    struct: 'struct_definitions',
    witness: 'witness_statements',
} as const;

/** The fuzzers, named by their entry nonterminal above. */
export type FuzzerName = keyof typeof ENTRY_POINTS;

/* ================================================================== *
 * Syntax constructors
 *
 * The only place the punctuation of a contract preamble, a call, a method call,
 * a generic argument list or a const binding is written down.
 * ================================================================== */

const contract = (...parts: Token[]): Alternative => ['import CompactStandardLibrary;', 'line_separator', ...parts];

const generics = (nodes: Token[]): Token[] => (nodes.length ? ['<', ...join(nodes, ','), '>'] : []);

/*
 * Calls take an explicit argument list rather than one node repeated `arity`
 * times: the arguments of a call are independent, and the hand-written grammar
 * this table replaced varied them independently. Use `same()` for the uniform case.
 */
const call = (name: Token, genericNodes: Token[], argNodes: Token[]): Alternative =>
    [name, ...generics(genericNodes), '(', ...join(argNodes, ', '), ')'];

const method = (receiver: Token, op: Token, argNodes: Token[]): Alternative =>
    ['optional_statement_variable', receiver + op + '(', ...join(argNodes, ', '), ')', 'valid_end_line'];

const same = (node: Token, arity: number): Token[] => Array.from({ length: arity }, () => node);

/**
 * Argument lists of length `arity` drawn from `choices`: every argument the same,
 * plus -- for arity > 1 -- every list with a single argument switched, and -- for
 * arity > 2 -- the alternating lists. The full cross product is exponential and,
 * for a fuzzer, mostly redundant; these are the shapes the old per-call lists
 * spelled out by hand (for arity 2 it is exactly the four they listed).
 */
const argLists = (arity: number, choices: Token[]): Token[][] => {
    if (arity === 0) return [[]];
    const lists = choices.map((choice) => same(choice, arity));
    if (arity > 1) {
        for (const base of choices) {
            for (const other of choices) {
                if (other === base) continue;
                for (let i = 0; i < arity; i++) {
                    const list = same(base, arity);
                    list[i] = other;
                    lists.push(list);
                }
            }
        }
    }
    if (arity > 2) {
        for (let offset = 0; offset < choices.length; offset++) {
            lists.push(Array.from({ length: arity }, (_, i) => choices[(i + offset) % choices.length]));
        }
    }
    const seen = new Set<string>();
    return lists.filter((list) => {
        const key = JSON.stringify(list);
        if (seen.has(key)) return false;
        seen.add(key);
        return true;
    });
};

/* Somewhere the grammar wants an identifier: a name, a prefix, a parameter. */
const identifierPosition = (extra: Alternative[] = []): Alternative[] => [
    ['random_string'],
    ['random_keyword'],
    ['random_table'],
    ['random_version'],
    ['random_number'],
    ...extra,
];

/* The value shapes a generated `const` can bind, without their terminator. */
const BINDING_VALUES: Record<string, (name: Token, typeNode: Token) => Alternative> = {
    default: (n, t) => ['const ', n, ' = ', 'default<', t, '>'],
    typedDefault: (n, t) => ['const ', n, ' : ', t, ' = ', 'default<', t, '>'],
    pad: (n) => ['const ', n, ' = ', 'pad(', 'random_number', ', "', 'random_string', '")'],
    smallNumber: (n) => ['const ', n, ' = ', 'small_random_number'],
    number: (n) => ['const ', n, ' = ', 'random_number'],
    string: (n) => ['const ', n, ' = ', 'random_string'],
    sliceOfDefault: (n, t) => ['const ', n, ' = ', 'slice<', 'random_number', '>(default<', t, '>, ', 'random_number', ')'],
    sliceOfTuple: (n) => ['const ', n, ' = ', 'slice<', 'random_number', '>([', 'random_mixed_table', '], ', 'random_number', ')'],
    // slice() takes a value; a type there cannot parse
    sliceOfType: (n, t) => ['const ', n, ' = ', 'slice<', 'random_number', '>(', t, ', ', 'random_number', ')'],
    spreadSliceOfType: (n, t) => ['const ', n, ' = ', '[...slice<', 'random_number', '>(', t, ', ', 'random_number', ')]'],
};

/*
 * How each shape terminates. These bindings are the preamble that sets up the
 * statement under test, so a shape terminated with `valid_end_line` always reaches
 * it, while one terminated with `end_line` is invalid half the time by design.
 * Giving every shape the fuzzed terminator looks tidier but costs coverage
 * geometrically: it takes a four-binding preamble from always valid to 1 in 16,
 * so the statement being fuzzed is almost never reached.
 */
const BINDING_TERMINATOR: Record<string, Token> = {
    default: 'valid_end_line',
    typedDefault: 'valid_end_line',
    pad: 'valid_end_line',
    smallNumber: 'end_line',
    number: 'end_line',
    string: 'end_line',
    sliceOfDefault: 'end_line',
    sliceOfTuple: 'end_line',
    sliceOfType: 'end_line',
    spreadSliceOfType: 'end_line',
};

const bindings = (name: Token, kinds: string[], typeNode: Token = 'valid_types', terminator?: Token): Alternative[] =>
    kinds.map((kind) => [...BINDING_VALUES[kind](name, typeNode), terminator ?? BINDING_TERMINATOR[kind]]);

const ASSERT_BINDINGS = ['default', 'pad', 'spreadSliceOfType', 'sliceOfType', 'sliceOfDefault'];
const IF_BINDINGS = ['default', 'typedDefault', 'smallNumber', 'number', 'string', 'sliceOfType', 'sliceOfDefault'];
const STATEMENT_BINDINGS = ['default', 'smallNumber'];
const STATEMENT_TYPE = 'statement_valid_types';

/*
 * The names the `std` and `single` preambles bind, in the order they are bound.
 * They are the operands every statement under test draws on, so this one list
 * drives the bindings themselves, the `statement_variable` operand, and the
 * literal argument lists of the ledger calls below.
 */
const PREAMBLE_VARS: Token[] = ['bob', 'tom', 'greg', 'adonis'];

/**
 * One binding production per preamble name, all sharing a set of shapes.
 * `extra` adds shapes to a single binding, by index.
 */
const preambleBindings = (
    prefix: string,
    count: number,
    kinds: string[],
    options: { typeNode?: Token; terminator?: Token; extra?: Record<number, string[]> } = {},
): Grammar =>
    Object.fromEntries(
        PREAMBLE_VARS.slice(0, count).map((name, i) => [
            `${prefix}${name}`,
            bindings(name, [...kinds, ...(options.extra?.[i] ?? [])], options.typeNode, options.terminator),
        ]),
    );

/** The names of those productions, in binding order, for the body that uses them. */
const preambleRefs = (prefix: string, count: number): Token[] =>
    PREAMBLE_VARS.slice(0, count).map((name) => `${prefix}${name}`);

const prefix = (before: Token, alternative: Alternative, after: Token): Alternative => [
    before,
    ...alternative,
    after,
];

const assertStatement: Alternative[] = [['assert (', ' 1 < 2 ', ', ', '"Secret message"', ')', 'end_line']];
const genericValues: Alternative[] = [['N'], ['#N'], ['T']];
const genericTypes = (v: Token): Alternative[] => [
    ['Uint<', v, '>'], ['Uint<', v, '..', v, '>'], ['Bytes<', v, '>'],
    ['Vector<', v, ', ', v, '>'], ['Maybe<', v, '>'], ['Either<', v, ',', v, '>'],
    ['MerkleTreePath<', v, ',', v, '>'],
];
/*
 * Where a std type writes a size. The `statement_*` family keeps these small and
 * concrete so the contract it lands in still compiles; the `valid_*` family fuzzes
 * them. Everything else about the two lists is identical.
 */
interface TypeSizes {
    uint: Token;
    range: Token[];
    bytes: Token;
    vector: Token;
}

/*
 * The std types Compact offers -- twenty-one shapes that were two hand-maintained
 * copies of each other, differing only in the sizes above and which list they nest.
 */
const stdTypes = (self: Token, size: TypeSizes): Alternative[] => [
    ['Boolean'],
    ['Field'],
    ['Uint<', size.uint, '>'],
    ['Uint<', ...size.range, '>'],
    ['Opaque<"string">'],
    ['Opaque<"Uint8Array">'],
    ['Bytes<', size.bytes, '>'],
    ['Vector<', size.vector, ', ', self, '>'],
    ['Maybe<', self, '>'],
    ['Either<', self, ',', self, '>'],
    ['JubjubPoint'],
    ['MerkleTreeDigest'],
    ['MerkleTreePathEntry'],
    ['MerkleTreePath<', size.vector, ',', self, '>'],
    ['ContractAddress'],
    ['ShieldedCoinInfo'],
    ['QualifiedShieldedCoinInfo'],
    ['ZswapCoinPublicKey'],
    ['ShieldedSendResult'],
    ['UserAddress'],
    ['[]'],
];

/*
 * The ledger ADTs as types. `element` is what the single-element ADTs nest; Map
 * takes its key and value separately because the two callers do not agree on
 * either -- the statement family writes `Map<std, valid>`, the fuzzing family
 * `Map<valid, std>`.
 */
const ledgerTypes = (element: Token, mapKey: Token, mapValue: Token, size: Token): Alternative[] => [
    ['Kernel'],
    ['Counter'],
    ['List<', element, '>'],
    ['Set<', element, '>'],
    ['Map<', mapKey, ', ', mapValue, '>'],
    ['MerkleTree<', size, ', ', element, '>'],
    ['HistoricMerkleTree<', size, ', ', element, '>'],
];

/* What an `import`/`prefix` clause will accept where a library name belongs. */
const libraryName: Alternative[] = identifierPosition([
    ['CompactStandardLibrary'],
    ['"CompactStandardLibrary"'],
    // `valid_types` was written `valid_type`, undefined, and emitted as literal text
    ['valid_types'],
    ['random_number', ' ', 'random_operator', ' ', 'random_number'],
]);

const returnStatements = (self: Token): Alternative[] => [
    ['optional_end'], // a bare `;` is an empty statement, which Compact does not have
    ['return', 'optional_end'],
    ['return', 'optional_end', self],
    ['return ', 'random_keyword', 'optional_end'],
    ['return ', 'random_string', 'optional_end'],
    ['return ', 'random_number', 'optional_end'],
];
const commaList = (item: Alternative, self: Token): Alternative[] => [item, [...item, ', ', self]];

/*
 * The ledger ADTs the statement fuzzers exercise, and the type each is declared
 * with. `kernel` is ambient -- there is nothing to declare -- so its type is empty.
 * The `std` preamble, the per-ADT `single` preambles and the ADT call productions
 * are all generated from this one map, so they cannot drift apart.
 */
const LEDGER_ADT_TYPES: Record<string, Token[]> = {
    kernel: [],
    counter: ['Counter'],
    set: ['Set<', 'statement_std_types', '>'],
    map: ['Map<', 'statement_std_types', ',', 'statement_valid_types', '>'],
    list: ['List<', 'statement_std_types', '>'],
    mt: ['MerkleTree<', '20', ',', 'statement_std_types', '>'],
    hmt: ['HistoricMerkleTree<', '20', ',', 'statement_std_types', '>'],
};

/* The ADTs that need a declaration to be usable -- every one but the kernel. */
const DECLARED_ADTS = Object.entries(LEDGER_ADT_TYPES).filter(([, type]) => type.length > 0);

const adtDeclaration = (adt: string, type: Token[]): Alternative =>
    [`export ledger var_${adt}: `, ...type, 'valid_end_line'];

/* ================================================================== *
 * harness -- the contract each fuzzer wraps around its subject
 * ================================================================== */

const harness: Grammar = {
    // entry point #2
    statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'statement_variables', 'statement_declaration', 'statement_body'],
    ],
    // the same declarations the `single` fuzzers use, all of them at once
    statement_variables: [DECLARED_ADTS.flatMap(([adt, type]) => adtDeclaration(adt, type))],
    statement_declaration: [['constructor()'], ['export circuit test(): []']],
    statement_body: [['{\n ', ...preambleRefs('binding_', 4), 'statement', 'after_statement', '\n}']],
    assert_statements: [contract('constructor_harness', 'assert_body')],
    assert_body: [['{\n ', ...preambleRefs('assert_binding_', 2), 'assert_statement', '\n}']],
    if_statements: [contract('constructor_harness', 'if_body')],
    if_body: [
        ['{\n ', ...preambleRefs('if_binding_', 3), 'if_statement', '\n}'],
        // ['{\n ', 'generate_nested_if', '\n}'],
    ],
    for_statements: [
        contract('constructor_harness', 'for_body'),
        contract('counter_declaration', 'constructor_harness', 'for_body'),
    ],
    for_body: [
        ['{\n', 'for_loop_range', '\n}'],
        // ['{\n', 'generate_nested_for', '\n}'],
    ],
    constructor_statements: [contract('constructor_declaration', 'constructor_body')],
    constructor_body: [['{\n ', 'fixed_assert_statement', 'constructor_return_statements', '\n}']],
    // assert, if and for all wrap their statement under test in the same contract
    constructor_harness: [['constructor()']],
    circuit_statements: [
        // `circuit_declaration` has no block, but a circuit definition requires one
        contract('optional_circuit', ' ', 'circuit_declaration'),
        ['optional_circuit', ' ', 'circuit_declaration'],
        contract('valid_optional_circuit', 'circuit_declaration_with_body', 'circuit_body'),
        // struct hoisted above the circuit, so a body may reference var_struct
    ],
    circuit_body: [
        ['{\n ', 'fixed_assert_statement', 'circuit_return_statements', '\n}'], 
        ['{\n ', 'circuit_multi_const_statements', 'circuit_return_statements', '\n}'],
        // a struct declaration is a program element, not a statement: it cannot sit
        // inside a circuit body. The twins below rely on the hoisted form above.
        ['{\n ', 'struct_decl', 'circuit_multi_const_statements_struct', 'circuit_return_statements', '\n}'],
        ['{\n ', 'struct_decl', 'circuit_spread_statements', 'circuit_return_statements', '\n}'],
        ['{\n ', 'struct_decl', 'circuit_map_fold_statements', 'circuit_return_statements', '\n}'],
    ],
    struct_definitions: [contract('struct_decl', 'struct_definition')],
    enum_definitions: [contract('enum_definition')],
    witness_statements: [
        contract('export ', 'witness_declaration'),
        contract('witness_declaration'),
    ],
    ledger_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'optional_modifier', ' ledger ', 'random_string', ': ', 'compact_types', 'end_line'],
        // ['optional_modifier', 'ledger ', 'random_string', ': ', 'compact_types', 'end_line', 'ledger_statements'],
    ],
    module_statements: [
        // ['generate_modules'],
        ['module_statement'],
    ],
    pragma_statements: [
        ['pragma ', 'pragma_constraints', 'end_line'],
        // ['pragma ', 'pragma_constraints', 'end_line', 'pragma_statements'],
    ],
    import_statements: [
        ['import_statement'],
        // ['import_statement', 'import_statements']
    ],
    include_statements: [
        ['include_statement'],
        // ['include_statement', 'include_statements']
    ],
};

/* ================================================================== *
 * lexical
 * ================================================================== */

const lexical: Grammar = {
    end_line: [['valid_end_line'], ['invalid_start_or_end_line']],
    valid_end_line: [[';'], [';\n']],
    line_separator: [['\n']],
    optional_end: [[''], ['end_line']],
    random_keyword: [
        ['javascript_keywords'],
        ['compact_keywords'],
        ['other_keywords'],
    ],
    random_operator: [['valid_operator'], ['invalid_operator']],
    statement_operator: [['||'], ['&&'], ['=='], ['!='], ['+'], ['-'], ['*'], ['<'], ['<='], ['>='], ['>']],
    invalid_start_or_end_line: [
        [''],
        ['.\n'],
        ['!'],
        ['?'],
        [','],
        [':'],
        ['\n\n'],
        ['\/'],
        ['\//'],
        ['('],
        [')'],
        ['{'],
        ['}'],
        ['>'],
        ['<'],
        ['['],
        [']'],
        ['$'],
        ['&'],
        ['*'],
        ['='],
        ['_'],
        ['%'],
        ['@'],
        ['±'],
        ['§'],
        ['%s'],
        ['%c'],
        ['%d'],
        ['%h'],
        ['%i'],
        ['\t'],
    ],
    javascript_keywords: [
        'abstract',
        'arguments',
        'await',
        'boolean',
        'break',
        'byte',
        'case',
        'catch',
        'char',
        'class',
        'const',
        'continue',
        'debugger',
        'default',
        'delete',
        'do',
        'double',
        'else',
        'enum',
        'eval',
        'export',
        'extends',
        'false',
        'final',
        'finally',
        'float',
        'for',
        'function',
        'goto',
        'if',
        'implements',
        'import',
        'in',
        'instanceof',
        'int',
        'interface',
        'let',
        'long',
        'native',
        'new',
        'null',
        'package',
        'private',
        'protected',
        'public',
        'return',
        'short',
        'static',
        'super',
        'switch',
        'synchronized',
        'this',
        'throw',
        'throws',
        'transient',
        'true',
        'try',
        'typeof',
        'var',
        'void',
        'volatile',
        'while',
        'with',
        'yield',
        'Array',
        'Date',
        'hasOwnProperty',
        'Infinity',
        'isFinite',
        'isNaN',
        'isPrototypeOf',
        'length',
        'Math',
        'NaN',
        'name',
        'Number',
        'Object',
        'prototype',
        'String',
        'toString',
        'undefined',
        'valueOf',
    ],
    compact_keywords: [
        'false',
        'true',
        'export',
        'from',
        'import',
        'module',
        'prefix',
        'as',
        'assert',
        'circuit',
        'const',
        'constructor',
        'contract',
        'default',
        'disclose',
        'else',
        'emit',
        'enum',
        'fold',
        'for',
        'if',
        'include',
        'ledger',
        'map',
        'new',
        'of',
        'pad',
        'pragma',
        'pure',
        'return',
        'sealed',
        'slice',
        'struct',
        'type',
        'witness',
        'Boolean',
        'Bytes',
        'Field',
        'Opaque',
        'Uint',
        'Vector',
        'arguments',
        'await',
        'break',
        'case',
        'catch',
        'class',
        'continue',
        'debugger',
        'delete',
        'do',
        'eval',
        'event',
        'extends',
        'finally',
        'function',
        'implements',
        'in',
        'instanceof',
        'interface',
        'let',
        'null',
        'package',
        'private',
        'protected',
        'public',
        'static',
        'super',
        'switch',
        'this',
        'throw',
        'try',
        'typeof',
        'var',
        'void',
        'while',
        'with',
        'yield',
    ],
    other_keywords: ['self', 'https://', 'file://', 'ftp://', 'define', 'lambda'],
    valid_operator: [
        [' > '],
        [' < '],
        [' = '],
        [' ! '], // prefix-only: `a ! b` cannot parse
        [' * '],
        [' / '], // Compact's expression grammar has no division operator
        [' + '],
        [' - '],
        [' || '],
        [' && '],
        [' <= '],
        [' >= '],
        [' != '],
        [' == '],
    ],
    invalid_operator: [
        [''],
        [' '],
        ['\n'],
        [' . '],
        [' ` '],
        [' # '],
        [' ± '],
        [' § '],
        [' , '],
        [' : '],
        [' ; '],
        [' [ '],
        [' ] '],
        [' { '],
        [' } '],
        [' ( '],
        [' ) '],
        [' % '],
        [' & '],
        [' ? '],
        ['   '],
        [' ~ '],
        [" ' "],
        [' " '],
        [' \\'],
        [' ^ '],
        [' | '],
        [' := '],
        [' |= '],
        [' /= '],
        [' %= '],
        [' &= '],
        [' ^= '],
        [' &! '],
        [' !! '],
        [' ** '],
        [' !* '],
        [' !> '],
        [' <! '],
        [' >> '],
        [' << '],
        [' >< '],
        [' <> '],
        [' => '],
        [' =< '],
        [' [] '],
        [' {} '],
        [' () '],
        [' ,, '],
        [' ;; '],
        [' :: '],
        [' ;: '],
        [' :; '],
        [' ?: '],
        [' %s '],
        [' .. '],
        [' __ '],
        [' ~= '],
        [' ±= '],
        [' <~ '],
        [' =! '],
        [' += '],
        [' *= '],
        [' -= '],
        [' =+ '],
        [' =* '],
        [' =- '],
        [' ++ '],
        [' -- '],
        [' === '],
        [' >>> '],
        [' <<< '],
        [' <<= '],
        [' >>= '],
    ],
};

/* ================================================================== *
 * types
 * ================================================================== */

const types: Grammar = {
    compact_types: [
        ['valid_types'],
        // `as` is an expression cast; it cannot appear in a type position
        ['valid_types', ' as ', 'valid_types'],
        ['valid_types', ' as ', 'invalid_types'],
        ['invalid_types'],
        ['invalid_types', ' as ', 'invalid_types'],
        ['invalid_types', ' as ', 'valid_types'],
    ],
    contaminated_compact_types: [
        ['compact_types'],
        ['random_string'],
        ['random_keyword'],
        ['random_number'],
        ['random_version'],
        ['random_table'],
    ],
    valid_types: [['valid_std_types'], ['valid_ledger_types']],
    invalid_types: [['invalid_std_types'], ['invalid_ledger_types']],
    // shared by circuit and constructor bodies. An empty ending leaves `return`
    // unterminated before the closing brace, which cannot parse.
    // circuit and witness had identical copies of both of these
    generic_value: genericValues,
    generic_type: genericTypes('generic_value'),
    module_generic_value: [
        ['N'],
        ['#N'],
        ['T'],
        ['#T'],
        ['random_string'],
        ['A, B, C, D, E, F, G, H, I, J, K, L, M, N, O, U, P, Q, R, S, T, U, V, W, X'],
        ['#A, #B, #C, #D, #E, #F, #G, #H, #I, #J, #K, #L, #M, #N, #O, #U, #P, #Q, #R, #S, #T, #U, #V, #W, #X'],
    ],
    statement_valid_types: [['statement_ledger_types'], ['statement_std_types']],
    // sizes fixed and small: these types have to compile
    statement_std_types: stdTypes('statement_std_types', {
        uint: '254',
        range: ['0', '..', 'small_random_number'],
        bytes: 'small_random_number',
        vector: '20',
    }),
    statement_ledger_types: ledgerTypes('statement_std_types', 'statement_std_types', 'statement_valid_types', '20'),
    // the same shapes with every size fuzzed
    valid_std_types: stdTypes('valid_std_types', {
        uint: 'random_number',
        range: ['random_number', '..', 'random_number'],
        bytes: 'random_number',
        vector: 'random_number',
    }),
    invalid_std_types: [
        ['Uint<', 'random_string', '>'],
        ['Bytes<', 'random_string', '>'],
        ['Bytes<', 'random_string', '..', 'random_string', '>'],
        ['Bytes<', 'compact_types', '..', 'compact_types', '>'],
        ['Opaque<', 'random_number', '>'],
        ['Opaque<', 'random_string', '>'],
        ['Opaque<', 'compact_types', '>'],
        ['Vector<', 'random_number', ', ', 'invalid_types', '>'],
        ['Vector<', 'random_string', ', ', 'invalid_types', '>'],
        ['Vector<', 'random_number', ', ', 'valid_std_types', '>'],
        ['Maybe<', 'compact_types', '>'],
        ['Either<', 'compact_types', ',', 'compact_types', '>'],
        ['MerkleTreePath<', 'random_number', ',', 'compact_types', '>'],
    ],
    valid_ledger_types: ledgerTypes('valid_std_types', 'valid_types', 'valid_std_types', 'random_number'),
    invalid_ledger_types: [
        ['Cell<', 'random_number', '>'],
        ['Cell<', 'compact_types', ', ', 'compact_types', '>'],
        ['Set<', 'random_number', '>'],
        ['Set<', 'compact_types', '>'],
        ['Set<', 'compact_types', ', ', 'compact_types', '>'],
        ['Map<', 'random_number', '>'],
        ['Map<', 'compact_types', '>'],
        ['Map<', 'random_number', 'compact_types', '>'],
        ['List<', 'random_number', '>'],
        ['List<', 'compact_types', '>'],
        ['List<', 'compact_types', ', ', 'compact_types', '>'],
        ['MerkleTree<', 'random_number', '>'],
        ['MerkleTree<', 'compact_types', ', ', 'compact_types', '>'],
        ['MerkleTree<', 'random_number', ', ', 'compact_types', '>'],
        ['HistoricMerkleTree<', 'compact_types', '>'],
        ['HistoricMerkleTree<', 'compact_types', ', ', 'compact_types', '>'],
        ['HistoricMerkleTree<', 'random_number', ', ', 'compact_types', '>'],
    ],
};

/* ================================================================== *
 * declarations
 * ================================================================== */

const declarations: Grammar = {
    /*
     * The grammar is `pragma <id> <version-expr>;` -- one identifier followed by a
     * single version expression. `&&` and `||` join version *terms* inside that
     * expression, so they cannot join two `language_version ...` constraints, and a
     * general binary operator is not a version operator.
     */
    pragma_constraints: [
        ['pragma_constraint'],
        ['pragma_constraints', ' ', 'random_operator', ' ', 'pragma_constraint'],
    ],
    pragma_constraint: [['pragma_type', ' ', 'random_operator', ' ', 'version_number']],
    pragma_type: identifierPosition([
        ['language_version'],
        ['compiler_version'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ]),
    version_number: [
        ['random_version'],
        ['random_version', 'random_version'],
        ['random_keyword'],
        ['(', 'random_version', ')'],
        ['[', 'random_version', ']'],
        ['{', 'random_version', '}'],
        ['<', 'random_version', '>'],
        ['random_string'],
        [''],
    ],
    import_statement: [
        ['random_keyword', ' import ', 'import_library', 'end_line'],
        ['random_string', ' import ', 'import_library', 'end_line'],
        ['import ', 'import_library', 'end_line'],
        ['import ', 'import_library', ' prefix ', 'prefix_string', 'end_line'],
    ],
    // an imported library and an import prefix accept the same operands
    import_library: libraryName,
    prefix_string: libraryName,
    include_statement: [
        ['random_keyword', ' include ', 'include_file', 'end_line'],
        ['random_string', ' include ', 'include_file', 'end_line'],
        ['include ', 'include_file', 'end_line'],
    ],
    /*
     * `include` takes a string literal -- the grammar is `include <file> ;` where
     * <file> is the string-literal terminal. Every unquoted operand below is a parse
     * error, which is why this fuzzer never got past the parser at all.
     */
    include_file: [
        ['CompactStandardLibrary'],
        ['path/to/file'],
        ['//path//to//file'],
        ['\\path\\to\\file'],
        ['\/path\/to\/file'],
        ['\path\to\file'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['valid_types'],  // was `valid_type`, which is undefined and emitted literally
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
    module_statement: [
        ['module ', 'module_name', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '<', 'module_params', '>', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '<', 'module_generic_value', ',', 'module_generic_value', '>', ' {', 'line_separator', '}', 'line_separator'],
        // a generic parameter list is angle-bracketed
        ['module ', 'module_name', '[', 'module_params', ']', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '(', 'module_params', ')', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '{', 'module_params', '}', ' {', 'line_separator', '}', 'line_separator'],
    ],
    // a generic parameter is `T` or `#N`; a module name is an identifier
    module_params: [
        ...identifierPosition([['compact_types'], ['random_number', ' ', 'random_operator', ' ', 'random_number']]),
        ['random_string', ', ', 'module_params'],
    ],
    module_name: identifierPosition([['compact_types'], ['random_number', ' ', 'random_operator', ' ', 'random_number']]),
    // the grammar is (OPT export) (OPT sealed) ledger -- in that order
    optional_modifier: [
        [''],
        ['export'],
        ['sealed'],
        ['export sealed'],
        ['sealed export'],
        ['random_keyword'],
        ['random_string'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
    ],
    counter_declaration: [
        ['export ledger counter: Counter', 'end_line']
    ],
    witness_declaration: [
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '():', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '(', 'witness_params', '):', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<#N, T>', '(x:', 'generic_value', '):', 'generic_type', 'end_line'],
        ['witness ', 'random_string', '(', 'witness_params', '):', 'compact_types', 'end_line'],
    ],
    witness_args: [['random_keyword'], ...commaList(['random_string'], 'witness_args')],
    witness_params: [
        ['random_string', ' : ', 'compact_types'],
        ['random_keyword', ' : ', 'compact_types'],
        ['random_number', ' : ', 'compact_types'],
        ['random_table', ' : ', 'compact_types'],
        ['random_version', ' : ', 'compact_types'],
        ['random_string', ' : ', 'compact_types', ', ', 'witness_params'],
    ],
    struct_definition: [
        ['struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
        ['random_keyword', ' struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
    ],
    struct_fields: [['struct_field'], ['struct_field', ',', 'line_separator', 'struct_fields']],
    struct_field: [
        ['  ', 'random_string', ': ', 'valid_types'],
        ['  ', 'random_string', ': ', 'var_struct'],  // the struct declared by struct_decl
        ['  ', 'random_keyword', ': ', 'valid_types'],
        ['  ', 'random_string', ': ', 'compact_types'],
    ],
    // the struct that circuit bodies and the struct fuzzer both declare
    struct_decl: [['struct ', 'var_struct', ' {\n', 'struct_decl_fields', '\n}', 'valid_end_line']],
    struct_decl_fields: [['  ', 'random_string', ': ', 'valid_types']],
    enum_definition: [
        ['enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        ['export enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        // ['generate_large_enum'],
    ],
    // an enum name and its members are identifiers
    enum_name: identifierPosition(),
    enum_values: [
        ...identifierPosition().map((alternative) => prefix('  ', alternative, 'line_separator')),
        ['  ', 'random_string', ',', 'line_separator', 'enum_values'],
    ],
    constructor_declaration: [
        ['random_keyword', ' ', 'constructor()'],
        ['random_string', ' ', 'constructor()'],
        ['constructor()'],
        ['constructor(', 'constructor_params', ')'],
    ],
    constructor_params: [
        ['random_string', ' : ', 'constructor_param_types'],
        ['random_keyword', ' : ', 'constructor_param_types'],
        ['random_string', ' : ', 'constructor_param_types', ', ', 'constructor_params'],
    ],
    constructor_param_types: identifierPosition([['compact_types']]),
    optional_circuit: [['random_keyword'], ['random_string'], ['optional_circuit']],
    // the grammar is (OPT export) (OPT pure) circuit -- in that order, at most once each
    valid_optional_circuit: [['export '], ['pure '],   ['valid_optional_circuit']],
    circuit_declaration: [
        ['circuit ', 'random_string', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_keyword', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<#N, T>', '(x:', 'generic_value', '):', 'generic_type', 'end_line'],
        ['circuit ', 'random_string', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
    ],
    circuit_declaration_with_body: [
        ['circuit ', 'random_string', '(): ', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'circuit_params', '):', 'valid_types'],
        ['circuit ', 'random_string', '(', 'circuit_params', '):', 'valid_types'],
    ],
    circuit_args: commaList(['random_string'], 'circuit_args'),
    circuit_params: commaList(['random_string', ' : ', 'valid_types'], 'circuit_params'),
    contaminated_circuit_params: [
        ['random_string', ' : ', 'contaminated_compact_types'],
        ['random_keyword', ': ', 'contaminated_compact_types'],
        ['random_string', ' : ', 'contaminated_compact_types', ', ', 'circuit_params'],
    ],
};

/* ================================================================== *
 * statements
 * ================================================================== */

const statements: Grammar = {
    // circuit and constructor bodies both open with this same fixed assertion
    fixed_assert_statement: assertStatement,
    constructor_return_statements: returnStatements('constructor_return_statements'),
    circuit_return_statements: returnStatements('circuit_return_statements'),
    circuit_spread_statements: [
        ['const a', ' = [...slice<', 'random_number', '>(', 'valid_types' , ', ', 'random_number', ')]', 'end_line'],
        // a type is not a binding name, nor an expression
        ['const [', 'valid_types', ', ', 'valid_types', '] = ', '[...', 'valid_types', ', ', '...', 'valid_types', ']', 'end_line' ],
        ['const a', ' = [...', 'random_string', ', ...', 'random_number', ']', 'end_line' ],
        ['const a', ' = [...[', 'random_string', '], ...[', 'random_number', ']]', 'end_line' ],
        ['const a', ' = [...', 'random_table', ', ...', 'random_mixed_table', ']', 'end_line' ],
        ['const a', ' = [...[', 'random_table', '], ...[', 'random_mixed_table', ']]', 'end_line' ],
    ],
    circuit_multi_const_statements: [
        // random_mixed_table is unbracketed, so its commas continue the const binding list
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ' = ', 'random_number', ', ', 'random_string', ' = ', 'random_mixed_table', 'end_line'],
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ' = ', 'small_random_number', ', ', 'random_string', ' = ', 'random_keyword', 'end_line'],
        ['const ', 'random_string', ':', 'valid_types', ' = ', 'default<', 'valid_types', '>', ', ' , 'random_string', ':', 'valid_types', ' = ', 'random_number', ', ', 'random_string', ':', 'valid_types', ' = ', 'random_keyword', 'end_line'],
    ],
    circuit_multi_const_statements_struct: [
        ['const ', 'random_string', ' = ', 'default<', 'var_struct', '>', ', ' , 'random_string', ' = ', 'random_string', ', ', 'random_string', ' = ', 'random_number', 'end_line'],
    ],
    circuit_map_fold_statements: [
        // the trailing operands are types, and map/fold take expressions there
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'valid_types' , ')', 'valid_end_line'],
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'default<', ', ', 'valid_types' , '>)', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'valid_types', ', ', 'valid_types' , ')', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'default<', 'valid_types', '>, default<', 'valid_types' , '>)', 'valid_end_line'],
    ],
    ...preambleBindings('assert_binding_', 2, ASSERT_BINDINGS),
    assert_statement: [
        ['assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'random_keyword', ', "', 'random_string', '")', 'end_line'],
        // unbalanced quote / missing comma
        ['assert (', 'assert_condition', ' ', 'random_keyword', '")', 'end_line'],
        ['assert (', 'assert_condition', 'random_keyword', 'random_string', '")', 'end_line'],
        ['random_keyword', ' ', 'assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
    ],
    // the third binding also gets the tuple form
    ...preambleBindings('if_binding_', 3, IF_BINDINGS, { extra: { 2: ['sliceOfTuple'] } }),
    if_statement: [
        // Compact has no empty statement, so `if (...) {};` cannot parse; and joining
        // two conditions with a second relational operator chains them, which the
        // non-associative expr3 rule rejects.
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line'],
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line', 'if_statement'],
    ],
    for_loop_range: [
        ['for (const ', 'bob', ' of ', 'very_small_random_number', '..', 'very_small_random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'counter_operation', ') {\n', '}\n'],
        // ['for (const ', 'bob', ' of ', 'small_random_number', '..', 'small_random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_table', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'valid_types', ']) {\n', '}\n'],  // a type is not an expression
        ['for (const ', 'bob', ' of ', '[', 'default<', 'valid_types', '>]) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_keyword', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '(', 'random_table', ')) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '{', 'random_table', '}) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '<', 'random_table', '>) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_table', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_keyword', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_version', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'valid_types', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'default<', 'valid_types', '>) {\n', '}\n'],
        // a range bound is a type size (a nat or an id), not a cast expression
        ['for (const ', 'bob', ' of ', 'random_number', ' as Uint<455>', '..', 'random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_number', '..', 'random_number', ' as Uint<455>', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_string', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_mixed_table', ']', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(', 'random_table', ', ', 'random_number', ')) {\n', '}\n'],
    ],
    /*
     * These four are the operands of the ledger statement under test, so they
     * always terminate validly: a fuzzed terminator here would only ever stop the
     * contract short of the statement it exists to exercise.
     */
    ...preambleBindings('binding_', 4, STATEMENT_BINDINGS, {
        typeNode: STATEMENT_TYPE,
        terminator: 'valid_end_line',
    }),
    /*
     * These were named for the ADT alone -- `kernel`, `counter`, `set` -- which
     * collided with the language's own words: `counter_operation` emits a literal
     * `counter` referring to the ledger counter the `for` harness declares, and
     * once a production claimed that name the literal expanded into a whole
     * statement instead. Prefixed names cannot collide, and unlike a bare word
     * they are checkable: `validate()` only inspects tokens containing `_`.
     */
    statement: Object.keys(LEDGER_ADT_TYPES).map((adt) => [`adt_${adt}`]),
    optional_statement_variable: [['const adam = ']],
    after_statement: [
        ['no_variable_after_statement'], ['variable_after_statement'],
    ],
    variable_after_statement: [
        ['assert (', 'adam', ' ', 'statement_operator', ' ', 'statement_variable', ', ', '"check this out"', ')', 'valid_end_line'],
        ['assert (', 'adam', ' ? ', 'statement_variable', ' : ', 'statement_variable', ', ', '"check this out"', ')', 'valid_end_line'],
        ['assert (', 'adam', ' ? ', 'statement_methods', ' : ', 'statement_methods', ', ', '"check this out"', ')', 'valid_end_line'],
        ['const z = adam', ' ', 'statement_operator', ' ', 'statement_variable', 'valid_end_line'],
        ['const t = ', 'default<', 'statement_variable', '>', 'valid_end_line'],
        ['const t = ', 'disclose(', 'statement_variable', ')', 'valid_end_line'],
        ['return ', 'statement_variable', 'valid_end_line'],
        ['return ', 'disclose(', 'statement_variable', ')', 'valid_end_line'],
    ],
    no_variable_after_statement: [
        ['assert (', 'adam', ' ', 'statement_operator', ' ', 'no_variable_statement_methods', ', ', '"check this out"', ')', 'valid_end_line'],
        ['const z = ', 'no_variable_statement_methods', ' ', 'statement_operator', ' ', 'no_variable_statement_methods', 'valid_end_line'],
        ['const t = ', 'no_variable_statement_methods', 'valid_end_line'],
        ['const t = ', 'default<', 'no_variable_statement_methods', '>', 'valid_end_line'],
        ['const t = ', 'disclose(', 'no_variable_statement_methods', ')', 'valid_end_line'],
        ['return ', 'no_variable_statement_methods', 'valid_end_line'],
        ['return ', 'disclose(', 'no_variable_statement_methods', ')', 'valid_end_line'],
    ],
};

/* ================================================================== *
 * expressions
 * ================================================================== */

const expressions: Grammar = {
    assert_condition: [
        // two operands with no operator between them
        ['tom', 'random_string', 'bob'],
        ['tom', ' ', 'random_keyword', ' ', 'bob'],
        ['tom', 'random_operator', 'bob'],
        // Compact's relational operators are non-associative (expr3 :: expr4 < expr4),
        // so chaining two of them cannot parse
        ['tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'random_mixed_table'],
        ['bob', 'random_operator', 'tom', 'random_operator', 'tom'],
        ['tom', 'random_operator', 'tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['bob', 'random_operator', 'tom'],
        ['bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'tom'],
        ['tom', 'random_operator', 'random_keyword'],
        ['random_keyword', 'random_operator', 'bob'],
    ],
    if_condition: [
        ['tom', 'random_operator', 'bob'],
        ['tom', 'random_keyword', 'bob'],              // no operator between operands
        ['tom', 'random_operator', 'bob', 'random_operator', 'greg'],  // chained comparison
        ['tom', 'random_operator', 'bob', 'random_keyword', 'greg'],
        ['tom', 'random_operator', 'random_number'],
        ['tom', 'random_operator', '"', 'random_string', '"'],
        ['"', 'random_string', '"', 'random_operator', 'tom'],
        ['tom * bob', 'random_operator', 'random_number'],
        ['tom + bob', 'random_operator', 'random_number'],
        ['tom - bob', 'random_operator', 'random_number'],
        ['tom / bob', 'random_operator', 'random_number'],  // no division operator
        ['tom', ' as ', 'valid_types', 'random_operator', 'random_number'],
        ['tom', 'random_operator', 'bob', ' as ', 'valid_types'],
        ['random_number', 'random_operator', 'tom'],
        ['random_number', 'random_operator', 'tom * bob'],
        ['random_number', 'random_operator', 'tom + bob'],
        ['random_number', 'random_operator', 'tom - bob'],
        ['random_number', 'random_operator', 'tom / bob'],
        ['default<', 'valid_types', '>', 'random_operator', 'default<', 'valid_types', '>'],
    ],
    counter_operation: [
        ['counter', 'random_operator', 'random_number'],
        ['counter', 'random_operator', 'small_random_number'],
        ['counter', 'random_operator', 'random_number', 'counter_operation'],  // no operator between the two
    ],
    random_input: [
        ['small_random_number'],
        ['random_string'],
        ['random_version'],
        ['random_table'],
        ['[', 'random_table', ']'],
        ['random_keyword'],
    ],
    // whatever the preamble bound, referred to as an operand
    statement_variable: PREAMBLE_VARS.map((name) => [name]),
};

/* ================================================================== *
 * ledger ADTs
 *
 * `mint` and `pathFoLeaf` are stale -- `mint` was renamed `mintShielded`, and
 * `pathFoLeaf` misspells a method that is TypeScript-only anyway. Both are kept
 * so this reorganisation changes no coverage; they are a backlog item.
 * ================================================================== */

const LEDGER_OPS: Record<string, string[]> = {
    kernel: ['checkpoint', 'claimContractCall', 'claimZswapCoinReceive', 'claimZswapCoinSpend',
             'claimZswapNullifier', 'mint', 'self'],
    counter: ['decrement', 'increment', 'lessThan', 'read', 'resetToDefault'],
    set: ['insert', 'insertCoin', 'isEmpty', 'member', 'remove', 'resetToDefault', 'size'],
    map: ['insert', 'insertCoin', 'insertDefault', 'isEmpty', 'lookup', 'member', 'remove',
          'resetToDefault', 'size'],
    list: ['head', 'isEmpty', 'length', 'popFront', 'pushFront', 'pushFrontCoin', 'resetToDefault'],
    mt: ['checkRoot', 'findPathForLeaf', 'firstFree', 'insert', 'insertHash', 'insertHashIndex',
         'insertIndex', 'insertIndexDefault', 'pathFoLeaf', 'resetToDefault', 'root'],
    hmt: ['check_root', 'findPathForLeaf', 'firstFree', 'history', 'insert', 'insertHash',
          'insertHashIndex', 'insertIndex', 'insertIndexDefault', 'pathFoLeaf', 'resetToDefault',
          'root'],
};

/*
 * Operations whose literal-argument form takes more than the default two
 * arguments. Keyed by `adt.op` because the arity is a property of the operation on
 * that ADT: `map.insert` takes a key and a value where `set.insert` takes only a
 * member. Over-applying an operation is the point -- these are the calls that
 * should be rejected -- so the arity here is the widest form to emit, not the
 * correct one.
 */
const WIDE_ARITY: Record<string, number> = {
    'kernel.claimContractCall': 4,
    'kernel.mint': 3,
    'set.insertCoin': 4,
    'map.insert': 3,
    'map.insertCoin': 4,
    'list.pushFrontCoin': 3,
    'mt.insertHashIndex': 3,
    'mt.insertIndex': 3,
    'mt.pathFoLeaf': 3,
    'hmt.insertHashIndex': 3,
    'hmt.insertIndex': 3,
    'hmt.pathFoLeaf': 3,
};

/* The kernel is ambient: it is addressed by name, not through a declared var. */
const receiverFor = (adt: string): Token => (adt === 'kernel' ? 'kernel.' : `var_${adt}.`);

const ledgerAdts: Grammar = {
    single_statements: Object.entries(LEDGER_ADT_TYPES).map(([adt, type]) =>
        contract(...(type.length ? [`single_${adt}`] : []), 'statement_declaration', `single_${adt}_body`)),

    ...Object.fromEntries(DECLARED_ADTS.map(([adt, type]) => [`single_${adt}`, [adtDeclaration(adt, type)]])),

    ...Object.fromEntries(Object.keys(LEDGER_ADT_TYPES).map((adt) => [
        `single_${adt}_body`,
        [['{\n ', `no_variable_${adt}`, 'no_variable_after_statement', '\n}']],
    ])),

    ...Object.fromEntries(Object.entries(LEDGER_OPS).flatMap(([adt, ops]) => {
        const recv = receiverFor(adt);
        return [
            [`adt_${adt}`, [[`variable_${adt}`], [`no_variable_${adt}`]]],
            [`variable_${adt}`, ops.flatMap((op) => [
                // the declared preamble variables, applied two at a time and wider
                ...Array.from(
                    { length: (WIDE_ARITY[`${adt}.${op}`] ?? 2) - 1 },
                    (_, i) => method(recv, op, PREAMBLE_VARS.slice(0, i + 2)),
                ),
                method(recv, op, same('statement_variable', 1)),
                method(recv, op, same('statement_variable', 2)),
            ])],
            [`no_variable_${adt}`, [
                // an operation this ADT does not have
                ['optional_statement_variable', recv, 'random_input', '()', 'valid_end_line'],
                ...ops.flatMap((op) => [
                    method(recv, op, same('random_input', 0)),
                    method(recv, op, same('random_input', 1)),
                ]),
            ]],
        ];
    })),
};

/* ================================================================== *
 * standard library and native circuits
 * ================================================================== */

const T = 'statement_std_types';
const N = 'small_random_number';

interface StdlibCall {
    name: Token;
    generics: Token[];
    /** The call's arity. */
    args: number;
    /**
     * The lowest arity to also emit, for calls the old grammar under-applied on
     * purpose. Defaults to one below `args`, which is what it spelled out for most
     * of them; set it equal to `args` for a call it only ever applied fully.
     */
    minArgs?: number;
}

const STDLIB_CALLS: StdlibCall[] = [
    { name: 'some', generics: [T], args: 1 },
    { name: 'none', generics: [T], args: 1 },
    { name: 'left', generics: [T, T], args: 1 },
    { name: 'right', generics: [T, T], args: 1 },
    { name: 'transientHash', generics: [T], args: 1 },
    { name: 'transientCommit', generics: [T], args: 2 },
    { name: 'persistentHash', generics: [T], args: 1 },
    { name: 'persistentCommit', generics: [T], args: 2 },
    { name: 'hashToCurve', generics: [T], args: 1 },
    { name: 'merkleTreePathRoot', generics: [N, T], args: 2 },
    { name: 'merkleTreePathRootNoLeafHash', generics: [N], args: 1 },
    { name: 'degradeToTransient', generics: [], args: 1 },
    { name: 'upgradeFromTransient', generics: [], args: 1 },
    { name: 'ecAdd', generics: [], args: 2 },
    { name: 'ecMul', generics: [], args: 2 },
    { name: 'ecMulGenerator', generics: [], args: 1 },
    { name: 'nativeToken', generics: [], args: 1 },
    { name: 'tokenType', generics: [], args: 2 },
    { name: 'evolveNonce', generics: [], args: 2 },
    { name: 'shieldedBurnAddress', generics: [], args: 1 },
    { name: 'mintShieldedToken', generics: [], args: 4 },
    { name: 'mintUnshieldedToken', generics: [], args: 3 },
    { name: 'receiveShielded', generics: [], args: 2 },
    { name: 'receiveUnshielded', generics: [], args: 2 },
    { name: 'sendShielded', generics: [], args: 4 },
    { name: 'sendImmediateShielded', generics: [], args: 4 },
    { name: 'sendUnshielded', generics: [], args: 3 },
    { name: 'mergeCoin', generics: [], args: 3 },
    { name: 'mergeCoinImmediate', generics: [], args: 3 },
    { name: 'unshieldedBalance', generics: [], args: 2 },
    { name: 'unshieldedBalanceLt', generics: [], args: 3 },
    { name: 'unshieldedBalanceLte', generics: [], args: 3 },
    { name: 'unshieldedBalanceGt', generics: [], args: 3 },
    { name: 'unshieldedBalanceGte', generics: [], args: 3 },
    { name: 'ownPublicKey', generics: [], args: 2 },
    { name: 'createZswapInput', generics: [], args: 2 },
    { name: 'createZswapOutput', generics: [], args: 3 },
];

/*
 * The arities to emit for a call. Under-applying is a error class of its own, and
 * the grammar this replaced listed the short forms for most calls by hand, so the
 * default runs from one argument up to the call's real arity.
 */
const arities = (c: StdlibCall): number[] => {
    const min = c.minArgs ?? 1;
    return Array.from({ length: Math.max(0, c.args - min + 1) }, (_, i) => min + i);
};

/*
 * A generic argument list with its last entry replaced. A wrong generic argument
 * is its own class of error -- distinct from a wrong value argument -- and the
 * grammar this table replaced fuzzed it for every call that takes one.
 */
const badGenerics = (genericNodes: Token[], node: Token): Token[] =>
    genericNodes.length ? [...genericNodes.slice(0, -1), node] : [];

/* What can stand in an argument position, with and without a preamble to draw on. */
const VALUE_ARGS: Token[] = ['statement_variable', 'statement_methods'];
const NO_VALUE_ARGS: Token[] = ['random_input', 'statement_std_types', 'no_variable_statement_methods'];
const BAD_GENERIC_ARGS: Token[] = ['random_input', 'statement_methods'];

const stdlib: Grammar = {
    statement_methods: [['variable_statement_methods'], ['no_variable_statement_methods']],

    /*
     * Calls whose arguments are the preamble variables, other calls, or a mixture.
     * Arguments vary independently: `transientCommit<T>(bob, someCall())` reaches a
     * different path than either all-variable or all-call form.
     */
    variable_statement_methods: STDLIB_CALLS.flatMap((c) => [
        ...arities(c).flatMap((arity) =>
            argLists(arity, VALUE_ARGS).map((args) => call(c.name, c.generics, args)),
        ),
        ...(c.generics.length
            ? BAD_GENERIC_ARGS.flatMap((bad) =>
                  arities(c).map((arity) =>
                      call(c.name, badGenerics(c.generics, bad), same('statement_variable', arity)),
                  ),
              )
            : []),
    ]),

    /* The same calls with nothing bound to draw on: junk, types, and other calls. */
    no_variable_statement_methods: STDLIB_CALLS.flatMap((c) => [
        call(c.name, c.generics, []),
        ...arities(c).flatMap((arity) =>
            NO_VALUE_ARGS.map((node) => call(c.name, c.generics, same(node, arity))),
        ),
        ...(c.generics.length
            ? [
                  call(c.name, badGenerics(c.generics, 'random_input'), []),
                  ...arities(c).map((arity) =>
                      call(c.name, badGenerics(c.generics, 'random_input'), same('statement_std_types', arity)),
                  ),
              ]
            : []),
    ]),
};

/* ================================================================== */

export const CATEGORIES = {
    harness,
    lexical,
    types,
    declarations,
    statements,
    expressions,
    ledgerAdts,
    stdlib,
} satisfies Record<string, Grammar>;

export type Category = keyof typeof CATEGORIES;

export const compact: Grammar = Object.assign({}, ...Object.values(CATEGORIES)) as Grammar;
