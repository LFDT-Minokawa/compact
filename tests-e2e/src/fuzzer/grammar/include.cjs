/*
 * Include statements related grammar.
 */
const include = {
    include_statements: [
        ['include_statement'],
        // ['include_statement', 'include_statements']
    ],
    include_statement: [
        ['random_keyword', ' include ', 'include_file', 'end_line'],
        ['random_string', ' include ', 'include_file', 'end_line'],
        ['include ', 'include_file', 'end_line'],
    ],
    include_file: [
        ['CompactStandardLibrary'],
        ['path/to/file'],
        ['//path//to//file'],
        ['\\path\\to\\file'],
        ['\/path\/to\/file'],
        ['\path\to\file'],
        ['random_string'],
        ['random_keyword'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['valid_type'],
        ['random_number', ' ', 'random_operator', ' ', 'random_number'],
    ],
};

exports.include = include;
