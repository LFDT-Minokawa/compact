# Compact → Rust codegen — Implementation design spec

**Author:** ysh
**Date:** 2026-05-25
**Status:** Design approved by author. Ready for `writing-plans` to turn into an executable plan.
**Companion:** `2026-05-25-rust-codegen-feasibility.md` (the "why and is-this-feasible" doc).
**Validated by:** Spike at `spike/` (compiles against real published Midnight crates; byte-structurally matches real `compactc` output for counter.compact).

---

## 1. Goals

1. Add a `--rust` flag to `compactc` that, alongside the existing TypeScript
   output, emits a native Rust crate equivalent to the generated
   `contract/index.{js,d.ts}` files.
2. Ship a new sibling runtime crate (`runtime-rs/` → `compact-runtime` on
   crates.io eventually) that mirrors the TS `runtime/`'s public surface in
   Rust.
3. Generated Rust must be usable from server services (async/tokio), CLI
   tools (sync, std), and browser dApps (wasm-bindgen) without per-app
   forks. Feature flags on `compact-runtime` distinguish the shapes; the
   per-contract generated code stays identical.
4. Preserve full backward compatibility: an invocation that does not pass
   `--rust` behaves byte-for-byte as it does today.

## 2. Non-goals

1. Refactoring the existing TS codegen path or extracting a shared
   "emit-target" abstraction.
2. Building a Rust equivalent of `midnight-js`, the wallet, or the dApp
   connector. Generated Rust contracts are libraries; orchestration is the
   caller's problem.
3. Publishing `midnight-zkir-v3` (out of scope — owned by the Midnight
   ledger team).
4. End-to-end runtime semantic parity verification in v1. Byte-parity of
   the Op program against the TS output is the v1 correctness signal;
   semantic state-transition parity is the v1.1 follow-up.

## 3. Architecture overview

### 3.1 Repository layout

```
compact/                            (this repo)
├── compiler/                       Chez Scheme — existing
│   ├── compactc.ss                 + add `--rust` flag (~10 LOC)
│   ├── passes.ss                   + add emit-rust branch in generate-everything (~15 LOC)
│   ├── ledger.ss                   consume the existing rust-type field in declare-ledger-type
│   ├── midnight-natives.ss         + add rust-name to declare-native-entry rows
│   ├── typescript-passes.ss        unchanged
│   └── rust-passes.ss              NEW — analogous to typescript-passes.ss
│
├── runtime/                        existing TS runtime — unchanged
│
├── runtime-rs/                     NEW — Rust runtime facade
│   ├── Cargo.toml
│   ├── README.md
│   └── src/
│       ├── lib.rs                  curated re-exports + module declarations
│       ├── context.rs              CircuitContext / ConstructorContext aggregates
│       ├── witness.rs              WitnessContext + NoWitnesses marker
│       ├── results.rs              CircuitResults / ConstructorResult
│       ├── version.rs              check_runtime_version! macro
│       ├── built_ins.rs            keccak256, max_field, optional add_field/sub_field/mul_field
│       ├── zswap.rs                empty_zswap_local_state helper
│       └── error.rs                CompactError type
│
└── tests-e2e/                      add a `rust-output/` subdirectory parallel to TS
```

### 3.2 Pipeline integration

```
.compact source
    ↓
Lparser → Lsrc → Lexpr → Lflat → Lnodisclose
    ↓
analysis-passes, save-contract-info-passes
    ↓
prepare-for-typescript ── Ltypescript ──┬──→ print-typescript → contract/index.{js,d.ts}
                                        │
                                        └──→ print-rust → contract/lib.rs   ← NEW
    ↓
circuit-passes → zkir-(v2|v3)-passes
    ↓
zkir/*.zkir
```

The TS and Rust emitters share the same `Ltypescript` IR — there is no
parallel `Lrust` and no shared abstraction (matching the existing
TS/ZKIR split).

## 4. The `compact-runtime` crate (runtime-rs)

### 4.1 Curated re-exports

These are the symbols generated code references directly. The Rust crate
prelude looks like the following (full paths are the actual crate lib names
verified against the spike — note the `midnight_` prefix on each):

```rust
// Encoding / alignment / value bus.
pub use midnight_base_crypto::fab::{Aligned, AlignedValue, Alignment, Value};

// Field arithmetic + proof-system primitives.
pub use midnight_transient_crypto::curve::{Fr, EmbeddedGroupAffine as JubjubPoint};
pub use midnight_transient_crypto::repr::{FieldRepr, FromFieldRepr};
pub use midnight_transient_crypto::merkle_tree::{MerkleTreeDigest, MerklePath, MerklePathEntry};

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
pub use midnight_coin_structure::coin::{Info as CoinInfo, QualifiedInfo as QualifiedShieldedCoinInfo, PublicKey as CoinPublicKey};
pub use midnight_coin_structure::transfer::Recipient;
pub use midnight_coin_structure::contract::ContractAddress;

// Storage backend.
pub use midnight_storage::db::{DB, InMemoryDB};
pub use midnight_storage::DefaultDB;
pub use midnight_storage::storage::Array;

// Hashes (re-exported as bare names — usability win over fully-qualified paths).
pub use midnight_transient_crypto::hash::{hash_to_curve, transient_commit, transient_hash};
pub use midnight_base_crypto::hash::{persistent_commit, persistent_hash};

// Zswap local state.
pub use midnight_zswap::local::State as ZswapLocalState;
```

### 4.2 Facade aggregates

These are the only types `compact-runtime` defines from scratch. Each is a
small bundle of existing crate types in the shape the compiler emits
references to.

```rust
pub struct CircuitContext<PS, D = DefaultDB>
where D: DB {
    pub current_private_state: PS,
    pub current_query_context: QueryContext<D>,
    pub current_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}

pub struct ConstructorContext<PS, D = DefaultDB>
where D: DB {
    pub initial_private_state: PS,
    pub empty_zswap_local_state: ZswapLocalState<D>,
    pub cost_model: CostModel,
    pub gas_limit: Option<RunningCost>,
}

pub struct WitnessContext<L, PS, D = DefaultDB>
where D: DB {
    pub ledger: L,
    pub private_state: PS,
    pub contract_address: ContractAddress,
    pub query_context: QueryContext<D>,
}

pub struct CircuitResults<PS, R, D = DefaultDB>
where D: DB {
    pub result: R,
    pub context: CircuitContext<PS, D>,
    pub gas_cost: RunningCost,
}

pub struct ConstructorResult<PS, D = DefaultDB>
where D: DB {
    pub current_contract_state: ChargedState<D>,
    pub current_private_state: PS,
    pub current_zswap_local_state: ZswapLocalState<D>,
}
```

The `Witnesses<PS>` "trait" is actually emitted per-contract by the codegen
(see §5.4) — it's not in `compact-runtime` because the method signatures
vary per contract. `compact-runtime` provides a `NoWitnesses` marker type
that the codegen uses as the default bound when a contract declares zero
witnesses.

### 4.3 Macros & helpers

```rust
#[macro_export]
macro_rules! check_runtime_version {
    ($expected:literal) => {
        const _: () = assert!(
            $crate::version::const_str_eq($expected, $crate::version::COMPACT_RUNTIME_VERSION),
            "compact-runtime version mismatch"
        );
    };
}

pub fn max_field() -> Fr { -Fr::from(1u64) }
pub fn keccak256(bytes: &[u8]) -> [u8; 32] { /* sha3 crate */ }
pub fn empty_zswap_local_state(cpk: &CoinPublicKey) -> ZswapLocalState { /* ... */ }

// Optional named-function forms over `Fr` operators.
#[inline] pub fn add_field(a: Fr, b: Fr) -> Fr { a + b }
#[inline] pub fn sub_field(a: Fr, b: Fr) -> Fr { a - b }
#[inline] pub fn mul_field(a: Fr, b: Fr) -> Fr { a * b }
```

### 4.4 Cargo features

```toml
[features]
default = ["std"]
std     = []
async   = ["dep:async-trait"]
wasm    = ["dep:wasm-bindgen", "dep:js-sys", "dep:serde-wasm-bindgen"]
serde   = ["dep:serde"]
```

- `default` / `std` — sync trait surface. Fits CLI tools and any server
  service that wraps async I/O on the outside.
- `async` — adds parallel `AsyncWitnesses<PS>` traits via `async_trait`. A
  small `BlockingWitnesses<A>` adapter so an `AsyncWitnesses` impl can
  satisfy `Witnesses` from sync callers via `block_on`.
- `wasm` — adds `wasm-bindgen` glue exporting a JS-friendly contract API +
  a JS-callback adapter for the `Witnesses` trait.
- `serde` — opt-in `Serialize`/`Deserialize` derives on facade aggregates.

### 4.5 Versioning & release alignment

- `compact-runtime`'s major version tracks `midnight-onchain-runtime`'s
  major version (matches what the TS facade does relative to
  `@midnight-ntwrk/onchain-runtime-v3`).
- Generated Rust pins a compatible range via `check_runtime_version!()`
  expanded at the contract's compile time.
- Release cadence follows the existing compactc release cadence — every
  compactc release ships matched runtime/, runtime-rs/, and the npm
  package together.

## 5. Compiler changes (`compiler/`)

### 5.1 CLI flag

`compiler/compactc.ss` — add `--rust` alongside existing flags (current
flag set is in lines 86–122). The flag is purely additive; with `--rust`
and without `--skip-ts` (a new no-op default), both backends emit. If the
user wants Rust *only*, they pass `--skip-ts` (new) in addition.

### 5.2 Pipeline branch

`compiler/passes.ss::generate-everything` — after `prepare-for-typescript`
runs (which registers type descriptors and dedups types), branch:

```scheme
(when (typescript-output?)
  (with-target-ports '((contract.d.ts . "contract/index.d.ts")
                       (contract.js   . "contract/index.js"))
    (print-typescript ltypescript-ir)))

(when (rust-output?)                                              ;; NEW
  (with-target-ports '((contract.rs . "contract/lib.rs"))
    (print-rust ltypescript-ir)))
```

### 5.3 The new `rust-passes.ss`

Mirrors `typescript-passes.ss`'s structure. One module, walks `Ltypescript`,
calls `printf`/`display-string` against `(get-target-port 'contract.rs)`.

Major emitted constructs (described in §5.4–§5.8 below).

### 5.4 Codegen mapping reference

| TS output | Rust output |
|---|---|
| `import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';` | `use compact_runtime::*;` |
| `__compactRuntime.checkRuntimeVersion('0.16.100');` | `compact_runtime::check_runtime_version!("0.16.100");` |
| `class CompactTypeFoo { alignment(); toValue(v); fromValue(v); }` | `impl Aligned for Foo`, `impl FieldRepr for Foo`, `impl FromFieldRepr for Foo` — manual impls, uniform across struct/enum |
| `export type Witnesses<PS> = { secretKey(ctx, ...): [PS, R]; ... }` | `pub trait Witnesses<PS> { fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, PS>, ...) -> (PS, R); ... }` |
| `export type Circuits<PS>` / `ImpureCircuits` / `PureCircuits` | inherent methods on `impl<PS, W: Witnesses<PS>> Contract<PS, W>` |
| `export declare class Contract<PS, W>` | `pub struct Contract<PS, W: Witnesses<PS>> { witnesses: W, _ps: PhantomData<PS> }` + `pub fn new(w: W) -> Self` |
| `this.circuits = { foo: (ctx, ...) => ... }` (impure/provable) | `pub fn foo(&self, ctx: CircuitContext<PS>, ...) -> Result<CircuitResults<PS, R>, TranscriptRejected<DefaultDB>>` on `impl Contract` |
| `export const pureCircuits = { foo: (...) => ... }` (pure) | `pub mod pure_circuits { pub fn foo(...) -> R { ... } }` — module-level free functions, no `Contract` instance, no `CircuitContext` |
| `export function ledger(state): Ledger` | `pub fn ledger<'a, D: DB>(state: &'a ChargedState<D>) -> Ledger<'a, D>` |
| `assert(cond)` | `assert!(cond)` (panic by default; `Result<_, CompactError>` for declared failure) |
| `disclose(x)` | no-op marker function (matches TS — the check is compile-time) |
| `__compactRuntime.transientHash<T>(v)` | `transient_hash(&v)` (the `<T>` is implicit via Rust generics) |
| `__compactRuntime.queryLedgerState(ctx, pd, prog)` | `ctx.current_query_context.query(&prog, ctx.gas_limit.clone(), &ctx.cost_model)?` — no facade wrapper; no `partialProofData` builder; events are pulled from `QueryResults` after the call |
| Primitive type descriptors (`CompactTypeField`, `CompactTypeBytes<N>`, `CompactTypeUnsignedInteger`, `CompactTypeVector<N,T>`, `CompactTypeBoolean`, `CompactTypeEnum`, `CompactTypeOpaqueString`, `CompactTypeJubjubPoint`) | Plain Rust types — `Fr`, `[u8; N]`, `u64`/`u128`/etc. matched to width, `[T; N]` or `Vec<T>`, `bool`, generated enum, `Vec<u8>`, `JubjubPoint`. No descriptor objects. |
| Ledger ADTs (`Counter`/`Cell<T>`/`Map<K,V>`/`Set<T>`/`MerkleTree<T>`/`List<T>`) | Use the `rust-type` field already declared in `ledger.ss:36` per ADT; each maps to a typed wrapper around `StateValue::{Cell, Map, ...}` already in `midnight-onchain-state` |

### 5.5 Type-descriptor emission (struct/enum case)

For a user-declared struct or enum, the emitter produces a manual impl of
`Aligned`, `FieldRepr`, and `FromFieldRepr` rather than `#[derive(...)]`:

- `Aligned` has no derive macro upstream — always manual.
- `FieldRepr` / `FromFieldRepr` derives exist but panic on enums; emitting
  manual impls uniformly avoids a per-type branch in the emitter.
- Future work: contribute enum derive support upstream and switch to
  derives. Doing this now would add risk for marginal gain.

Manual impl shape:

```rust
impl Aligned for STATE {
    fn alignment() -> Alignment {
        Alignment::singleton(AlignmentAtom::Bytes { length: 1 })
    }
}
impl FieldRepr for STATE { fn field_repr<W: MemWrite<Fr>>(&self, w: &mut W) { ... } fn field_size(&self) -> usize { 1 } }
impl FromFieldRepr for STATE { const FIELD_SIZE: usize = 1; fn from_field_repr(r: &[Fr]) -> Option<Self> { ... } }
```

### 5.6 Witness emission

For a contract with one witness `witness secretKey(): Bytes<32>`:

```rust
pub trait Witnesses<PS> {
    fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, PS>) -> (PS, [u8; 32]);
}
```

The contract is generic over `W: Witnesses<PS>`. The user supplies a struct
implementing the trait. For contracts with zero witnesses, the codegen
emits an empty trait and a blanket `impl<PS> Witnesses<PS> for NoWitnesses
{}`, and defaults `W = NoWitnesses` on `Contract`.

`async` feature: codegen additionally emits an `AsyncWitnesses<PS>` trait
with the same methods marked `async`, via `#[async_trait::async_trait]`.

### 5.6.1 Pure-circuit emission

In TS, `pureCircuits` is a top-level exported object, not a Contract
method (it carries no context). In Rust, pure circuits become free
functions in a `pub mod pure_circuits` submodule of the generated crate.
Compact source `circuit foo(x: Field): Field { ... }` (pure) becomes
`pub fn foo(x: Fr) -> Fr { ... }` under `mod pure_circuits`. No
`Contract` instance or `CircuitContext` needed.

### 5.7 `initialState()` emission

Mirrors the TS `Contract.initialState(constructorContext)`. The emitter
constructs the initial `StateValue::Array` for the contract's ledger,
seeds each field with its declared initial value (e.g., `Counter`'s
`state-value 'cell (align 0 8)` becomes `StateValue::Cell(0u64)` lowered
through `push`+`push`+`ins` Op sequences identical to the TS path), and
returns `ConstructorResult` with the resulting `ChargedState` and
`ZswapLocalState`.

### 5.8 `ledger()` view function

```rust
pub fn ledger<'a, D: DB>(state: &'a ChargedState<D>) -> Ledger<'a, D> {
    Ledger { state }
}

pub struct Ledger<'a, D: DB = DefaultDB> { state: &'a ChargedState<D> }

impl<'a, D: DB> Ledger<'a, D> {
    pub fn round(&self) -> u64 {
        // Op program: dup -> idx[path 0] -> popeq, then decode AlignedValue → u64
        ...
    }
}
```

Each ledger field becomes a method on `Ledger<'a, D>` (matching the TS
getters). The Op program is the same dup+idx+popeq pattern the TS emits.

### 5.8.1 Compact standard library mapping

`CompactStandardLibrary` exposes a handful of generic types and functions
that every contract may use. The Rust equivalents live in
`compact-runtime::std_lib`:

| Compact | Rust |
|---|---|
| `Maybe<T>` (`is_some: Bool`, `value: T`) | `Option<T>` (with manual `Aligned`/`FieldRepr`/`FromFieldRepr` blanket impls for `T: Aligned + FieldRepr + FromFieldRepr`) |
| `Either<L, R>` (`is_left: Bool`, `left: L`, `right: R`) | `Result<L, R>` (semantics flipped — Compact's `Either` is symmetric; map `is_left=true → Ok`, `is_left=false → Err`) OR a dedicated `Either<L, R>` enum if symmetry matters. Decision: ship dedicated `Either<L, R>` to preserve symmetry. |
| `some<T>(x)` / `none<T>()` | `Some(x)` / `None` |
| `default<T>` | `<T as Default>::default()` — emitted as `Default::default()` with type-annotated context |
| `pad(n, "lit")` | `compact_runtime::pad::<{N}>(b"lit")` — generic length parameter |
| `persistentHash<T>(v)` | `persistent_hash(&v)` — Rust generics infer `T` |
| `transientHash<T>(v)` | `transient_hash(&v)` |
| `Counter` ledger ADT | `compact_runtime::Counter` (newtype over `StateValue::Cell(u64)`) |
| `Cell<T>` ledger ADT | `compact_runtime::Cell<T>` (newtype over `StateValue::Cell(AlignedValue)`) |
| `Map<K, V>` ledger ADT | `compact_runtime::Map<K, V>` (newtype over `StateValue::Map`) |
| `Set<T>` | `compact_runtime::Set<T>` |
| `List<T>` | `compact_runtime::List<T>` |
| `MerkleTree<T>` | `compact_runtime::MerkleTree<T>` |
| `assert(cond)` / `assert(cond, msg)` | `compact_runtime::assert!(cond)` / `compact_runtime::assert!(cond, msg)` — macros that return `Err(CompactError::AssertionFailed(...))` rather than panic (see §5.10.1) |
| `disclose(x)` | `compact_runtime::disclose(x)` — identity function, no-op (the disclose check is enforced at the Compact frontend, before codegen) |

The ledger-ADT newtypes (`Counter`, `Cell<T>`, `Map<K,V>`, etc.) live in
`compact-runtime` rather than in generated code, because their Op-program
methods (e.g., `Counter::read()` emitting `dup+idx+popeq`) are shared
across every contract that uses them. This matches how `runtime/` puts
the corresponding logic in the TS facade rather than inlining it per-
contract.

`compiler/midnight-natives.ss` already declares each native circuit with
its Compact signature and TypeScript name. The Rust addition is a single
new field per row:

```scheme
(declare-native-entry persistent-hash
  (type-formal T)
  ((arg "v" (type-var T)) ...)
  (result Field)
  (typescript "persistentHash")
  (rust       "persistent_hash"))    ;; NEW
```

`rust-passes.ss` reads the `rust` field and emits
`compact_runtime::persistent_hash(...)` accordingly.

### 5.9 Naming conventions

- Compact `camelCase` identifiers → Rust `snake_case`. (`publicKey` →
  `public_key`; `set` stays `set`.)
- Compact `PascalCase` types preserved.
- A reserved-keyword pass mirrors the existing one in
  `prepare-for-typescript` — Rust keywords (`fn`, `mod`, `type`, `match`,
  `enum`, `struct`, `impl`, ...) get `r#` prefix when colliding.

### 5.9.1 Result-mode generic

`Op<M, D>` is parameterised by `M: ResultMode<D>` (`ResultModeVerify` for
non-proving execution, `ResultModeGather` for transcript capture during
proving). Generated circuit methods are generic over `M`:

```rust
pub fn increment<M: ResultMode<DefaultDB>>(
    &self,
    ctx: CircuitContext<PS>,
) -> Result<CircuitResults<PS, ()>, TranscriptRejected<DefaultDB>>
where
    Op<M, DefaultDB>: /* the bounds needed by query() */,
{
    let ops: Vec<Op<M, DefaultDB>> = vec![ /* same shape as spike */ ];
    let results = ctx.current_query_context.query::<M>(&ops, ...)?;
    Ok(CircuitResults { /* ... */ })
}
```

In practice, generated code uses two top-level entry points per circuit:
a thin `pub fn verify_increment(...)` that pins `M = ResultModeVerify`,
and `pub fn prove_increment(...)` that pins `M = ResultModeGather` and
returns the gathered transcript alongside `CircuitResults`. This matches
the way the TS path distinguishes `impureCircuits` (verify-only execution)
from `provableCircuits` (transcript-gathering for the proof system).

### 5.10.1 Error handling

Compact's `assert(cond, "msg")` aborts the circuit. The Rust equivalent
returns `Err(CompactError::AssertionFailed(msg))` rather than panicking
— panic in a contract executed inside a server process would crash the
whole service. Generated code propagates with `?`:

```rust
pub fn clear(&self, ctx: CircuitContext<PS>) -> Result<CircuitResults<PS, ()>, CompactError> {
    compact_runtime::assert!(self.in_state(STATE::Set), "clear: no value is currently recorded")?;
    /* ... */
}
```

`TranscriptRejected<D>` from the VM is `From`-converted into `CompactError`
so a circuit's signature only needs one error type. Generated code uses
`Result<CircuitResults<PS, R>, CompactError>` uniformly.

### 5.10.2 Witness trait lifetimes

The witness trait takes `&WitnessContext<Ledger<'_>, PS>`. `Ledger<'a, D>`
borrows from `ChargedState<D>`. To let a single witness impl be called
across different state borrows, the trait uses higher-ranked trait bounds:

```rust
pub trait Witnesses<PS> {
    fn secret_key<'a>(
        &self,
        ctx: &WitnessContext<Ledger<'a>, PS>,
    ) -> (PS, [u8; 32]);
}
```

The HRTB is emitted automatically by the codegen — the user's impl writes
`fn secret_key<'a>(&self, ctx: ...) -> ...` and the compiler ensures the
trait is implementable for any caller's lifetime.

### 5.10.3 Cargo.toml emission

`compactc --rust` emits two artifacts when the target directory does not
contain an existing `Cargo.toml`:

1. `contract/lib.rs` — the generated Rust source.
2. `contract/Cargo.toml` — a minimal manifest declaring `compact-runtime`
   as the sole dependency:

```toml
[package]
name = "<contract-name>"
version = "0.1.0"
edition = "2021"

[lib]
path = "lib.rs"

[dependencies]
compact-runtime = "<pinned-version>"
```

If a `Cargo.toml` already exists in the target directory, the compiler
only emits `lib.rs` and prints a hint about the required `compact-runtime`
dep. This matches what the TS path does today with `package.json`.

### 5.11 Sourcemaps

v1 deferred. The TS path emits `.js.map`; the equivalent for Rust is a
custom format that `rust-analyzer`/`cargo` won't natively consume. Defer
until there's a concrete debugging-experience requirement.

## 6. Testing

### 6.1 Unit tests in `rust-passes.ss`

Follow the existing `compiler/test.ss` convention — `(returns ...)`,
`(oops ...)`, etc. — for each major emit construct (struct alignment, enum
field_repr, single-circuit class, ledger view, witness trait).

### 6.2 E2E suite: `tests-e2e/rust-output/`

New parallel directory. For each `.compact` test:

1. Run `compactc --rust --skip-zk` on the source.
2. Drop the generated `contract/lib.rs` into a templated cargo project
   (workspace pinning the production `compact-runtime` version).
3. `cargo check` — gate 1: types resolve.
4. `cargo test` — gate 2: hand-written exercise tests for the contract
   complete without panic.

### 6.3 Cross-language byte parity (v1 correctness signal)

For each test contract, run both `--rust` and the default TS emission.
For a fixed initial state and a fixed sequence of circuit calls:

1. Execute the TS contract via `@midnight-ntwrk/compact-runtime` (using
   `runtime/test/` harness as a model).
2. Execute the Rust contract via `compact-runtime` directly.
3. Compare the resulting `ChargedState` after each step byte-for-byte
   (`Serializable` round-trip both sides → equal byte vectors).
4. Compare the public transcript byte-for-byte.

This proves correctness at the level of "the Rust output produces the
same state machine as the TS output". Full ZK proof verification is v1.1.

### 6.4 Initial coverage targets

- `examples/counter.compact` — single field, no witnesses, single
  impure circuit. (Already covered by the spike.)
- `examples/tiny.compact` — witness trait + enum + constructor +
  multiple circuits + hashing.
- `examples/proposal.compact` — exercises more ledger ADTs.

## 7. Phasing & milestones

| Phase | Deliverable | Effort | Status |
|---|---|---|---|
| **M1** | `compact-runtime` v0.1.0 published from `runtime-rs/`. Compiles, ships re-exports + facade aggregates + macro. Covered by unit tests. | 1w | ✅ Complete |
| **M2** | `compactc --rust counter.compact` produces a `contract/lib.rs` that compiles via `cargo check` and matches the TS Op program byte-for-byte. Foundational `rust-passes.ss` skeleton. | 2w | ✅ Complete |
| **M3** | `tiny.compact` + `proposal.compact` working — full struct/enum/witness/hash coverage. Cross-language byte-parity harness running in CI. | 2w | pending |
| **M4** | `compact-runtime` feature `async` + emitter support. `AsyncWitnesses` exercised in a server-shape sample. | 1w | pending |
| **M5** | `compact-runtime` feature `wasm` + emitter support. Browser-loadable sample shipped. | 2w | pending |
| **M6** | Documentation, examples, public announcement, contribution of enum derive to `midnight-base-crypto-derive`. | 1w | pending |
| **Total v1 (M1–M3)** | sync/std Rust path, byte-parity with TS, covered by CI | **5w** | M1+M2 ✅ |
| **Total full (M1–M6)** | adds async + wasm + docs + upstream cleanups | **9w** | M1+M2 ✅ |

## 8. Risks & mitigations

(See feasibility doc §5 — same register, not duplicated.)

## 9. Open decisions

1. **Repo location for `runtime-rs/`** — same monorepo (this design's
   assumption) vs separate `midnight-compact-runtime-rs` repo. Defer to
   the LFDT-Minokawa governance decision.
2. **Crate name** — `compact-runtime` (matches TS package name) vs
   `midnight-compact-runtime` (matches existing crates.io prefix
   convention). Recommend the latter for consistency with the
   `midnight-*` ecosystem; document `compact-runtime` as a local
   convenience alias.
3. **`async` trait machinery** — `async_trait` (v1) vs AFIT (v2). Defer.
4. **Whether `--skip-ts` should be added now** for users who want
   Rust-only output, or deferred until someone asks. Defer.

## 10. Acceptance criteria for the design

A reviewer should be able to:

- Identify, from this document alone, where every change in the compiler
  must go (file + reason).
- Predict, for any TS construct in the current `print-typescript` output,
  what the Rust equivalent looks like.
- Run the v1 acceptance test: `compactc --rust counter.compact` → drop
  into a cargo project against published `compact-runtime` → `cargo
  check` passes → state-transition byte-parity vs TS holds for an
  agreed sequence of inputs.

## 11. Appendix A — spike artifacts

The spike that validated this design is preserved under `spike/` in this
repo. It contains:

- `spike/runtime-rs/` — minimal `compact-runtime` (110 LOC) exercising the
  re-export + facade-aggregate pattern.
- `spike/counter-contract/` — hand-translated `counter.compact` against the
  spike runtime. Compiles clean.

The spike is throwaway: the v1 implementation reuses the design but starts
from a clean slate. Keep `spike/` until the v1 PR lands as a reference for
reviewers who want to see the design's compile-time validity outside the
implementation work itself.

## 12. Appendix B — complete worked example: counter.compact → contract/lib.rs

Given `examples/counter.compact`:

```compact
import CompactStandardLibrary;
export ledger round: Counter;
export circuit increment(): [] { round.increment(1); }
```

`compactc --rust counter.compact` would emit `contract/lib.rs`:

```rust
// Generated by compactc 0.31.103. Do not edit by hand.
// SPDX-License-Identifier: Apache-2.0

#![allow(clippy::all, dead_code, unused_imports, unused_variables)]

use compact_runtime::*;
use std::marker::PhantomData;

compact_runtime::check_runtime_version!("0.16.100");

// ---- Witnesses (none declared in source) ----
pub trait Witnesses<PS> {}
impl<PS> Witnesses<PS> for NoWitnesses {}

// ---- Contract ----
pub struct Contract<PS, W = NoWitnesses>
where
    W: Witnesses<PS>,
{
    pub witnesses: W,
    _ps: PhantomData<PS>,
}

impl<PS, W> Contract<PS, W>
where
    W: Witnesses<PS>,
{
    pub fn new(witnesses: W) -> Self {
        Self { witnesses, _ps: PhantomData }
    }

    /// Initial state: seed `round` with a `Counter` set to 0.
    pub fn initial_state(
        &self,
        ctx: ConstructorContext<PS>,
    ) -> Result<ConstructorResult<PS>, CompactError> {
        let initial_state = StateValue::new_array();
        let initial_state = initial_state.array_push(StateValue::new_null());

        let mut state = ContractState::default();
        state.data = ChargedState::new(initial_state);
        state.set_operation(
            "increment".into(),
            ContractOperation::default(),
        );

        let qctx = QueryContext::new(state.data.clone(), dummy_contract_address());
        let ops: Vec<Op<ResultModeVerify>> = vec![
            Op::Push {
                storage: false,
                value: StateValue::new_cell(AlignedValue::from(0u8)),
            },
            Op::Push {
                storage: true,
                value: StateValue::new_cell(AlignedValue::from(0u64)),
            },
            Op::Ins { cached: false, n: 1 },
        ];
        let results = qctx.query(&ops, ctx.gas_limit.clone(), &ctx.cost_model)?;

        Ok(ConstructorResult {
            current_contract_state: ChargedState::new(results.context.state),
            current_private_state: ctx.initial_private_state,
            current_zswap_local_state: ctx.empty_zswap_local_state,
        })
    }

    /// Circuit: `increment()`.
    pub fn increment(
        &self,
        ctx: CircuitContext<PS>,
    ) -> Result<CircuitResults<PS, ()>, CompactError> {
        let ops: Vec<Op<ResultModeVerify>> = vec![
            Op::Idx {
                cached: false,
                push_path: true,
                path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
            },
            Op::Addi { immediate: 1 },
            Op::Ins { cached: true, n: 1 },
        ];

        let results = ctx
            .current_query_context
            .query(&ops, ctx.gas_limit.clone(), &ctx.cost_model)?;

        Ok(CircuitResults {
            result: (),
            context: CircuitContext {
                current_query_context: results.context,
                ..ctx
            },
            gas_cost: results.gas_cost,
        })
    }
}

// ---- Ledger view ----
pub struct Ledger<'a, D: DB = DefaultDB> {
    state: &'a ChargedState<D>,
}

pub fn ledger<'a, D: DB>(state: &'a ChargedState<D>) -> Ledger<'a, D> {
    Ledger { state }
}

impl<'a, D: DB> Ledger<'a, D> {
    pub fn round(&self) -> Result<u64, CompactError> {
        let qctx = QueryContext::new(self.state.clone(), dummy_contract_address());
        let ops: Vec<Op<ResultModeVerify>> = vec![
            Op::Dup { n: 0 },
            Op::Idx {
                cached: false,
                push_path: false,
                path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]),
            },
            Op::Popeq { cached: true, result: AlignedValue::default() },
        ];
        let results = qctx.query(&ops, None, &CostModel::initial())?;
        Ok(decode_u64(results.events.last().unwrap()))
    }
}

// ---- Pure circuits (none declared) ----
pub mod pure_circuits {}
```

Notes on this worked example:

- The `Op::Push` immediate alignment for the path key is u8 (one byte) — same as the TS `_descriptor_7`, not u64.
- `initial_state` mirrors the TS `Contract.initialState()` Op sequence (`push storage=false 0u8`, `push storage=true 0u64`, `ins n=1`).
- `Ledger::round()` returns `Result<u64, CompactError>` rather than panicking on a malformed state — see §5.10.1.
- `decode_u64` is a small helper provided by `compact-runtime` that converts an `AlignedValue` event to a `u64`. Each primitive Compact type has a corresponding `decode_*` helper.

## 13. Appendix C — comparison of spike output vs real compactc output

For `examples/counter.compact`, the real TS compiler emits:

```js
__compactRuntime.queryLedgerState(context, partialProofData, [
  { idx: { cached: false, pushPath: true, path: [{ tag: 'value', value: ... }] } },
  { addi: { immediate: 1 } },
  { ins: { cached: true, n: 1 } }
]);
```

The spike's hand-translated Rust emits:

```rust
let ops: Vec<Op<ResultModeVerify>> = vec![
    Op::Idx { cached: false, push_path: true, path: Array::from(vec![Key::Value(AlignedValue::from(0u8))]) },
    Op::Addi { immediate: 1 },
    Op::Ins { cached: true, n: 1 },
];
ctx.current_query_context.query(&ops, ctx.gas_limit.clone(), &ctx.cost_model)?;
```

These are structurally identical and will produce the same `ChargedState`
transition. The Rust path is shorter because it does not need a
`partialProofData` builder — proof transcript bytes are pulled from
`QueryResults` after the call.
