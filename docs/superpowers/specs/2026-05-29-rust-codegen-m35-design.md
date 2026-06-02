# Compact → Rust codegen M3.5 — Test matrix close-out

## Status

Design — approved verbally; implementation phasing in `docs/superpowers/plans/2026-05-29-rust-codegen-m35.md`.

## Goal

After M3 (commit `d29c668`), `compactc --rust examples/tiny.compact` produces a Rust crate that
compiles and passes 4 byte-parity e2e tests vs the TypeScript reference. M3 covered a narrow
slice of the language: one ADT (Counter via counter.compact, Cell via tiny), enums (one
non-exported), `Maybe<T>`, witnesses, hashes (one native), parameterised constructor.

M3.5's job is to **close test coverage across all Midnight ledger types and language primitives**
so the Rust path can be trusted for arbitrary contracts. The two concrete deliverables:

1. A **test matrix** with every primitive, ADT, user-type kind, native function, and circuit/constructor
   shape covered by either a snapshot test, a cargo-build test, or a byte-parity e2e test.
2. The **emitter, runtime, and fixture work** required to fill every gap in that matrix.

This is bigger than M3 was. The phasing is in `2026-05-29-rust-codegen-m35.md`.

## Non-goals

- Cross-contract calls. Compact does not support calling circuits across contracts (only sharing
  circuit modules at compile time via `import`); the Rust emitter therefore needs **no runtime
  cross-contract dispatch**. `tcontract` references in source position resolve to `ContractAddress`
  handles (F4 from M3 already does this).
- Reimplementing types that exist upstream. Map, Set, MerkleTree, HistoricMerkleTree, and primitive
  field/hash machinery already live in `midnight-storage`, `midnight-onchain-state`,
  `midnight-base-crypto`, and `midnight-transient-crypto`. M3.5 wraps these in thin `compact-runtime`
  re-exports / facade types; it does NOT clone them.
- proposal.compact verbatim. The file as written uses `type Ledger = { ... }` syntax that the
  current frontend rejects. M3.5 substitutes **zerocash.compact** (which parses today, has the same
  three M3.5-flagged features modulo Map: user struct + HistoricMerkleTree + Set + Opaque) plus
  a small purpose-built **Map fixture**. proposal.compact's syntax-rewrite is a separate cleanup,
  not blocking M3.5.

## Test matrix

The matrix has rows for every language feature and columns for the fixture/test that covers it.
After M3, the matrix looks like:

### Primitive types

| Feature | counter | tiny | zerocash | election | New fixture |
|---|---|---|---|---|---|
| `Field` (Fr) | | ✅ | ✅ | ✅ | — |
| `Boolean` (bool) | | ✅ | | | — |
| `Uint<8>` | | | | | `uints-fixture.compact` |
| `Uint<16>` | ✅ | | | | — |
| `Uint<32>` | | | | | `uints-fixture.compact` |
| `Uint<64>` | ✅ | | | | — |
| `Uint<128>` | | | | | `uints-fixture.compact` |
| `Bytes<N>` | | ✅ | ✅ | ✅ | — |
| `Vector<N, T>` | | 🟡 | | | `vector-fixture.compact` |
| `Opaque<"string">` | | | | ✅ | — |
| `Opaque<other>` | | | ✅ | | from zerocash |

### ADT types (ledger fields)

| ADT | counter | tiny | zerocash | election | M3.5 owner |
|---|---|---|---|---|---|
| `Counter` | ✅ | | | ✅ | done in M3 |
| `Cell<T>` | | ✅ | | ✅ | done in M3 |
| `Map<K, V>` | | | | | **`map-fixture.compact`** |
| `Set<T>` | | | ✅ | ✅ | **zerocash byte-parity** |
| `MerkleTree<H, T>` | | | | ✅ | **election byte-parity** |
| `HistoricMerkleTree<H, T>` | | | ✅ | | **zerocash byte-parity** |
| `List<T>` | | | | | only if Compact has it; investigate |

### User types

| Feature | covered? | M3.5 owner |
|---|---|---|
| exported enum | 🟡 manual fixture | promote to byte-parity fixture |
| non-exported enum | ✅ tiny | done in M3 |
| exported struct | 🟡 manual fixture | promote to byte-parity fixture |
| non-exported struct | ❌ | promote-to-exported pass + zerocash |
| transparent type alias | ❌ | `alias-fixture.compact` |
| nominal type alias | ❌ | `alias-fixture.compact` |

### Witness shapes

| Return type | covered? | M3.5 owner |
|---|---|---|
| `Bytes<N>` | ✅ tiny | done |
| `Field` | ❌ | `witnesses-fixture.compact` |
| user struct | ❌ | covered via zerocash |
| `Maybe<T>` | ❌ | `witnesses-fixture.compact` |
| witness with args | ❌ | `witnesses-fixture.compact` |

### Native functions

| Native | L2 mapped | Byte-parity | M3.5 owner |
|---|---|---|---|
| `transientHash` | ✅ | ❌ | byte-parity fixture |
| `transientCommit` | ✅ | ❌ | byte-parity fixture |
| `persistentHash` | ✅ (encoding gap) | tiny passes coincidentally | **fix encoding + mixed-input fixture** |
| `persistentCommit` | ✅ | ❌ | byte-parity fixture |
| `keccak256` | ❌ | ❌ | L2.1 + fixture |
| Jubjub bundle (6 fns) | ❌ | ❌ | L2.2 + fixture |
| `degradeToTransient` / `upgradeFromTransient` | ❌ | ❌ | L2.3 |
| Zswap witnesses (`ownPublicKey`, `createZswapInput`/`Output`) | ❌ | ❌ | L2.4 |

### Circuit / constructor shapes

| Shape | counter | tiny | zerocash | election | M3.5 owner |
|---|---|---|---|---|---|
| empty constructor | ✅ | | | ✅ | done |
| constructor with args | | ✅ | | ✅ | done |
| **implicit constructor (no decl)** | | | ✅ | | **emitter fix** |
| pure circuit | | ✅ | ✅ | | done shape; zerocash byte-parity |
| impure returning `()` | ✅ | ✅ | ✅ | ✅ | done |
| impure returning value | | ✅ | | | done shape; zerocash byte-parity |
| `assert` | | ✅ | likely | likely | done shape; zerocash byte-parity |
| `if-statement` (not ternary) | | ❌ | likely | likely | **`if-stmt-fixture.compact`** |
| cross-circuit call (exported) | | | ✅ | ✅ | zerocash byte-parity |
| cross-circuit call (non-exported, inlined) | | ✅ | ✅ | ✅ | done shape |
| native hash call | | ✅ | ✅ | | byte-parity |
| Map/Set/MerkleTree method calls | | | ✅ | ✅ | byte-parity |

## Architecture deltas vs M3

### Emitter

**E1. Implicit constructor support.** When a contract has no source-level `constructor`, the
frontend synthesises one. The Ltypescript IR likely contains `(constructor src () (tuple))` —
empty args, unit body. Verify `emit-initial-state` walks this cleanly (it should, since J2's body
walker handles `(tuple)` as the terminal "no-op").

**E2. Non-exported user struct promotion.** When a ledger field references a user struct that the
source doesn't `export`, the struct is still needed in the Rust output (for the typed Ledger view).
Add a frontend pre-pass that scans ledger-field types for `tstruct` references and synthesises an
`export-typedef` for each. zerocash uses ~7 such structs.

**E3. Typed Ledger materialised view.** Currently the emitted `Ledger<'a, D>` is a thin reader
wrapper with per-field accessor methods (K2). For ADT-heavy contracts the user-facing API is much
better if `Ledger` is a struct with proper field types (`pub nullifiers: Set<Nullifier>` etc.). This
becomes the "real Ledger" the contract exposes; the per-field accessor methods can be kept as a
secondary read path or replaced.

Option A: emit two structs — `Ledger<'a>` (current thin wrapper) plus `LedgerSnapshot` (fully
materialised, derived from the wrapper via a `.snapshot()` method).
Option B: replace the wrapper outright with a materialised struct.

Going with **Option A** for backwards compatibility and to keep gather-mode reads cheap.

**E4. Map/Set/MerkleTree/HistoricMerkleTree method-call emission.** Each ADT method (e.g.
`Map.lookup`, `Set.insert`, `MerkleTree.check_root`) is a `(public-ledger ... <op-class> ...)`
expression in the IR. The existing I3 walker handles Cell.write / Counter.increment; extend it to
recognise op-classes for the new ADTs and emit the right runtime call (whichever upstream method
on the wrapper type).

**E5. Cross-circuit-call to exported circuit.** I3b/3 inlined non-exported circuits via the
`in_state` special-case. M3.5 needs the general case: when a circuit body contains
`(call <function-name> <arg>*)` whose target is an exported circuit, emit `self.<snake-name>(ctx, args)`.
For non-exported targets, generalise the inlining beyond the in_state special-case.

**E6. `if-statement` (vs `if-expression`) shape.** I3b/4 handled `(if cond then else)` in
statement-of-non-unit-return position. M3.5 needs `(if cond then-stmt else-stmt)` in
statement-of-unit-return position (with each branch a sequence of statements).

### Runtime

**R1. Re-export `Set<T>`, `Map<K, V>`, `MerkleTree<H, T>`, `HistoricMerkleTree<H, T>`.** All four
live upstream. Re-exported via `compact_runtime::std_lib` so generated code can write
`Set<Nullifier>` etc.

**R2. Native function bindings — full audit.** `compact-runtime/src/lib.rs:64-68` re-exports four
hash functions. M3.5 audits `midnight-natives.ss` against actual upstream symbols and re-exports
the rest: `keccak256` (likely in `midnight_base_crypto::hash`), Jubjub primitives (likely in
`midnight_transient_crypto::curve`), `degradeToTransient`/`upgradeFromTransient`. Add `(rust ...)`
mappings to each entry in `midnight-natives.ss` (L2 pattern from M3).

**R3. `persistent_hash` argument encoding.** Current Rust emission is
`[a, b, ...].concat().0` — a raw byte-string concat. TS goes through `rtType.toValue(value)` which
adds alignment framing. The two coincide for uniform inputs (e.g. two `[u8; 32]`s) but diverge for
mixed-type inputs. M3.5 emits an alignment-aware Value-encoded byte buffer.

**R4. Decoders for additional read types.** `decoder-for-type` (K2.1) currently handles tunsigned,
tfield, tbytes (added in I3b/3), tenum (added in I3b/3). Extend to tstruct (return the struct via
its `FromFieldRepr` impl), Maybe<T> (via Maybe's existing FromFieldRepr), and any others surfaced by
the matrix.

### Fixtures

**F1. zerocash.compact** — already in tree; add `constructor() {}` if implicit support is not yet
landed, otherwise leave as-is. M3.5 target: clean cargo build of the emitted crate + byte-parity test.

**F2. election.compact** — already in tree; same target. Covers `MerkleTree` + `Set` + multiple
enums + `Maybe<Opaque<"string">>`.

**F3. `map-fixture.compact`** — small (~20 lines) contract using `Map<Field, Field>` or similar
simple types. Exercises Map.insert/lookup/remove.

**F4. `uints-fixture.compact`** — tiny contract storing u8, u32, u128 ledger fields. Exercises
all integer widths in K1/K2 paths.

**F5. `vector-fixture.compact`** — tiny contract using `Vector<3, Field>` as a ledger field type
or function arg. Exercises tvector emission + repr.

**F6. `aliases-fixture.compact`** — tiny contract with a transparent type alias and a nominal
type alias.

**F7. `witnesses-fixture.compact`** — tiny contract with witnesses returning Field, Maybe<T>, and
a user struct. Exercises G1's arg emission for the arg-bearing case.

**F8. `if-stmt-fixture.compact`** — tiny contract with `if (cond) { stmts } else { stmts }` in a
circuit body (vs the ternary `cond ? expr : expr`).

Each fixture gets its own snapshot test in `compiler/test.ss` + a cargo-build test (one expressed
as a workspace member like tiny). Where a runtime sequence is small enough, a byte-parity test too.

## Phasing — see plan doc

Implementation phasing lives in `docs/superpowers/plans/2026-05-29-rust-codegen-m35.md`. Summary
of the dependency graph:

1. **E1 (implicit constructor)** — small, blocks zerocash. Lands first.
2. **F4–F8 small fixtures + their emitter/runtime extensions** — these are independent and
   parallelisable; each closes one matrix row.
3. **E2 (non-exported struct promotion) + zerocash compile** — unlocks F1, F2.
4. **R2 (native audit) + R3 (persistent_hash encoding)** — needed before byte-parity for any
   contract that hashes.
5. **R1 (ADT re-exports) + E4 (ADT method emission) + E3 (typed Ledger view)** — unlocks
   zerocash + election + map-fixture byte-parity. The biggest single piece.
6. **E5 (general cross-circuit calls) + E6 (if-statement)** — fills out remaining circuit-shape gaps.
7. **Byte-parity tests** — F3 (map), F1 (zerocash), F2 (election). One per fixture, mirroring M2/M2.1.

Each phase ends with the matrix's covered cells flipping from ❌/🟡 to ✅. M3.5 closes when
every cell is ✅ or has a documented carve-out.
