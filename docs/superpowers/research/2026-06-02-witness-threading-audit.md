# Witness threading security audit — `compactc --rust`

Date: 2026-06-02
Auditor: Claude Opus 4.7 (read-only audit, no code changes)
Branch: `codegen-rust`
Worktree: `/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/`

## 1. TL;DR

**Verdict: SOUND.** The two-world invariant — private state (`PS`) never enters
`ContractState.data` — is upheld by the current Rust codegen and runtime. The
runtime types confine `PS` to four well-known fields
(`ConstructorContext.initial_private_state`, `CircuitContext.current_private_state`,
`ConstructorResult.current_private_state`, `WitnessContext.private_state`), all
of which flow into `ConstructorResult` / `CircuitResults` and never into the
`ChargedState` that becomes `ContractState.data`. `PS` is an unbounded generic
parameter throughout `runtime-rs` and the emitted code (no `Aligned` /
`FieldRepr` / `From<…> for AlignedValue` bounds), so the type system actually
forbids a careless codegen change from pushing `PS` into a `StateValue` cell.
Every witness emit site in `rust-passes-walker.ss` and `rust-passes-streaming.ss`
binds the witness return as `let (current_private_state, NAME) = self.witnesses.<m>(...)`,
threading the PS slot to a stable identifier never reused as a circuit operand.
Residual risk is procedural, not structural: there is no negative test that
asserts a sentinel PS value (e.g. `[7u8; 32]`) is absent from the serialised
contract state, and the contract author can still legitimately push a witness's
*value* return (`T`) onto the ledger — the codegen cannot tell which `T` values
are private by intent.

## 2. Methodology

Files read end-to-end or in target ranges:

- `runtime-rs/src/lib.rs` (full) — curated prelude + module wiring.
- `runtime-rs/src/witness.rs` (full) — `WitnessContext`, `NoWitnesses`.
- `runtime-rs/src/context.rs` (full) — `ConstructorContext`, `CircuitContext`.
- `runtime-rs/src/results.rs` (full) — `ConstructorResult`, `CircuitResults`.
- `compiler/rust-passes-walker.ss` — witness-call hoist / bind paths around
  lines 740–860 (`witness-call-bound`, `collect-witness-subcalls`,
  `emit-hoisted-witnesses`), 1340–1540 (const-binding + bare-call witness
  emit), and tail-flush sites at 2073–2450.
- `compiler/rust-passes-streaming.ss` — parallel emit sites at lines 240–390.
- `tests-e2e-rust/contracts/tiny/lib.rs` (full).
- `tests-e2e-rust/contracts/witnesses-fixture/lib.rs` (full).
- `tests-e2e-rust/contracts/zerocash/lib.rs` — `spend()` around 600–790,
  trait + Contract decl at 532–595.
- `tests-e2e-rust/tests/tiny.rs` 1–120 — to check for sentinel-leak assertions.

Greps used (illustrative, not exhaustive):

```
grep -rn "current_private_state\|initial_private_state" runtime-rs/ tests-e2e-rust/
grep -rn "<PS" runtime-rs/src/ tests-e2e-rust/contracts/
grep -rn "PS:\s*\(Aligned\|FieldRepr\|From\|Into\)" runtime-rs/ tests-e2e-rust/contracts/
grep -rn "impl.*From.*for AlignedValue\|impl.*Aligned for\|impl<T> .*AlignedValue" runtime-rs/src/
grep -n "self.witnesses\|let (current_private_state" compiler/rust-passes-*.ss
grep -n "current_contract_state\|results.context.state" tests-e2e-rust/contracts/{tiny,witnesses-fixture}/lib.rs
```

End-to-end trace performed: the `tiny` fixture's `private_secret_key` witness
returning `((), [7u8; 32])` was followed through `initial_state` / `set` /
`clear` in `tests-e2e-rust/contracts/tiny/lib.rs`. Confirmed `sk: [u8; 32]` is
only ever consumed by `pure_circuits::public_key(sk)` (a `persistent_hash`
call), with the *hash* — not the raw `sk` — being pushed via `new_cell(tmp)`.

## 3. Findings

### 3.1 Runtime type discipline

- `PS` is a free generic on `WitnessContext<L, PS, D>`, `CircuitContext<PS, D>`,
  `ConstructorContext<PS, D>`, `CircuitResults<PS, R, D>`, `ConstructorResult<PS, D>`.
  No `Aligned`, `FieldRepr`, `BinaryHashRepr`, `From<…>` or `Into<…>` bounds
  exist on `PS` anywhere in `runtime-rs/src/{witness,context,results}.rs`.
  Verified: `grep -rn "PS:\s*\(Aligned\|FieldRepr\|From\|Into\)" runtime-rs/`
  returned zero hits.
- `Contract<PS, W>` in generated code carries `_ps: PhantomData<PS>` — `PS`
  never appears as a concrete field on the contract itself.
- No blanket `impl<T> From<T> for AlignedValue` or `impl<T> Aligned for T`
  exists in `runtime-rs/src/`. The two `Aligned` impls
  (`runtime-rs/src/std_lib/maybe.rs:45`, `runtime-rs/src/std_lib/opaque.rs:34`)
  are confined to specific types, not blankets.
- `ContractState.data` is a `ChargedState<D>` (re-export of
  `midnight_onchain_state::state::ChargedState`). Generated code only ever
  populates this from `qctx.state` or `results.context.state`, where the
  query context is mutated exclusively by `OpProgramVerify` op programs.
  `PS` cannot be passed to `OpProgramVerify::push` because `push` requires a
  `StateValue`-typed builder argument and `PS` carries no conversion bound.

### 3.2 Codegen — witness call shape

Every witness call site in the Rust emitter follows the same shape:

```text
let _witness_ctx_N = WitnessContext::new(ledger(<state>), <prev-priv>, <qctx-ref>);
let (current_private_state, <rust-name>) = self.witnesses.<m>(&_witness_ctx_N, args...);
```

Confirmed at:
- `compiler/rust-passes-walker.ss:848` (hoist path, asserts).
- `compiler/rust-passes-walker.ss:1384` (const-binding witness call).
- `compiler/rust-passes-walker.ss:1526` (bare-call statement; discards value
  but still re-binds PS via `let (current_private_state, _) = …`).
- `compiler/rust-passes-streaming.ss:261, 382` (streaming emitter — same two
  patterns).

`<prev-priv>` is resolved by `compiler/rust-passes-walker.ss:1369-1373` (and
the streaming twin at `:249-252`):

- First witness call in ctor: `ctx.initial_private_state`.
- First witness call in a circuit: `ctx.current_private_state`.
- Subsequent witness calls in the same body: the prior `current_private_state`
  shadow binding.

`<rust-name>` is derived from the LHS variable name of the `const` binding (or
`_` for bare calls), and is the only identifier through which the witness's
*value* (`T`) reaches subsequent statements. The `PS` slot is bound to the
fixed literal identifier `current_private_state`, which is then consumed by
the result-construction emitters
(`rust-passes-walker.ss:2105, 2210, 2297, 2373, 2431`, all of the form
`current_private_state,\n` inside `CircuitResults { context: CircuitContext { … } }`
or `ConstructorResult { … }`). No emit site ever uses the
`current_private_state` binding as input to `OpProgramVerify`, `new_cell`,
`AlignedValue::from`, or any other on-chain-state-bearing API.

### 3.3 End-to-end trace — `tiny.compact`

`tiny`'s witness signature: `private_secret_key(ctx) -> (PS, [u8; 32])`.
In the test driver `tests-e2e-rust/tests/tiny.rs:31-37` the impl returns
`((), [7u8; 32])`. Walked in `tests-e2e-rust/contracts/tiny/lib.rs`:

- `initial_state` body (lines 54–69):
  - `let (current_private_state, sk) = self.witnesses.private_secret_key(&_witness_ctx_0);`
  - `let tmp = pure_circuits::public_key(sk);` — `sk` is moved into the hash
    function (`tiny/lib.rs:340-347`: `persistent_hash_aligned(&[label_av, AlignedValue::from(sk)])`).
    The hash output `tmp` is pushed via `new_cell(tmp)` at line 60. The raw
    32 bytes of `sk` never appear in a `new_cell` call.
- `set` body (lines 112–129): identical pattern — `sk → public_key(sk) → apk`,
  push `apk` not `sk`.
- `clear` body (lines 241–276): `sk` is hashed to `apk`, compared against the
  ledger-stored authority via `compact_assert!`, and `tmp = [0u8; 32]` (a
  hard-coded zero, not `sk`) is what gets written back on clear.

In all three circuits, `current_private_state` flows directly into the
`CircuitResults { context: CircuitContext { current_private_state, .. } }`
or `ConstructorResult { current_private_state, … }` envelope. PS does not
touch any builder.

### 3.4 End-to-end trace — `zerocash.spend`

`zerocash/lib.rs:606-789` chains four witness calls
(`private_zk_secret_key`, `context_path_of`, `context_new_coin_info`,
`context_encrypt`) plus a bare-call `private_remove_coin`. For each:

- The PS slot is bound to the literal `current_private_state` and shadow-
  chained through the body, finally landing in `CircuitResults.context.current_private_state`.
- Witness *value* outputs that flow on-chain do so through pure-circuit
  transforms or as explicit, contract-author-chosen encrypted ciphertext:
  - `source_secret_key` → `pure_circuits::derive_nullifier(...)` /
    `pure_circuits::derive_zk_public_key(...)` (cryptographic transforms; raw
    `source_secret_key` is never pushed).
  - `commitment_path` → `merkle_tree_path_root(commitment_path)` then used in
    a `member` ledger *read*, not a write.
  - `fresh_coin_info` → `pure_circuits::commitment_from_coin_info(...)` (a
    commitment hash) before being pushed.
  - `ciphertext` → pushed via `new_cell(ciphertext.clone())` (this is the
    designed-public encrypted payload).
- `private_remove_coin`'s return value is bound to `_` (discarded); only PS
  is threaded.

Conclusion: zerocash's on-chain writes contain only commitments, nullifiers,
and ciphertext — never raw witness `T` outputs that were meant to remain
secret. The codegen mechanically threads PS correctly across all five witness
calls in this single body.

### 3.5 Constructor / circuit result construction

The five locations in `rust-passes-walker.ss` that emit the
`ConstructorResult { current_contract_state, current_private_state, … }` or
`CircuitResults { context: CircuitContext { current_private_state, .. } }`
envelopes (lines 2073–2450) use:
- `current_contract_state: <results>.context.state` or `qctx.state` — i.e.
  the `ChargedState` from a `query_for_verify` (or the freshly built one for
  a body with no writes).
- `current_private_state` — the PS shadow from the last witness call (or
  `ctx.initial_private_state` / `ctx.current_private_state` if no witness was
  invoked).

These are independent fields on independent structs. There is no codepath
that re-routes `current_private_state` into `current_contract_state`.

### 3.6 Tests

`tests-e2e-rust/tests/tiny.rs` performs byte-parity vs the captured TS
reference state. Because the TS reference is produced by a correctly-
threading TS runtime, byte-parity *implicitly* covers the invariant (if PS
leaked into the Rust serialisation, the bytes would diverge). However there
is **no explicit negative assertion** — e.g. no test that does
`assert!(!buf.windows(32).any(|w| w == [7u8; 32]))` after serialising the
ChargedState. The same gap applies to zerocash and election.

## 4. Gaps and recommendations

Listed in approximate priority order.

1. **Add negative serialisation tests.** For each fixture with a non-trivial
   `PS`, add a regression test that picks a sentinel byte pattern in the
   witness return (e.g. `tiny`'s `[7u8; 32]`, or use a distinctive value like
   `[0xDE, 0xAD, 0xBE, 0xEF, …]`) and asserts the pattern does NOT appear in
   the `tagged_serialize`-produced bytes of `ContractState`. Cheap to add,
   directly tests the invariant.

2. **Document the invariant in the Witnesses<PS> trait emission.** The
   generated `pub trait Witnesses<PS> { fn …(…) -> (PS, T); }` could be
   preceded by a rustdoc comment warning that the second slot (`T`) IS what
   reaches ledger sites and the first slot (`PS`) is the only place to
   hold-private data. Cheap docs win — minimises misuse by contract authors
   writing the trait impl by hand.

3. **Defensive trait bound: consider `PS: ?Sized + 'static`** (no functional
   change, just to make explicit that `PS` carries no encoding capability).
   More importantly, a `#[deny]` lint or compile-fail test could be added
   that confirms `PS` does NOT satisfy `Aligned`-style bounds: e.g. an
   intentionally-failing compile test where a generated body attempts to
   call `new_cell(current_private_state)` should fail with a clear "PS:
   Aligned is not satisfied" message.

4. **Codegen fuzz / property test (low priority).** A small property-based
   test that generates random witness bodies and checks the emitter never
   produces the string `new_cell(current_private_state` or
   `AlignedValue::from(current_private_state` would be a cheap structural
   guard against future regressions in the walker.

5. **Witness *value* (`T`) leakage is the contract author's responsibility.**
   The codegen cannot statically decide whether a witness's `T` output is
   meant to stay private. Contract author can write `ledger.foo = witness();`
   and that's a legitimate emit. Recommend: surface this in the
   `doc/rust-codegen-user-guide.md` (Witnesses section) with a worked
   example.

## 5. Verdict

**Sound.** No leak path identified from `PS` into `ContractState.data` in the
current Rust codegen + runtime. The two-world separation is enforced both
structurally (separate fields on separate structs, unbounded `PS` generic) and
operationally (mechanical bind pattern across all witness-call emit sites). No
P0 concern; gaps listed above are hardening / defensive opportunities.
