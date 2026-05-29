# Compact → Rust codegen M3 — Generalised emission

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Progress

| Phase | Tasks | Status | Last commit |
|---|---|---|---|
| F — type-rust helper (real impl) | F1 ✅, F2–F4 pending | partial | `6747791` |
| G — Witnesses trait emission | G1 ✅, G2 ✅, G3 ✅ | done | `ef7bf13` |
| H — Enum + struct emission | H1–H4 | pending | — |
| I — Per-circuit emission | I1–I4 | pending | — |
| J — Constructor with parameters | J1–J2 | pending | — |
| K — Multi-ledger-field | K1–K2 | pending | — |
| L — Compact stdlib mapping | L1–L4 | pending | — |
| M — Tests for tiny.compact | M1–M3 | pending | — |

**Resume here:** H1 (enum emission). Phases F1 + G are complete; F2–F4 (talias/tname, tenum, tstruct references) can be done as part of H or interleaved.

**State at end of this session's M3 work:**

- `compactc --rust tiny.compact /tmp/out/` no longer crashes (previously failed in `camel->snake` because witness function-name is an id record, not a plain symbol — fix in commit `2ac8f8f`).
- The witness trait emits cleanly: `pub trait Witnesses<PS> { fn private_secret_key<'a>(&self, ctx: &WitnessContext<Ledger<'a>, PS>) -> (PS, [u8; 32]); }`. Note `$` in `private$secret_key` is sanitised to `_`, and the `[u8; 32]` return type comes from F1's real `type-rust` walking `tbytes` properly.
- counter.compact regression: no diff against the committed snapshot. M1+M2 work fully preserved.
- The full tiny.compact emission is NOT yet a complete crate — circuit emission is still hardcoded to counter's `increment()` (I1+ replaces this), and enum/struct emission (H phase) is pending. So while the witness trait now emits, the broader contract is not yet compilable.

**Key implementation notes for the next session:**

- The Ltypescript Type IR was thoroughly mapped during F1; see `compiler/rust-passes.ss` `type-rust` for the canonical variant→Rust mapping. Add new variants there in F2/F3/F4 (talias, tenum, tstruct, etc.).
- The witness IR's `function-name` field is an id record: always use `(id-sym function-name)` to extract the symbol. Same pattern applies to circuit declarations.
- `camel->snake` now also handles `$` characters. If other special characters appear (e.g. backtick-quoted operators in identifiers), extend there.
- The `(when (null? witness-decl*) ...)` guard around the `impl<PS> Witnesses<PS> for NoWitnesses {}` blanket is already in place — G3 effectively done.
- F1 surfaced a parallel-work commit `9a5c0fc` ("test(m3a): minimal witness repro + diagnostic note") and a `compact-runtime-macros` crate (`51aac77`, `58b11ab`). Those are user-driven proc-macro experiments orthogonal to the compactc-side codegen path; leave them alone unless explicitly merging the two approaches.

**Goal:** Make `compactc --rust examples/tiny.compact` produce a working Rust crate that compiles, runs, and byte-parity-matches the existing TS path's `ContractState`. tiny.compact exercises witnesses, enums, multiple circuits (pure + impure), hashing, `Maybe<T>` returns, `disclose()`, `default<T>`, and a parameterized constructor — the full generalisation surface.

**Architecture:** Continue the M1+M2 pattern. `rust-passes.ss` walks `Ltypescript`, emitting per-construct via small helper functions. Most M3 work is replacing hardcoded counter.compact emissions with real IR walks. The runtime crate already supports everything needed; new helpers only get added if a new Compact stdlib type lacks a Rust mapping.

**Tech Stack:** Chez Scheme + Nanopass (compiler emitter); Rust 1.88+ (runtime crate + generated code); published `midnight-*` crates (no new deps expected).

**Companion docs:**
- Design spec: `docs/superpowers/specs/2026-05-25-rust-codegen-design.md` — §5.4 mapping table, §5.5 type descriptors, §5.6 witness emission, §5.8.1 stdlib mapping, Appendix B worked example
- M1+M2 plan: `docs/superpowers/plans/2026-05-25-rust-codegen.md` — completed
- Upstream-PRs proposal: `docs/superpowers/specs/2026-05-25-rust-codegen-upstream-prs.md`

**State at start:**
- HEAD: `2fe3015` on branch `codegen-rust`
- `compactc --rust counter.compact` works and produces byte-parity output vs TS
- `rust-passes.ss` has stub `type-rust` returning `"/* TODO: type-rust */"`
- `rust-passes.ss` has hardcoded `emit-increment-circuit` (matches counter.compact only)
- `rust-passes.ss` has hardcoded `emit-initial-state` (matches counter.compact only)
- `rust-passes.ss` has hardcoded `Ledger::round()` ledger view (matches counter.compact only)
- `compact-runtime` has the full M1 + Tier 1/3 helper set

**TS target reference** (`/tmp/tiny-ts/contract/index.d.ts`):

```typescript
export type Maybe<T> = { is_some: boolean; value: T };
export type Witnesses<PS> = {
  private$secret_key(context: WitnessContext<Ledger, PS>): [PS, Uint8Array];
}
export type ImpureCircuits<PS> = {
  set(context: CircuitContext<PS>, v_0: bigint): CircuitResults<PS, []>;
  get(context: CircuitContext<PS>): CircuitResults<PS, Maybe<bigint>>;
  clear(context: CircuitContext<PS>): CircuitResults<PS, []>;
}
export type PureCircuits = {
  public_key(sk_0: Uint8Array): Uint8Array;
}
export type Ledger = { readonly value: bigint; }   // only `value` is exported; authority and state are not
export declare class Contract<PS, W> {
  initialState(context: ConstructorContext<PS>, v_0: bigint): ConstructorResult<PS>;
}
```

The Rust target mirror is straightforward per the design spec §5.4–§5.6. The biggest deltas vs counter.compact are:
- `Witnesses` is no longer empty
- 3 impure + 1 pure circuit (vs 1)
- 3 ledger fields (vs 1) — `authority: Bytes<32>`, `value: Field`, `state: STATE`
- A `STATE` enum (`unset`, `set`)
- Parameterized constructor
- `persistentHash` native
- `Maybe<Field>` return type

---

## Phase F — `type-rust` helper (real implementation)

The foundation. Every per-construct emission depends on it. Currently stubbed; replace with a real Ltypescript Type walker.

### Task F1: type-rust for primitives + tuple/vector

**Files:** `compiler/rust-passes.ss`

Walk the Ltypescript `Type` nonterminal and emit Rust type strings. Read `compiler/langs.ss` for the actual nonterminal definition. Key forms:

| Compact type | Rust |
|---|---|
| `Field` (tfield) | `Fr` |
| `Boolean` (tboolean) | `bool` |
| `Uint<N>` (tunsigned with bit width) | `u8`/`u16`/`u32`/`u64`/`u128` matched to bit width |
| `Bytes<N>` (tbytes) | `[u8; N]` |
| `Vector<N, T>` (tvector) | `[T; N]` if N is a constant, else `Vec<T>` |
| `[T1, T2, ...]` (ttuple) | `(T1, T2, ...)` |
| `Maybe<T>` | `Option<T>` |
| `Either<L, R>` | TBD (custom enum or `Result`) — see L1 |
| `OpaqueString` | `String` |
| `JubjubPoint` (tjubjub) | `JubjubPoint` |
| User type ref (tref / tname / similar) | the user type name verbatim |

- [ ] **Step 1: Find the actual Type nonterminal definition**

```bash
grep -nE "Type\s*\(.+\)\s*$" /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/compiler/langs.ss | head -20
```

Read the result. Note every variant of Type. Cross-reference against how typescript-passes.ss handles each.

- [ ] **Step 2: Replace the `type-rust` stub**

In `compiler/rust-passes.ss`, find the existing stub:
```scheme
(define (type-rust type)
  "/* TODO(M3): type-rust */")
```

Replace with a `nanopass-case` over the Type IR, returning a Rust type string per variant. Start with the primitives + ttuple + tvector listed above. Use placeholder `"/* TODO M3-F4 */"` for `tstruct`, `talias`, `tenum` until later tasks.

- [ ] **Step 3: Add a unit test in `compiler/test.ss`**

Test that compactc parses a `.compact` file whose Witnesses or circuit signatures use each type form, and the emitted `contract/lib.rs` contains the expected Rust types. Use small targeted test inputs.

- [ ] **Step 4: Smoke**

```bash
RUST_BIN=$(ls -t /nix/store/*-compact-all/bin/compactc | head -1)
rm -rf /tmp/counter-after-f1 && \
  $RUST_BIN --rust --skip-zk examples/counter.compact /tmp/counter-after-f1/ && \
  diff /tmp/counter-after-f1/contract/lib.rs compiler/snapshots/counter-rust-expected.rs.snap
```

Expected: no diff. counter.compact uses no witnesses and no user types, so type-rust shouldn't affect its emission.

- [ ] **Step 5: Commit**

Commit subject: `rust-passes: implement type-rust for primitives + tuple/vector`. Sign with `-S -s`.

### Task F2: type-rust for talias + tname (type aliases and user type references)

**Files:** `compiler/rust-passes.ss`

Compact has type aliases (`type Foo = ...`). The TS emitter chases through `talias` via `de-alias`. For Rust we should preserve user-named types (emit `Foo` instead of expanding). Read how typescript-passes.ss's `Type` pass handles `talias` and `tname` / `tref`.

- [ ] **Step 1: Add `talias` and user-name reference handling to `type-rust`**

```scheme
[(talias ,src ,nominal? ,type-name ,type)
 (if nominal?
     (format "~a" type-name)        ;; nominal alias: keep the name
     (type-rust type))]              ;; transparent alias: expand
[(tname ,src ,name)
 (format "~a" name)]
```

- [ ] **Step 2: Counter smoke (no diff expected — uses no aliases)**

- [ ] **Step 3: Commit**

### Task F3: type-rust for tenum (user enum reference)

**Files:** `compiler/rust-passes.ss`

For now, just emit the enum name. The enum *definition* lands in Phase H. This task only handles enum *references* in type positions.

- [ ] **Step 1: Add `tenum` case to `type-rust`**

- [ ] **Step 2: Commit**

### Task F4: type-rust for tstruct (user struct reference)

**Files:** `compiler/rust-passes.ss`

Same pattern as F3 — handle the reference; definition emission is Phase H.

- [ ] **Step 1: Add `tstruct` case to `type-rust`**

- [ ] **Step 2: Commit**

---

## Phase G — Witnesses trait emission (real)

D2 emits an empty `Witnesses<PS>` trait. M3 emits real method signatures.

### Task G1: Walk witness declarations, emit one method per witness

**Files:** `compiler/rust-passes.ss`

Already has `(witness?)` predicate from D2. Need:
- Camel-to-snake on witness names
- Args: `(arg-name, arg-type)` pairs from the Witness IR
- Return type via `type-rust`

For tiny.compact's `witness private$secret_key(): Bytes<32>`, the emitted Rust:
```rust
pub trait Witnesses<PS> {
    fn private_secret_key<'a>(&self, ctx: &WitnessContext<Ledger<'a>, PS>) -> (PS, [u8; 32]);
}
```

Note the HRTB-style `<'a>`, and the `private$secret_key` → `private_secret_key` (snake-case with `$` becoming `_`).

- [ ] **Step 1: Update `emit-witnesses` to walk args + return type**

For each witness in the list, emit:
```rust
    fn <snake-name><'a>(
        &self,
        ctx: &WitnessContext<Ledger<'a>, PS>,
        <each_arg_name>: <type-rust each_arg_type>,
        ...
    ) -> (PS, <type-rust ret_type>);
```

- [ ] **Step 2: Counter smoke (no witnesses; output unchanged)**

- [ ] **Step 3: tiny.compact smoke**

```bash
$RUST_BIN --rust --skip-zk examples/tiny.compact /tmp/tiny-after-g1/
grep -A 3 "pub trait Witnesses" /tmp/tiny-after-g1/contract/lib.rs
```

Expected: `private_secret_key` method appears with correct signature.

- [ ] **Step 4: Commit**

### Task G2: Identifier sanitisation for `$` and other special chars

**Files:** `compiler/rust-passes.ss`

Compact allows `$` in identifiers (`private$secret_key`). Rust doesn't. Extend the `camel->snake` helper (or add a separate `sanitize-ident`) to map `$` to `_`.

- [ ] **Step 1: Add sanitization**

- [ ] **Step 2: Commit**

### Task G3: Verify NoWitnesses blanket impl still works

**Files:** `compiler/rust-passes.ss`

When the contract has witnesses, the emitter must NOT emit the `impl<PS> Witnesses<PS> for NoWitnesses {}` blanket — that would conflict with the user-implementing struct's impl. Emit the blanket only when the witness list is empty.

- [ ] **Step 1: Wrap blanket emission in `(when (null? witness-decl*) ...)`**

- [ ] **Step 2: Both counter and tiny smokes pass**

- [ ] **Step 3: Commit**

---

## Phase H — Enum and struct emission

### Task H1: Emit user enums

**Files:** `compiler/rust-passes.ss`

For tiny.compact's `enum STATE { unset, set }`, the Rust:
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum STATE {
    unset = 0,
    set = 1,
}
```

Walk the Ltypescript IR for enum declarations. Each enum is a list of variant names (no associated data in Compact's enum). Emit with `#[repr(u8)]` and explicit discriminants.

- [ ] **Step 1: Add `enum?` predicate + `program-enums` collector**

- [ ] **Step 2: Add `emit-enum-decls` helper, call from Program after header**

- [ ] **Step 3: Smoke — tiny.compact emits the STATE enum**

- [ ] **Step 4: Commit**

### Task H2: Emit `impl Aligned` for user enums

**Files:** `compiler/rust-passes.ss`

```rust
impl Aligned for STATE {
    fn alignment() -> Alignment {
        Alignment::singleton(base_crypto::fab::AlignmentAtom::Bytes { length: 1 })
    }
}
```

- [ ] **Step 1: Add `emit-enum-aligned` helper**

- [ ] **Step 2: Commit**

### Task H3: Emit `impl FieldRepr` for user enums

**Files:** `compiler/rust-passes.ss`

```rust
impl FieldRepr for STATE {
    fn field_repr<W: midnight_transient_crypto::repr::MemWrite<Fr>>(&self, w: &mut W) {
        let discriminant: u8 = match self {
            Self::unset => 0,
            Self::set => 1,
        };
        discriminant.field_repr(w);
    }
    fn field_size(&self) -> usize { 1 }
}
```

- [ ] **Step 1: Emit per-variant discriminant in the match**

- [ ] **Step 2: Commit**

### Task H4: Emit `impl FromFieldRepr` for user enums

**Files:** `compiler/rust-passes.ss`

```rust
impl FromFieldRepr for STATE {
    const FIELD_SIZE: usize = 1;
    fn from_field_repr(r: &[Fr]) -> Option<Self> {
        let n: u8 = u8::from_field_repr(r)?;
        match n {
            0 => Some(Self::unset),
            1 => Some(Self::set),
            _ => None,
        }
    }
}
```

- [ ] **Step 1: Emit per-variant match arms**

- [ ] **Step 2: Commit**

### Task H5–H7: Same for structs

Repeat H1–H4 for user struct declarations. tiny.compact has no structs (only the enum), but proposal.compact has `struct Foo { bar: Bytes<32>; baz: Boolean }`. M3 implements both for symmetry; struct work can be deferred to a stretch task if context is tight.

---

## Phase I — Per-circuit emission

### Task I1: Walk circuit declarations, classify pure vs impure

**Files:** `compiler/rust-passes.ss`

Replace the hardcoded `emit-increment-circuit` with a real walk. Read how typescript-passes.ss distinguishes pure / impure / provable circuits (see `get-provable-circuit-names`, `print-contract-class`).

- [ ] **Step 1: Add `circuit?` predicate + classifier**

- [ ] **Step 2: For each impure circuit, emit a method on `impl Contract`**

- [ ] **Step 3: For each pure circuit, emit a free function in `mod pure_circuits`**

- [ ] **Step 4: Counter smoke (output unchanged structurally)**

- [ ] **Step 5: tiny smoke — produces `set`, `get`, `clear` methods + `public_key` pure fn**

- [ ] **Step 6: Commit**

### Task I2: Emit circuit args via type-rust

**Files:** `compiler/rust-passes.ss`

- [ ] **Step 1: For each circuit, walk arg list, emit `arg_name: arg_type`**

- [ ] **Step 2: Commit**

### Task I3: Walk circuit body and emit Op program

**Files:** `compiler/rust-passes.ss`

This is the hardest M3 task. The circuit body in Ltypescript is a sequence of statements; each statement maps to Op-program builder calls + Rust expressions. The TS emitter (`typescript-passes.ss`) has thousands of lines doing this; the Rust emitter needs the equivalent.

**Recommendation:** start by emitting **only** the Op sequences for circuits that map directly to ledger ADT operations (`round.increment(1)`, `state.read()`, etc.). For complex circuit bodies involving local variables, conditionals, and witness calls, emit a TODO placeholder and split into follow-up tasks I3a, I3b, etc.

- [ ] **Step 1: Walk circuit body forms, emit basic-shape Op programs**

- [ ] **Step 2: Smoke counter — must still produce identical output**

- [ ] **Step 3: Smoke tiny — at least one circuit produces a non-trivial Op program**

- [ ] **Step 4: Commit (may be DONE_WITH_CONCERNS if some circuit bodies are placeholders)**

### Task I4: Return type emission + assert! mapping

**Files:** `compiler/rust-passes.ss`

For circuits returning a value, emit `Result<CircuitResults<PS, T>, CompactError>` with `T` from `type-rust`. For `assert(cond, "msg")` in the body, emit `compact_assert!(cond, "msg");`.

- [ ] **Step 1: Emit return types via type-rust**

- [ ] **Step 2: Emit assert calls**

- [ ] **Step 3: Commit**

---

## Phase J — Constructor with parameters

### Task J1: Walk constructor declaration, extract params

**Files:** `compiler/rust-passes.ss`

For tiny.compact's `constructor(v: Field) { ... }`, the emitted `initial_state` takes `v: Fr`:

```rust
pub fn initial_state(
    &self,
    ctx: ConstructorContext<PS>,
    v: Fr,
) -> Result<ConstructorResult<PS>, CompactError> {
    ...
}
```

- [ ] **Step 1: Walk constructor IR, emit params**

- [ ] **Step 2: Commit**

### Task J2: Walk constructor body, emit initialization Op programs

**Files:** `compiler/rust-passes.ss`

Constructor body initializes ledger fields, may call witnesses, calls hashing primitives, etc. This overlaps with I3.

- [ ] **Step 1: Walk constructor body**

- [ ] **Step 2: Commit**

---

## Phase K — Multi-ledger-field

### Task K1: Generate per-field path indices in initial_state

**Files:** `compiler/rust-passes.ss`

tiny.compact has 3 ledger fields (`authority: Bytes<32>`, `value: Field`, `state: STATE`). The current `emit-initial-state` hardcodes one Counter field. Generalise to N fields, each with the right initial value (per the type) and the right path index (0, 1, 2, ...).

The TS emitter does this — see how it walks the ledger field list to generate the push+push+ins Op sequence per field.

- [ ] **Step 1: Walk ledger fields, emit per-field init Op sequence**

- [ ] **Step 2: Commit**

### Task K2: Generate per-field ledger view methods

**Files:** `compiler/rust-passes.ss`

Currently `Ledger::round()` is hardcoded. Generalise to one method per ledger field, each with the right path index and type-rust return type. **Note**: tiny.compact only exports `value` from the ledger (the TS Ledger type has just `value`); `authority` and `state` are NOT exported. Read how typescript-passes.ss respects this — likely by checking an `exported?` flag on each ledger field IR.

- [ ] **Step 1: Walk exported ledger fields, emit per-field reader**

- [ ] **Step 2: Commit**

---

## Phase L — Compact stdlib mapping

### Task L1: `Maybe<T>` mapping

**Files:** `runtime-rs/src/std_lib.rs` (or new `runtime-rs/src/stdlib.rs`)

Compact's `Maybe<T>` is `{ is_some: bool, value: T }`. The TS facade emits it as a literal object type. For Rust we have two choices:
- (a) Reuse `Option<T>` (idiomatic Rust)
- (b) Emit a dedicated `Maybe<T>` struct matching the TS shape exactly

Choice (b) makes byte-parity simpler (the struct layout matches the TS object layout). Recommended: emit `pub struct Maybe<T> { pub is_some: bool, pub value: T }` per-contract or in `compact-runtime::stdlib`.

- [ ] **Step 1: Add `Maybe<T>` to `compact-runtime`**

```rust
pub struct Maybe<T> {
    pub is_some: bool,
    pub value: T,
}
impl<T: Aligned> Aligned for Maybe<T> { ... }
impl<T: FieldRepr> FieldRepr for Maybe<T> { ... }
impl<T: FromFieldRepr + Default> FromFieldRepr for Maybe<T> { ... }
```

- [ ] **Step 2: Emit `compact_runtime::Maybe` in type-rust for Maybe<T>**

- [ ] **Step 3: Commit**

### Task L2: `persistent_hash` and `transient_hash` native bindings

**Files:** `compiler/midnight-natives.ss`, `compiler/rust-passes.ss`

The `(declare-native-entry ...)` rows already have a TypeScript name. Add `rust-name` fields per the M2 plan's note. Then `rust-passes.ss` reads the `rust-name` when emitting calls to native functions.

- [ ] **Step 1: Audit `midnight-natives.ss` and add `(rust ...)` field to each declare-native-entry**

- [ ] **Step 2: Update `rust-passes.ss` to emit native calls using rust-name**

- [ ] **Step 3: Commit**

### Task L3: `pad` helper in compact-runtime

**Files:** `runtime-rs/src/std_lib.rs`

```rust
pub fn pad<const N: usize>(input: &[u8]) -> [u8; N] {
    let mut out = [0u8; N];
    let len = input.len().min(N);
    out[..len].copy_from_slice(&input[..len]);
    out
}
```

- [ ] **Step 1: Add pad function + test**

- [ ] **Step 2: Commit**

### Task L4: `disclose` as identity

**Files:** `runtime-rs/src/std_lib.rs`

```rust
#[inline(always)]
pub fn disclose<T>(value: T) -> T { value }
```

The disclose check is enforced at the Compact frontend; in Rust it's just an identity function.

- [ ] **Step 1: Add and re-export**

- [ ] **Step 2: Commit**

---

## Phase M — Tests for tiny.compact

### Task M1: TS reference state for tiny.compact

**Files:** `tests-e2e-rust/fixtures/tiny-ts-state.json`

Mirror the E1 procedure: drive the TS path's tiny.compact through a known sequence (set(42), get, clear), serialize the resulting ContractState, write to fixture.

The driver needs a `private$secret_key` witness implementation (return a fixed test key).

- [ ] **Step 1: Set up TS driver for tiny.compact**
- [ ] **Step 2: Capture fixture**
- [ ] **Step 3: Commit**

### Task M2: Rust byte-parity test for tiny.compact

**Files:** `tests-e2e-rust/tests/tiny.rs`

Drive the Rust side through the same sequence, build the ContractState, serialize, compare bytes.

- [ ] **Step 1: Write the parity test**
- [ ] **Step 2: Iterate until bytes match (the critical correctness gate)**
- [ ] **Step 3: Commit**

### Task M3: Snapshot test for tiny.compact emitted output

**Files:** `compiler/snapshots/tiny-rust-expected.rs.snap`, `compiler/test.ss`

Capture the now-working emitted `contract/lib.rs` as a snapshot. Add a snapshot test entry.

- [ ] **Step 1: Capture snapshot**
- [ ] **Step 2: Add test entry**
- [ ] **Step 3: Commit**

---

## Plan completion

When all phases are green and tiny.compact byte-parity matches the TS reference, M3 is complete. Update the Progress section at the top of this plan and the design spec's §7 phasing table to mark M3 ✅. proposal.compact (Map, MerkleTree, struct) is M3.5 — a separate follow-up plan once tiny.compact is shipping.
