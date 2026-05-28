# Compact → Rust codegen M3a — Implementation Design

**Status:** approved · **Date:** 2026-05-29 · **Author:** Claude (brainstormed with @yshyn-iohk)

The M2 milestone of the codegen-rust branch is complete: `compactc --rust --skip-ts examples/counter.compact <out>` succeeds and the emitted crate builds. **M3a is the next focused milestone — what it takes to compile `examples/tiny.compact` end-to-end.** The full M3 surface (multi-struct, generics, Map/Set ledger ADTs, module imports) is deferred to M3b and M3c.

This design originated from a discovery during a *downstream* project (`midnight-did-rs` cycle-1 spike): `compactc` crashes on `did.compact` because it uses features outside M2's Counter-shaped envelope. Rather than wait for upstream, the project chose to drive M3 ourselves. M3a is the first phase.

## 1. Goal

`compactc --rust --skip-ts examples/tiny.compact <out>` succeeds AND the emitted Rust crate compiles against `compact-runtime`, with the existing `counter.compact` byte-parity test remaining green.

## 2. Non-goals

- `did.compact` itself (waits for M3b + M3c).
- Map<K,V> / Set<T> ledger ADT emission (M3b).
- Opaque<"string"> support (M3b).
- Multiple structs with nested alignment (M3b).
- Generic struct emission (M3c — `SchnorrHashInput<#n>`).
- Module imports / `prefix Foo_` (M3c).
- Async witnesses; WASM; sourcemaps; cross-language byte-parity for tiny.compact (best-effort only).
- Refactoring the existing M1/M2 work.

## 3. Scope — what tiny.compact exercises

From `examples/tiny.compact` (the M3a test target):

| Feature | Tiny uses | M2 has it? | M3a must add |
|---|---|---|---|
| Enum (variants) | `enum STATE { unset, set }` | No | Yes — emit Rust `enum` + `Aligned`/`FieldRepr`/`FromFieldRepr` impls per enum |
| Witness with concrete return type | `witness private$secret_key(): Bytes<32>` | Stub only | Yes — full witness emission via proc-macro pattern |
| Constructor calling witness | `constructor(v: Field) { const sk = private$secret_key(); … }` | No | Yes — constructor body IR walk incl. witness calls |
| Multiple circuits with args + control flow | 5 circuits: `in_state`, `set`, `get`, `clear`, `public_key` | Counter-only hardcoded | Yes — generic circuit-body IR walker emitting Op programs |
| `assert(cond, msg)` | 3 sites | No | Yes — emit `Op::Eq` + `Op::Branch` skip-on-false (or runtime panic equivalent) |
| `disclose(x)` no-op | 2 sites | No | Yes — emit as identity via `compact_runtime::disclose` |
| Standard library: `Maybe<T>`, `some<T>`, `none<T>`, `default<T>`, `pad`, `persistentHash<T>` | All used | No | Yes — codegen mapping table + compact-runtime extensions |
| Primitive types: `Bytes<N>`, `Field`, `Boolean` | All used | Field only (as `Fr`) | Add `Bytes<N>` alias + `Boolean → bool` mapping |
| Equality `==` and ternary `?:` | Used in `in_state`, `get`, `clear` | No | Yes — emit Rust `==` in non-circuit context; `Op::Eq` + `Branch` in circuit context |

## 4. Architecture — where things live

Clean separation between **universal** concerns (in `compact-runtime`) and **per-contract** concerns (in emitted code):

```
┌─────────────────────────────────────────────────────────────────────┐
│  compact-runtime  +  compact-runtime-macros (new sibling crate)     │
│  ──────────────────────────────────────────────────────────────     │
│  • Bytes<const N: usize> = [u8; N]   (alias + helper impls)         │
│  • Maybe<T> enum + some()/none()/is_some()                          │
│  • pad(w: usize, s: &str) -> Vec<u8>                                │
│  • disclose<T>(x: T) -> T  (identity no-op)                         │
│  • #[witness] proc-macro: registers a fn as a witness               │
│  • witness_registry::<C, F>() lookup mechanism                      │
└─────────────────────────────────────────────────────────────────────┘
                ▲                                ▲
                │                                │
                │ re-exports from prelude        │ macro use sites
                │                                │
┌───────────────┴────────────────┐  ┌────────────┴──────────────────┐
│  Emitted contract crate         │  │  User code (per project)      │
│  ───────────────────────────    │  │  ─────────────────────────    │
│  • enum STATE { ... }           │  │  #[witness]                   │
│    + Aligned/FieldRepr impls    │  │  fn secret_key() -> Bytes<32> │
│  • Contract<W, …> struct        │  │  { /* user logic */ }         │
│  • fn constructor<W>(…)         │  │                               │
│  • fn set/get/clear/… (Op       │  │                               │
│    programs)                    │  │                               │
│  • ledger() view                │  │                               │
└─────────────────────────────────┘  └───────────────────────────────┘
```

## 5. Decisions (locked at brainstorm)

| # | Decision | Rationale |
|---|---|---|
| D1 | **Witness pattern: `#[witness]` proc-macro registration**, not per-contract trait | User chose. Trade-offs accepted: more infrastructure (new `compact-runtime-macros` crate, proc-macro build dep), but more flexible — witnesses can live anywhere, no per-contract trait impl boilerplate. |
| D2 | **Enum `Aligned`/`FieldRepr`/`FromFieldRepr` impls are hand-emitted per enum**, not derived | Faster path. `base-crypto-derive` doesn't support enums today (verified). Forking it to add enum support is a worthwhile cycle-N investment but not M3a — emit by hand for now (≈20 LOC per enum × few enums). |
| D3 | **Universals (`Bytes<N>`, `Maybe<T>`, `pad`, `disclose`) live in `compact-runtime`**; per-contract code is fully in the emitted crate | Keeps the facade thin; emitted code is self-contained except for the curated runtime. |
| D4 | **No backwards-compat shims for M2 output**: counter.compact emission may need touch-ups | M2 emitter hardcodes Counter; M3a's generic circuit-body walker should subsume it. If counter.compact byte-parity test goes red, we either fix the new walker or update the snapshot. |
| D5 | **Test contract for M3a is `examples/tiny.compact` only**. did.compact + proposal.compact + election.compact are M3b/M3c gates | Bounded scope. tiny.compact exercises the M3a feature set without dragging in M3b/c surface. |
| D6 | **Cross-language byte-parity (vs TS output) is best-effort, not a gate** | TS reference for tiny.compact may not exist or may differ stylistically. M3a's hard gate is `cargo build`, not byte parity. Byte parity is the M3b/c gate where it's tractable. |

## 6. Deliverables

### 6.1 `compact-runtime` extensions (~150 LOC)

In `runtime-rs/src/lib.rs` (or split into sub-modules under `runtime-rs/src/std_lib/`):

```rust
// Universal type aliases for Compact primitives
pub type Bytes<const N: usize> = [u8; N];

// Maybe<T> — Compact's standard-library Option
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Maybe<T> {
    Some(T),
    None,
}

impl<T> Maybe<T> {
    pub fn is_some(&self) -> bool { matches!(self, Maybe::Some(_)) }
    pub fn unwrap(self) -> T { match self { Maybe::Some(x) => x, Maybe::None => panic!("Maybe::unwrap on None") } }
    // … other helpers as tiny.compact exercises them
}

pub fn some<T>(v: T) -> Maybe<T> { Maybe::Some(v) }
pub fn none<T>() -> Maybe<T> { Maybe::None }

// pad(width, s) — pads byte representation of s to `width` bytes
pub fn pad(width: usize, s: &str) -> Vec<u8> {
    let mut v = s.as_bytes().to_vec();
    v.resize(width, 0);
    v
}

// disclose: identity in Rust; tagged in IR
#[inline]
pub fn disclose<T>(x: T) -> T { x }
```

### 6.2 `compact-runtime-macros` (new sibling crate)

```toml
# runtime-rs-macros/Cargo.toml
[package]
name = "compact-runtime-macros"
edition = "2021"

[lib]
proc-macro = true

[dependencies]
syn   = "2"
quote = "1"
proc-macro2 = "1"
```

Provides a `#[witness]` proc-macro attribute:

```rust
#[proc_macro_attribute]
pub fn witness(_attr: TokenStream, item: TokenStream) -> TokenStream { … }
```

Applied as:
```rust
use compact_runtime::witness;

#[witness]
fn secret_key() -> Bytes<32> { /* user impl */ }
```

Macro responsibilities:
- Validate the function signature (no `self`, return type is a representable Rust type).
- Register the function in a per-process or per-contract dispatch table keyed by `(contract_id, witness_name)`.
- Emit a thin wrapper that the generated contract code can call by name (e.g. `compact_runtime::witnesses::secret_key()` or `WitnessRegistry::call("secret_key", ...)`).
- The exact registry mechanism is an M3a sub-design — see §11 Open decisions.

`compact-runtime` re-exports the macro: `pub use compact_runtime_macros::witness;`

### 6.3 `compiler/rust-passes.ss` extensions (~600-800 LOC of Scheme)

New emit-* functions (one per concern):

- **`emit-enums`** — walks all enum decls; emits `enum Foo { A, B, ... }` + hand-written `Aligned`/`FieldRepr`/`FromFieldRepr` impls per enum. Discriminant assigned by declaration order; alignment is `Alignment::field(1)` (single field for discriminant); FieldRepr serializes discriminant as a small int.
- **`emit-witness-trait`** — emits per-contract no-op marker: the macro-based pattern means **no compiler-emitted trait** is needed; instead the emitter records witness signatures in `pure_circuits` module as `extern fn`-style declarations that link to the macro-registered impls at runtime.
- **`emit-constructor`** — generic constructor body IR walk. Recurses on each statement/expression, emitting Rust assignments and witness calls (`compact_runtime::witnesses::secret_key()`). Handles `disclose(x)` as identity.
- **`emit-circuits-generic`** — generic circuit-body IR walker (replaces M2's hardcoded `emit-increment-circuit`). For each circuit:
  - Emit fn signature with arguments.
  - Walk body: `assert` → `assert!()` macro call (or Op::Eq+Branch in circuit context); `if`/`?:` → Rust if-else; method calls on ledger → corresponding Op sequence; control flow over enum variants → match expressions.
- **`emit-stdlib-mapping`** — table-driven mapping. The walker consults this when it sees a stdlib reference.

Mapping table extract:

| Compact | Emitted Rust |
|---|---|
| `disclose(x)` | `compact_runtime::disclose(x)` |
| `persistentHash<T>(v)` | Two-step: emit `let __h_buf = <T as compact_runtime::FieldRepr>::field_repr(&v);` then `compact_runtime::persistent_hash(&__h_buf)`. `FieldRepr::field_repr` already exists in midnight-ledger; the buffer type is `Vec<Fr>` or `&[u8]` per its signature — resolve concretely during implementation by reading the trait signature. |
| `default<T>()` | `<T as core::default::Default>::default()` |
| `pad(w, s)` | `compact_runtime::pad(w, s)` |
| `some<T>(v)` | `compact_runtime::some(v)` |
| `none<T>()` | `compact_runtime::none::<T>()` |
| `Field` | `compact_runtime::Fr` |
| `Bytes<N>` | `compact_runtime::Bytes::<N>` |
| `Boolean` | `bool` |
| `Uint<8/16/32/64>` | `u8/u16/u32/u64` |

### 6.4 Cargo.toml emission (small update)

`emit-cargo-toml` already exists; extend it to depend on the new `compact-runtime-macros` crate via re-export from `compact-runtime`. No new dep entry in emitted Cargo.toml expected (the proc-macro is re-exported transitively).

## 7. Testing

**Hard gates (must pass):**
1. `nix develop --command bash -c 'compactc --rust --skip-ts examples/tiny.compact /tmp/tiny-out && cd /tmp/tiny-out && cargo build'` succeeds.
2. `examples/tiny.compact`'s emitted crate has at least one unit test in the generated `#[cfg(test)]` block exercising the constructor + one circuit call (smoke test).
3. The M2 byte-parity test `tests-e2e-rust/tests/counter.rs` still passes — no regression.
4. `nix flake check` for the compact repo still passes.

**Soft gates (nice to have, not blocking):**
- Cross-language byte parity for tiny.compact vs `compactc` legacy TS output (only if TS output is generated easily for comparison).

## 8. Risks & mitigations

| # | Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|---|
| R1 | The `%getSchnorrReduction` crash signature suggests an upstream-of-rust-passes issue (IR construction) — fixing rust-passes alone may not be enough | High | Could block M3a even after we extend rust-passes | Reproduce the crash on a minimal witness contract first; if upstream, expand M3a scope or pause |
| R2 | Proc-macro registration mechanism (witness dispatch table) ends up complex | Medium | Slips M3a | Mitigation: start with the simplest possible registration (plain function table, no dynamic dispatch). Iterate. |
| R3 | Per-enum hand-emit produces buggy alignment vs what TS expects | Medium | Subtle runtime bugs not caught by `cargo build` | Add a small Rust unit test per emitted enum verifying round-trip `FieldRepr` ↔ `FromFieldRepr`. |
| R4 | M2's hardcoded counter emitter gets stale or conflicts with new generic walker | Medium | counter.compact byte-parity test goes red | Either delete M2's hardcoded path entirely (replaced by generic walker) or gate via a feature flag |
| R5 | M3a effort actually closer to 3 weeks than 2 | Low-medium | Schedule slip | Build incrementally; phase M3a internally if needed (enums → witnesses → circuits) |

## 9. Phasing within M3a (suggested implementation order)

Implementation order matters because earlier features unblock later ones:

1. **`compact-runtime` extensions** (Bytes, Maybe, pad, disclose) — small, independent.
2. **`compact-runtime-macros` crate skeleton** + `#[witness]` macro stub (registers + emits dummy code).
3. **Enum emission in `rust-passes.ss`** (`emit-enums`) — STATE first, independent of circuits.
4. **Stdlib mapping table + primitive type mapping** — needed before circuit body walks.
5. **Witness emission** (per the macro pattern from D1) — needed before constructor.
6. **Generic constructor walker** — short body in tiny.compact.
7. **Generic circuit body walker** — the biggest piece; covers `assert`, `if`/`?:`, equality, method calls.
8. **End-to-end test of tiny.compact** + M2 regression check.

## 10. Repo touch list

In `/Users/ysh/iohk/compact` (branch `codegen-rust`):

- Create: `runtime-rs-macros/Cargo.toml`
- Create: `runtime-rs-macros/src/lib.rs` (`#[witness]` proc-macro)
- Modify: `runtime-rs/Cargo.toml` (add macros dep)
- Modify: `runtime-rs/src/lib.rs` (re-export macro; add `Bytes`, `Maybe`, `pad`, `disclose`, `some`, `none`)
- Possibly create: `runtime-rs/src/std_lib/` submodule for the stdlib helpers
- Modify: `compiler/rust-passes.ss` (substantial — ~600-800 LOC new)
- Modify: `compiler/passes.ss` (potential — if entry point needs adjustment)
- Add: `tests-e2e-rust/tests/tiny.rs` (smoke test for emitted tiny crate)
- Possibly add: `tests-e2e-rust/fixtures/tiny-ts-state.json` (cross-language reference if byte parity attempted)
- Modify: `Cargo.toml` (workspace root) — add `runtime-rs-macros` member

## 11. Open decisions (resolve during implementation)

These are deliberately not fixed in this spec — they require code-level investigation:

1. **Witness registry mechanism shape.** Options:
   - Static `inventory` crate-style registration at link time.
   - Function-pointer table built at startup via a `lazy_static`/`OnceLock`.
   - Per-contract trait that the proc-macro generates on-the-fly.
   - Simplest first; iterate. Document choice in the M3a plan.
2. **Where the generated code calls into witnesses.** Options:
   - Direct function call: `secret_key()` (requires the user's function to be in scope).
   - Through a dispatch: `compact_runtime::call_witness::<_, Bytes<32>>("secret_key")`.
   - The macro determines the name; rust-passes emits the call form expected by whatever shape we pick.
3. **Whether to fork `base-crypto-derive` for enum derives**. Resolve based on M3b enum count: if M3b adds ≥3 more enums, fork; otherwise keep hand-emitting.
4. **Cross-language byte parity for tiny.compact**. Skip in M3a (per D6), revisit if it falls out for free.

## 12. Cultivated context

Captured in `~/.claude/skills/midnight-identity-rust/SKILL.md`. M3a-relevant entries added 2026-05-29:
- M2-vs-M3 milestone gap (decisive — codegen-rust hard-codes Counter ADT).
- midnight-ledger primitives inventory: Fr, Op, persistent_hash, Aligned/FieldRepr stack all exist.
- Witness boundary undefined in compact-runtime; M3a creates the pattern.
- Enum derives missing from `base-crypto-derive`; hand-emit for now.

## 13. Next steps

1. User reviews this committed spec.
2. On approval, invoke `superpowers:writing-plans` for the M3a implementation plan.
3. Execute via `superpowers:subagent-driven-development`.
4. When tiny.compact builds successfully, brainstorm M3b (Map/Set ledger ADTs + multi-struct + Opaque support).
