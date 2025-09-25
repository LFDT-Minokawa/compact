/*
 * If statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz ifs, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const if_grammar = {
    if_statements: [['import CompactStandardLibrary;', 'line_separator', 'if_declaration', 'if_body']],
    if_declaration: [['constructor()']],
    if_body: [
        ['{\n ', 'if_variable_a', 'if_variable_b', 'if_variable_c', 'if_body_statements', '\n}'],
        // ['{\n ', 'generate_nested_if', '\n}'],
    ],
    if_body_statements: [['if_statement']],
    if_variable_a: [
        ['const ', 'bob', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'bob', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'bob', ' = ', 'random_number', 'end_line'],
    ],
    if_variable_b: [
        ['const ', 'tom', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'tom', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'tom', ' = ', 'random_number', 'end_line'],
    ],
    if_variable_c: [
        ['const ', 'greg', ' = ', 'default<', 'valid_types', '>; \n'],
        ['const ', 'greg', ' = ', 'small_random_number', 'end_line'],
        ['const ', 'greg', ' = ', 'random_number', 'end_line'],
    ],
    if_statement: [
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line'],
        ['if (', 'if_condition', 'random_operator', 'if_condition', ')', '{}', 'end_line', 'if_statement'],
    ],
    if_condition: [
        ['tom', 'random_operator', 'bob'],
        ['tom', 'random_keyword', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'greg'],
        ['tom', 'random_operator', 'bob', 'random_keyword', 'greg'],
        ['tom', 'random_operator', 'random_number'],
        ['tom', 'random_operator', '"', 'random_string', '"'],
        ['"', 'random_string', '"', 'random_operator', 'tom'],
        ['tom * bob', 'random_operator', 'random_number'],
        ['tom + bob', 'random_operator', 'random_number'],
        ['tom - bob', 'random_operator', 'random_number'],
        ['tom / bob', 'random_operator', 'random_number'],
        ['tom', ' as ', 'valid_types', 'random_operator', 'random_number'],
        ['tom', 'random_operator', 'bob', ' as ', 'valid_types'],
        ['random_number', 'random_operator', 'tom'],
        ['random_number', 'random_operator', 'tom * bob'],
        ['random_number', 'random_operator', 'tom + bob'],
        ['random_number', 'random_operator', 'tom - bob'],
        ['random_number', 'random_operator', 'tom / bob'],
        ['default<', 'valid_types', '>', 'random_operator', 'default<', 'valid_types', '>'],
    ],
};

exports.if_grammar = if_grammar;
