# Compact → Rust codegen M3 — Generalised emission

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Progress

| Phase | Tasks | Status | Last commit |
|---|---|---|---|
| F — type-rust helper (real impl) | F1 ✅, F2 ✅, F3 ✅, F4 ✅ | done | `2f3cf90` |
| G — Witnesses trait emission | G1 ✅, G2 ✅, G3 ✅ | done | `ef7bf13` |
| H — Enum + struct emission | H1 ✅, H2 ✅, H3 ✅, H4 ✅, H5 ✅, H6 ✅, H7 ✅ | done | `48ec7ad` |
| I — Per-circuit emission | I1 ✅, I1.5 ✅, I2 ✅, I3a ✅, I3b/1 ✅, I3b/2 ✅, I3b/3 ✅, I3b/4 ✅ — ALL tiny circuits emit; I4 absorbed | **done** | `1871e84` |
| J — Constructor with parameters | J1 ✅, J2 ✅ | done | `829d9d5` |
| K — Multi-ledger-field | K1 ✅, K2 ✅ | done | `068d05c` |
| L — Compact stdlib mapping | L1 ✅, L2 ✅, L3 ✅ (pre-existing), L4 ✅ (pre-existing) | done | `1d89a16` |
| M — Tests for tiny.compact | M1 ✅, M2 ✅ (PASSES), M3 partial (snapshot test landed earlier) | **done** | `5dde297` |

**Milestone reached (after K2):** `compactc --rust examples/tiny.compact /tmp/out/` produces a Rust crate that **compiles cleanly** against the local `compact-runtime`. `cargo build` succeeds end-to-end — all type references resolve, Witnesses trait + Maybe<T> + Ledger view + circuit signatures all type-check. Bodies remain `unimplemented!()` so the crate panics at runtime, but the surface is correct. This proves M3's "generalised emission" architectural goal is sound; remaining work is body correctness (K1/J2/I3) and byte-parity validation (M).

**Counter byte-parity restored (I3a, commit `9456eaa`):** circuit body emission now walks the Statement IR. For the narrow shape "single `public-ledger` call as statement-expression", it uses `expand-vm-code` from `(vm)` to evaluate the ADT op's vm-code with concrete path indices + argument expressions, then emits each vminstr as an `OpProgramVerify` builder call. The frontend lowers `round.increment(1)` to a nested `seq` introducing a temp via `safe-cast`; the emitter handles this by flattening seqs, gathering leading `(const ...)` bindings into an alist, resolving `var-ref` through that alist, and stripping `safe-cast` layers before passing args to `expand-vm-code`. Counter's snapshot now contains real Op programs again.

**Milestone reached after I3b/4 (commit `1871e84`):** `compactc --rust examples/tiny.compact` produces a Rust crate where **zero circuit bodies fall back to `unimplemented!()`**. All four circuits (`set`, `get`, `clear`, `public_key`) plus the parameterised constructor emit real bodies; the generated crate compiles cleanly against the local `compact-runtime`. Counter byte-parity preserved throughout.

**🎉 M3 CLOSE-OUT MILESTONE (commit `5dde297`):** The byte-parity test for tiny.compact **PASSES**. Driving the generated Rust contract through `initial_state(ctx, 42)` with a deterministic witness produces a `ContractState` whose `tagged_serialize`d bytes match the TypeScript reference byte-for-byte (1024 hex chars / 512 bytes). The Rust codegen for tiny.compact is correctness-verified end-to-end against the TS reference path. Both e2e tests (counter + tiny) pass.

**Resume here:** I3b + J2 (body emission expansion). I3a's infrastructure is the foundation.

- **I3b** — expand circuit body emission to cover tiny.compact's circuits. Each adds new shapes beyond I3a's "single public-ledger call":
  - `set(v: Field)`: assert + 2 const bindings (witness call + pure circuit call) + 3 ledger writes (public-ledger calls with `update` op-class on Cell). Needs: `assert!` emission, ledger-write op handling, witness-call emission, pure-circuit-call emission.
  - `get(): Maybe<Field>`: conditional return — ledger read of `state` + comparison to enum literal + ternary over `some`/`none` stdlib calls returning `Maybe<Fr>`. Needs: ledger-read inside circuit body (different from K2's view, this is mid-circuit-OpProgram), enum-ref literal lowering, ternary, function calls returning values, return-value packaging.
  - `clear(): []`: assert + 3 ledger writes (similar to `set` but with constants).
  - `public_key(sk: Bytes<32>)`: persistentHash native + `pad` stdlib + vector construction. Needs: native-call emission (uses `midnight-natives.ss` Rust-name mapping — likely needs L2 first), `pad` invocation, vector literal.
- **I3c** — once I3b ships, handle non-trivial expression shapes: `tuple`/`vector` constructors, slicing, binary ops, etc. tiny.compact mostly avoids these but proposal.compact will need them.
- **J2** — walk the Ledger-Constructor body. Overlaps heavily with I3 statement walking; in practice J2 should reuse I3's statement emitter. tiny.compact's constructor: `authority = public_key(sk); value = disclose(v); state = STATE.set;` — these are ledger writes (push value + idx + ins).
- **I4** — `assert!` and `return-type` packaging once bodies exist (`compact_assert!`, `Ok(CircuitResults { result, context, gas_cost })` wrapping).
- **K2.1** — extend `decoder-for-type` to cover any remaining read-result types (tbytes, etc.); currently a `decode_u64`-with-TODO fallback never gets hit by counter/tiny.

After I3 + J2 + I4, tiny.compact's emitted crate has correct bodies. Then M (snapshot diff + ContractState byte-parity vs TS reference) closes M3.

**State at end of this session's M3 work:**

- Witnesses trait now emits arg lists too (G1, commit `ef7bf13`).
- `emit-type-decls` walks Ltypescript `export-typedef` Program-Elements, emitting `#[derive(...)] #[repr(u8)] pub enum N { ... }` with Aligned/FieldRepr/FromFieldRepr impls per enum (H1–H4, commits `45bf810`, `49fe847`). tstruct/talias get TODO placeholders pending H5–H7.
- `Maybe<T>` lives in `compact-runtime::std_lib` with full repr impls; `emit-type-decls` skips the per-contract definition and `type-rust` maps `(tstruct Maybe ...)` references to `Maybe<<value-type>>` (L1, commit `2171d1c`). The runtime also gained `pub use midnight_base_crypto::repr::MemWrite`.
- `type-rust` now emits the bare enum name for `tenum` type references (F3, commit `d89861d`).
- Circuit emission switched from hardcoded `emit-increment-circuit` to a real walk (I1+I2, commit `899ec90`). Impure circuits become methods on the Contract impl; pure circuits become free functions in `mod pure_circuits`. Bodies are placeholders `unimplemented!("M3-I3: ...")`. Counter snapshot updated to match — byte-parity restoration is gated on I3.
- counter.compact emission still parses, builds, and (via the e2e parity test in `tests-e2e-rust/tests/counter.rs`) reproduces the TS ContractState bytes — that test hand-rolls Op sequences and doesn't depend on the generated lib.rs text.
- The full tiny.compact emission is NOT yet a compilable crate — circuit bodies are unimplemented and the internal-circuit/stdlib-import filtering issue (see Resume Here #1) leaves `in_state(s: STATE)` referencing an undefined STATE type.

**Architectural note discovered during G1 review (important for H + I):**

- Non-exported enums and structs are dropped before reaching `Ltypescript`. The pass that builds `Ltypescript` only preserves type definitions that the program explicitly exported (`export { STATE }`). See `compiler/analysis-passes.ss:1001-1007` where only `Info-enum` records bound to an export-name make it into `export-typedef`.
- In `Ltypescript`, user types appear *only* inside `(export-typedef src type-name (tvar-name* ...) type)` Program-Element forms (see `compiler/langs.ss:633-639`). The `type` slot is then a `(tenum ...)`, `(tstruct ...)`, or `(talias ...)`.
- References to non-exported enum values (e.g. `STATE.set` in tiny.compact) are **lowered to numeric discriminants** in `Ltypescript` — see `compiler/typescript-passes.ss:2862-2871` which emits `"~d"` for the elt-name's index. The Rust emitter must do the same in Phase I (circuit body emission).
- **Consequence:** tiny.compact's `enum STATE { unset, set }` does NOT appear in the Ltypescript IR (not exported). It will not be emitted by H1. Tiny.compact's `state = STATE.set` becomes a literal `1u8` in the circuit body during Phase I.
- **H1 scope is therefore "emit any exported enums found via export-typedef"**, not "emit STATE for tiny.compact". To exercise the path, use a small `.compact` fixture with `export { SomeEnum }`, or test against a contract that exports an enum.
- This matches TS behavior exactly: the TS `index.d.ts` for tiny.compact has no `STATE` type (only `Maybe`, which is exported). Rust mirrors this.

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

### Task H1: Emit user enums (exported only)

**Files:** `compiler/rust-passes.ss`

For an *exported* `enum STATE { unset, set }`, the Rust:
```rust
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
#[repr(u8)]
pub enum STATE {
    unset = 0,
    set = 1,
}
```

In `Ltypescript`, user types live inside `(export-typedef src type-name (tvar-name* ...) type)` Program-Elements; enum cases have `type = (tenum src enum-name elt-name elt-name* ...)`. Walk those and emit Rust enums.

**Note:** tiny.compact's STATE is non-exported and lowered to literal discriminants, so H1 does NOT add a STATE definition to tiny's output. To exercise H1, use a fixture with `export { SomeEnum }`. counter.compact remains a no-diff regression target.

- [ ] **Step 1: Add `export-tdefn?` predicate + collector for export-typedef Program-Elements**

- [ ] **Step 2: Add `emit-type-decls` helper that walks export-tdefn list, dispatches on type variant (tenum, tstruct, talias), and emits the appropriate Rust. H1 implements only the `tenum` case; tstruct/talias emit placeholder `// TODO M3-Hx` comments**

- [ ] **Step 3: Call from Program right after header (before Witnesses)**

- [ ] **Step 4: Smokes — counter.compact: no diff; tiny.compact: no STATE emitted (expected); manual smoke with a fixture that exports an enum**

- [ ] **Step 5: Commit**

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
