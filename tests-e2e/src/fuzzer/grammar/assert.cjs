/*
 * Assert statements related grammar.
 *
 * Switched to valid types in variables, as we are trying to fuzz assert, but in most cases fail on variable setup.
 * Statement fuzzing will be covered in statement fuzzer.
 *
 * TODO: make grammar more flexible so we can use different grammars together (like common)
 */
const asserts = {
    assert_statements: [['import CompactStandardLibrary;', 'line_separator', 'assert_declaration', 'assert_body']],
    assert_declaration: [['constructor()']],
    assert_body: [['{\n ', 'assert_variable_a', 'assert_variable_b', 'assert_body_statements', '\n}']],
    assert_body_statements: [['assert_statement']],
    assert_variable_a: [['const ', 'bob', ' = ', 'default<', 'valid_types', '>', 'valid_end_line']],
    assert_variable_b: [['const ', 'tom', ' = ', 'default<', 'valid_types', '>', 'valid_end_line']],
    assert_statement: [
        ['assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'random_keyword', ', "', 'random_string', '")', 'end_line'],
        ['assert (', 'assert_condition', ' ', 'random_keyword', '")', 'end_line'],
        ['assert (', 'assert_condition', 'random_keyword', 'random_string', '")', 'end_line'],
        ['random_keyword', ' ', 'assert (', 'assert_condition', ', "', 'random_string', '")', 'end_line'],
    ],
    assert_condition: [
        ['tom', 'random_string', 'bob'],
        ['tom', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['tom', ' ', 'random_keyword', ' ', 'bob'],
        ['bob', 'random_operator', 'tom'],
        ['bob', 'random_operator', 'tom', 'random_operator', 'tom'],
        ['bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'tom'],
        ['tom', 'random_operator', 'tom', 'random_operator', 'bob', 'random_operator', 'bob'],
        ['tom', 'random_operator', 'random_keyword'],
        ['random_keyword', 'random_operator', 'bob'],
    ],
};

exports.asserts = asserts;
