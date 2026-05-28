# M3a Witness Crash — Diagnostic Note

**Date:** 2026-05-29
**Plan:** [`docs/superpowers/plans/2026-05-29-rust-codegen-m3a.md`](../plans/2026-05-29-rust-codegen-m3a.md), Task M4.

## Minimal repro contract

`tests/witness-minimal.compact`:

```compact
import CompactStandardLibrary;

export { try_witness }

witness w_bytes32(): Bytes<32>;

export circuit try_witness(): [] {
  const v = w_bytes32();
  disclose(v);
}
```

## Command + observed output

```
$ export PATH="$PWD/result/bin:$PATH"
$ export COMPACT_PATH="$PWD/compiler"
$ compactc --rust tests/witness-minimal.compact /tmp/witness-min-out
Internal error (please report): Exception in symbol->string: %w_bytes32.0 is not a symbol
```

Exit code: 0 (compactc swallows the error and exits 0). Output directory empty.

Without `--rust`, compilation succeeds — the crash is `--rust`-specific.

## Outcome (per plan §M4)

**Outcome 2 with a refinement.** The plan framed outcome 2 as "witness emission *itself* crashes upstream of rust-passes." In fact the crash is **inside `rust-passes.ss`**, not upstream:

- `compiler/rust-passes.ss:42` — `camel->snake` calls `(symbol->string s)`
- The argument `s` is a `function-name` extracted from `(witness ,src ,function-name (,arg* ...) ,type)`. In the post-typescript `Ltypescript` language (`compiler/langs.ss:487`), `function-name` is an `id` record (not a symbol).
- `id` is defined at `compiler/langs.ss:441` as a record with fields `src sym refcount flags uniq`; the symbol is accessed via `id-sym`.
- Other passes (e.g. `typescript-passes.ss:378`) consistently use `(symbol->string (id-sym id))`.

The bug was dormant in M2 because counter.compact has zero witnesses, so `camel->snake` was never invoked. The first witness-bearing contract trips it.

## Tentative fix

In `compiler/rust-passes.ss:42`, change:

```scheme
(let* ([str (symbol->string s)]
```

to:

```scheme
(let* ([str (symbol->string (id-sym s))]
```

This needs to happen before M7 lands (M7 explicitly calls `camel->snake` on witness function names and would re-trip the same bug).

## Implication for the rest of the plan

- M5-M9 remain in scope as written.
- The fix above is a one-line precursor that should land before or as part of M7. Suggest folding into M7 (`feat(rust-passes): emit witness trait with real args + return types`) since that's the first task that actually exercises witness emission end-to-end.
- The `id-sym` accessor must also be threaded through the new `expr-rust`/`stmt-rust` walkers in M8/M9 wherever identifiers are emitted (e.g. `(camel->snake name)` in `expr-rust` for `[(ident ,name) ...]`).
