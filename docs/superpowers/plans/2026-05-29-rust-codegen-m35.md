# Compact → Rust codegen M3.5 — Implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: `superpowers:subagent-driven-development`.
> Each task is a focused unit; fresh subagent per task; counter + tiny snapshots MUST stay
> byte-identical throughout.

## Progress

| Phase | Tasks | Status | Last commit |
|---|---|---|---|
| **E1** — Implicit constructor support | E1.1 ✅ (verified, no fix needed) | done | — |
| **E2** — Non-exported struct promotion | E2.1 ✅ | done | `c56372e` |
| **R1** — Re-export ADT wrappers in compact-runtime + builder helpers | R1.1 ✅, R1.2 ✅, R1.3 ✅ | done | `3e0bb74` |
| **R2** — Native function mapping audit | R2.1 ✅ (TODO), R2.2 ✅, R2.3 ✅, R2.4 ✅ (TODO), R2.5 ✅ | done | `8f71d7f` |
| **R3** — persistent_hash argument encoding fix | R3.1 ✅ | done | — |
| **R4** — Extended decoders + collection-ADT view skip | R4.1 ✅ | done | `88af088` |
| **E3** — Typed Ledger materialised view | E3.1 | pending | — |
| **E4** — ADT method emission | E4.1 ✅ infrastructure, E4.2+3 ✅ walker, E4.4 ✅ closure — zerocash_mint emits | mostly done | `cd3da3e` |
| **E5** — Cross-circuit call (exported + general non-exported) | E5.1, E5.2 | pending | — |
| **E6** — `if-statement` body shape | E6.1 | pending | — |
| **F4** — `uints-fixture.compact` | F4.1 ✅ byte-parity | done | `56c049f` |
| **F5** — `vector-fixture.compact` | F5.1 ⏸ blocked (Vector emitter gaps) | partial | `56c049f` |
| **F6** — `aliases-fixture.compact` | F6.1 ✅ byte-parity (transparent only — nominal emits alias name but no decl) | done | `56c049f` |
| **F7** — `witnesses-fixture.compact` | F7.1 ✅ byte-parity | done | `56c049f` |
| **F8** — `if-stmt-fixture.compact` | F8.1 | pending — needs E6 first | — |
| **F3** — `map-fixture.compact` + byte-parity | F3.1 ✅ | done | `e1a53d6` |
| **F1** — zerocash.compact byte-parity | F1.1 ✅ (init), F1.2 (circuits) pending | partial | `3c64488` |
| **F2** — election.compact byte-parity | F2.1 ✅ (init), F2.2 (circuits) pending | partial | `f80e22e` |

**Resume here:** Phase F (fixtures) + Phase E4 (ADT method emission in circuit bodies) + Phase F1/F2 (zerocash + election byte-parity).

**Milestone reached (commit `0d4f393`):** all four example contracts (counter, tiny, zerocash, election) now **compile cleanly** as Rust crates via the M3.5 emitter + runtime work. Path here, in order: E1 verified ✅ → R1 (ADT runtime + builders) ✅ → E2 (struct/enum promotion) ✅ → close-zerocash (Opaque/[u8;N]/aliases via codegen specials) ✅ → OpaqueString + Maybe<T> Value conv (election) ✅.

Counter + tiny snapshots remain byte-identical throughout. 5 e2e parity tests still pass.

What's left:
- **Byte-parity tests for zerocash + election** (F1, F2): TS capture driver + Rust e2e test. Some emission may need refinement to match TS byte-for-byte; the Vec<u8>/OpaqueString FieldRepr semantics flagged by the close-zerocash subagent need verification.
- **Map fixture** (F3): no current example contract uses Map; needs a small purpose-built fixture + byte-parity test.
- **ADT method emission in circuit bodies** (E4): zerocash + election circuits invoke Set.insert / MerkleTree.check_root / Map.lookup etc. as ledger writes. The current emitter emits `unimplemented!()` for circuit bodies that contain these. E4 lights up real Op programs for them.
- **Small targeted fixtures** (F4-F8): uints, vector, aliases, witnesses, if-statement.
- **R2 (native audit)** + **R3 (persistent_hash encoding fix)** + **R4 (extended decoders)** remain.

**Goal:** every cell in the M3.5 design's test matrix flips to ✅ (or has a documented carve-out).

**Companion spec:** `docs/superpowers/specs/2026-05-29-rust-codegen-m35-design.md`.

**State at start:**
- HEAD: `d29c668` on branch `codegen-rust`
- 5 e2e parity tests green (counter + 4 tiny)
- counter and tiny snapshots stable
- M3 emitter + runtime infrastructure in place (see M3 plan for inventory)

**Conventions** (same as M3):
- Every commit `git commit -S -s` with HEREDOC body, NO manual Signed-off-by, end with Co-Authored-By line.
- Verify `G` via `git log --format="%h %G? %s" -1`; amend with `git commit --amend -S --no-edit` if needed.
- Push to `origin/codegen-rust` after each task.

---

## Phase E1 — Implicit constructor support ✅

### Task E1.1: Verify + fix `emit-initial-state` for contracts without source-level constructor ✅

Verified by inspection (2026-05-29). Both zerocash.compact (no source-level constructor) and election.compact (no source-level constructor) emit clean `pub fn initial_state(...) -> Result<ConstructorResult<...>>` shells through the existing J1+J2 path. The frontend synthesises an implicit `(constructor src () (tuple))` form; the body-walker returns immediately on the `(tuple)` no-op terminator, producing zero body lines — same shape as counter's explicit `constructor() {}`. No code change required.

The actual zerocash compile failures (12 errors at last count) are downstream: ADT-typed ledger fields seeded as `new_cell(Default::default())` where the inner type can't be inferred. Addressed by R1 + K1.1.

---

## Phase E2 — Non-exported struct promotion

### Task E2.1: Promote ledger-referenced user structs to export-typedef

**Files:** `compiler/analysis-passes.ss` (or wherever export-typedef synthesis lives — see M3 plan's architectural note about `Info-struct` at line 985-999 of analysis-passes.ss)

When a user struct is referenced by a ledger field's type but not in the `export {...}` list, it currently doesn't survive into Ltypescript. M3.5 adds a pre-pass that finds such structs and synthesises `export-typedef` entries for them so H5-H7 picks them up.

- [ ] Walk Lpreexpand (or whichever IR has the ledger declarations + non-exported struct defs) collecting tstruct references in ledger-field types
- [ ] For each unique tstruct, if not already exported, synthesise an `(export-typedef ,src ,struct-name () (tstruct ,src ,struct-name ...))` entry
- [ ] Verify zerocash emission gains pub struct decls for `Nonce`, `opening`, `nullifier`, `zk_secret_key`, `zk_public_key`, `commitment`, `coin_info`, `public_key`
- [ ] Counter + tiny snapshots unchanged
- [ ] Commit + push

---

## Phase R1 — ADT runtime re-exports

### Task R1.1: Re-export Set, Map, MerkleTree, HistoricMerkleTree

**Files:** `runtime-rs/src/lib.rs`, possibly new wrapper module if upstream API doesn't fit codegen needs

- [ ] Locate upstream types (`midnight_storage::storage::HashMap`, `midnight_storage::storage::Set` if it exists, `midnight_onchain_state::merkle_tree::*` or wherever)
- [ ] Re-export under stable names: `compact_runtime::Set<T>`, `compact_runtime::Map<K, V>`, `compact_runtime::MerkleTree<const H: usize, T>`, `compact_runtime::HistoricMerkleTree<const H: usize, T>`
- [ ] If the upstream API exposes methods with names that match the Compact-level method names (`insert`, `remove`, `lookup`, `check_root`, `find_element`, etc.), great; if not, add a thin wrapper struct in `runtime-rs/src/std_lib.rs`
- [ ] Add a unit test that constructs each and exercises one method
- [ ] Counter + tiny snapshots untouched
- [ ] Commit + push

### Task R1.2: type-rust maps Compact ADT references → runtime types

**Files:** `compiler/rust-passes.ss`

The Ltypescript `tadt` form wraps Compact ADT references. `type-rust` currently handles `Counter` and `Cell` implicitly via the binding's read-op-type. Map / Set / MerkleTree / HMT references in non-ledger positions (e.g. circuit args, return types, struct fields) need direct mapping.

- [ ] Extend `type-rust` so `(tadt src adt-name (...) ...)` dispatches on `adt-name`:
  - Set → `Set<T>`
  - Map → `Map<K, V>`
  - MerkleTree → `MerkleTree<H, T>`
  - HistoricMerkleTree → `HistoricMerkleTree<H, T>`
  - Counter → `u64` (or `Counter` wrapper if R1.1 added one)
  - Cell<T> → `T` (already correct via read-op-type)
- [ ] Counter + tiny snapshots unchanged
- [ ] zerocash + election emissions now reference the ADT types
- [ ] Commit + push

---

## Phase R2 — Native function mapping audit

### Task R2.1: keccak256 mapping

**Files:** `compiler/midnight-natives.ss`, `runtime-rs/src/lib.rs`

- [ ] Find keccak256 in upstream (`midnight_base_crypto::hash::keccak256` likely)
- [ ] Re-export from `compact-runtime`
- [ ] Add `(rust "compact_runtime::keccak256")` to keccak256's `declare-native-entry`
- [ ] Commit + push

### Task R2.2: Jubjub bundle (6 functions)

**Files:** same as above

- [ ] Locate each upstream function: `jubjubPointX`/`Y`, `ecAdd`, `ecMul`, `ecMulGenerator`, `hashToCurve`, `constructJubjubPoint`
- [ ] Re-export from `compact-runtime`
- [ ] Annotate each native entry with `(rust "...")`
- [ ] Commit + push

### Task R2.3: degradeToTransient + upgradeFromTransient

- [ ] Same pattern

### Task R2.4: Zswap witness natives

**Files:** same. **Note:** these are witness-class natives, not circuits — different code path in the emitter.

- [ ] Locate upstream `ownPublicKey`, `createZswapInput`, `createZswapOutput`
- [ ] Re-export + annotate

### Task R2.5: Audit pass

- [ ] After R2.1–R2.4, every `declare-native-entry` should have a `(rust ...)` annotation OR a documented `// TODO M3.5+` comment
- [ ] Commit + push

---

## Phase R3 — persistent_hash argument encoding fix

### Task R3.1: Replace `.concat().0` with FieldRepr-aware Value encoding

**Files:** `compiler/rust-passes.ss` (specifically the I3b/1 `compact_runtime::persistent_hash` specialisation in `call-rust`)

Background: I3b/1 (commit `5c76f9e`) emits `persistent_hash(&[a, b].concat()).0` which produces a 64-byte raw concat for two `[u8; 32]` inputs. The TS path uses `rtType.toValue(value)` which adds alignment framing. They coincide for uniform `Bytes<32>` inputs (which is why tiny passes) but diverge for mixed-type inputs.

- [ ] Replace the specialisation with an alignment-aware emit: serialize the args through `FieldRepr` / `Aligned` so the byte sequence matches TS's `toValue` output
- [ ] Specifically: emit `let mut buf = Vec::new(); (a, b, ...).field_repr_bytes(&mut buf); persistent_hash(&buf)` or similar
- [ ] Verify tiny byte-parity still passes (which it should — its inputs are uniform)
- [ ] Add a small unit test in compact-runtime that hashes a mixed `(Fr, Bytes<32>)` input and confirms the output matches a known TS hash output
- [ ] Commit + push

---

## Phase R4 — Extended decoders

### Task R4.1: decoder-for-type extends to tstruct, Maybe<T>, others

**Files:** `compiler/rust-passes.ss`, possibly `runtime-rs/src/std_lib.rs`

- [ ] When a ledger field's read-op returns a user struct, the Ledger view reader needs to decode it via `<StructName as FromFieldRepr>::from_field_repr(...)`. Extend `decoder-for-type` so the tstruct case emits the right call
- [ ] Same for Maybe<T>: emit `<Maybe<T> as FromFieldRepr>::from_field_repr(...)`
- [ ] Counter + tiny snapshots unchanged (neither has a struct-typed exported ledger field)
- [ ] Commit + push

---

## Phase E3 — Typed Ledger materialised view

### Task E3.1: Emit `LedgerSnapshot` struct alongside the existing `Ledger<'a>` wrapper

**Files:** `compiler/rust-passes.ss`

The current `Ledger<'a, D>` is a thin wrapper around `&ChargedState<D>` with per-field gather methods (K2). Add a sibling struct `LedgerSnapshot` (or similar name) with one field per ledger field, fully materialised:

```rust
pub struct LedgerSnapshot {
    pub nullifiers: Set<Nullifier>,
    pub commitments: HistoricMerkleTree<32, Commitment>,
    pub ciphertexts: Opaque<...>,
    ...
}

impl<'a, D: DB> Ledger<'a, D> {
    pub fn snapshot(&self) -> Result<LedgerSnapshot, CompactError> { ... }
}
```

- [ ] Walk all ledger fields (not just exported), emit one field per
- [ ] Emit a snapshot() method on the wrapper that decodes each field
- [ ] Counter + tiny gain LedgerSnapshot too (with their respective fields) — snapshots update; the e2e tests still pass because they construct ContractState manually
- [ ] Commit + push

---

## Phase E4 — ADT method emission

### Task E4.1: Map.lookup/insert/remove

**Files:** `compiler/rust-passes.ss`

When a circuit body contains `(public-ledger ,field-id ... <op-class> ,arg*)` where the ADT is Map, emit the right runtime call. The op-class names are `lookup`, `insert`, `remove`, etc. — they match the ADT op names in midnight-ledger.ss.

- [ ] Extend `emit-impure-circuit` body walker to handle Map ops
- [ ] Each Map op compiles to either a method call on `self.ledger().<field>().lookup(key)` OR an inline Op program (whichever matches the ADT runtime in R1.1)
- [ ] Add a Map fixture (F3) that exercises this
- [ ] Counter + tiny unchanged
- [ ] Commit + push

### Task E4.2: Set.insert/remove/member

- [ ] Same shape as E4.1 but for Set ops
- [ ] Exercised via zerocash (nullifiers Set)
- [ ] Commit + push

### Task E4.3: MerkleTree.insert / check_root

- [ ] Same shape, MerkleTree ops
- [ ] Exercised via election
- [ ] Commit + push

### Task E4.4: HistoricMerkleTree.insert / check_root / find_element

- [ ] Same shape, HMT ops
- [ ] Exercised via zerocash
- [ ] Commit + push

---

## Phase E5 — Cross-circuit call generalisation

### Task E5.1: Generalised non-exported circuit inlining

**Files:** `compiler/rust-passes.ss`

I3b/3 inlined `in_state` via a name-based special-case. Generalise: when a circuit body contains `(call <function-name> <arg>*)` and the target is a non-exported user circuit (registered in `program-circuits` but filtered out of the public surface), inline the target's body at the call site.

- [ ] Track non-exported user circuits in a separate map (not just filtered out)
- [ ] At call sites, recursively inline the target's body, substituting formal args
- [ ] Handle multi-statement target bodies (the in_state special-case only handled single-statement)
- [ ] Counter + tiny snapshots unchanged
- [ ] Commit + push

### Task E5.2: Exported-circuit call sites

**Files:** `compiler/rust-passes.ss`

When the target is exported, emit `self.<snake-name>(<args>)` instead of inlining.

- [ ] Emit method call on `self`
- [ ] Thread context through if the target is impure
- [ ] Exercised via zerocash (mint calls helpers, etc.)
- [ ] Commit + push

---

## Phase E6 — if-statement shape

### Task E6.1: Statement-position if with unit return

**Files:** `compiler/rust-passes.ss`

I3b/4 handled `(if cond then else)` as the WHOLE body of a non-unit circuit. M3.5 needs the case where `if` appears INSIDE a body with other statements before/after, and the branches are statement sequences (not expressions).

- [ ] Extend the body walker to recognise `(if cond then-stmt else-stmt)` mid-body
- [ ] Emit Rust `if cond { <then-body> } else { <else-body> }`
- [ ] Both branches are statement sequences that the walker handles recursively
- [ ] Add `if-stmt-fixture.compact` to exercise
- [ ] Commit + push

---

## Phase F4 — `uints-fixture.compact`

### Task F4.1: Fixture + snapshot test

- [ ] Author a small contract with ledger fields of Uint<8>, Uint<32>, Uint<128>
- [ ] Add snapshot test in `compiler/test.ss`
- [ ] Add a cargo-build test (workspace member or inline)
- [ ] Optional byte-parity if simple
- [ ] Commit + push

(Tasks F5, F6, F7, F8 follow the same template — fixture + snapshot + cargo build + optional byte-parity.)

---

## Phase F3 — Map fixture + byte-parity

### Task F3.1: Author `map-fixture.compact`

- [ ] ~20 lines: ledger Map<Field, Field>, one circuit that inserts, one that looks up
- [ ] Snapshot test
- [ ] Commit + push

### Task F3.2: Byte-parity test

- [ ] Mirror M2/M2.1 pattern: TS capture driver, Rust test, hex-compare
- [ ] Commit + push

---

## Phase F1 — zerocash byte-parity

### Task F1.1: Get the generated zerocash crate to compile

- [ ] Run compactc, inspect 12 current errors, fix each (most should be unblocked by E1–E5 + R1–R4)
- [ ] Add as workspace member `tests-e2e-rust/contracts/zerocash`
- [ ] Verify `cargo build -p compact-contract-zerocash` succeeds
- [ ] Commit + push

### Task F1.2: zerocash byte-parity test

- [ ] TS capture driver (similar to capture-tiny.mjs)
- [ ] Rust test driving zerocash through a short sequence
- [ ] Assert byte-parity
- [ ] Commit + push

---

## Phase F2 — election byte-parity

### Task F2.1: Get election to compile

- [ ] Similar to F1.1 — drive through whatever errors remain

### Task F2.2: election byte-parity test

- [ ] Similar to F1.2

---

## Plan completion

When every cell in the test matrix (design §test-matrix) is ✅ or has a documented carve-out, M3.5 closes. Update the Progress table at the top + the M3.5 design's matrix.
