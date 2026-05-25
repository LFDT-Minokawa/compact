# Compact → Rust codegen — Feasibility report

**Author:** ysh
**Date:** 2026-05-25
**Status:** Validated by spike. Ready for design-spec sign-off.
**Companion:** `2026-05-25-rust-codegen-design.md` (full implementation spec)

---

## 1. The idea

Today the Compact compiler emits TypeScript that depends on the npm package
`@midnight-ntwrk/compact-runtime`, which is itself a thin facade over the
wasm-compiled `@midnight-ntwrk/onchain-runtime-v3`.

Proposal: add a new compiler flag (working name `--rust`) that emits a native
Rust crate equivalent to the TypeScript output. Generated Rust depends on a
new sibling runtime crate, `compact-runtime` (under `runtime-rs/` in this
repo), which in turn re-exports the published Midnight Rust crates
(`midnight-onchain-runtime`, `midnight-onchain-state`, etc.) that the wasm
packages are built from.

End goal: Compact contracts usable inside native Rust applications — server
services, CLI tools, and (via wasm-bindgen) browser dApps — without going
through the TypeScript path.

This document covers the feasibility judgement. The companion design spec
covers the implementation in detail.

## 2. Verdict

**Go.** The supporting Rust ecosystem already exists and is consumable from
crates.io today. A throwaway validation spike has compiled a hand-translated
contract against the published crates with no design-level surprises.

## 3. What we found

### 3.1 Compiler architecture is friendly to a second backend

- The compiler (Chez Scheme + Nanopass) ends in a pass `print-typescript`
  that walks the post-frontend IR `Ltypescript` and writes the contract files
  directly. ZKIR is a separate, parallel backend on `Lflattened`. There is
  no shared "emit-target" abstraction — each backend is monolithic. The
  pattern we'd follow is identical: a new `print-rust` pass on the same
  `Ltypescript` IR.
- The CLI dispatcher (`compiler/compactc.ss`) parses flags in ~30 lines.
  Adding `--rust` is purely additive — the new branch runs alongside (or
  instead of) the TS emitter, so a single compactc invocation can emit both.
- The codebase already anticipates this. `compiler/ledger.ss:36` declares a
  `rust-type` field on every ledger ADT (currently unused). ZKIR passes carry
  comments like `;; in sync with the rust version.` Someone left the seam.

### 3.2 The required Rust crates are published and consumable

The wasm packages used by the TS runtime are built from
[midnightntwrk/midnight-ledger](https://github.com/midnightntwrk/midnight-ledger),
which publishes the following crates to crates.io. All resolved in the spike:

| Crate | Version | Role |
|---|---|---|
| `midnight-base-crypto` | 1.0.0 | hashing, alignment, encoding |
| `midnight-base-crypto-derive` | 1.0.0 | `#[derive(FieldRepr)]` |
| `midnight-transient-crypto` | 2.1.0 | field arithmetic, JubjubPoint, merkle, hash-to-curve |
| `midnight-onchain-state` | 3.0.0 | `StateValue`, `ContractState`, `ChargedState` |
| `midnight-onchain-vm` | 3.1.0 | `Op<M,D>`, `Key`, cost model |
| `midnight-onchain-runtime` | 3.1.0 | `QueryContext::query`, transcript |
| `midnight-coin-structure` | 2.0.1 | `Recipient`, `ContractAddress`, coin types |
| `midnight-storage` | 2.0.1 | DB-generic state primitives, `Array` |
| `midnight-zswap` | 8.1.0 | `local::State` (zswap local state) |

The flake pins the wasm layer to `ledger-8.0.2`; the crates.io versions
above match that branch.

### 3.3 The new "facade" runtime crate is genuinely thin

A pre-implementation audit was done to check that we wouldn't duplicate any
existing crate. The result:

- **Re-export** (no original code): all hashes (`transient_hash`,
  `persistent_hash`, `transient_commit`, `persistent_commit`, `hash_to_curve`),
  EC operations, `StateValue`, `ChargedState`, `ContractState`, `QueryContext`,
  `Op`, `Key`, `Array`, `Aligned`, `FieldRepr`, `FromFieldRepr`, `Fr`,
  `EmbeddedGroupAffine` (re-exported as `JubjubPoint`), `MerkleTreeDigest`/
  `MerklePath`/`MerklePathEntry`, `Recipient`, `ContractAddress`, coin types,
  `zswap::local::State` (as `ZswapLocalState`), `Fr::{as_le_bytes,
  from_le_bytes}`, `RunningCost`, `CostModel`, `TranscriptRejected`.
- **Genuine additions** (~250–400 LOC total in real implementation):
  facade aggregates `CircuitContext`/`ConstructorContext`/`WitnessContext`/
  `CircuitResults`/`ConstructorResult`, a `Witnesses<PS>` trait alias used by
  the compiler, the `check_runtime_version!` macro, `keccak256` (depending on
  the `sha3` crate), a `max_field()` helper, an `empty_zswap_local_state`
  constructor, named function forms of `add_field`/`sub_field`/`mul_field`
  if we want them (operator-form `+`/`-`/`*` on `Fr` already works), and a
  `CompactError` type.
- **Skip entirely**: all the `Encoded*` types from the TS facade — they exist
  because TS distinguishes a JSON-friendly view from a byte view of the
  same object. Rust uses one canonical type via `Serializable`.

The TS `runtime/` is ~2266 LOC. The Rust `runtime-rs/` is projected at
~300–500 LOC.

### 3.4 Derive macros: partial coverage

- `Aligned` — no derive. Manual impls required.
- `FieldRepr` — derive exists, structs only (panics on enums).
- `FromFieldRepr` — derive exists, structs only.

Practical consequence: the emitter produces manual impls uniformly (matching
how the TS emitter produces explicit `CompactTypeFoo` classes for every
user type). Contributing enum derive support upstream is a future-work item
that lets the emitter switch to `#[derive(...)]` later.

### 3.5 ZKIR is independent of the chosen output language

The Compact compiler emits `.zkir` files separately; an external `zkir` tool
turns them into proving keys. Generated contract code (whether TS or Rust)
loads keys at runtime. The Rust backend inherits this separation unchanged,
so the fact that `midnight-zkir-v3` is unpublished on crates.io (`publish =
false`) is **not** a blocker. The Rust backend consumes proving keys exactly
the same way the TS backend does.

## 4. Validation spike

A throwaway spike was built under `spike/` to validate the design end-to-end
before committing to a full implementation plan.

### 4.1 What was built

```
spike/
├── Cargo.toml             (workspace pinning all 9 Midnight crates)
├── runtime-rs/            ~110 LOC — minimal `compact-runtime` facade
│   └── src/
│       ├── lib.rs         curated re-exports
│       ├── context.rs     CircuitContext / ConstructorContext aggregates
│       ├── witness.rs     WitnessContext + NoWitnesses marker
│       └── version.rs     check_runtime_version! macro
└── counter-contract/      hand-translated examples/counter.compact
    └── src/lib.rs
```

The contract translated:

```compact
import CompactStandardLibrary;
export ledger round: Counter;
export circuit increment(): [] { round.increment(1); }
```

### 4.2 Results

- All 9 Midnight crates resolved from crates.io and built from source in
  ~15s on first build.
- `compact-runtime` stub: compiles clean, no warnings.
- `counter-contract`: compiles clean, no warnings, depending only on
  `compact-runtime` (`Key`, `Array`, etc. are re-exported through the
  facade — generated code never reaches around it).
- Compared the spike's `increment()` Op program byte-for-byte against the
  real TS output (`compactc --skip-zk counter.compact`). The lowering is
  structurally identical: `Op::Idx { cached:false, push_path:true, path:[Key::Value(0)] }`
  → `Op::Addi { immediate:1 }` → `Op::Ins { cached:true, n:1 }`. Same
  sequence as the TS `[ { idx: ... }, { addi: ... }, { ins: ... } ]`.

### 4.3 Corrections surfaced by the spike

| Item | Pre-spike assumption | Reality | Status |
|---|---|---|---|
| `Key` re-export | not listed | needed for `Op::Idx::path` | added to runtime-rs |
| `Array` re-export | not listed | path is `Array<Key, D>` | added to runtime-rs |
| `TranscriptRejected` error | bare type | takes `<D: DB>` generic | plumb DB generic through Results |
| Path key alignment | u64 | u8 (per `_descriptor_7` in real TS) | codegen picks smallest fit |
| `ProofData` builder | flagged as gap | not needed — `QueryContext::query()` returns transcript | removed from runtime-rs scope |
| Crate lib names | shorthand `base_crypto::*` | `midnight_base_crypto::*` (with prefix) | absorbed by facade re-exports |
| `check_runtime_version!` macro | inline helpers | needs `$crate::` qualification | standard macro hygiene |

None are structural problems with the design. All are now reflected in the
companion spec.

## 5. Risk register

| Risk | Severity | Mitigation |
|---|---|---|
| Upstream Rust crates change shape between releases | medium | Pin runtime-rs major version to onchain-runtime major version; run cross-language byte-parity tests on every compiler release |
| `Aligned` lacks a derive macro | low | Emit manual impls (uniform across struct/enum); contribute upstream later |
| Enum derive panics for `FieldRepr`/`FromFieldRepr` | low | Same as above — emit manual impls |
| `midnight-zkir-v3` is `publish = false` | none | ZKIR pipeline is decoupled from contract code; Rust backend doesn't import zkir at all |
| Compile-time cost of pulling 9 crates | low | First-time `cargo build` ~15s; cached after. Generated code itself compiles in <1s |
| No Rust dApp/wallet/SDK exists | medium (scope) | Out of scope for this work (deferred to "option C" in brainstorming). The Rust contract crate is consumed by user-built Rust code today |
| Wasm target divergence | medium | Behind a cargo feature; not required for the v1 deliverable |
| Compiler dev environment is nix-gated | low | First `nix build` of compactc downloads ~1 GB of derivations; CI cache exists at cache.iog.io. Document the warm-up time in the contributor README. |
| Witness lifetime ergonomics | low | HRTB shape (`fn secret_key<'a>(&self, ctx: &WitnessContext<Ledger<'a>, ...>)`) is verified compilable in Rust 1.88+ but slightly less ergonomic for users. Mitigation: provide a `WitnessesExt` extension trait with simpler-looking blanket impls in v1.1. |

## 6. Effort estimate

Rough engineer-week breakdown assuming one full-time engineer familiar with
both Chez Scheme and Rust:

| Workstream | Effort |
|---|---|
| `compact-runtime` Rust crate (the facade) | 1 week |
| `compiler/rust-passes.ss` — codegen pass | 3–4 weeks |
| `compactc.ss` + `passes.ss` integration | 0.5 week |
| `tests-e2e` cross-language byte parity harness | 1 week |
| Documentation, examples, CI wiring | 1 week |
| **Total — v1 (sync, std, default feature)** | **5–7 engineer-weeks** |
| `async` cargo feature (witness trait variant) | +1 week |
| `wasm` cargo feature (wasm-bindgen layer) | +2 weeks |
| Contribute enum derives upstream to midnight-ledger | +0.5 week |
| **Total — full feature matrix** | **8–10 engineer-weeks** |

(Companion design doc breaks v1 into delivery milestones M1–M3 totalling
5 weeks of focused codegen + runtime + cross-language parity harness. The
7-week upper bound here adds slack for docs, CI wiring, and review cycles.)

These are first-cut estimates. The codegen pass is the dominant unknown;
the spike makes the runtime crate and dependency story low-risk.

## 7. Open questions

1. Should `runtime-rs/` ship from this monorepo (LFDT-Minokawa/compact)
   or be its own repo under `midnightntwrk/`? The design assumes the former
   to match where `runtime/` lives today, but ownership/release cadence may
   point elsewhere.
2. Do we publish `compact-runtime` to crates.io, or vendor it from a git
   tag the way the TS runtime depends on a specific ledger commit?
3. Will Midnight publish `midnight-zkir-v3` to crates.io within this work's
   timeline? (Not blocking, but affects how external tooling can verify
   v3-emitted IR.)
4. Witness API for the `async` feature — `async_trait` (object-safe, easy
   shipping) or AFIT (cleaner, recent stable Rust)? Defer the decision until
   the v1 sync trait is shipped.

## 8. Recommendation

Adopt the design captured in `2026-05-25-rust-codegen-design.md`. Begin with
the v1 deliverable (sync, std, default feature) — 6–7 engineer-weeks. The
spike has eliminated the dependency-availability and shape-design risks; the
remaining work is straightforward codegen plumbing closely paralleling the
existing TS path.
