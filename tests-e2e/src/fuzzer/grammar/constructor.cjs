/*
 * Constructor statements related grammar.
 */
const constructor = {
    constructor_statements: [['import CompactStandardLibrary;', 'line_separator', 'constructor_declaration', 'constructor_body']],
    constructor_declaration: [
        ['random_keyword', ' ', 'constructor()'],
        ['random_string', ' ', 'constructor()'],
        ['constructor()'],
        ['constructor(', 'constructor_params', ')'],
    ],
    constructor_body: [['{\n ', 'constructor_assert_statements', 'constructor_return_statements', '\n}']],
    constructor_assert_statements: [['assert (', ' 1 < 2 ', ', ', '"Secret message"', ')', 'end_line']],
    constructor_return_statements: [
        ['optional_end'],
        ['return', 'optional_end'],
        ['return', 'optional_end', 'constructor_return_statements'],
        ['return ', 'random_keyword', 'optional_end'],
        ['return ', 'random_string', 'optional_end'],
        ['return ', 'random_number', 'optional_end'],
    ],
    optional_end: [[''], ['end_line']],
    constructor_params: [
        ['random_string', ' : ', 'constructor_param_types'],
        ['random_keyword', ' : ', 'constructor_param_types'],
        ['random_string', ' : ', 'constructor_param_types', ', ', 'constructor_params'],
    ],
    constructor_param_types: [['random_keyword'], ['random_string'], ['random_table'], ['random_version'], ['compact_types']],
};

exports.constructor = constructor;
