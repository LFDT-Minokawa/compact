# Compact → Rust codegen — Upstream parity gap report

## Status

Research artefact produced 2026-06-02 after M3.5 emitter-validation closure (commit `f6e2f1a`). Drives iterations 3-N of the codegen polish work.

## TL;DR

Our Rust codegen covers the structural backbone of Compact: scalars, ADTs as ledger fields (Counter / Cell / Map / Set / MerkleTree / HistoricMerkleTree), user structs and enums, transparent + nominal type aliases, witnesses, native hashes, `if`-statement bodies, ADT method calls (`insert` / `lookup` / `member` / `checkRoot`), cross-circuit calls. 25 e2e byte-parity tests cover this surface.

What's NOT covered is roughly orthogonal:
1. **Higher-order control flow** — `fold` / `map` / lambda-as-expression / `for`-range / `for`-iterable loops
2. **Module system** — `module M { ... }` / `import M` / prefix renaming / nested modules
3. **Generic circuits** — `circuit f<#N>()` / `<#S, #E>` multi-param
4. **`List<T>` ADT** — the only core ADT we haven't fixtured
5. **`Uint<L..U>`** bounded ranges

Effort estimates and priority below.

## Test surface stats

- **487 `.compact` sources** at `compiler/javascript-code/test{533..1034}/src/compiler/testdir/testfile.compact`
- **~2,938 inline `(test ...)` blocks** in `compiler/test.ss` (most are parser / IR / negative tests; only the 487 above produced JS output and thus exercise full lowering)
- Heaviest features by file count: `export circuit` (446), `disclose` (247), `Field` (280), `Uint<>` (206), `Vector<>` (182), `import` (169), `?:` (46), `fold(` (36), `enum` (29), `if` (26), `for` (20), `module` (35)

## Coverage table

| Category | Feature | Test count | Rust coverage | Severity |
|---|---|---|---|---|
| Primitive | Field / Boolean / Bytes<N> / Vector<N,T> / Uint<8…128> | 280 / 156 / 146 / 182 / 206 | ✅ | — |
| Primitive | Opaque<"string"> / Opaque<other> | 11 | ✅ | — |
| Primitive | Maybe<T> | 5 | ✅ | — |
| Primitive | **Uint<L..U>** (bounded range) | 13 | ❌ | Medium |
| ADT | Counter / Cell | 19 | ✅ | — |
| ADT | Map<K,V> incl. nested Map<K, Map<…>> | 34 | ✅ basic; nested chained lookup not exercised | Medium |
| ADT | Set<T> (member/insert/size/isEmpty) | 15 | ✅ insert+member; `.size()`/`.isEmpty()` untested | Medium |
| ADT | MerkleTree<H,T> | 16 | ✅ | — |
| ADT | HistoricMerkleTree<H,T> (`.checkRoot`, `.insertIndexDefault`) | 9 | ✅ checkRoot; **insertIndexDefault not** | Medium |
| ADT | **List<T>** (pushFront/popFront/head/length/isEmpty) | 16 | ❌ no fixture | **High** |
| User type | struct (exported/non-exported/nested/parameterised `S<a,#n>`) | 35 | ✅ exported+non-exported; **generic structs** not | Medium |
| User type | enum (return/compare/`default<E>`) | 29 | ✅ | — |
| User type | type alias (transparent/nominal/chained) | 13 | ✅ direct; chained alias untested | Low |
| Circuit | export circuit / impure / pure modifier | 446 / many / 4 | ✅ basic; `pure circuit` modifier not explicitly fixtured | Low |
| Circuit | **generic circuit** `circuit f<#N>()` | 2+ | ❌ | **High** |
| Circuit | constructor with args / implicit | 20 | ✅ | — |
| Witness | various args/returns | 17 | ✅ | — |
| Witness | module-local witness | 1 | ❌ | Low |
| Control flow | if/else, ternary | 26 / 46 | ✅ | — |
| Control flow | **for (const i of L..U)** range loop | 9 | ❌ | **High** |
| Control flow | **for (const x of iterable)** element loop | 3+ | ❌ | **High** |
| Control flow | **fold(λ, init, vec)** | 36 | ❌ | **High** |
| Control flow | **map(λ, arr)** | 47 | ❌ | **High** |
| Control flow | **lambda-as-expression** `(x) => …` / IIFE | 88 (`=>` count) | ❌ | **High** |
| Control flow | comma-sequenced exprs | 4+ | ✅ basic | Medium |
| Casts | `as Uint` / `as Bytes` / `as Field` | 21 / 15 / 16 | ✅ trivial; explicit-cast-as-expr generally untested | Medium |
| Modules | **module / import / prefix imports** | 35 / 169 / 10 | ❌ | **High** |
| Modules | nested modules, sealed ledger | 1 / 3 | ❌ | Medium/Low |
| Modules | `export { … }` block | 30+ | ✅ partial | Low |
| Natives | persistentHash/Commit/transientHash/Commit | rare | ✅ | — |
| Natives | hashToCurve / Jubjub / Zswap | 1+ | ✅ mapped (R2); no byte-parity test | Low |
| Natives | keccak256 / sha256 | 0 in test corpus | ✅ mapped | — |
| Natives | `pad(N, "str")` | 50+ | ✅ | — |
| Misc | Bytes-literal `Bytes[1,2,3,…]` | 73 | ✅ | — |
| Misc | array-literal `[a,b,c]` (incl. mixed-type) | 87 | ✅ tuple-return; **mixed-type literal** untested | Medium |
| Misc | compound `+=` | 10 | ✅ | — |
| Misc | indexed read `v[i]` | 73 | ✅ | — |
| Misc | `contract C {}` declaration | 4 | ❌ | Low |

## Top 5 gaps (priority order)

### Gap 1 — `for`-loops (range + iterable) [HIGH, Medium effort]
- `for (const i of 0..N) { ... }` and `for (const x of disclose(bv)) { ... }`
- Used in ~12 tests including test682 (Set seeded with 256 items), test780 (Counter accumulator), test895 (Bytes folding), test900, test1020.
- Without this, any contract with a non-trivial constructor seed loop can't be ported.

### Gap 2 — Higher-order stdlib: fold / map / lambda [HIGH, Medium-Large effort]
- `fold((acc, x) => acc + x, 0, vec)` (36 tests), `map(fn, arr)` (47 tests), bare lambdas in expression position (88 `=>` occurrences).
- `fold` is the canonical bounded-loop-with-accumulator in Compact.

### Gap 3 — Module system [HIGH, Large effort]
- `module M { ... }`, `import M`, `import M prefix P_`, nested modules, module-local witness, sealed ledgers.
- 35 tests use `module`, 169 use `import`.
- Needs design decision: do prefixed imports become Rust modules or flattened with renamed symbols? Verify whether `desugar-modules` already runs pre-Rust-IR.

### Gap 4 — `List<T>` ADT [HIGH, Small-Medium effort]
- One of the seven core ADTs. test700, test620 (Map<…, List<…>>), test689.
- Runtime wrapper pattern is identical to Set/Map — modest work.

### Gap 5 — Generic circuits + bounded uints [HIGH, Medium-Large effort]
- `circuit f<#N>(): ...` (test1020), `foo1<#S, #E>()` (test1021).
- Investigate whether `monomorphise` runs before Rust IR (likely yes — verify).
- `Uint<L..U>` (13 tests) — likely lowers to underlying Uint width.

## Honourable mentions (lower priority but real)

- HistoricMerkleTree.`insertIndexDefault` (test937)
- Nested Map chained lookup (test1010)
- Sealed ledger (3 tests)
- `pure circuit` modifier (4 tests)
- `hashToCurve` byte-parity
- Mixed-type array literals `[Uint<8>, Bytes<8>]` (test729)
- `contract C {}` declarations (4 tests)

## Suggested next iterations

| Iter | Item | Effort | Tests unlocked |
|---|---|---|---|
| 3 | List<T> ADT (runtime wrapper + emitter dispatch + fixture) | Small-Medium | 16 |
| 4 | for-range loop | Medium | ~5-8 |
| 5 | for-iterable loop | Medium | ~3-5 |
| 6 | fold basic (closed over var, no side-effects) | Medium-Large | ~20 |
| 7 | map + lambda-as-expression | Medium-Large | ~50 |
| 8 | Uint<L..U> bounded ranges | Small | 13 |
| 9 | Pure circuit modifier + sealed ledger | Small | 7 |
| 10 | Modules (basic flat `import M`) | Large | ~30 |
| 11 | Generic circuits (verify monomorphise + fixture) | Medium | 2-5 |
| 12 | Mop-up: nested Maps, HMT.insertIndexDefault, hashToCurve byte-parity | Medium | ~5 |

Done sequentially this is ~10 iterations of meaningful work, ~3-5 days at the dispatch rate we've been running.

---

Drives iterations 3-12 of the M3.5 → M4 transition.
