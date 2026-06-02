# Upstream PRs to retire `compact-runtime` friction wrappers

**Author:** ysh
**Date:** 2026-05-25
**Status:** Forward-looking proposal. Each PR is independently submittable.
**Companions:** `2026-05-25-rust-codegen-design.md` §4.6 (the catalogue of
findings these PRs resolve), `2026-05-25-rust-codegen-feasibility.md`.

---

`midnight-ledger` (`midnightntwrk/midnight-ledger`) is the Rust workspace
that publishes the core on-chain primitives consumed by the Midnight node
and by `compact-runtime`: `midnight-base-crypto`, `midnight-transient-crypto`,
`midnight-onchain-state`, `midnight-onchain-vm`, `midnight-onchain-runtime`,
`midnight-storage`, `midnight-coin-structure`, `midnight-zswap`. Today
`compact-runtime` (this repo's `runtime-rs/`) carries a small set of
ergonomic wrappers — documented in design spec §4.6 — that paper over
gaps between the upstream Rust API and the conventions the TypeScript
facade exposes (and that idiomatic Rust expects). The PRs below retire
each gap at its source, so future Rust consumers of `midnight-ledger`
(not just the Compact codegen) don't have to rediscover them. Each
wrapper either becomes a trivial re-export or is deleted outright once
the corresponding upstream PR lands.

---

## PR 1: `StateValue::new_cell` and `StateValue::new_array` constructors

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-onchain-state`
- **File:** `src/state.rs`
- **Why:** The TypeScript facade exposes `StateValue.newCell(v)` and
  `StateValue.newArray()` as factory methods. The Rust side forces
  variant-construction via `StateValue::Cell(Sp::new(v.into()))` or a
  bare `From` conversion, which obscures intent at call sites that
  cross-reference the TS path. Factory methods are also more discoverable
  via rustdoc than a `From` impl.
- **Proposed change:**

  ```rust
  impl<D: DB> StateValue<D> {
      pub fn new_cell<T: Into<AlignedValue>>(v: T) -> Self {
          Self::Cell(Sp::new(v.into()))
      }
      pub fn new_array() -> Self {
          Self::Array(Array::new())
      }
      pub fn array_push(self, value: Self) -> Self {
          match self {
              Self::Array(arr) => Self::Array(arr.push(value)),
              other => other,
          }
      }
  }
  ```

- **Impact on `compact-runtime`:** Deletes `new_cell`, `new_array`, and
  `new_empty_array` from `compact-runtime::builders`. Call sites in
  generated code shift from `compact_runtime::new_cell(v)` to
  `StateValue::new_cell(v)`.
- **Estimated effort:** ~12 lines + doctest. 30 minutes.

---

## PR 2: `ChargedState: Default`

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-onchain-state`
- **File:** `src/state.rs`
- **Why:** `Default` is the conventional empty-construction trait in
  Rust. Today empty `ChargedState` requires the longhand
  `ChargedState::new(StateValue::Null)`, and `ContractState::new(...)`
  callers have to supply that longhand for the `data` field.
- **Proposed change:**

  ```rust
  impl<D: DB> Default for ChargedState<D> {
      fn default() -> Self { Self::new(StateValue::Null) }
  }
  ```

- **Impact on `compact-runtime`:** Deletes `empty_charged_state` from
  `compact-runtime::builders`. Generated code uses
  `ChargedState::default()`.
- **Estimated effort:** ~5 lines. 15 minutes.

---

## PR 3: `CostModel::initial` associated constructor

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-onchain-vm`
- **File:** `src/cost_model.rs`
- **Why:** Matches the conventional Rust idiom (`T::initial()` reads
  better than `INITIAL_T_MODEL.clone()`) and aligns with the TypeScript
  facade's `CostModel.initialCostModel()` factory. The const is fine to
  keep — this is purely an additive associated function.
- **Proposed change:**

  ```rust
  impl CostModel {
      pub fn initial() -> Self { INITIAL_COST_MODEL.clone() }
  }
  ```

- **Impact on `compact-runtime`:** Deletes `initial_cost_model` from
  `compact-runtime::builders`. Generated code calls `CostModel::initial()`
  directly.
- **Estimated effort:** ~3 lines. 10 minutes.

---

## PR 4: `EntryPointBuf::from<&str>`

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-onchain-state`
- **File:** wherever `EntryPointBuf` is defined (likely `src/state.rs`)
- **Why:** Operation keys are universally string-named in Compact source
  (`circuit increment(): []`). Today the upstream constructor is
  `EntryPointBuf(b"increment".to_vec())` — a raw-bytes ceremony that adds
  no information at the call site. A `From<&str>` makes the intent
  obvious and supports the `"name".into()` idiom.
- **Proposed change:**

  ```rust
  impl From<&str> for EntryPointBuf {
      fn from(s: &str) -> Self { EntryPointBuf(s.as_bytes().to_vec()) }
  }
  ```

- **Impact on `compact-runtime`:** `entry_point("name")` becomes
  `EntryPointBuf::from("name")` or simply `"name".into()` at call sites
  with type inference.
- **Estimated effort:** ~4 lines. 10 minutes.

---

## PR 5: Enum derive support for `FieldRepr` / `FromFieldRepr`

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-base-crypto-derive`
- **Why:** Compact contracts use enums extensively (e.g., the
  `STATE { unset, set }` enum in `tiny.compact`). Today the
  `FieldRepr` / `FromFieldRepr` derive macros panic on enums with "Only
  structs can currently derive FieldRepr". The M3 codegen will need to
  emit manual impls uniformly until this lands — manageable but verbose.
  Enabling enum derives lets the codegen use a single
  `#[derive(FieldRepr, FromFieldRepr)]` line per user-declared type.
- **Proposed change:** Non-trivial — the derive macro needs to compute
  per-variant tags, emit a discriminant write before the variant payload,
  and pick a stable variant ordering (probably source order, matching
  what the Compact frontend already enforces). Estimated 50–100 LOC of
  proc-macro code with attention to:
    - variant ordering (must match the Compact source order so the
      computed `STATE::unset = 0`, `STATE::set = 1` matches what the
      compiler expects);
    - forward compatibility with new variants (additive at the tail);
    - variant payloads (`STATE::set(Field)` vs unit-only variants —
      Compact frontend currently emits unit-only, but the derive should
      support payloads for future-proofing).
- **Impact on `compact-runtime`:** The M3 codegen can use
  `#[derive(FieldRepr, FromFieldRepr)]` on generated enums instead of
  emitting manual impls per type. Reduces generated-LOC noticeably.
- **Estimated effort:** ~1 day including tests, plus design review for
  the variant-ordering invariant.

---

## PR 6: Document the variable-length zero-stripping of numeric atoms

- **Repository:** `midnightntwrk/midnight-ledger`
- **Affected crate:** `midnight-base-crypto`
- **File:** `src/fab/` or `src/conversions.rs` (wherever
  `impl From<u64> for AlignedValue` etc. live)
- **Why:** The canonical encoding for `AlignedValue::from(N: u*)` strips
  trailing zero bytes — `AlignedValue::from(42u64)` is a 1-byte atom
  `[42]`, not 8 bytes. This is non-obvious and the first place every
  downstream Rust consumer hits a wall. Documenting it in the rustdoc of
  `AlignedValue::from<u*>` and the inverse decode path makes the
  invariant discoverable before someone writes a fixed-width decoder and
  loses an afternoon to it. (This wrapper's `compact-runtime` cousin —
  the `decode_u*` family — already handles the variable-length case
  correctly; this PR is about discoverability of the upstream
  invariant.)
- **Proposed change:** Rustdoc additions only — no code changes. One
  paragraph each on `From<u8>`, `From<u16>`, `From<u32>`, `From<u64>`,
  `From<u128>`, with a worked example showing the trailing-zero strip.
- **Impact on `compact-runtime`:** No change to the `decode_*` helpers
  (they're correct), but reduces the chance of future consumers
  discovering the invariant the hard way.
- **Estimated effort:** ~30 minutes of rustdoc.

---

## PR 7: `prepare-for-typescript` rename + export from `typescript-passes.ss` *(already done in this branch — flag as completed)*

- **Repository:** this repo (`midnight-ntwrk/compact` or wherever this
  monorepo lives — not `midnight-ledger`).
- **File:** `compiler/typescript-passes.ss`, `compiler/passes.ss`.
- **Why:** Needed for any second backend (Rust, future Swift/Kotlin) to
  share the `Ltypescript` IR with the TS emitter. Without the export,
  `passes.ss` cannot thread the IR into the Rust emitter.
- **Status:** Already shipped in this branch. Renamed to
  `prepare-for-typescript-passes` and `print-typescript-passes`, both
  exported.
- **Proposed follow-up:** Consider further renames for clarity —
  `prepare-for-typescript-passes` → `prepare-for-codegen-passes`, and
  `print-typescript-passes` → keep as-is (it remains TS-specific). No
  functional change; cleanup only.
- **Impact on `compact-runtime`:** None (this is compiler-side).
- **Estimated effort:** ~30 minutes if pursued.

---

## How to track

- Open PRs 1–6 as separate issues/PRs against
  `midnightntwrk/midnight-ledger`. They're independent and can land in
  any order.
- PRs 1–4 are tiny (3–12 lines each) and should land in a single
  afternoon collectively, modulo review cycles.
- PR 5 is the only one with non-trivial design work; treat it as a
  standalone feature, not a drive-by fix.
- PR 6 is rustdoc only — bundle with the next routine docs sweep.
- PR 7 is internal to this repo and is already done; track only the
  optional rename follow-up.

Once PRs 1–4 land, the entire `compact-runtime::builders` module
(~90 LOC) collapses to a handful of re-exports or is deleted outright.
Once PR 6 lands, the `decode_*` family's rustdoc can reference the
upstream rustdoc rather than re-explaining the invariant. Once PR 5
lands, the M3 codegen can drop ~10–20 LOC of manual `FieldRepr` impl
emission per user-declared enum type.
