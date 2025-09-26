/*
 * Enum definition related grammar.
 */
const enums = {
    enum_definitions: [['import CompactStandardLibrary;', 'line_separator', 'enum_definition']],
    enum_definition: [
        ['enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        ['export enum ', 'enum_name', ' {\n', 'enum_values', '}', 'end_line'],
        // ['generate_large_enum'],
    ],
    enum_name: [['random_string'], ['random_keyword'], ['random_number'], ['random_table'], ['random_version']],
    enum_values: [
        ['  ', 'random_string', 'line_separator'],
        ['  ', 'random_number', 'line_separator'],
        ['  ', 'random_table', 'line_separator'],
        ['  ', 'random_version', 'line_separator'],
        ['  ', 'random_keyword', 'line_separator'],
        ['  ', 'random_string', ',', 'line_separator', 'enum_values'],
    ],
};

exports.enums = enums;
