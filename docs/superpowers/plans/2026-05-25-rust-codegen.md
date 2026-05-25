# Compact → Rust codegen v1 — Implementation Plan (M1 + M2)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Progress

| Phase | Tasks | Status | Last commit |
|---|---|---|---|
| A — Pre-flight | A0 | ✅ Complete | (verified in session) |
| B — runtime-rs crate (M1) | B1–B10 ✅ | ✅ **M1 complete** | `0cc805c` |
| C — `--rust` flag plumbing | C1–C4 ✅ | ✅ **flag live; stub emits** | `69666d2` |
| D — counter.compact emission | D2–D8 | pending | — |
| E — Byte-parity validation | E1–E5 | pending | — |

**Resume here:** Task D2 (`Emit Witnesses trait` — first real codegen task).

**State today (after C4):**
- `runtime-rs` crate exports the full public API the codegen will reference. 16 tests pass, no warnings, clippy clean.
- `compactc --rust counter.compact /tmp/out/` produces a stub `contract/lib.rs` that compiles cleanly against `compact-runtime`. The stub contains the file header, `check_runtime_version!`, an empty `Witnesses<PS>` trait + `NoWitnesses` blanket impl, and a placeholder `Contract<PS, W>` struct. Real circuit / ledger / witness / initial_state emission lands in D2-D7.
- `compact-runtime` version is pinned to **`0.16.100`** (matched to the TS runtime version that `runtime-version-string` from `compiler/runtime-version.ss` resolves to). Keep them in lockstep on future bumps.

**Upstream-API corrections already applied to the plan (do not rediscover these):**

1. `CostModel::initial()` doesn't exist — use `INITIAL_COST_MODEL` (re-exported from `compact-runtime`).
2. `ChargedState::default()` doesn't exist — use `ChargedState::new(StateValue::Null)`.
3. `StateValue::new_cell(X)` doesn't exist — use `StateValue::from(X)` (via `impl From<AlignedValue> for StateValue<D>`).
4. `StateValue::new_array().array_push(X)` doesn't exist — build with `Array::<StateValue, _>::new().push(X)` and wrap in `StateValue::Array(...)`. `Array::push` takes `&self` and returns a new Array (immutable update).
5. `AlignedValue.value` is `Value(Vec<ValueAtom>)`; access bytes via `av.value.0.first()` returning `Option<&ValueAtom>`, then `atom.0` for the byte slice.
6. base-crypto strips trailing zero bytes from numeric atoms — `AlignedValue::from(42u64)` is a 1-byte atom `[42]`. `decode_u64` (already in `compact_runtime::std_lib`) accepts variable-length (≤ 8 byte) atoms and zero-pads, little-endian.
7. `ContractState::new(data, operations, maintenance_authority)` is the actual constructor — requires `HashMap<EntryPointBuf, ContractOperation, D>` and `ContractMaintenanceAuthority` (no Defaults).
8. `QueryResults.context.state` is `ChargedState<D>`, not `StateValue<D>`. To get the inner StateValue, call `.get_ref()` on the ChargedState.

**Critical for D-phase (IR shape gotcha surfaced in C3):**

The plan said `rust-passes` operates on `Ltypescript` IR. **It doesn't yet.** `prepare-for-typescript` (the Lnodisclose→Ltypescript pass) is private to `typescript-passes.ss` and not exported. The C3 stub consumes `Lnodisclose` directly. **Before D2 can emit real type information, one of the following must happen:**

(a) Export `prepare-for-typescript` from `typescript-passes.ss` and call it from `rust-passes.ss`, OR
(b) Have `passes.ss` thread the post-prepare `Ltypescript` IR into the rust-emit branch (reusing the prepare pass), OR
(c) Build a parallel `prepare-for-rust` pass on `Lnodisclose` if the type-descriptor registration logic differs.

(b) is the simplest. Pick it up at the start of D2. The plan body for D2 (and downstream) still mentions Ltypescript — that's correct; just make sure the IR threading actually delivers Ltypescript by the time `rust-passes` runs.

**Other implementer notes worth remembering:**
- `(runtime-version)` is a Scheme **library/module**, not a callable. Its export is the identifier `runtime-version-string` (a string value). Use it directly in `(format "..." runtime-version-string)`.
- `nix build --print-out-paths` gives you the freshly-built path. Don't `ls /nix/store/*-compact-all/bin/compactc | head -1` — alphabetical ordering may return a stale build.

---

**Goal:** Ship a v1 of `compactc --rust` that emits a working Rust crate for `examples/counter.compact`, plus a new `compact-runtime` crate the generated code depends on. Result is a counter contract you can build with `cargo` and exercise from native Rust, producing the same on-chain state transitions as the existing TypeScript output.

**Architecture:** Mirror the existing TS path. Add a `--rust` flag in `compactc.ss` that triggers a new branch in `passes.ss::generate-everything`. The new branch runs a parallel emitter `rust-passes.ss` (analogous to `typescript-passes.ss`) over the existing `Ltypescript` IR. Generated Rust depends on a thin new `runtime-rs/` crate that curates re-exports of published Midnight crates (`midnight-onchain-runtime`, `midnight-onchain-state`, etc.) and adds a handful of facade aggregates (`CircuitContext`, `WitnessContext`, etc.).

**Tech Stack:** Chez Scheme + Nanopass framework (compiler emitter); Rust 1.88+ stable (runtime crate + generated code); published `midnight-*` crates v3.x/v8.x from crates.io; nix-driven compactc build.

**Scope:** M1 (runtime-rs crate) + M2 (compactc emits working counter.compact). Out of scope: tiny.compact / proposal.compact full coverage (M3), async feature (M4), wasm feature (M5), polished docs/CI (M6). Those land as separate follow-up plans once M1+M2 are green.

**Companion docs:**
- Feasibility: `docs/superpowers/specs/2026-05-25-rust-codegen-feasibility.md`
- Full design spec: `docs/superpowers/specs/2026-05-25-rust-codegen-design.md` (Appendix B is the canonical reference for what the emitter should produce)
- Validation spike: `spike/` (the hand-translated reference; M2 codegen must produce equivalent output)

---

## File map

Files this plan touches:

| Path | Purpose | Created / Modified |
|---|---|---|
| `Cargo.toml` (workspace root) | Add `runtime-rs` to workspace members | Modified |
| `runtime-rs/Cargo.toml` | New crate manifest | Created |
| `runtime-rs/README.md` | Crate-level docs | Created |
| `runtime-rs/src/lib.rs` | Curated re-exports + module declarations | Created |
| `runtime-rs/src/context.rs` | `CircuitContext` / `ConstructorContext` aggregates | Created |
| `runtime-rs/src/witness.rs` | `WitnessContext` + `NoWitnesses` | Created |
| `runtime-rs/src/results.rs` | `CircuitResults` / `ConstructorResult` | Created |
| `runtime-rs/src/error.rs` | `CompactError` type | Created |
| `runtime-rs/src/version.rs` | `check_runtime_version!` macro | Created |
| `runtime-rs/src/std_lib.rs` | `Counter` newtype + helpers needed by counter.compact | Created |
| `runtime-rs/tests/integration.rs` | Behavioural tests | Created |
| `compiler/config-params.ss` | Add `emit-rust` parameter | Modified |
| `compiler/compactc.ss` | Add `--rust` flag handling | Modified |
| `compiler/passes.ss` | Add emit-rust branch in `generate-everything`; import rust-passes | Modified |
| `compiler/midnight-natives.ss` | Add `rust-name` to relevant declare-native-entry rows | Modified |
| `compiler/ledger.ss` | Consume the existing `rust-type` field for Counter ADT | Modified |
| `compiler/rust-passes.ss` | NEW — codegen pass (analogous to typescript-passes.ss) | Created |
| `compiler/test.ss` | Add test cases for `--rust` output | Modified |
| `tests-e2e-rust/Cargo.toml` | NEW byte-parity test harness workspace | Created |
| `tests-e2e-rust/src/lib.rs` | Helpers for driving generated contracts | Created |
| `tests-e2e-rust/tests/counter.rs` | Counter parity test | Created |
| `tests-e2e-rust/fixtures/counter-ts-state.json` | TS reference snapshot for counter | Created |
| `.gitignore` | Exclude `tests-e2e-rust/target/` | Modified |

The Rust source files in `runtime-rs/` are deliberately small and single-purpose (the audit projected ~300–500 LOC across the whole crate).

---

## Phase A — Pre-flight (5 minutes)

### Task A0: Confirm environment is ready

**Files:** none.

- [ ] **Step 1: Confirm worktree and branch**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/
git status --short
git branch --show-current
```

Expected: clean working tree (or only unrelated changes), branch `codegen-rust`.

- [ ] **Step 2: Confirm compactc binary is built**

```bash
ls /nix/store/*-compact-all/bin/compactc 2>/dev/null | head -1
```

Expected: a path like `/nix/store/.../bin/compactc`. If empty, run `nix build --no-link --print-out-paths` first (takes 30–60 min cold, seconds if cached).

- [ ] **Step 3: Confirm Rust toolchain**

```bash
cargo --version
rustc --version
```

Expected: cargo 1.88+ and rustc 1.88+ (stable).

- [ ] **Step 4: Confirm git-iohk config applied**

```bash
git config user.signingkey && git config commit.gpgsign
```

Expected: a key ID and `true`. If not, run `bash ~/iohk/git-iohk.sh`.

---

## Phase B — compact-runtime crate (M1)

This phase ships `runtime-rs/` as a self-contained crate. Each task ends with a green `cargo test` + a signed commit. The crate is small (~10 source files) but every type the codegen will reference must be present and stable before Phase C starts.

### Task B1: Create crate skeleton and add to workspace

**Files:**
- Create: `runtime-rs/Cargo.toml`
- Create: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/README.md`
- Modify: `Cargo.toml` (workspace root)

- [ ] **Step 1: Add `runtime-rs` to workspace members**

Edit the workspace root `Cargo.toml`. Change:

```toml
[workspace]
resolver = "3"
members = ["tools/*"]
```

to:

```toml
[workspace]
resolver = "3"
members = ["tools/*", "runtime-rs"]

[workspace.dependencies]
# Pinned to the same midnight-ledger line the TS runtime uses (ledger-8.0.2 per flake.nix).
midnight-base-crypto      = "1"
midnight-transient-crypto = "2"
midnight-serialize        = "1"
midnight-storage          = "2"
midnight-coin-structure   = "2"
midnight-onchain-state    = "3"
midnight-onchain-vm       = "3"
midnight-onchain-runtime  = "3"
midnight-zswap            = "8"
```

- [ ] **Step 2: Create `runtime-rs/Cargo.toml`**

```toml
[package]
name        = "compact-runtime"
version     = "0.1.0"
edition     = "2021"
license     = "Apache-2.0"
description = "Native Rust runtime facade for code generated by compactc --rust. Mirrors @midnight-ntwrk/compact-runtime."
repository  = "https://github.com/LFDT-Minokawa/compact"
readme      = "README.md"

[lib]
name = "compact_runtime"
path = "src/lib.rs"

[dependencies]
midnight-base-crypto      = { workspace = true }
midnight-transient-crypto = { workspace = true }
midnight-onchain-state    = { workspace = true }
midnight-onchain-vm       = { workspace = true }
midnight-onchain-runtime  = { workspace = true }
midnight-coin-structure   = { workspace = true }
midnight-zswap            = { workspace = true }
midnight-serialize        = { workspace = true }
midnight-storage          = { workspace = true }
```

- [ ] **Step 3: Create a stub `runtime-rs/src/lib.rs`**

```rust
// SPDX-License-Identifier: Apache-2.0
//
// compact-runtime — native Rust facade matching @midnight-ntwrk/compact-runtime.
//
// Generated code emitted by `compactc --rust` depends on this crate. It exposes:
//   - a curated set of re-exports from the published `midnight-*` Rust crates
//     (state, VM, crypto, storage, zswap)
//   - a handful of facade aggregates (CircuitContext, WitnessContext, etc.)
//     that don't exist upstream
//   - the `check_runtime_version!` macro
//   - a thin `std_lib` module covering Compact stdlib types this codegen depth
//     needs (Counter ledger ADT, etc.)
//
// See docs/superpowers/specs/2026-05-25-rust-codegen-design.md §4 for the full
// API contract.

#![forbid(unsafe_code)]
```

- [ ] **Step 4: Create `runtime-rs/README.md`**

```markdown
# compact-runtime

Native Rust runtime for contracts emitted by `compactc --rust`.

This crate is the Rust counterpart to the TypeScript package
`@midnight-ntwrk/compact-runtime`. Generated contract code (`contract/lib.rs`)
depends on it; users typically do not consume it directly.

See [Compact docs](../doc/) for the language reference and
[Rust codegen design spec](../docs/superpowers/specs/2026-05-25-rust-codegen-design.md)
for runtime API details.
```

- [ ] **Step 5: Verify cargo metadata resolves**

```bash
cargo metadata --format-version 1 --manifest-path runtime-rs/Cargo.toml > /dev/null
```

Expected: no output (success). Failure indicates a missing crate version or workspace mis-configuration.

- [ ] **Step 6: Verify `cargo check` passes**

```bash
cargo check -p compact-runtime
```

Expected: `Finished` with no errors or warnings.

- [ ] **Step 7: Commit**

```bash
git add Cargo.toml runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: scaffold compact-runtime crate

Adds an empty `compact-runtime` crate under runtime-rs/. Wired into the
workspace and pinned to the published midnight-ledger crate versions
matching the ledger-8.0.2 line used by the TS runtime path.

Subsequent commits populate the public API.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

Verify signature:

```bash
git log --format="%h %G? %s" -1
```

Expected: `... G runtime-rs: scaffold compact-runtime crate`.

---

### Task B2: Curated re-exports

**Files:**
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/reexports.rs`

This task ensures every type the codegen plans to reference is reachable through `compact_runtime::*`.

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/reexports.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Smoke test asserting that every type the codegen will reference is
// reachable through the `compact_runtime` prelude. Catches regressions
// in re-exports without exercising behaviour.

use compact_runtime::*;

#[test]
fn prelude_resolves_all_required_symbols() {
    // Encoding / alignment
    let _: fn() -> Alignment = || Alignment::singleton(base_crypto::fab::AlignmentAtom::Bytes { length: 0 });
    let _: fn(u64) -> AlignedValue = AlignedValue::from;
    let _ = std::any::type_name::<Value>();

    // Field arithmetic
    let _: fn(u64) -> Fr = Fr::from;
    let _ = std::any::type_name::<JubjubPoint>();

    // Hashes (re-exported as bare names)
    let _ = std::any::type_name::<fn() -> ()>(); // placeholder — hash signatures vary

    // VM ops + path keys
    let _: fn(AlignedValue) -> Key = Key::Value;

    // State
    let _ = std::any::type_name::<StateValue>();
    let _ = std::any::type_name::<ContractState>();
    let _ = std::any::type_name::<ChargedState>();

    // Runtime / context
    let _ = std::any::type_name::<QueryContext>();
    let _ = std::any::type_name::<QueryResults<ResultModeVerify>>();

    // Storage backend
    let _ = std::any::type_name::<DefaultDB>();
    let _ = std::any::type_name::<InMemoryDB>();
    let _: fn(Vec<Key>) -> Array<Key> = Array::from;

    // Cost / gas
    let _ = std::any::type_name::<CostModel>();
    let _ = std::any::type_name::<RunningCost>();

    // Coin / contract addressing
    let _ = std::any::type_name::<ContractAddress>();
    let _ = std::any::type_name::<CoinPublicKey>();

    // Zswap
    let _ = std::any::type_name::<ZswapLocalState>();
}
```

- [ ] **Step 2: Run the test and confirm it fails**

```bash
cargo test -p compact-runtime --test reexports 2>&1 | tail -20
```

Expected: many `error[E0432]: unresolved import` errors — the symbols aren't re-exported yet.

- [ ] **Step 3: Add the re-exports**

Replace the body of `runtime-rs/src/lib.rs` with:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// compact-runtime — native Rust facade. See lib doc comment in Task B1.

#![forbid(unsafe_code)]

// Re-export the foundational crates so generated code can write
// `base_crypto::*` etc. when needed for less-common types.
pub use midnight_base_crypto as base_crypto;
pub use midnight_transient_crypto as transient_crypto;
pub use midnight_onchain_state as onchain_state;
pub use midnight_onchain_vm as onchain_vm;
pub use midnight_onchain_runtime as onchain_runtime;
pub use midnight_coin_structure as coin_structure;
pub use midnight_storage as storage;
pub use midnight_zswap as zswap;

// ---------------------------------------------------------------------------
// Curated prelude — the symbols the codegen references directly.
// ---------------------------------------------------------------------------

// Encoding / alignment / value bus.
pub use midnight_base_crypto::fab::{Aligned, AlignedValue, Alignment, Value};

// Field arithmetic + proof-system primitives.
pub use midnight_transient_crypto::curve::{EmbeddedGroupAffine as JubjubPoint, Fr};
pub use midnight_transient_crypto::repr::{FieldRepr, FromFieldRepr};
pub use midnight_transient_crypto::merkle_tree::{MerklePath, MerklePathEntry, MerkleTreeDigest};

// Cost / gas.
pub use midnight_base_crypto::cost_model::RunningCost;
pub use midnight_onchain_vm::cost_model::CostModel;

// VM ops + path keys.
pub use midnight_onchain_vm::ops::{Key, Op};
pub use midnight_onchain_vm::result_mode::{ResultMode, ResultModeGather, ResultModeVerify};

// On-chain state.
pub use midnight_onchain_state::state::{ChargedState, ContractState, StateValue};

// Runtime / context.
pub use midnight_onchain_runtime::context::{QueryContext, QueryResults};
pub use midnight_onchain_runtime::error::TranscriptRejected;
pub use midnight_onchain_runtime::transcript::Transcript;

// Coin / contract addressing.
pub use midnight_coin_structure::coin::{
    Info as CoinInfo, PublicKey as CoinPublicKey, QualifiedInfo as QualifiedShieldedCoinInfo,
};
pub use midnight_coin_structure::contract::ContractAddress;
pub use midnight_coin_structure::transfer::Recipient;

// Storage backend.
pub use midnight_storage::db::{InMemoryDB, DB};
pub use midnight_storage::storage::Array;
pub use midnight_storage::DefaultDB;

// Hashes (re-exported as bare names — usability over fully-qualified paths).
pub use midnight_base_crypto::hash::{persistent_commit, persistent_hash};
pub use midnight_transient_crypto::hash::{hash_to_curve, transient_commit, transient_hash};

// Zswap local state.
pub use midnight_zswap::local::State as ZswapLocalState;
```

- [ ] **Step 4: Re-run the test**

```bash
cargo test -p compact-runtime --test reexports 2>&1 | tail -10
```

Expected: `test prelude_resolves_all_required_symbols ... ok` and `test result: ok. 1 passed`.

- [ ] **Step 5: Verify no warnings**

```bash
cargo check -p compact-runtime --all-targets 2>&1 | grep -E "warning|error" | head
```

Expected: no output.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: curated re-exports of midnight-* crates

Adds the prelude generated code will import via `use compact_runtime::*;`.
Covers state (StateValue, ContractState, ChargedState), VM ops (Op, Key,
Array), runtime (QueryContext, QueryResults, TranscriptRejected,
Transcript), encoding (Aligned, AlignedValue, Alignment, Value), field
arithmetic (Fr, FieldRepr, FromFieldRepr, JubjubPoint), hashes
(transient_hash, persistent_hash, transient_commit, persistent_commit,
hash_to_curve), cost (CostModel, RunningCost), zswap (ZswapLocalState),
coin / contract addressing.

A smoke test (`tests/reexports.rs`) asserts every symbol is reachable.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B3: Facade aggregates — `CircuitContext`, `ConstructorContext`

**Files:**
- Create: `runtime-rs/src/context.rs`
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/context.rs`

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/context.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0

use compact_runtime::*;

#[test]
fn circuit_context_can_be_constructed() {
    let qctx = QueryContext::new(ChargedState::new(StateValue::Null), ContractAddress::default());
    let ctx: CircuitContext<()> = CircuitContext {
        current_private_state: (),
        current_query_context: qctx,
        current_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _ = ctx.cost_model;
}

#[test]
fn constructor_context_can_be_constructed() {
    let cctx: ConstructorContext<()> = ConstructorContext {
        initial_private_state: (),
        empty_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _ = cctx.cost_model;
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test context 2>&1 | tail -10
```

Expected: errors that `CircuitContext` and `ConstructorContext` are unresolved.

- [ ] **Step 3: Implement context aggregates**

Create `runtime-rs/src/context.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Facade aggregates bundling existing upstream state types into the shapes
// the compiler emits references to. Mirror TS `CircuitContext<PS>`,
// `ConstructorContext<PS>` from @midnight-ntwrk/compact-runtime.

use crate::{ChargedState, CostModel, DefaultDB, QueryContext, RunningCost, ZswapLocalState, DB};

/// Context passed into each impure / provable circuit invocation.
#[derive(Clone)]
pub struct CircuitContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_private_state: PS,
    pub current_query_context: QueryContext<D>,
    pub current_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}

/// Context passed into the contract constructor.
#[derive(Clone)]
pub struct ConstructorContext<PS, D = DefaultDB>
where
    D: DB,
{
    pub initial_private_state: PS,
    pub empty_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}
```

- [ ] **Step 4: Re-export from lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
mod context;
pub use context::{CircuitContext, ConstructorContext};
```

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test context 2>&1 | tail -10
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add CircuitContext and ConstructorContext aggregates

Bundles QueryContext, ZswapLocalState, CostModel, and gas limit in the
shape generated code references. PS (private state) is generic.
Defaults D to DefaultDB.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B4: Facade aggregates — `CircuitResults`, `ConstructorResult`

**Files:**
- Create: `runtime-rs/src/results.rs`
- Modify: `runtime-rs/src/lib.rs`
- Modify: `runtime-rs/tests/context.rs` (extend with results coverage)

- [ ] **Step 1: Extend the failing test**

Append to `runtime-rs/tests/context.rs`:

```rust
#[test]
fn circuit_results_can_be_constructed() {
    let qctx = QueryContext::new(ChargedState::new(StateValue::Null), ContractAddress::default());
    let ctx: CircuitContext<()> = CircuitContext {
        current_private_state: (),
        current_query_context: qctx,
        current_zswap_local_state: ZswapLocalState::default(),
        cost_model: INITIAL_COST_MODEL,
        gas_limit: None,
    };
    let _: CircuitResults<(), ()> = CircuitResults {
        result: (),
        context: ctx,
        gas_cost: RunningCost::default(),
    };
}

#[test]
fn constructor_result_can_be_constructed() {
    let _: ConstructorResult<()> = ConstructorResult {
        current_contract_state: ChargedState::new(StateValue::Null),
        current_private_state: (),
        current_zswap_local_state: ZswapLocalState::default(),
    };
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test context 2>&1 | tail -10
```

Expected: errors for `CircuitResults` and `ConstructorResult`.

- [ ] **Step 3: Implement results aggregates**

Create `runtime-rs/src/results.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0

use crate::{ChargedState, CircuitContext, DefaultDB, RunningCost, ZswapLocalState, DB};

/// Return of a provable / impure circuit. Mirrors the TS
/// `CircuitResults<PS, R>` from @midnight-ntwrk/compact-runtime.
#[derive(Clone)]
pub struct CircuitResults<PS, R, D = DefaultDB>
where
    D: DB,
{
    pub result: R,
    pub context: CircuitContext<PS, D>,
    pub gas_cost: RunningCost,
}

/// Return of the contract constructor.
#[derive(Clone)]
pub struct ConstructorResult<PS, D = DefaultDB>
where
    D: DB,
{
    pub current_contract_state: ChargedState<D>,
    pub current_private_state: PS,
    pub current_zswap_local_state: ZswapLocalState<D>,
}
```

- [ ] **Step 4: Re-export from lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
mod results;
pub use results::{CircuitResults, ConstructorResult};
```

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test context 2>&1 | tail -10
```

Expected: all four tests pass.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add CircuitResults and ConstructorResult aggregates

Result types returned by impure/provable circuits and the contract
constructor respectively. Match the TS CircuitResults<PS,R> and
ConstructorResult<PS> shapes.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B5: `WitnessContext` and `NoWitnesses` marker

**Files:**
- Create: `runtime-rs/src/witness.rs`
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/witness.rs`

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/witness.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// counter.compact has no witnesses, so we exercise NoWitnesses + the
// shape of WitnessContext (concrete type construction). Lifetime/HRTB
// exercise lands in M3 when tiny.compact is implemented.

use compact_runtime::*;

#[test]
fn no_witnesses_is_default_constructible() {
    let _ = NoWitnesses::default();
    let _ = NoWitnesses;
}

#[test]
fn witness_context_struct_resolves() {
    // For counter.compact-style contracts (no witnesses), the codegen
    // would never actually construct a WitnessContext. This test just
    // confirms the type is reachable for future contracts that need it.
    fn assert_type<T>() {}
    assert_type::<WitnessContext<(), ()>>();
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test witness 2>&1 | tail -10
```

Expected: errors for `NoWitnesses` and `WitnessContext`.

- [ ] **Step 3: Implement witness module**

Create `runtime-rs/src/witness.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Witness execution context + a trivial `NoWitnesses` marker for contracts
// that declare zero witnesses.

use crate::{ContractAddress, DefaultDB, QueryContext, DB};

/// Read-only context handed to a witness implementation.
///
/// `L` is the projected ledger view that the compiler emits per-contract.
/// `PS` is the private state.
#[derive(Clone)]
pub struct WitnessContext<L, PS, D = DefaultDB>
where
    D: DB,
{
    pub ledger: L,
    pub private_state: PS,
    pub contract_address: ContractAddress,
    pub query_context: QueryContext<D>,
}

/// Marker for contracts that declare zero witnesses. The compiler uses
/// `NoWitnesses` as the default bound when a contract has no `witness`
/// declarations, so users don't have to write an empty trait impl.
#[derive(Clone, Copy, Default, Debug)]
pub struct NoWitnesses;
```

- [ ] **Step 4: Re-export from lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
mod witness;
pub use witness::{NoWitnesses, WitnessContext};
```

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test witness 2>&1 | tail -10
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add WitnessContext and NoWitnesses marker

WitnessContext<L,PS,D> exposes the projected ledger view, private
state, contract address, and the read-only query context to witness
implementations. NoWitnesses is the empty-trait default the codegen
uses when a contract declares zero witnesses.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B6: `CompactError` and assertion helpers

**Files:**
- Create: `runtime-rs/src/error.rs`
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/error.rs`

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/error.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0

use compact_runtime::*;

#[test]
fn compact_error_constructs_assertion() {
    let e = CompactError::AssertionFailed("test".into());
    assert_eq!(e.to_string(), "assertion failed: test");
}

#[test]
fn transcript_rejected_converts_to_compact_error() {
    // The codegen will use `?` on QueryContext::query() results, relying
    // on a From<TranscriptRejected<D>> for CompactError impl. We can't
    // easily construct a TranscriptRejected, but we can verify the
    // conversion path exists at the type level.
    fn _conversion_exists<D: DB>(t: TranscriptRejected<D>) -> CompactError {
        t.into()
    }
}

#[test]
fn compact_assert_macro_passes_when_true() {
    fn check() -> Result<(), CompactError> {
        compact_runtime::compact_assert!(2 + 2 == 4, "math broken");
        Ok(())
    }
    check().unwrap();
}

#[test]
fn compact_assert_macro_errors_when_false() {
    fn check() -> Result<(), CompactError> {
        compact_runtime::compact_assert!(2 + 2 == 5, "nope");
        Ok(())
    }
    match check() {
        Err(CompactError::AssertionFailed(msg)) => assert_eq!(msg, "nope"),
        other => panic!("expected AssertionFailed, got {other:?}"),
    }
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test error 2>&1 | tail -15
```

Expected: errors that `CompactError` and `compact_assert!` are unresolved.

- [ ] **Step 3: Implement error.rs**

Create `runtime-rs/src/error.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Unified error type for generated contract code. Encompasses
// assertion failures (from `assert(cond, msg)` in Compact source) and
// VM-level transcript rejections.

use crate::{DefaultDB, TranscriptRejected, DB};
use std::fmt;

#[derive(Debug)]
pub enum CompactError {
    AssertionFailed(String),
    TranscriptRejected(String),
}

impl fmt::Display for CompactError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::AssertionFailed(msg) => write!(f, "assertion failed: {msg}"),
            Self::TranscriptRejected(msg) => write!(f, "transcript rejected: {msg}"),
        }
    }
}

impl std::error::Error for CompactError {}

impl<D: DB> From<TranscriptRejected<D>> for CompactError {
    fn from(t: TranscriptRejected<D>) -> Self {
        Self::TranscriptRejected(format!("{t:?}"))
    }
}

/// `compact_assert!(cond, "msg")` — returns `Err(CompactError::AssertionFailed)`
/// from the enclosing function (which must return `Result<_, CompactError>`)
/// if `cond` is false. Mirrors Compact's `assert(cond, "msg")`.
#[macro_export]
macro_rules! compact_assert {
    ($cond:expr, $msg:expr) => {
        if !($cond) {
            return Err($crate::CompactError::AssertionFailed($msg.into()));
        }
    };
    ($cond:expr) => {
        if !($cond) {
            return Err($crate::CompactError::AssertionFailed(
                concat!("at ", file!(), ":", line!()).into(),
            ));
        }
    };
}
```

- [ ] **Step 4: Re-export from lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
mod error;
pub use error::CompactError;
```

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test error 2>&1 | tail -10
```

Expected: all 4 tests pass.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add CompactError type and compact_assert! macro

Unified error type covering Compact `assert(cond,"msg")` failures and
VM-level transcript rejections. `compact_assert!` returns
`Err(CompactError::AssertionFailed)` from the enclosing fn rather than
panicking — a panic in a contract running inside a server process
would crash the host service.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B7: `check_runtime_version!` macro

**Files:**
- Create: `runtime-rs/src/version.rs`
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/version.rs`

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/version.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0

#[test]
fn matching_version_compiles() {
    // The macro expands to a const assertion. If the expected string equals
    // compact_runtime::COMPACT_RUNTIME_VERSION, the assertion passes and the
    // test compiles. If not, compilation fails.
    compact_runtime::check_runtime_version!("0.1.0");
}

#[test]
fn version_constant_is_exposed() {
    assert_eq!(compact_runtime::COMPACT_RUNTIME_VERSION, "0.1.0");
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test version 2>&1 | tail -10
```

Expected: macro and constant unresolved.

- [ ] **Step 3: Implement version.rs**

Create `runtime-rs/src/version.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Generated contracts call `check_runtime_version!("x.y.z")` at module
// load to assert that the runtime they were compiled against is
// ABI-compatible with the one they're being linked with. Mirrors the
// TS path's `__compactRuntime.checkRuntimeVersion(...)`.

/// The published version of this crate, expanded at build time.
pub const COMPACT_RUNTIME_VERSION: &str = env!("CARGO_PKG_VERSION");

/// Compile-time string equality, used by `check_runtime_version!`.
#[doc(hidden)]
pub const fn const_str_eq(a: &str, b: &str) -> bool {
    let a = a.as_bytes();
    let b = b.as_bytes();
    if a.len() != b.len() {
        return false;
    }
    let mut i = 0;
    while i < a.len() {
        if a[i] != b[i] {
            return false;
        }
        i += 1;
    }
    true
}

/// Fail the build if the linked compact-runtime doesn't match the
/// version the contract was compiled against.
#[macro_export]
macro_rules! check_runtime_version {
    ($expected:literal) => {
        const _: () = assert!(
            $crate::version::const_str_eq($expected, $crate::version::COMPACT_RUNTIME_VERSION),
            "compact-runtime version mismatch"
        );
    };
}
```

- [ ] **Step 4: Wire up lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
pub mod version;
pub use version::COMPACT_RUNTIME_VERSION;
```

(`pub mod` rather than `mod` because the macro expansion references `$crate::version::const_str_eq`.)

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test version 2>&1 | tail -10
```

Expected: both tests pass.

- [ ] **Step 6: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add check_runtime_version! macro

Compile-time assertion that generated contract code was built against a
matching runtime version. COMPACT_RUNTIME_VERSION comes from
CARGO_PKG_VERSION so the version bumps automatically with each release.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B8: `std_lib::Counter` newtype

**Files:**
- Create: `runtime-rs/src/std_lib.rs`
- Modify: `runtime-rs/src/lib.rs`
- Create: `runtime-rs/tests/std_lib.rs`

This task implements just what counter.compact needs from the Compact standard library: the `Counter` ledger ADT. Map/Set/MerkleTree/Cell/List land in the M3 follow-up plan.

The Counter is lowered by the compiler (see `compiler/midnight-ledger.ss:587-606`) into raw `Op` sequences operating on a `StateValue::Cell(u64)`. So `runtime-rs::Counter` is more of a typed read helper than a heavyweight wrapper — the actual mutation ops live in generated code.

- [ ] **Step 1: Write the failing test**

Create `runtime-rs/tests/std_lib.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0

use compact_runtime::*;
use compact_runtime::std_lib::Counter;

#[test]
fn counter_decode_reads_u64_from_state_value() {
    let sv = StateValue::from(AlignedValue::from(42u64));
    let value = Counter::decode_from(&sv).expect("decode");
    assert_eq!(value, 42);
}

#[test]
fn counter_decode_errors_on_wrong_shape() {
    let sv = StateValue::Null;
    let err = Counter::decode_from(&sv).expect_err("should not decode");
    assert!(matches!(err, CompactError::AssertionFailed(_)));
}
```

- [ ] **Step 2: Run and confirm failure**

```bash
cargo test -p compact-runtime --test std_lib 2>&1 | tail -10
```

Expected: errors that `Counter` and `std_lib` are unresolved.

- [ ] **Step 3: Implement std_lib**

Create `runtime-rs/src/std_lib.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Compact standard library types used by generated contract code.
//
// Each ledger ADT (Counter / Cell / Map / Set / MerkleTree / List) lives
// here as a newtype + a `decode_from(&StateValue)` helper. The compiler
// lowers mutating operations (e.g., `round.increment(1)`) directly to
// Op programs, so the wrappers don't need methods for those.

use crate::{AlignedValue, CompactError, StateValue};

/// Compact's `Counter` ledger ADT. Represented at runtime as
/// `StateValue::Cell` containing a u64 aligned-value.
pub struct Counter;

impl Counter {
    /// Decode the current counter value from a `StateValue::Cell`.
    /// Returns `Err(AssertionFailed)` if `sv` is not a Cell or its
    /// contents are not a u64-aligned value.
    pub fn decode_from(sv: &StateValue) -> Result<u64, CompactError> {
        let cell = match sv {
            StateValue::Cell(c) => c,
            _ => {
                return Err(CompactError::AssertionFailed(
                    "Counter::decode_from: expected StateValue::Cell".into(),
                ));
            }
        };
        decode_u64(cell)
    }
}

/// Decode an `AlignedValue` known to be a u64 (8-byte) value into a u64.
pub fn decode_u64(av: &AlignedValue) -> Result<u64, CompactError> {
    let bytes = av.value.first().ok_or_else(|| {
        CompactError::AssertionFailed("decode_u64: aligned value is empty".into())
    })?;
    if bytes.len() != 8 {
        return Err(CompactError::AssertionFailed(format!(
            "decode_u64: expected 8 bytes, got {}",
            bytes.len()
        )));
    }
    let mut buf = [0u8; 8];
    buf.copy_from_slice(bytes);
    Ok(u64::from_be_bytes(buf))
}
```

(Note: the byte ordering — `from_be_bytes` vs `from_le_bytes` — must match what `AlignedValue::from(u64)` produces. If the test fails with a wrong value, swap to `from_le_bytes` and re-run.)

- [ ] **Step 4: Wire up lib.rs**

Append to `runtime-rs/src/lib.rs`:

```rust
pub mod std_lib;
```

- [ ] **Step 5: Re-run the test**

```bash
cargo test -p compact-runtime --test std_lib 2>&1 | tail -10
```

Expected: both tests pass. If the first test fails with `assertion left == right` showing the bytes interpreted in the wrong order, switch `u64::from_be_bytes` to `u64::from_le_bytes` in `decode_u64`.

- [ ] **Step 6: Verify the full suite is still green**

```bash
cargo test -p compact-runtime 2>&1 | tail -5
```

Expected: `test result: ok` across all test files.

- [ ] **Step 7: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: add std_lib::Counter and decode_u64 helper

Compact's Counter ledger ADT, exposed as a typed read helper. The
compiler lowers mutating ops (round.increment(1)) directly to Op
programs, so this module only needs to surface the read path.

decode_u64 is shared with future ledger ADT decoders (Cell<u64>, etc.)
that land in the M3 follow-up plan.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B9: Integration smoke test — assemble a contract by hand

**Files:**
- Create: `runtime-rs/tests/integration.rs`

This task uses the runtime crate exactly as generated code will use it. Failure here means the codegen will not work — fix the runtime, not the codegen.

- [ ] **Step 1: Write the integration test**

Create `runtime-rs/tests/integration.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// End-to-end smoke test exercising the public API as generated code does.
// Constructs a counter, runs the `increment` Op sequence, decodes the new
// value. If this passes, the runtime is ready for codegen.

use compact_runtime::std_lib::Counter;
use compact_runtime::*;

#[test]
fn increment_counter_end_to_end() {
    // Seed contract state: array with one Cell(u64=0) at index 0.
    let initial = StateValue::Array(Array::new().push(StateValue::from(AlignedValue::from(0u64))));
    let state = ChargedState::new(initial);
    let qctx = QueryContext::new(state, ContractAddress::default());

    // Op program for `round.increment(1)`:
    //   idx [cached:false, push_path:true, path:[Key::Value(0u8)]]
    //   addi [immediate:1]
    //   ins  [cached:true, n:1]
    let ops: Vec<Op<ResultModeVerify>> = vec![
        Op::Idx {
            cached: false,
            push_path: true,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Addi { immediate: 1 },
        Op::Ins {
            cached: true,
            n: 1,
        },
    ];

    let results = qctx
        .query(&ops, None, &INITIAL_COST_MODEL)
        .expect("query");

    // Decode the counter at path [0] from the resulting state.
    let new_state = results.context.state.get_ref();
    let cell = match new_state {
        StateValue::Array(arr) => arr.get(0).expect("first element"),
        _ => panic!("expected StateValue::Array"),
    };
    let counter_value = Counter::decode_from(&cell).expect("decode counter");
    assert_eq!(counter_value, 1);
}
```

- [ ] **Step 2: Run the test**

```bash
cargo test -p compact-runtime --test integration 2>&1 | tail -20
```

Expected: pass. If it fails:
- "expected StateValue::Array" → the state didn't initialize as an array; check the `new_array().array_push(...)` chain against the actual `midnight-onchain-state` API by reading `~/.cargo/registry/src/.../midnight-onchain-state-3.0.0/src/state.rs` and adapting.
- "expected 8 bytes, got N" → the alignment of `AlignedValue::from(0u64)` doesn't match `decode_u64`'s assumption; inspect via dbg!() and adjust.
- A `TranscriptRejected` → the path `Key::Value(0u8)` isn't matching the array index; try `0u32` or check `Op::Ins` semantics.

This is the highest-information test in Phase B. Take the time to make it green.

- [ ] **Step 3: Commit**

```bash
git add runtime-rs/
git commit -S -s -m "$(cat <<'EOF'
runtime-rs: integration smoke test — increment counter end-to-end

Constructs a contract state by hand, runs the Op sequence the compiler
will emit for `round.increment(1)`, and decodes the result. This is
the contract the runtime makes with generated code; if this passes,
codegen has a working target API.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task B10: Phase B done — verify full suite

**Files:** none.

- [ ] **Step 1: Full suite + warnings**

```bash
cargo test -p compact-runtime 2>&1 | tail -10
cargo check -p compact-runtime --all-targets 2>&1 | grep -E "warning|error" | head
cargo clippy -p compact-runtime --all-targets -- -D warnings 2>&1 | tail -5
```

Expected: all tests pass, no warnings, clippy clean.

- [ ] **Step 2: Lock in (no commit — verification only)**

If anything is dirty (untracked / unstaged), fix it and commit before moving to Phase C.

---

## Phase C — `--rust` flag + minimal emitter (M2 part 1)

This phase adds the CLI flag and a stub `rust-passes.ss` that emits *empty* but compiling output. Real emission lands in Phase D.

### Task C1: Add `emit-rust` to `config-params.ss`

**Files:**
- Modify: `compiler/config-params.ss`

- [ ] **Step 1: Add the parameter**

Edit `compiler/config-params.ss`. Add after the `feature-zkir-v3` line:

```scheme
  ; Rust emit (M2)
  (export-parameter emit-rust #f)
```

- [ ] **Step 2: Confirm Scheme syntax loads**

```bash
nix develop --command bash -c "cd compiler && echo '(import (config-params))' | scheme -q --libdirs ."
```

Expected: no error output.

- [ ] **Step 3: Commit**

```bash
git add compiler/config-params.ss
git commit -S -s -m "$(cat <<'EOF'
compiler: add emit-rust parameter to config-params

Adds a new boolean parameter the --rust CLI flag will toggle.
Defaulting to #f preserves backward compatibility — without --rust
the compiler behaves identically.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C2: Add `--rust` flag to `compactc.ss`

**Files:**
- Modify: `compiler/compactc.ss`

- [ ] **Step 1: Add the flag clause**

Edit `compiler/compactc.ss`. Inside the `(flags ...)` list (currently lines ~88–100), add a new line after `[(--feature-zkir-v3)]`:

```scheme
             [(--feature-zkir-v3)]
             [(--rust)])
```

(Move the closing `)` to follow the new entry.)

Add `emit-rust` to the `parameterize` block (currently lines ~104–110):

```scheme
     (parameterize ([trace-passes ?--trace-passes]
                    [skip-zk ?--skip-zk]
                    [no-communications-commitment ?--no-communications-commitment]
                    [feature-zkir-v3 ?--feature-zkir-v3]
                    [emit-rust ?--rust]
                    [compact-path (if ?--compact-path (split-search-path search-list) (compact-path))]
                    [trace-search ?--trace-search])
```

Add `emit-rust` to the `config-params` import at the top of the file (alongside other config parameters).

Also mirror the flag in the second `(flags ...)` block (the error-on-bad-args block near the bottom):

```scheme
             [(--feature-zkir-v3)]
             [(--rust)])
```

- [ ] **Step 2: Update `print-help`**

Add to the help text in `print-help` after the `--feature-zkir-v3` section:

```scheme
  --rust causes the compiler to additionally emit a Rust crate (contract/lib.rs)
    alongside the TypeScript output. Generated Rust depends on the `compact-runtime`
    crate. See docs/superpowers/specs/2026-05-25-rust-codegen-design.md for details.
```

- [ ] **Step 3: Rebuild compactc**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3
```

Expected: a `/nix/store/...-compact-all` path. If a build error references `?--rust` or `emit-rust`, re-check the flag wiring.

- [ ] **Step 4: Smoke-test the flag**

```bash
$(ls /nix/store/*-compact-all/bin/compactc | head -1) --help 2>&1 | grep -A1 "\-\-rust"
```

Expected: the help text for `--rust` appears.

```bash
$(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust-test/ 2>&1 | tail -5
```

Expected: success exit, files in `/tmp/counter-rust-test/contract/` (the TS files for now — Rust emission lands in Phase D).

- [ ] **Step 5: Commit**

```bash
git add compiler/compactc.ss
git commit -S -s -m "$(cat <<'EOF'
compiler: add --rust CLI flag

Wires the flag through to the new emit-rust config parameter. When
unset (default), the compiler behaves exactly as before. When set,
the next phase will trigger Rust emission alongside the existing TS
output.

The flag also appears in --help.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C3: Stub `rust-passes.ss` (header + identity pass)

**Files:**
- Create: `compiler/rust-passes.ss`

The first version of `rust-passes.ss` is a near-no-op that prints the file header. Subsequent tasks fill in real emission.

- [ ] **Step 1: Create the stub**

Create `compiler/rust-passes.ss`:

```scheme
#!chezscheme

;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;; 	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;; Rust code generator. Mirrors typescript-passes.ss in spirit: walks
;;; the post-prepare-for-typescript `Ltypescript` IR and emits a Rust
;;; crate (contract/lib.rs) that depends on the `compact-runtime` crate.
;;;
;;; See docs/superpowers/specs/2026-05-25-rust-codegen-design.md for the
;;; full mapping between Compact constructs and Rust output.

(library (rust-passes)
  (export rust-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (nanopass)
          (langs)
          (pass-helpers)
          (natives)
          (runtime-version)
          (ledger)
          (vm))

  (define-pass print-rust : Ltypescript (ir) -> Ltypescript ()
    (definitions
      (define (out s)
        (display-string s (get-target-port 'contract.rs)))
      (define (header)
        (out "// SPDX-License-Identifier: Apache-2.0\n")
        (out "// Generated by compactc. Do not edit by hand.\n")
        (out "\n")
        (out "#![allow(clippy::all, dead_code, unused_imports, unused_variables)]\n")
        (out "\n")
        (out "use compact_runtime::*;\n")
        (out "use std::marker::PhantomData;\n")
        (out "\n")
        (out (format "compact_runtime::check_runtime_version!(\"~a\");\n" (runtime-version)))
        (out "\n")
        (out "// TODO(rust-codegen M2/D): emit Witnesses trait, Contract struct, circuits, ledger view.\n")
        (out "// Placeholder body so the file compiles against compact-runtime.\n")
        (out "\n")
        (out "pub trait Witnesses<PS> {}\n")
        (out "impl<PS> Witnesses<PS> for NoWitnesses {}\n")
        (out "\n")
        (out "pub struct Contract<PS, W = NoWitnesses>\n")
        (out "where W: Witnesses<PS>\n")
        (out "{ pub witnesses: W, _ps: PhantomData<PS> }\n")
        (out "\n")
        (out "impl<PS, W: Witnesses<PS>> Contract<PS, W> {\n")
        (out "    pub fn new(witnesses: W) -> Self { Self { witnesses, _ps: PhantomData } }\n")
        (out "}\n")))
    (Program : Program (ir) -> Program ()
      [(program ,src ,version ,pelt* ...)
       (header)
       ir]))

  (define-passes rust-passes
    (print-rust          Ltypescript)))
```

- [ ] **Step 2: Rebuild compactc**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3
```

Expected: success. If a library-not-found error mentions `rust-passes`, the file is missing from `compiler/` or the Nanopass IR import is wrong — check that `Ltypescript` is exported from `langs.ss` (it is; same import as `typescript-passes.ss`).

- [ ] **Step 3: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
compiler: scaffold rust-passes.ss

Stub Rust emitter that prints a file header + minimal Contract<PS,W>
placeholder. Subsequent tasks fill in witnesses, circuits, initial
state, and the ledger view function.

Built on the existing Ltypescript IR — no parallel Lrust needed.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task C4: Wire `rust-passes` into `passes.ss`

**Files:**
- Modify: `compiler/passes.ss`

- [ ] **Step 1: Import rust-passes**

In `compiler/passes.ss`, add to the imports block (lines ~24–37):

```scheme
          (typescript-passes)
          (rust-passes)            ;; NEW
          (circuit-passes)
```

- [ ] **Step 2: Add the emit-rust branch**

In `generate-everything`, after the existing `(with-target-ports '((contract.js . "contract/index.js") ...))` block (the last `with-target-ports` in the function, around line 175), add:

```scheme
                          (when (emit-rust)
                            (with-target-ports
                              '((contract.rs . "contract/lib.rs"))
                              (run-passes rust-passes analyzed-ir)))
```

Also add the `(config-params)` import if it's not already present (check the import block — `emit-rust` parameter must be reachable from this file). It is imported as part of `(config-params)` which is already on line 22.

- [ ] **Step 3: Rebuild + test**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3
```

Expected: success.

```bash
rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  cat /tmp/counter-rust/contract/lib.rs | head -25
```

Expected: the stub `lib.rs` content prints, including `compact_runtime::check_runtime_version!("...");` and the `Contract<PS, W>` placeholder struct.

- [ ] **Step 4: Verify the stub compiles**

```bash
mkdir -p /tmp/counter-rust-build && cd /tmp/counter-rust-build && cp /tmp/counter-rust/contract/lib.rs src-temp.rs && \
  cat > Cargo.toml <<'EOF'
[package]
name = "counter-stub"
version = "0.0.0"
edition = "2021"

[lib]
path = "src-temp.rs"

[dependencies]
compact-runtime = { path = "/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/runtime-rs" }
EOF
cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors. If a `check_runtime_version!` mismatch fires, the version literal in the emitter doesn't match `runtime-rs/Cargo.toml`'s version — fix by editing `(runtime-version)` call in `rust-passes.ss` or by bumping the runtime-rs version.

- [ ] **Step 5: Commit**

```bash
git add compiler/passes.ss
git commit -S -s -m "$(cat <<'EOF'
compiler: wire rust-passes into generate-everything

Adds the emit-rust branch to generate-everything. When --rust is
passed, contract/lib.rs is emitted alongside the existing
contract/index.{js,d.ts}. Without --rust, behavior is unchanged.

The Rust output currently is a stub placeholder; real circuit /
ledger / witness emission lands in Phase D.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase D — Counter.compact emission (M2 part 2)

This phase fills in real codegen. After Phase D, `compactc --rust counter.compact` produces a working Rust contract. Design Appendix B (`docs/superpowers/specs/2026-05-25-rust-codegen-design.md` §12) shows the target output, but treat it as guidance — the canonical regression oracle is the byte-parity test (Phase E), not Appendix B verbatim. The snapshot test gets its expected file captured **after** the emitter is working (Task E4 step 1), so the snapshot reflects what actually compiles and passes parity.

### Task D2: Emit Witnesses trait

**Files:**
- Modify: `compiler/rust-passes.ss`

- [ ] **Step 1: Replace the placeholder with the real Witnesses trait emitter**

In `compiler/rust-passes.ss`, replace the `header` definition and add a witness-emission helper:

```scheme
      (define (emit-witnesses witness-decl*)
        (out "pub trait Witnesses<PS> {\n")
        (for-each
          (lambda (w)
            ;; witness-decl* is a list of Ltypescript Witness records.
            ;; Each has a name and a signature. For M2 (counter.compact),
            ;; the list is empty.
            (nanopass-case (Ltypescript Witness) w
              [(witness ,src ,name ,arg* (,ret-type))
               (out (format "    fn ~a(&self, ctx: &WitnessContext<Ledger<'_>, PS>" (camel->snake (id-sym name))))
               ;; Argument emission deferred to M3.
               (out (format ") -> (PS, ~a);\n" (type-rust ret-type)))]))
          witness-decl*)
        (out "}\n")
        (when (null? witness-decl*)
          (out "impl<PS> Witnesses<PS> for NoWitnesses {}\n"))
        (out "\n"))
```

Update `Program` to call `emit-witnesses` with the contract's witness list. The exact accessor depends on Ltypescript's Program structure — read `compiler/langs.ss` `define-language Ltypescript` to find the right path (likely a `witness*` field on Program or a member among `pelt*`).

For counter.compact (zero witnesses), the call is `(emit-witnesses '())`, which emits just the trait + the `NoWitnesses` blanket impl.

Also add helper utilities to the `(definitions ...)` block:

```scheme
      (define (camel->snake s)
        (let* ([s (symbol->string s)]
               [chars (string->list s)])
          (string->symbol
            (apply string-append
              (let loop ([chars chars] [first? #t])
                (cond
                  [(null? chars) '()]
                  [(char-upper-case? (car chars))
                   (cons (if first? "" "_")
                         (cons (string (char-downcase (car chars)))
                               (loop (cdr chars) #f)))]
                  [else (cons (string (car chars)) (loop (cdr chars) #f))]))))))

      (define (type-rust type)
        ;; M2 minimum: recognise the types counter.compact uses.
        ;; tbytes / tfield / tuint / tboolean / ttuple [] / tvec / tenum.
        ;; Real implementation lands in Task D5.
        "/* TODO: type-rust */")
```

- [ ] **Step 2: Rebuild + smoke**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3
rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -E "Witnesses|NoWitnesses" /tmp/counter-rust/contract/lib.rs
```

Expected: `pub trait Witnesses<PS> {` + `impl<PS> Witnesses<PS> for NoWitnesses {}` appear in the output.

- [ ] **Step 3: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit Witnesses trait

For contracts with witness declarations, emits one trait method per
witness. For contracts without (e.g., counter.compact), emits an
empty trait + blanket impl for NoWitnesses so the default W bound
just works.

Includes camel->snake helper for identifier conversion. type-rust
helper is stubbed; real implementation lands in Task D5.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D3: Emit Contract struct and `new()`

**Files:**
- Modify: `compiler/rust-passes.ss`

- [ ] **Step 1: Add the contract struct emitter**

In `rust-passes.ss`, add to the `(definitions ...)` block:

```scheme
      (define (emit-contract-struct)
        (out "pub struct Contract<PS, W = NoWitnesses>\n")
        (out "where\n")
        (out "    W: Witnesses<PS>,\n")
        (out "{\n")
        (out "    pub witnesses: W,\n")
        (out "    _ps: PhantomData<PS>,\n")
        (out "}\n")
        (out "\n")
        (out "impl<PS, W> Contract<PS, W>\n")
        (out "where\n")
        (out "    W: Witnesses<PS>,\n")
        (out "{\n")
        (out "    pub fn new(witnesses: W) -> Self {\n")
        (out "        Self { witnesses, _ps: PhantomData }\n")
        (out "    }\n"))

      (define (close-contract-struct)
        (out "}\n\n"))
```

Update `Program` to call `emit-contract-struct` after `emit-witnesses`, emit circuits / initial-state inside the impl (next tasks), and then `close-contract-struct`.

- [ ] **Step 2: Rebuild + smoke**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -A2 "pub struct Contract" /tmp/counter-rust/contract/lib.rs
```

Expected: the Contract struct, `where W: Witnesses<PS>`, and the `new()` constructor appear in the emitted file.

- [ ] **Step 3: Verify it still compiles**

```bash
cd /tmp/counter-rust-build && cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors.

- [ ] **Step 4: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit Contract<PS,W> struct + new()

Generates the public Contract struct generic over private state PS
and witnesses impl W, with W defaulting to NoWitnesses. The `new`
constructor takes the user-supplied witnesses by value. Subsequent
tasks add circuit methods and initial_state into the same impl block.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D4: Emit `initial_state` for counter

**Files:**
- Modify: `compiler/rust-passes.ss`

- [ ] **Step 1: Add initial-state emitter**

In `rust-passes.ss`, add an `emit-initial-state` helper that walks the constructor program in the Ltypescript IR and emits the equivalent Rust. For counter.compact, the constructor implicitly seeds `round` to 0 (Counter's default), producing the Op sequence:

```scheme
      (define (emit-initial-state ledger-field*)
        (out "    pub fn initial_state(\n")
        (out "        &self,\n")
        (out "        ctx: ConstructorContext<PS>,\n")
        (out "    ) -> Result<ConstructorResult<PS>, CompactError> {\n")
        (out "        let mut sv = Array::<StateValue, _>::new();\n")
        ;; For each ledger field, push its initial StateValue + run the
        ;; ins op the compiler would emit. counter.compact has one field
        ;; (Counter, initial value Cell(0u64)).
        (for-each
          (lambda (lf)
            (out "        sv = sv.push(StateValue::from(AlignedValue::from(0u64)));\n"))
        ;; Wrap accumulator in StateValue::Array after loop.
        (out "        let sv = StateValue::Array(sv);\n")
          ledger-field*)
        (out "        let state = ChargedState::new(sv);\n")
        (out "        let qctx = QueryContext::new(state, ContractAddress::default());\n")
        (out "        Ok(ConstructorResult {\n")
        (out "            current_contract_state: ChargedState::new(qctx.state),\n")
        (out "            current_private_state: ctx.initial_private_state,\n")
        (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
        (out "        })\n")
        (out "    }\n\n"))
```

This implementation hard-codes Counter as the only supported ADT (counter.compact's only field). Generalising to other ADTs is M3 work — leave a `TODO(M3)` comment in the .ss file.

Call `emit-initial-state` from `Program` with the list of ledger fields. The exact accessor for ledger fields on the Ltypescript Program record is what you'll find by reading `compiler/langs.ss` — likely `(program ... (lfield ...) ...)` or similar.

- [ ] **Step 2: Rebuild + smoke**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -A 15 "pub fn initial_state" /tmp/counter-rust/contract/lib.rs
```

Expected: the `initial_state` method appears with the Op sequence and the `ConstructorResult` return.

- [ ] **Step 3: Compile-check**

```bash
cd /tmp/counter-rust-build && cp /tmp/counter-rust/contract/lib.rs src-temp.rs && cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors. Any errors here mean a type/method name doesn't match `compact-runtime` — fix the emitter, not the runtime.

- [ ] **Step 4: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit Contract::initial_state for counter.compact

Generates the constructor that seeds a Counter ledger field to 0.
Currently hardcodes Counter as the only supported ADT — generalising
to Cell/Map/Set/MerkleTree/List is M3 work.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D5: Emit `increment` circuit

**Files:**
- Modify: `compiler/rust-passes.ss`

This is the meat of the codegen — turning a Compact circuit body into a Rust method that emits the same Op program the TS path does.

- [ ] **Step 1: Add circuit emitter**

In `rust-passes.ss`, add a circuit-emission helper. For counter.compact's `increment()` body (`round.increment(1)`), the Op sequence comes straight from `compiler/midnight-ledger.ss:602-606`:

```scheme
      (define (emit-increment-circuit)
        ;; Hard-coded for counter.compact's single `increment()` circuit
        ;; calling Counter.increment(1). M3 generalises to arbitrary circuit
        ;; bodies via a proper IR walk.
        (out "    pub fn increment(\n")
        (out "        &self,\n")
        (out "        ctx: CircuitContext<PS>,\n")
        (out "    ) -> Result<CircuitResults<PS, ()>, CompactError> {\n")
        (out "        let ops: Vec<Op<ResultModeVerify>> = vec![\n")
        (out "            Op::Idx {\n")
        (out "                cached: false,\n")
        (out "                push_path: true,\n")
        (out "                path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),\n")
        (out "            },\n")
        (out "            Op::Addi { immediate: 1 },\n")
        (out "            Op::Ins { cached: true, n: 1 },\n")
        (out "        ];\n")
        (out "\n")
        (out "        let results = ctx\n")
        (out "            .current_query_context\n")
        (out "            .query(&ops, ctx.gas_limit.clone(), &ctx.cost_model)?;\n")
        (out "\n")
        (out "        Ok(CircuitResults {\n")
        (out "            result: (),\n")
        (out "            context: CircuitContext {\n")
        (out "                current_query_context: results.context,\n")
        (out "                ..ctx\n")
        (out "            },\n")
        (out "            gas_cost: results.gas_cost,\n")
        (out "        })\n")
        (out "    }\n\n"))
```

Call this from `Program` after `emit-initial-state`. Wrap in a runtime check: if the program has any circuit named `increment` of the expected shape, call `emit-increment-circuit`. Otherwise emit a `// M3: generalise circuit emission` comment placeholder. For counter.compact this triggers.

- [ ] **Step 2: Rebuild + smoke**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -A 25 "pub fn increment" /tmp/counter-rust/contract/lib.rs
```

Expected: the `increment` circuit method appears with the Op sequence and returns `CircuitResults`.

- [ ] **Step 3: Compile-check**

```bash
cd /tmp/counter-rust-build && cp /tmp/counter-rust/contract/lib.rs src-temp.rs && cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors.

- [ ] **Step 4: Behavioural check — run the increment**

In `/tmp/counter-rust-build/`, add a quick test in `src-temp.rs` (just append, this is throwaway):

```rust
#[cfg(test)]
mod _smoke {
    use super::*;
    use compact_runtime::*;

    #[test]
    fn increment_works() {
        let contract: Contract<()> = Contract::new(NoWitnesses);
        let cctx = ConstructorContext {
            initial_private_state: (),
            empty_zswap_local_state: ZswapLocalState::default(),
            cost_model: INITIAL_COST_MODEL,
            gas_limit: None,
        };
        let init = contract.initial_state(cctx).expect("init");

        let qctx = QueryContext::new(init.current_contract_state.clone(), ContractAddress::default());
        let ctx = CircuitContext {
            current_private_state: (),
            current_query_context: qctx,
            current_zswap_local_state: init.current_zswap_local_state,
            cost_model: INITIAL_COST_MODEL,
            gas_limit: None,
        };
        let result = contract.increment(ctx).expect("increment");
        // The returned state should contain Counter == 1
        let new_state = result.context.current_query_context.state;
        // Walk to the counter cell at path [0]
        let arr = match new_state { StateValue::Array(a) => a, _ => panic!() };
        let cell = arr.get(0).unwrap();
        let value = compact_runtime::std_lib::Counter::decode_from(&cell).unwrap();
        assert_eq!(value, 1);
    }
}
```

```bash
cd /tmp/counter-rust-build && cargo test 2>&1 | tail -10
```

Expected: `test _smoke::increment_works ... ok`. Then delete the test (it's throwaway).

- [ ] **Step 5: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit increment() circuit for counter.compact

Emits the Op sequence (Idx, Addi, Ins) the TS path uses, wrapped in a
Result-returning method on Contract<PS, W>. Currently hardcodes the
counter shape — M3 generalises to arbitrary circuit bodies via a real
IR walk.

Verified end-to-end: the generated contract compiles against
compact-runtime and a hand-written increment test produces Counter==1
after one call.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D6: Emit `ledger()` view function

**Files:**
- Modify: `compiler/rust-passes.ss`

- [ ] **Step 1: Add ledger-view emitter**

In `rust-passes.ss`, add (called from `Program` after the contract impl block is closed):

```scheme
      (define (emit-ledger-view)
        (out "pub struct Ledger<'a, D: DB = DefaultDB> {\n")
        (out "    state: &'a ChargedState<D>,\n")
        (out "}\n\n")
        (out "pub fn ledger<'a, D: DB>(state: &'a ChargedState<D>) -> Ledger<'a, D> {\n")
        (out "    Ledger { state }\n")
        (out "}\n\n")
        (out "impl<'a, D: DB> Ledger<'a, D> {\n")
        ;; Each ledger field → one method. Counter currently only.
        (out "    pub fn round(&self) -> Result<u64, CompactError> {\n")
        (out "        let qctx = QueryContext::new((*self.state).clone(), ContractAddress::default());\n")
        (out "        let ops: Vec<Op<ResultModeVerify>> = vec![\n")
        (out "            Op::Dup { n: 0 },\n")
        (out "            Op::Idx {\n")
        (out "                cached: false,\n")
        (out "                push_path: false,\n")
        (out "                path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),\n")
        (out "            },\n")
        (out "            Op::Popeq { cached: true, result: AlignedValue::default() },\n")
        (out "        ];\n")
        (out "        let results = qctx.query(&ops, None, &INITIAL_COST_MODEL)?;\n")
        (out "        let event = results.events.last().ok_or_else(|| CompactError::AssertionFailed(\"empty events\".into()))?;\n")
        (out "        compact_runtime::std_lib::decode_u64(event)\n")
        (out "    }\n")
        (out "}\n\n"))
```

- [ ] **Step 2: Rebuild + smoke**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -A 5 "pub fn ledger" /tmp/counter-rust/contract/lib.rs
```

Expected: the `ledger()` function and `Ledger::round()` method appear.

- [ ] **Step 3: Compile-check**

```bash
cd /tmp/counter-rust-build && cp /tmp/counter-rust/contract/lib.rs src-temp.rs && cargo check 2>&1 | tail -5
```

Expected: `Finished`.

- [ ] **Step 4: Sanity-check the generated file end-to-end**

```bash
wc -l /tmp/counter-rust/contract/lib.rs
grep -cE "pub fn|pub struct|pub trait|impl" /tmp/counter-rust/contract/lib.rs
```

Expected: roughly 100 lines, and at least 6 matches for declaration lines (Witnesses trait, Contract struct, Contract impl block, initial_state fn, increment fn, ledger fn, Ledger struct + impl). Snapshot oracle lands in Task E4 after the whole emitter is green.

- [ ] **Step 5: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit ledger() view function

Adds the module-level ledger() factory and Ledger<'a,D> view struct
with a round() method that reads the Counter via dup+idx+popeq Op
sequence. Decodes the returned event to u64 via
std_lib::decode_u64.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D7: Emit `pure_circuits` module and pure_circuits export

**Files:**
- Modify: `compiler/rust-passes.ss`

counter.compact has no pure circuits, so this task just emits an empty module. The structure is in place for M3.

- [ ] **Step 1: Add pure-circuits emitter**

In `rust-passes.ss`:

```scheme
      (define (emit-pure-circuits pure-circuit*)
        (out "pub mod pure_circuits {\n")
        ;; M3: emit one `pub fn` per pure circuit.
        (for-each (lambda (c) (out "    // TODO(M3): emit pure circuit\n")) pure-circuit*)
        (out "}\n"))
```

Call from `Program` with `'()` for counter.compact (no pure circuits).

- [ ] **Step 2: Rebuild + verify**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  grep -A 3 "pub mod pure_circuits" /tmp/counter-rust/contract/lib.rs
```

Expected: `pub mod pure_circuits {}` (empty module).

- [ ] **Step 3: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit (empty) pure_circuits module

counter.compact has no pure circuits, so the module is emitted empty.
M3 fills it in for contracts that declare pure circuits.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task D8: Emit a `Cargo.toml` alongside `lib.rs`

**Files:**
- Modify: `compiler/rust-passes.ss`
- Modify: `compiler/passes.ss` (extend target ports)

Per Design §5.10.3, `compactc --rust` emits a Cargo.toml next to lib.rs.

- [ ] **Step 1: Add Cargo.toml output target to passes.ss**

In `passes.ss`, change the emit-rust branch:

```scheme
                          (when (emit-rust)
                            (with-target-ports
                              '((contract.rs       . "contract/lib.rs")
                                (contract-cargo.toml . "contract/Cargo.toml"))
                              (run-passes rust-passes analyzed-ir)))
```

- [ ] **Step 2: Emit Cargo.toml from rust-passes.ss**

In `rust-passes.ss`, add to `Program`:

```scheme
      (define (emit-cargo-toml)
        (let ([port (get-target-port 'contract-cargo.toml)])
          (display-string
            (format
              "[package]
name = \"compact-contract\"
version = \"0.1.0\"
edition = \"2021\"

[lib]
path = \"lib.rs\"

[dependencies]
compact-runtime = \"~a\"
"
              (runtime-version))
            port)))
```

Call `emit-cargo-toml` from `Program`.

- [ ] **Step 3: Rebuild + verify**

```bash
nix build --no-link --print-out-paths 2>&1 | tail -3 && \
  rm -rf /tmp/counter-rust && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-rust/ && \
  cat /tmp/counter-rust/contract/Cargo.toml
```

Expected: a valid Cargo.toml with `name = "compact-contract"` and a `compact-runtime` dep.

- [ ] **Step 4: Verify the emitted crate compiles by itself**

```bash
cd /tmp/counter-rust/contract && \
  sed -i.bak 's|^compact-runtime = .*|compact-runtime = { path = "/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/runtime-rs" }|' Cargo.toml && \
  cargo check 2>&1 | tail -5
```

Expected: `Finished` with no errors. (The sed is throwaway — it points the dep at the local crate for testing.)

- [ ] **Step 5: Commit**

```bash
git add compiler/passes.ss compiler/rust-passes.ss
git commit -S -s -m "$(cat <<'EOF'
rust-passes: emit Cargo.toml alongside lib.rs

The Cargo.toml declares compact-runtime as the sole dependency, pinned
to the runtime version the compiler embeds via check_runtime_version!.
Users can `cargo build` the emitted contract directly.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Phase E — Byte parity test harness (M2 validation)

This phase wires the cross-language byte-parity test described in Design §6.3. Failure means the Rust output diverges semantically from TS — a regression blocker.

### Task E1: Capture TS reference state

**Files:**
- Create: `tests-e2e-rust/fixtures/counter-ts-state.json`

- [ ] **Step 1: Drive the TS path to capture the post-increment ChargedState**

Set up a tiny TS script that loads the generated TS counter contract, runs `increment()` once, serializes the resulting `ChargedState`, and writes it to `tests-e2e-rust/fixtures/counter-ts-state.json`.

```bash
mkdir -p tests-e2e-rust/fixtures
cd /tmp && \
  rm -rf counter-ts-ref && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --skip-zk \
    /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/examples/counter.compact /tmp/counter-ts-ref/

cd /tmp/counter-ts-ref && \
  cat > package.json <<'EOF'
{
  "name": "counter-ts-ref",
  "type": "module",
  "dependencies": { "@midnight-ntwrk/compact-runtime": "^0.16.100" }
}
EOF

cat > driver.mjs <<'EOF'
import { Contract, ledger } from "./contract/index.js";
import * as cr from "@midnight-ntwrk/compact-runtime";

const witnesses = {};
const c = new Contract(witnesses);
const init = c.initialState({ initialPrivateState: undefined, initialZswapLocalState: cr.emptyZswapLocalState(cr.dummyContractAddress()) });

const ctx = {
  currentPrivateState: init.currentPrivateState,
  currentQueryContext: new cr.QueryContext(init.currentContractState.data, cr.dummyContractAddress()),
  currentZswapLocalState: init.currentZswapLocalState,
  costModel: cr.CostModel.initialCostModel(),
};

const result = c.circuits.increment(ctx);
const finalState = result.context.currentQueryContext.state;

// Serialize via the runtime's own canonical encoding.
const bytes = cr.encode(finalState);
console.log(JSON.stringify({ stateHex: Buffer.from(bytes).toString("hex"), counterValue: ledger(finalState).round }));
EOF

npm install >/dev/null 2>&1 && \
node driver.mjs > /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/tests-e2e-rust/fixtures/counter-ts-state.json

cat /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/tests-e2e-rust/fixtures/counter-ts-state.json
```

Expected: a JSON file with two fields — `stateHex` (the serialized ChargedState as hex) and `counterValue` (the integer counter value, which should be `"1"` because BigInt).

If `cr.encode` doesn't exist, use the appropriate canonical serializer from `@midnight-ntwrk/compact-runtime`; check `runtime/src/index.ts` for the right export name. The goal is a deterministic byte representation we can compare against the Rust path's serializer.

- [ ] **Step 2: Commit the fixture**

```bash
git add tests-e2e-rust/fixtures/counter-ts-state.json
git commit -S -s -m "$(cat <<'EOF'
tests-e2e-rust: capture TS reference state for counter.compact

After init + one increment(), serialize ChargedState canonically and
record the hex bytes + decoded counter value. The Rust parity test
will assert byte equality + value equality against this snapshot.

The fixture is checked in so the test is hermetic — no need to
re-run the TS path on every CI run.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task E2: Cargo workspace for tests-e2e-rust

**Files:**
- Create: `tests-e2e-rust/Cargo.toml`
- Create: `tests-e2e-rust/src/lib.rs`
- Modify: `Cargo.toml` (workspace root)
- Modify: `.gitignore`

- [ ] **Step 1: Add tests-e2e-rust to workspace**

In the root `Cargo.toml`:

```toml
[workspace]
resolver = "3"
members = ["tools/*", "runtime-rs", "tests-e2e-rust"]
```

- [ ] **Step 2: Create tests-e2e-rust/Cargo.toml**

```toml
[package]
name        = "tests-e2e-rust"
version     = "0.1.0"
edition     = "2021"
license     = "Apache-2.0"
publish     = false
description = "Cross-language byte-parity tests for compactc --rust output."

[lib]
path = "src/lib.rs"

[dependencies]
compact-runtime = { path = "../runtime-rs" }
serde       = { version = "1",   features = ["derive"] }
serde_json  = "1"
hex         = "0.4"
```

- [ ] **Step 3: Create a tiny helper lib**

`tests-e2e-rust/src/lib.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Helpers for cross-language byte-parity tests. Each test loads a TS
// reference state (captured to JSON under fixtures/), drives the
// equivalent Rust path, and asserts byte equality.

use serde::Deserialize;
use std::path::Path;

#[derive(Deserialize, Debug)]
pub struct TsReferenceState {
    #[serde(rename = "stateHex")]
    pub state_hex: String,
    #[serde(rename = "counterValue")]
    pub counter_value: String, // BigInt comes back as a string
}

impl TsReferenceState {
    pub fn load(path: impl AsRef<Path>) -> Self {
        let raw = std::fs::read_to_string(path).expect("read fixture");
        serde_json::from_str(&raw).expect("parse fixture")
    }

    pub fn state_bytes(&self) -> Vec<u8> {
        hex::decode(&self.state_hex).expect("decode hex")
    }
}
```

- [ ] **Step 4: Add target/ to gitignore**

Append to root `.gitignore`:

```
tests-e2e-rust/target/
```

- [ ] **Step 5: Verify it builds**

```bash
cargo check -p tests-e2e-rust 2>&1 | tail -5
```

Expected: `Finished` with no errors.

- [ ] **Step 6: Commit**

```bash
git add Cargo.toml tests-e2e-rust/ .gitignore
git commit -S -s -m "$(cat <<'EOF'
tests-e2e-rust: scaffold byte-parity workspace

Pulls in serde_json and hex for loading TS reference snapshots,
plus the local compact-runtime crate for driving the Rust path.

Subsequent commits add counter.rs (the parity test for counter.compact).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task E3: Counter byte-parity test

**Files:**
- Create: `tests-e2e-rust/tests/counter.rs`
- Modify: `tests-e2e-rust/Cargo.toml` (add a build-script if needed)

This test:
1. Runs `compactc --rust counter.compact` at test-time (via a build.rs or via a fixed pre-built path).
2. Imports the generated `lib.rs` somehow — easiest: read it as bytes and assert it contains the expected structure, then drive `compact-runtime` directly to reproduce the post-increment state.
3. Compares the resulting state against `fixtures/counter-ts-state.json`.

Because compiling generated Rust at test-time inside another cargo crate is awkward, the cleanest approach is: the test drives the runtime crate directly using the same Op sequence the generator emits, then asserts byte parity. The codegen snapshot test (Task D1) ensures the actual emitter produces matching Op sequences.

- [ ] **Step 1: Write the parity test**

Create `tests-e2e-rust/tests/counter.rs`:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Counter.compact byte-parity test.
//
// 1. Drive the Rust runtime through the same Op sequence the emitter
//    produces for counter.compact (init + one increment).
// 2. Serialize the resulting ChargedState canonically.
// 3. Compare byte-for-byte against the TS reference (fixtures/counter-ts-state.json).
//
// This is the v1 correctness signal. If it stays green, the Rust path
// reproduces TS state transitions for counter.compact.

use compact_runtime::std_lib::Counter;
use compact_runtime::*;
use midnight_serialize::Serializable;
use tests_e2e_rust::TsReferenceState;

#[test]
fn counter_init_plus_increment_byte_parity() {
    // Step 1: reproduce the TS init+increment sequence in Rust.
    let initial = StateValue::Array(Array::new().push(StateValue::from(AlignedValue::from(0u64))));
    let state = ChargedState::new(initial);
    let qctx = QueryContext::new(state, ContractAddress::default());

    let ops: Vec<Op<ResultModeVerify>> = vec![
        Op::Idx {
            cached: false,
            push_path: true,
            path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
        },
        Op::Addi { immediate: 1 },
        Op::Ins { cached: true, n: 1 },
    ];
    let results = qctx.query(&ops, None, &INITIAL_COST_MODEL).expect("query");
    let final_state = results.context.state;

    // Step 2: serialize.
    let mut buf = Vec::new();
    final_state.serialize(&mut buf).expect("serialize");

    // Step 3: load TS reference + compare.
    let ts_ref = TsReferenceState::load("fixtures/counter-ts-state.json");
    let ts_bytes = ts_ref.state_bytes();
    assert_eq!(
        buf, ts_bytes,
        "Rust state bytes differ from TS reference. \nRust: {}\nTS:   {}",
        hex::encode(&buf), hex::encode(&ts_bytes)
    );

    // Step 4: cross-check counter value matches what TS reported.
    // Walk to the counter at index [0] from the final array.
    let arr = match final_state {
        StateValue::Array(a) => a,
        _ => panic!("expected Array"),
    };
    let cell = arr.get(0).expect("first elem");
    let val = Counter::decode_from(&cell).expect("decode");
    let ts_val: u64 = ts_ref.counter_value.parse().expect("parse u64");
    assert_eq!(val, ts_val);
}
```

If the upstream `midnight-serialize::Serializable` API differs slightly, adjust to whatever the crate's canonical serializer is (look in `~/.cargo/registry/src/.../midnight-serialize-1.1.0/src/lib.rs`).

- [ ] **Step 2: Run the test**

```bash
cargo test -p tests-e2e-rust --test counter 2>&1 | tail -10
```

Expected: pass. If bytes differ, the most likely culprits are:
- Different `AlignedValue::from(u64)` ordering between TS and Rust → adjust path key alignment in Rust.
- `Op::Ins { cached: true, n: 1 }` expects `cached: false` in TS or vice versa → check the lowering table at `compiler/midnight-ledger.ss:602-606`.
- Different `dummyContractAddress` ↔ `ContractAddress::default()` between TS and Rust → make sure both sides use the same address.

This is the highest-value failure mode in the plan; spend time getting it green.

- [ ] **Step 3: Commit**

```bash
git add tests-e2e-rust/tests/counter.rs
git commit -S -s -m "$(cat <<'EOF'
tests-e2e-rust: byte-parity test for counter.compact

Asserts the Rust runtime + Op sequence the emitter produces yields a
byte-for-byte identical ChargedState to the TS reference (captured in
fixtures/counter-ts-state.json). This is the v1 correctness signal.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task E4: Snapshot test for emitter output

**Files:**
- Create: `compiler/testdir/counter-rust-expected.rs.snap`
- Modify: `compiler/test.ss`

The byte-parity test in Task E3 validates that the Op sequence is right. This task adds a complementary snapshot test that validates the emitter produces a stable lib.rs. The snapshot is captured from the now-working emitter so it reflects exactly what compiles + passes parity.

- [ ] **Step 0: Capture the working emitter's output as the expected snapshot**

```bash
rm -rf /tmp/counter-snap && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk examples/counter.compact /tmp/counter-snap/ && \
  cp /tmp/counter-snap/contract/lib.rs compiler/testdir/counter-rust-expected.rs.snap
```

Open the snapshot in an editor and verify it looks like Design Appendix B's worked example structurally (Contract struct, initial_state, increment, ledger fn, Ledger struct + round() method). Bytes don't have to match Appendix B verbatim — only the structure.

- [ ] **Step 1: Add the snapshot test**

In `compiler/test.ss`, find the section of TS emission tests (search for `print-typescript` test invocations). After them, add a new test:

```scheme
  (test
    "counter --rust emission"
    `((source-file "examples/counter.compact"))
    (output-file 'contract.rs "contract/lib.rs"
      (returns
        ,(call-with-input-file "compiler/testdir/counter-rust-expected.rs.snap"
           get-string-all))))
```

The exact syntax depends on the existing test machinery — read other tests in `test.ss` that compare against `compiler/testdir/*` snapshots to find the right pattern. The key behaviour: run `compactc --rust counter.compact` (or its in-process equivalent), capture the emitted `contract/lib.rs`, and compare against the snapshot.

The `with-emit-rust` parameter wrapper around the test should toggle `(emit-rust #t)` before running.

- [ ] **Step 2: Run the test**

```bash
./compiler/go 2>&1 | tail -10
```

Expected: tests pass. If the snapshot diff fails, hand-review the actual vs expected output — if the actual is correct and the snapshot is wrong, update the snapshot.

- [ ] **Step 3: Commit**

```bash
git add compiler/test.ss
git commit -S -s -m "$(cat <<'EOF'
compiler/test: snapshot test for counter.compact --rust output

Regression guard for the rust-passes emitter. Compares the generated
contract/lib.rs against the committed snapshot in
testdir/counter-rust-expected.rs.snap. A mismatch fails the test;
intentional output changes require updating the snapshot.

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

### Task E5: Plan-completion verification

**Files:** none.

- [ ] **Step 1: Full compiler test suite**

```bash
nix develop --command bash -c "./compiler/go" 2>&1 | tail -10
```

Expected: `tests passed: N (with N including the new counter-rust test).`

- [ ] **Step 2: Full Rust workspace tests**

```bash
cargo test --workspace 2>&1 | tail -15
```

Expected: all suites pass (compact-runtime tests + tests-e2e-rust counter parity test).

- [ ] **Step 3: Clippy clean**

```bash
cargo clippy --workspace --all-targets -- -D warnings 2>&1 | tail -10
```

Expected: no output beyond `Finished`.

- [ ] **Step 4: Smoke the full pipeline end-to-end**

```bash
rm -rf /tmp/counter-final && \
  $(ls /nix/store/*-compact-all/bin/compactc | head -1) --rust --skip-zk \
    examples/counter.compact /tmp/counter-final/ && \
  ls /tmp/counter-final/contract/
```

Expected: at minimum `index.js`, `index.d.ts`, `lib.rs`, `Cargo.toml` in the contract directory.

```bash
cd /tmp/counter-final/contract && \
  sed -i.bak 's|^compact-runtime = .*|compact-runtime = { path = "/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/runtime-rs" }|' Cargo.toml && \
  cargo build 2>&1 | tail -5
```

Expected: `Finished`. **This is the M2 milestone gate.**

- [ ] **Step 5: Document completion in the spec**

Update `docs/superpowers/specs/2026-05-25-rust-codegen-design.md` Section 7 (phasing table) to mark M1 and M2 as ✅ Complete.

```bash
git add docs/superpowers/specs/2026-05-25-rust-codegen-design.md
git commit -S -s -m "$(cat <<'EOF'
docs: mark M1 and M2 milestones complete

M1: compact-runtime crate shipped (re-exports + facade aggregates +
helpers + integration tests).
M2: compactc --rust counter.compact emits a working Rust crate that
byte-parity-matches the TS path.

Next: M3 follow-up plan extends emitter coverage to tiny.compact and
proposal.compact (witnesses, enums, multiple ledger fields).

Co-Authored-By: Claude Opus 4.6 (1M context) <noreply@anthropic.com>
EOF
)"
```

---

## Done definition

This plan is complete when:

1. `cargo test --workspace` passes from a clean clone.
2. `./compiler/go` passes from a clean clone.
3. `compactc --rust --skip-zk examples/counter.compact /tmp/out/` emits a `lib.rs` + `Cargo.toml` that:
   - Builds with `cargo build` against `compact-runtime`.
   - Reproduces the TS-path's post-increment `ChargedState` byte-for-byte (verified by `tests-e2e-rust/tests/counter.rs`).
4. The branch is pushed to `origin/codegen-rust` on the user's fork with each commit GPG-signed (`G`) and DCO-signed-off.

## Follow-up plans (out of scope here)

- **M3:** Extend emitter to `tiny.compact` (witnesses + enum + multiple circuits) and `proposal.compact` (multiple ledger fields + Cell/Map ADTs). Will need to land struct/enum manual impls of `Aligned`/`FieldRepr`/`FromFieldRepr` in `runtime-rs/src/std_lib.rs` and a real IR-walk in `rust-passes.ss`.
- **M4:** `async` cargo feature on `compact-runtime` + `AsyncWitnesses<PS>` trait emission.
- **M5:** `wasm` cargo feature + wasm-bindgen layer for browser dApps.
- **M6:** Documentation polish, examples, CI wiring, upstream contribution of enum derives to `midnight-base-crypto-derive`.
