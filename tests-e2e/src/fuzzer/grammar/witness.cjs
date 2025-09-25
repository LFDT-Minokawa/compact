/*
 * Witness statements related grammar.
 */
const witness = {
    witness_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'export ', 'witness_declaration'],
        ['import CompactStandardLibrary;', 'line_separator', 'witness_declaration'],
    ],
    witness_declaration: [
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '(): ', 'valid_types', 'end_line'],
        ['witness ', 'random_keyword', '(): ', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '():', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '<', 'witness_args', '>', '(', 'witness_params', '):', 'compact_types', 'end_line'],
        ['witness ', 'random_string', '(', 'witness_params', '):', 'compact_types', 'end_line'],
    ],
    witness_args: [['random_string'], ['random_keyword'], ['random_string', ', ', 'witness_args']],
    witness_params: [
        ['random_string', ' : ', 'compact_types'],
        ['random_keyword', ' : ', 'compact_types'],
        ['random_number', ' : ', 'compact_types'],
        ['random_table', ' : ', 'compact_types'],
        ['random_version', ' : ', 'compact_types'],
        ['random_string', ' : ', 'compact_types', ', ', 'witness_params'],
    ],
};

exports.witness = witness;
