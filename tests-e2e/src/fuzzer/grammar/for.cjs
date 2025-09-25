/*
 * For statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz for, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const for_grammar = {
    for_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'for_declaration', 'for_body'],
        ['import CompactStandardLibrary;', 'line_separator', 'counter_declaration', 'for_declaration', 'for_body'],
    ],
    counter_declaration: [
        ['export ledger counter: Counter', 'end_line']
    ],
    counter_operation: [
        ['counter', 'random_operator', 'random_number'],
        ['counter', 'random_operator', 'small_random_number'],
        ['counter', 'random_operator', 'random_number', 'counter_operation'],
    ],
    for_declaration: [['constructor()']],
    for_body: [
        ['{\n', 'for_loop_range', '\n}'],
        // ['{\n', 'generate_nested_for', '\n}'],
    ],
    for_loop_range: [
        ['for (const ', 'bob', ' of ', 'random_number', '..', 'random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'counter_operation', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', 'small_random_number', '..', 'small_random_number', ') {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'random_table', ']) {\n', '}\n'],
        ['for (const ', 'bob', ' of ', '[', 'valid_types', ']) {\n', '}\n'],
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
    ],
};

exports.for_grammar = for_grammar;
