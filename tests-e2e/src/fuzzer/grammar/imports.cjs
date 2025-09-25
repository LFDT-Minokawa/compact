/*
 * Imports statements related grammar.
 */
const imports = {
    import_statements: [
        ['import_statement'],
        // ['import_statement', 'import_statements']
    ],
    import_statement: [
        ['random_keyword', ' import ', 'import_library', 'end_line'],
        ['random_string', ' import ', 'import_library', 'end_line'],
        ['import ', 'import_library', 'end_line'],
        ['import ', 'import_library', ' prefix ', 'prefix_string', 'end_line'],
    ],
    import_library: [
        ['CompactStandardLibrary'],
        ['"CompactStandardLibrary"'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['valid_type'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
    prefix_string: [
        ['CompactStandardLibrary'],
        ['"CompactStandardLibrary"'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['valid_type'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
};

exports.imports = imports;
