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


import { Alternative, Token, Grammar } from './types';

/* Centralized grammar: keep Compact syntax and production definitions here. */

/* ================================================================== *
 * Terminals and entry points
 * ================================================================== */

/* `TERMINAL_GENERATORS` is typed against this list. */
export const TERMINALS = [
    'random_version', 'random_string', 'random_number', 'very_small_random_number',
    'small_random_number', 'random_table', 'random_mixed_table',
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

export type FuzzerName = keyof typeof ENTRY_POINTS;

/* ================================================================== *
 * Syntax constructors
 *
 * The only place the punctuation of a contract preamble, a call, a method call,
 * a generic argument list or a const binding is written down.
 * ================================================================== */

const contract = (...parts: Token[]): Alternative => ['import CompactStandardLibrary;', 'line_separator', ...parts];

const join = (nodes: Token[], separator: Token): Token[] => nodes.flatMap((node, i) => (i ? [separator, node] : [node]));

const generics = (nodes: Token[]): Token[] => (nodes.length ? ['<', ...join(nodes, ','), '>'] : []);

const call = (name: Token, genericNodes: Token[], argNodes: Token[]): Alternative =>
    [name, ...generics(genericNodes), '(', ...join(argNodes, ', '), ')'];

const method = (receiver: Token, op: Token, argNodes: Token[]): Alternative =>
    ['optional_statement_variable', receiver + op + '(', ...join(argNodes, ', '), ')', 'valid_end_line'];

const same = (node: Token, arity: number): Token[] => Array.from({ length: arity }, () => node);

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

const identifierPosition = (extra: Alternative[] = []): Alternative[] => [
    ['random_string'],
    ['random_keyword'],
    ['random_table'],
    ['random_version'],
    ['random_number'],
    ...extra,
];

const BINDING_VALUES = {
    default: (n, t) => ['const ', n, ' = ', 'default<', t, '>'],
    typedDefault: (n, t) => ['const ', n, ' : ', t, ' = ', 'default<', t, '>'],
    pad: (n) => ['const ', n, ' = ', 'pad(', 'random_number', ', "', 'random_string', '")'],
    smallNumber: (n) => ['const ', n, ' = ', 'small_random_number'],
    number: (n) => ['const ', n, ' = ', 'random_number'],
    string: (n) => ['const ', n, ' = ', 'random_string'],
    sliceOfDefault: (n, t) => ['const ', n, ' = ', 'slice<', 'random_number', '>(default<', t, '>, ', 'random_number', ')'],
    sliceOfTuple: (n) => ['const ', n, ' = ', 'slice<', 'random_number', '>([', 'random_mixed_table', '], ', 'random_number', ')'],
    sliceOfType: (n, t) => ['const ', n, ' = ', 'slice<', 'random_number', '>(', t, ', ', 'random_number', ')'],
    spreadSliceOfType: (n, t) => ['const ', n, ' = ', '[...slice<', 'random_number', '>(', t, ', ', 'random_number', ')]'],
} satisfies Record<string, (name: Token, typeNode: Token) => Alternative>;

type BindingKind = keyof typeof BINDING_VALUES;

const BINDING_TERMINATOR: Record<BindingKind, Token> = {
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

const bindings = (name: Token, kinds: BindingKind[], typeNode: Token = 'valid_types', terminator?: Token): Alternative[] =>
    kinds.map((kind) => [...BINDING_VALUES[kind](name, typeNode), terminator ?? BINDING_TERMINATOR[kind]]);

const ASSERT_BINDINGS: BindingKind[] = ['default', 'pad', 'spreadSliceOfType', 'sliceOfType', 'sliceOfDefault'];
const IF_BINDINGS: BindingKind[] = ['default', 'typedDefault', 'smallNumber', 'number', 'string', 'sliceOfType', 'sliceOfDefault'];
const STATEMENT_BINDINGS: BindingKind[] = ['default', 'smallNumber'];
const STATEMENT_TYPE = 'statement_valid_types';

const PREAMBLE_VARS: Token[] = ['bob', 'tom', 'greg', 'adonis'];

const preambleBindings = (
    prefix: string,
    count: number,
    kinds: BindingKind[],
    options: { typeNode?: Token; terminator?: Token; extra?: Record<number, BindingKind[]> } = {},
): Grammar =>
    Object.fromEntries(
        PREAMBLE_VARS.slice(0, count).map((name, i) => [
            `${prefix}${name}`,
            bindings(name, [...kinds, ...(options.extra?.[i] ?? [])], options.typeNode, options.terminator),
        ]),
    );

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
interface TypeSizes {
    uint: Token;
    range: Token[];
    bytes: Token;
    vector: Token;
}

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

const ledgerTypes = (element: Token, mapKey: Token, mapValue: Token, size: Token): Alternative[] => [
    ['Kernel'],
    ['Counter'],
    ['List<', element, '>'],
    ['Set<', element, '>'],
    ['Map<', mapKey, ', ', mapValue, '>'],
    ['MerkleTree<', size, ', ', element, '>'],
    ['HistoricMerkleTree<', size, ', ', element, '>'],
];

const libraryName: Alternative[] = identifierPosition([
    ['CompactStandardLibrary'],
    ['"CompactStandardLibrary"'],
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

const LEDGER_ADT_TYPES: Record<string, Token[]> = {
    kernel: [],
    counter: ['Counter'],
    set: ['Set<', 'statement_std_types', '>'],
    map: ['Map<', 'statement_std_types', ',', 'statement_valid_types', '>'],
    list: ['List<', 'statement_std_types', '>'],
    mt: ['MerkleTree<', '20', ',', 'statement_std_types', '>'],
    hmt: ['HistoricMerkleTree<', '20', ',', 'statement_std_types', '>'],
};

const DECLARED_ADTS = Object.entries(LEDGER_ADT_TYPES).filter(([, type]) => type.length > 0);

const adtDeclaration = (adt: string, type: Token[]): Alternative =>
    [`export ledger var_${adt}: `, ...type, 'valid_end_line'];

/* ================================================================== *
 * harness -- the contract each fuzzer wraps around its subject
 * ================================================================== */

const harness: Grammar = {
    statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'statement_variables', 'statement_declaration', 'statement_body'],
    ],
    statement_variables: [DECLARED_ADTS.flatMap(([adt, type]) => adtDeclaration(adt, type))],
    statement_declaration: [['constructor()'], ['export circuit test(): []']],
    statement_body: [['{\n ', ...preambleRefs('binding_', 4), 'statement', 'after_statement', '\n}']],
    assert_statements: [contract('constructor_harness', 'assert_body')],
    assert_body: [['{\n ', ...preambleRefs('assert_binding_', 2), 'assert_statement', '\n}']],
    if_statements: [contract('constructor_harness', 'if_body')],
    if_body: [['{\n ', ...preambleRefs('if_binding_', 3), 'if_statement', '\n}']],
    for_statements: [
        contract('constructor_harness', 'for_body'),
        contract('counter_declaration', 'constructor_harness', 'for_body'),
    ],
    for_body: [['{\n', 'for_loop_range', '\n}']],
    constructor_statements: [contract('constructor_declaration', 'constructor_body')],
    constructor_body: [['{\n ', 'fixed_assert_statement', 'constructor_return_statements', '\n}']],
    constructor_harness: [['constructor()']],
    circuit_statements: [
        contract('invalid_circuit_modifier', ' ', 'circuit_declaration'),
        ['invalid_circuit_modifier', ' ', 'circuit_declaration'],
        contract('valid_circuit_modifier', 'circuit_declaration_with_body', 'circuit_body'),
    ],
    circuit_body: [
        /* Struct declarations here are deliberate invalid-program cases. */
        ['{\n ', 'fixed_assert_statement', 'circuit_return_statements', '\n}'],
        ['{\n ', 'circuit_multi_const_statements', 'circuit_return_statements', '\n}'],
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
    ],
    module_statements: [['module_statement']],
    pragma_statements: [['pragma ', 'pragma_constraints', 'end_line']],
    import_statements: [['import_statement']],
    include_statements: [['include_statement']],
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
    statement_std_types: stdTypes('statement_std_types', {
        uint: '254',
        range: ['0', '..', 'small_random_number'],
        bytes: 'small_random_number',
        vector: '20',
    }),
    statement_ledger_types: ledgerTypes('statement_std_types', 'statement_std_types', 'statement_valid_types', '20'),
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
    import_library: libraryName,
    prefix_string: libraryName,
    include_statement: [
        ['random_keyword', ' include ', 'include_file', 'end_line'],
        ['random_string', ' include ', 'include_file', 'end_line'],
        ['include ', 'include_file', 'end_line'],
    ],
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
        ['module ', 'module_name', '[', 'module_params', ']', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '(', 'module_params', ')', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '{', 'module_params', '}', ' {', 'line_separator', '}', 'line_separator'],
    ],
    module_params: [
        ...identifierPosition([['compact_types'], ['random_number', ' ', 'random_operator', ' ', 'random_number']]),
        ['random_string', ', ', 'module_params'],
    ],
    module_name: identifierPosition([['compact_types'], ['random_number', ' ', 'random_operator', ' ', 'random_number']]),
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
    struct_decl: [['struct ', 'var_struct', ' {\n', 'struct_decl_fields', '\n}', 'valid_end_line']],
    struct_decl_fields: [['  ', 'random_string', ': ', 'valid_types']],
    enum_definition: [
        ['enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        ['export enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
    ],
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
    invalid_circuit_modifier: [['random_keyword'], ['random_string']],
    valid_circuit_modifier: [[''], ['export '], ['pure '], ['export pure ']],
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
    fixed_assert_statement: assertStatement,
    constructor_return_statements: returnStatements('constructor_return_statements'),
    circuit_return_statements: returnStatements('circuit_return_statements'),
    circuit_spread_statements: [
        ['const a', ' = [...slice<', 'random_number', '>(', 'valid_types', ', ', 'random_number', ')]', 'end_line'],
        ['const [', 'valid_types', ', ', 'valid_types', '] = ', '[...', 'valid_types', ', ', '...', 'valid_types', ']', 'end_line'],
        ['const a', ' = [...', 'random_string', ', ...', 'random_number', ']', 'end_line'],
        ['const a', ' = [...[', 'random_string', '], ...[', 'random_number', ']]', 'end_line'],
        ['const a', ' = [...', 'random_table', ', ...', 'random_mixed_table', ']', 'end_line'],
        ['const a', ' = [...[', 'random_table', '], ...[', 'random_mixed_table', ']]', 'end_line'],
    ],
    circuit_multi_const_statements: [
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ', 'random_string', ' = ', 'random_number', ', ', 'random_string', ' = ', 'random_mixed_table', 'end_line'],
        ['const ', 'random_string', ' = ', 'default<', 'valid_types', '>', ', ', 'random_string', ' = ', 'small_random_number', ', ', 'random_string', ' = ', 'random_keyword', 'end_line'],
        ['const ', 'random_string', ':', 'valid_types', ' = ', 'default<', 'valid_types', '>', ', ', 'random_string', ':', 'valid_types', ' = ', 'random_number', ', ', 'random_string', ':', 'valid_types', ' = ', 'random_keyword', 'end_line'],
    ],
    circuit_multi_const_statements_struct: [
        ['const ', 'random_string', ' = ', 'default<', 'var_struct', '>', ', ', 'random_string', ' = ', 'random_string', ', ', 'random_string', ' = ', 'random_number', 'end_line'],
    ],
    circuit_map_fold_statements: [
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'valid_types', ')', 'valid_end_line'],
        ['const a = ', 'fold(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'random_number', ', ', 'default<', ', ', 'valid_types', '>)', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'valid_types', ', ', 'valid_types', ')', 'valid_end_line'],
        ['const a = ', 'map(', 'a:', 'valid_types', ', x:', 'valid_types', '):', 'valid_types', '=> a + x, ', 'default<', 'valid_types', '>, default<', 'valid_types', '>)', 'valid_end_line'],
    ],
    ...preambleBindings('assert_binding_', 2, ASSERT_BINDINGS),
    assert_statement: [
        ['assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'random_keyword', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'assert_condition', ' ', 'random_keyword', '")', 'end_line'],
        ['assert (', 'assert_condition', 'random_keyword', 'random_string', '")', 'end_line'],
        ['random_keyword', ' ', 'assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
    ],
    ...preambleBindings('if_binding_', 3, IF_BINDINGS, { extra: { 2: ['sliceOfTuple'] } }),
    if_statement: [
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line'],
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line', 'if_statement'],
    ],
    for_loop_range: [
        /* Keep range bounds small: the compiler unrolls loops. */
        ['for (const ', 'bob', ' of ', 'very_small_random_number', '..', 'very_small_random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'counter_operation', ') {\n', '}\n'],
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
        ['for (const ', 'bob', ' of ', 'random_number', ' as Uint<455>', '..', 'random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_number', '..', 'random_number', ' as Uint<455>', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'random_string', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_mixed_table', ']', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(default<', 'valid_types', '>, ', 'random_number', ')) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'slice<', 'random_number', '>(', 'random_table', ', ', 'random_number', ')) {\n', '}\n'],
    ],
    ...preambleBindings('binding_', 4, STATEMENT_BINDINGS, {
        typeNode: STATEMENT_TYPE,
        terminator: 'valid_end_line',
    }),
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
        ['tom', 'random_string', 'bob'],
        ['tom', ' ', 'random_keyword', ' ', 'bob'],
        ['tom', 'random_operator', 'bob'],
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
    statement_variable: PREAMBLE_VARS.map((name) => [name]),
};

/* ================================================================== *
 * ledger ADTs
 *
 * The Compact-callable surface is examples/camelCase/all/ledger.compact, which is
 * exhaustive; this table is checked against it. Three kinds of entry here are not
 * on that list and are meant to stay:
 *
 *   deprecated aliases -- `check_root` is the snake_case spelling the compiler
 *     still accepts (compiler/standard-library-aliases.ss). It sits beside
 *     `checkRoot` so both paths are exercised.
 *   TypeScript-only    -- `findPathForLeaf`, `firstFree`, `root`, `history` exist
 *     on the ledger in TS but are not callable from Compact. Calling one is a
 *     negative test: the compiler should reject it.
 *   stale on purpose   -- `mint` (renamed `mintShielded`) and `pathFoLeaf` (a
 *     misspelling) should both be rejected, so they are worth generating.
 * ================================================================== */

/* Includes supported operations plus intentional negative cases. */
const LEDGER_OPS: Record<string, string[]> = {
    kernel: ['balance', 'balanceGreaterThan', 'balanceLessThan', 'blockTimeGreaterThan',
        'blockTimeLessThan', 'checkpoint', 'claimContractCall',
        'claimUnshieldedCoinSpend', 'claimZswapCoinReceive', 'claimZswapCoinSpend',
        'claimZswapNullifier', 'incUnshieldedInputs', 'incUnshieldedOutputs', 'mint',
        'mintShielded', 'mintUnshielded', 'self'],
    counter: ['decrement', 'increment', 'lessThan', 'read', 'resetToDefault'],
    set: ['insert', 'insertCoin', 'isEmpty', 'member', 'remove', 'resetToDefault', 'size'],
    map: ['insert', 'insertCoin', 'insertDefault', 'isEmpty', 'lookup', 'member', 'remove',
        'resetToDefault', 'size'],
    list: ['head', 'isEmpty', 'length', 'popFront', 'pushFront', 'pushFrontCoin', 'resetToDefault'],
    mt: ['checkRoot', 'findPathForLeaf', 'firstFree', 'insert', 'insertHash', 'insertHashIndex',
        'insertIndex', 'insertIndexDefault', 'isFull', 'pathFoLeaf', 'resetToDefault', 'root'],
    hmt: ['checkRoot', 'check_root', 'findPathForLeaf', 'firstFree', 'history', 'insert', 'insertHash',
        'insertHashIndex', 'insertIndex', 'insertIndexDefault', 'isFull', 'pathFoLeaf',
        'resetHistory', 'resetToDefault', 'root'],
};

const WIDE_ARITY: Record<string, number> = {
    'kernel.claimContractCall': 4,
    'kernel.claimUnshieldedCoinSpend': 4,
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
                ...Array.from(
                    { length: (WIDE_ARITY[`${adt}.${op}`] ?? 2) - 1 },
                    (_, i) => method(recv, op, PREAMBLE_VARS.slice(0, i + 2)),
                ),
                method(recv, op, same('statement_variable', 1)),
                method(recv, op, same('statement_variable', 2)),
            ])],
            [`no_variable_${adt}`, [
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
    maxArgs: number;
}

const STDLIB_CALLS: StdlibCall[] = [
    { name: 'some', generics: [T], maxArgs: 1 },
    { name: 'none', generics: [T], maxArgs: 1 },
    { name: 'left', generics: [T, T], maxArgs: 1 },
    { name: 'right', generics: [T, T], maxArgs: 1 },
    { name: 'transientHash', generics: [T], maxArgs: 1 },
    { name: 'transientCommit', generics: [T], maxArgs: 2 },
    { name: 'persistentHash', generics: [T], maxArgs: 1 },
    { name: 'persistentCommit', generics: [T], maxArgs: 2 },
    { name: 'hashToCurve', generics: [T], maxArgs: 1 },
    { name: 'merkleTreePathRoot', generics: [N, T], maxArgs: 2 },
    { name: 'merkleTreePathRootNoLeafHash', generics: [N], maxArgs: 1 },
    { name: 'degradeToTransient', generics: [], maxArgs: 1 },
    { name: 'upgradeFromTransient', generics: [], maxArgs: 1 },
    { name: 'ecAdd', generics: [], maxArgs: 2 },
    { name: 'ecMul', generics: [], maxArgs: 2 },
    { name: 'ecMulGenerator', generics: [], maxArgs: 1 },
    { name: 'nativeToken', generics: [], maxArgs: 1 },
    { name: 'tokenType', generics: [], maxArgs: 2 },
    { name: 'evolveNonce', generics: [], maxArgs: 2 },
    { name: 'shieldedBurnAddress', generics: [], maxArgs: 1 },
    { name: 'mintShieldedToken', generics: [], maxArgs: 4 },
    { name: 'mintUnshieldedToken', generics: [], maxArgs: 3 },
    { name: 'receiveShielded', generics: [], maxArgs: 2 },
    { name: 'receiveUnshielded', generics: [], maxArgs: 2 },
    { name: 'sendShielded', generics: [], maxArgs: 4 },
    { name: 'sendImmediateShielded', generics: [], maxArgs: 4 },
    { name: 'sendUnshielded', generics: [], maxArgs: 3 },
    { name: 'mergeCoin', generics: [], maxArgs: 3 },
    { name: 'mergeCoinImmediate', generics: [], maxArgs: 3 },
    { name: 'blockTimeLt', generics: [], maxArgs: 1 },
    { name: 'blockTimeLte', generics: [], maxArgs: 1 },
    { name: 'blockTimeGt', generics: [], maxArgs: 1 },
    { name: 'blockTimeGte', generics: [], maxArgs: 1 },
    { name: 'unshieldedBalance', generics: [], maxArgs: 2 },
    { name: 'unshieldedBalanceLt', generics: [], maxArgs: 3 },
    { name: 'unshieldedBalanceLte', generics: [], maxArgs: 3 },
    { name: 'unshieldedBalanceGt', generics: [], maxArgs: 3 },
    { name: 'unshieldedBalanceGte', generics: [], maxArgs: 3 },
    { name: 'ownPublicKey', generics: [], maxArgs: 2 },
    { name: 'createZswapInput', generics: [], maxArgs: 2 },
    { name: 'createZswapOutput', generics: [], maxArgs: 3 },
];

const arities = (c: StdlibCall): number[] => Array.from({ length: c.maxArgs }, (_, i) => i + 1);

const badGenerics = (genericNodes: Token[], node: Token): Token[] =>
    genericNodes.length ? [...genericNodes.slice(0, -1), node] : [];

const VALUE_ARGS: Token[] = ['statement_variable', 'statement_methods'];
const NO_VALUE_ARGS: Token[] = ['random_input', 'statement_std_types', 'no_variable_statement_methods'];
const BAD_GENERIC_ARGS: Token[] = ['random_input', 'statement_methods'];

const stdlib: Grammar = {
    statement_methods: [['variable_statement_methods'], ['no_variable_statement_methods']],

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
