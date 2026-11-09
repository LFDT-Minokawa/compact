# Inner verifying key fixtures

Files named by `prepareVerification` in the compiler tests in `compiler/test.ss`, which find them
through `--compact-path`.

- `testfile.verifier` is a placeholder, not a real key. The compiler reads a key's bytes at
  compile time and embeds them in the circuit without parsing them; only `zkir` parses them, and
  the compiler tests do not run `zkir`. Keeping it short keeps the expected ZKIR in the tests
  readable.
- `empty.verifier` is empty, which `prepareVerification` rejects.
