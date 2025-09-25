/*
 * Pragma statements related grammar.
 */
const pragma = {
    pragma_statements: [
        ['pragma ', 'pragma_constraints', 'end_line'],
        // ['pragma ', 'pragma_constraints', 'end_line', 'pragma_statements'],
    ],
    pragma_constraints: [['pragma_constraint'], ['pragma_constraints', ' ', 'random_operator', ' ', 'pragma_constraint']],
    pragma_constraint: [['pragma_type', ' ', 'random_operator', ' ', 'version_number']],
    pragma_type: [
        ['language_version'],
        ['compiler_version'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
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
};

exports.pragma = pragma;
