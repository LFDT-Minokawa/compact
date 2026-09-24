# Compiler fuzzer

Generates random Compact contracts from a grammar and checks that the compiler
never fails with an internal error on them.

## Layout

- `grammar/compact.ts`: the grammar table and its entry points, one per fuzzer.
- `grammar/index.ts`: validation that runs before any contract is generated.
- `utils/generators.ts`: generators for the random terminals such as
  `random_version`.
- `utils/fuzzer.ts`, `fuzzers.ts`: expand the grammar and write the contracts.

## Running

```
cd tests-e2e
NO_OF_FUZZER_TESTS=10 yarn test:fuzzer
```

`NO_OF_FUZZER_TESTS` is the number of contracts *per fuzzer* (default 1000, max
2000; anything outside 1–2000 falls back to the default). There is one fuzzer
per entry in `ENTRY_POINTS`, currently 15, so the command above compiles 150
contracts, not 10. Contracts that fail are kept in `tests-e2e/failed-contracts/`.

## Adding syntax

Add productions to `grammar/compact.ts`. A new fuzzer needs an entry in
`ENTRY_POINTS`, and a new random terminal needs a name in `TERMINALS` and a
generator in `utils/generators.ts`. Validation fails the run if a reference is
undefined or a production is unreachable.
