/*
 * Circuit statements related grammar.
 *
 * Description of output:
 * - circuit_declaration - will create more random circuit
 * - circuit_declaration_with_body - will try to more mimic "real" circuit definition
 */
const circuit = {
    circuit_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'optional_circuit', ' ', 'circuit_declaration'],
        ['optional_circuit', ' ', 'circuit_declaration'],
        ['import CompactStandardLibrary;', 'line_separator', 'valid_optional_circuit', 'circuit_declaration_with_body', 'circuit_body'],
    ],
    optional_circuit: [['random_keyword'], ['random_string'], ['optional_circuit']],
    valid_optional_circuit: [['export '], ['pure '], ['valid_optional_circuit']],
    circuit_declaration: [
        ['circuit ', 'random_string', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_keyword', '(): ', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
        ['circuit ', 'random_string', '(', 'contaminated_circuit_params', '):', 'contaminated_compact_types', 'end_line'],
    ],
    circuit_declaration_with_body: [
        ['circuit ', 'random_string', '(): ', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '():', 'valid_types'],
        ['circuit ', 'random_string', '<', 'circuit_args', '>', '(', 'circuit_params', '):', 'valid_types'],
        ['circuit ', 'random_string', '(', 'circuit_params', '):', 'valid_types'],
    ],
    circuit_body: [['{\n ', 'circuit_assert_statements', 'circuit_return_statements', '\n}']],
    circuit_assert_statements: [['assert (', ' 1 < 2 ', ', ', '"Secret message"', ')', 'end_line']],
    circuit_return_statements: [
        ['optional_end'],
        ['return', 'optional_end'],
        ['return', 'optional_end', 'circuit_return_statements'],
        ['return ', 'random_keyword', 'optional_end'],
        ['return ', 'random_string', 'optional_end'],
        ['return ', 'random_number', 'optional_end'],
    ],
    optional_end: [[''], ['end_line']],
    circuit_args: [['random_string'], ['random_string', ', ', 'circuit_args']],
    circuit_params: [
        ['random_string', ' : ', 'valid_types'],
        ['random_string', ' : ', 'valid_types', ', ', 'circuit_params'],
    ],
    contaminated_circuit_params: [
        ['random_string', ' : ', 'contaminated_compact_types'],
        ['random_keyword', ': ', 'contaminated_compact_types'],
        ['random_string', ' : ', 'contaminated_compact_types', ', ', 'circuit_params'],
    ],
};

exports.circuit = circuit;
