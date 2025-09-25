/*
 * Struct definition related grammar.
 */
const struct = {
    struct_definitions: [
        ['import CompactStandardLibrary;', 'line_separator', 'struct_definition'],
        // ['struct_definition', 'struct_definitions']
    ],
    struct_definition: [
        ['struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
        ['random_keyword', ' struct ', 'random_string', ' {\n', 'struct_fields', '\n}', 'end_line'],
    ],
    struct_fields: [['struct_field'], ['struct_field', ',', 'line_separator', 'struct_fields']],
    struct_field: [
        ['  ', 'random_string', ': ', 'valid_types'],
        ['  ', 'random_keyword', ': ', 'valid_types'],
        ['  ', 'random_string', ': ', 'compact_types'],
    ],
};

exports.struct = struct;
