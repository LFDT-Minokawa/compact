/*
 * Module statements related grammar.
 */
const module_grammar = {
    module_statements: [
        // ['generate_modules'],
        ['module_statement'],
    ],
    module_statement: [
        ['module ', 'module_name', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '<', 'module_params', '>', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '[', 'module_params', ']', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '(', 'module_params', ')', ' {', 'line_separator', '}', 'line_separator'],
        ['module ', 'module_name', '{', 'module_params', '}', ' {', 'line_separator', '}', 'line_separator'],
    ],
    module_params: [
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
        ['random_string', ', ', 'module_params'],
    ],
    module_name: [
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
};

exports.module_grammar = module_grammar;
