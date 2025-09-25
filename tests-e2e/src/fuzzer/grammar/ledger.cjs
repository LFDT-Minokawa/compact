/*
 * Ledger statements related grammar.
 */
const ledger = {
    ledger_statements: [
        ['import CompactStandardLibrary;', 'line_separator', 'optional_modifier', ' ledger ', 'random_string', ': ', 'compact_types', 'end_line'],
        // ['optional_modifier', 'ledger ', 'random_string', ': ', 'compact_types', 'end_line', 'ledger_statements'],
    ],
    optional_modifier: [
        [''],
        ['export'],
        ['sealed'],
        ['export sealed'],
        ['sealed export'],
        ['random_keyword'],
        ['random_string'],
        ['random_table'],
        ['random_version'],
        ['random_number'],
        ['compact_types'],
    ],
};

exports.ledger = ledger;
