# M3a Implementation Plan — tiny.compact end-to-end

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend `compiler/rust-passes.ss` and `runtime-rs/src/lib.rs` so that `compactc --rust --skip-ts examples/tiny.compact <out>` succeeds and the emitted Rust crate compiles, with `counter.compact` byte-parity regression remaining green.

**Architecture:** Universal helpers (`Bytes<N>`, `Maybe<T>`, `pad`, `disclose`) land in `compact-runtime`. A new sibling crate `compact-runtime-macros` provides a `#[witnesses]` proc-macro that auto-generates the `Witnesses<PS>` trait impl that `rust-passes.ss` emits. Per-contract code (enum impls, contract struct, constructor, circuits, ledger view) is generated in Rust by extending `rust-passes.ss`'s nanopass walk of the `Ltypescript` IR.

**Tech Stack:** Chez Scheme + nanopass framework (compiler); Rust 1.85+ edition 2021 (runtime + macros); `syn 2` + `quote 1` + `proc-macro2 1` (macros crate); existing midnight-ledger crates (Fr, Op, persistent_hash, AlignedValue, etc.).

---

## Pre-flight findings (verified during planning)

- `/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9` is the working worktree; branch `codegen-rust` (commit `03013c0` after M3a spec). DCO + GPG-signed commits enforced (`-S -s`).
- `compiler/rust-passes.ss` is 310 lines today. Existing emit functions: `header`, `emit-witnesses`, `emit-contract-struct`/`close-contract-struct`, `emit-initial-state`, `emit-increment-circuit` (counter-only hardcoded), `emit-ledger-view` (counter-only), `emit-pure-circuits` (empty), `emit-cargo-toml`.
- Existing M2 trait shape that the macro plugs into:
  ```rust
  pub trait Witnesses<PS> {
      fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, PS>) -> (PS, Bytes<32>);
  }
  impl<PS> Witnesses<PS> for NoWitnesses {}   // emitted only when contract has zero witnesses
  ```
- `runtime-rs/src/lib.rs` already re-exports `Fr`, `Op`, `WitnessContext`, `NoWitnesses`, `CircuitContext`, `ConstructorContext`, `persistent_hash`, `Aligned`, `FieldRepr`, `FromFieldRepr`, etc. `pub mod std_lib;` exists for stdlib helpers; `pub mod op_builder;` exposes `OpProgramVerify`/`OpProgramGather`.
- Workspace root `Cargo.toml` (path: `/Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9/Cargo.toml`) needs to learn about the new `runtime-rs-macros` workspace member.

---

## File map

| Path (relative to compact worktree) | Status | Purpose |
|---|---|---|
| `Cargo.toml` (workspace root) | modify | add `runtime-rs-macros` as a member |
| `runtime-rs/Cargo.toml` | modify | add `compact-runtime-macros` dep |
| `runtime-rs/src/lib.rs` | modify | re-export macro; add new universal helpers via `pub mod std_lib_ext`; or just add to `std_lib` |
| `runtime-rs/src/std_lib.rs` | modify | add `Bytes<N>` alias, `Maybe<T>`, `pad`, `disclose`, `some`, `none` |
| `runtime-rs-macros/Cargo.toml` | create | proc-macro crate manifest |
| `runtime-rs-macros/src/lib.rs` | create | `#[witnesses]` proc-macro |
| `runtime-rs-macros/tests/witnesses.rs` | create | trybuild-style smoke test for the macro |
| `compiler/rust-passes.ss` | modify (substantial) | enum emission, stdlib mapping, witness arg emission, constructor walker, circuit body walker |
| `examples/outputs/tiny.compact/` | create (regenerated) | snapshot of tiny.compact's emitted output |
| `tests-e2e-rust/tests/tiny.rs` | create | smoke test of emitted tiny crate |

---

## Conventions for every commit in this plan

```bash
git commit -S -s -m "<type>(<scope>): <subject>" -m "<body>" -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
```

After every commit:
```bash
git log --format="%h %G? %s" -1
```
Expect leading column `G`. If `B` or `N`, amend immediately: `git commit --amend --no-edit -S -s`.

**Do NOT** add `Signed-off-by:` to the commit body manually — `-s` adds it once.

---

## Task M1 — `compact-runtime` universal helpers

**Files:**
- Modify: `runtime-rs/src/std_lib.rs`
- Modify: `runtime-rs/src/lib.rs` (re-exports)
- Test: in-file `#[cfg(test)]` module

- [ ] **Step 1.1: Inspect current `std_lib.rs`** to see existing patterns

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
wc -l runtime-rs/src/std_lib.rs
head -30 runtime-rs/src/std_lib.rs
```

Note the existing function naming style; new helpers should match.

- [ ] **Step 1.2: Write failing test for `Maybe<T>` helpers**

Append to `runtime-rs/src/std_lib.rs`:

```rust
#[cfg(test)]
mod tests_m3a_helpers {
    use super::*;

    #[test]
    fn maybe_some_unwraps() {
        let m: Maybe<u32> = some(7);
        assert!(m.is_some());
        assert_eq!(m.unwrap(), 7);
    }

    #[test]
    fn maybe_none_is_none() {
        let m: Maybe<u32> = none();
        assert!(!m.is_some());
    }

    #[test]
    fn pad_truncates_and_zero_extends() {
        assert_eq!(pad(5, "abc"), vec![b'a', b'b', b'c', 0, 0]);
        // pad must not grow beyond width — truncates input if longer.
        // (Note: spec says "pads to width", so we treat width as a fixed
        // length; if the input is longer, behavior is documented in §1.5.)
    }

    #[test]
    fn disclose_is_identity() {
        let x = 42u64;
        assert_eq!(disclose(x), 42u64);
    }
}
```

- [ ] **Step 1.3: Run tests; expect failure**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
cargo test -p compact-runtime tests_m3a_helpers 2>&1 | tail -10
```
Expected: compilation errors — `some`, `none`, `Maybe`, `pad`, `disclose` not in scope.

- [ ] **Step 1.4: Add implementations to `std_lib.rs`**

Append before the `#[cfg(test)]` block:

```rust
// -------------------------------------------------------------------------
// M3a universal helpers — Bytes<N>, Maybe<T>, pad, disclose
// -------------------------------------------------------------------------

/// Compact's `Bytes<N>` primitive maps directly to a fixed-width byte array.
/// Generated code uses this alias rather than spelling `[u8; N]` everywhere.
pub type Bytes<const N: usize> = [u8; N];

/// Compact's standard-library `Maybe<T>` ADT — equivalent to `Option<T>`
/// but kept as a distinct type so generated code matches the TS spelling.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum Maybe<T> {
    Some(T),
    None,
}

impl<T> Maybe<T> {
    #[inline]
    pub fn is_some(&self) -> bool {
        matches!(self, Maybe::Some(_))
    }

    #[inline]
    pub fn unwrap(self) -> T {
        match self {
            Maybe::Some(v) => v,
            Maybe::None => panic!("Maybe::unwrap on None"),
        }
    }
}

#[inline]
pub fn some<T>(v: T) -> Maybe<T> {
    Maybe::Some(v)
}

#[inline]
pub fn none<T>() -> Maybe<T> {
    Maybe::None
}

/// Compact's `pad(width, s)` — return the bytes of `s` resized to exactly
/// `width` bytes. Truncates if `s` is longer; zero-extends if shorter.
pub fn pad(width: usize, s: &str) -> Vec<u8> {
    let mut v = s.as_bytes().to_vec();
    v.resize(width, 0);
    v
}

/// Compact's `disclose(x)` — identity in Rust. The compiler uses this to
/// mark a value as publicly revealed; the runtime side has no operational
/// difference.
#[inline]
pub fn disclose<T>(x: T) -> T {
    x
}
```

- [ ] **Step 1.5: Re-export in `lib.rs`**

In `runtime-rs/src/lib.rs`, after the existing `pub mod std_lib;` line (around line 87), add:

```rust
pub use std_lib::{disclose, none, pad, some, Bytes, Maybe};
```

- [ ] **Step 1.6: Run tests; expect pass**

```bash
cargo test -p compact-runtime tests_m3a_helpers 2>&1 | tail -10
```
Expected: 4 tests pass.

- [ ] **Step 1.7: Run the full crate test suite to confirm no regression**

```bash
cargo test -p compact-runtime 2>&1 | tail -10
```
Expected: all tests pass.

- [ ] **Step 1.8: Commit**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
git add runtime-rs/src/std_lib.rs runtime-rs/src/lib.rs
git commit -S -s -m "feat(runtime): add Bytes<N>, Maybe<T>, pad, disclose universal helpers" \
  -m "Universal types and helpers that every Compact-emitted contract needs (M3a step 1/10). Hand-written in std_lib so the codegen can reference them by short name (e.g. compact_runtime::Maybe, compact_runtime::pad)." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```
Expected: `<hash> G feat(runtime): …`

---

## Task M2 — `compact-runtime-macros` crate skeleton

**Files:**
- Create: `runtime-rs-macros/Cargo.toml`
- Create: `runtime-rs-macros/src/lib.rs`
- Modify: `Cargo.toml` (workspace root) — add new member

- [ ] **Step 2.1: Create `runtime-rs-macros/Cargo.toml`**

```toml
[package]
name        = "compact-runtime-macros"
version     = "0.16.100"
edition     = "2021"
license     = "Apache-2.0"
description = "Procedural macros for compact-runtime — emits Witnesses<PS> trait impls."
repository  = "https://github.com/LFDT-Minokawa/compact"

[lib]
name = "compact_runtime_macros"
path = "src/lib.rs"
proc-macro = true

[dependencies]
proc-macro2 = "1"
quote       = "1"
syn         = { version = "2", features = ["full"] }
```

- [ ] **Step 2.2: Add to workspace members**

In `Cargo.toml` (workspace root), find the `[workspace] members = [...]` line. Append `"runtime-rs-macros"` (preserve formatting).

Run:
```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
grep -A 5 '^\[workspace\]' Cargo.toml | head -10
```
to confirm the array form, then edit appropriately.

- [ ] **Step 2.3: Stub `runtime-rs-macros/src/lib.rs`**

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Procedural macros for compact-runtime. The `#[witnesses]` attribute
// macro generates `impl Witnesses<PS> for <UserType>` blocks matching the
// trait that rust-passes.ss emits in the generated contract crate.
//
// The macro design intentionally keeps the trait as the source of truth:
// rust-passes emits it (so the contract crate is self-describing); the
// macro just removes per-witness boilerplate from user code.

use proc_macro::TokenStream;
use quote::quote;

/// `#[witnesses]` attribute macro — see crate docs.
///
/// **Skeleton in Task M2.** Real implementation lands in Task M3.
#[proc_macro_attribute]
pub fn witnesses(_attr: TokenStream, item: TokenStream) -> TokenStream {
    // M2 stub: pass the input through unchanged so the crate compiles
    // and downstream wiring can be tested. M3 replaces this with the
    // real expansion.
    let item = proc_macro2::TokenStream::from(item);
    let expanded = quote! { #item };
    expanded.into()
}
```

- [ ] **Step 2.4: Verify the workspace builds**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
cargo build -p compact-runtime-macros 2>&1 | tail -10
```
Expected: builds cleanly.

- [ ] **Step 2.5: Commit**

```bash
git add runtime-rs-macros/Cargo.toml runtime-rs-macros/src/lib.rs Cargo.toml
git commit -S -s -m "feat(runtime-macros): scaffold compact-runtime-macros crate" \
  -m "New proc-macro sibling crate. M2 ships a stub #[witnesses] attribute (pass-through). M3 implements the trait-impl generation." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M3 — `#[witnesses]` proc-macro implementation

**Files:**
- Modify: `runtime-rs-macros/src/lib.rs`
- Modify: `runtime-rs/Cargo.toml` (add dep on macros)
- Modify: `runtime-rs/src/lib.rs` (re-export macro)
- Test: `runtime-rs-macros/tests/witnesses_attr.rs`

The macro must accept this user input:

```rust
#[witnesses(MyContract, PS = MyState)]
impl MyWitnesses {
    fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, MyState>) -> (MyState, Bytes<32>) {
        (ctx.private_state.clone(), [0u8; 32])
    }
}
```

…and emit:

```rust
impl MyWitnesses {
    fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, MyState>) -> (MyState, Bytes<32>) {
        (ctx.private_state.clone(), [0u8; 32])
    }
}

impl compact_runtime::Witnesses<MyState> for MyWitnesses {
    fn secret_key(&self, ctx: &compact_runtime::WitnessContext<crate::contract::Ledger<'_>, MyState>) -> (MyState, compact_runtime::Bytes<32>) {
        Self::secret_key(self, ctx)
    }
}
```

The macro parses the `impl Foo { ... }` block, extracts each `fn` declared, and emits a matching trait impl that forwards to the inherent methods. The trait is generated by `rust-passes.ss` in the same crate; `crate::contract::Ledger<'_>` is the path that rust-passes uses for the per-contract ledger view.

- [ ] **Step 3.1: Write failing trybuild-style integration test**

`runtime-rs-macros/tests/witnesses_attr.rs`:

```rust
// Integration test for #[witnesses] — exercised via cargo test.
// Validates that the macro generates a trait impl that satisfies a
// hand-written trait of the same shape rust-passes.ss would emit.

use compact_runtime::WitnessContext;
use compact_runtime_macros::witnesses;

#[allow(unused)]
struct MyState;

// Stand-in for the per-contract Ledger<'a, D> rust-passes emits — the
// macro should generate code referencing crate::contract::Ledger, so
// we expose that here for the test.
mod contract {
    pub struct Ledger<'a> {
        _phantom: std::marker::PhantomData<&'a ()>,
    }
}

// Stand-in for the per-contract Witnesses<PS> trait rust-passes emits.
// The macro must produce an impl that satisfies THIS trait.
pub trait Witnesses<PS> {
    fn secret_key(&self, ctx: &WitnessContext<contract::Ledger<'_>, PS>) -> (PS, [u8; 32]);
}

struct MyWitnesses;

#[witnesses(MyWitnesses, PS = MyState)]
impl MyWitnesses {
    fn secret_key(
        &self,
        ctx: &WitnessContext<contract::Ledger<'_>, MyState>,
    ) -> (MyState, [u8; 32]) {
        let _ = ctx;
        (MyState, [0u8; 32])
    }
}

#[test]
fn macro_generates_trait_impl_callable_via_trait_object() {
    fn call_as_trait_object<W: Witnesses<MyState>>(_w: &W) {}
    let w = MyWitnesses;
    call_as_trait_object(&w);
}
```

- [ ] **Step 3.2: Set up the macros crate's dev-dependencies**

In `runtime-rs-macros/Cargo.toml`, append:

```toml
[dev-dependencies]
compact-runtime = { path = "../runtime-rs" }
```

- [ ] **Step 3.3: Run test; expect failure**

```bash
cargo test -p compact-runtime-macros 2>&1 | tail -20
```
Expected: compile error like "trait `Witnesses` is not implemented for `MyWitnesses`" (the stub macro does nothing).

- [ ] **Step 3.4: Implement the macro**

Replace `runtime-rs-macros/src/lib.rs` with:

```rust
// SPDX-License-Identifier: Apache-2.0
//
// Procedural macros for compact-runtime.

use proc_macro::TokenStream;
use proc_macro2::TokenStream as TokenStream2;
use quote::quote;
use syn::{
    parse::{Parse, ParseStream},
    parse_macro_input, FnArg, Ident, ImplItem, ImplItemFn, ItemImpl, ReturnType, Token, Type,
};

/// Arguments to `#[witnesses(Name, PS = StateType)]`.
struct WitnessesArgs {
    /// The user's witness struct type (e.g. `MyWitnesses`).
    name: Ident,
    /// The private-state type the witnesses operate on.
    ps_type: Type,
}

impl Parse for WitnessesArgs {
    fn parse(input: ParseStream<'_>) -> syn::Result<Self> {
        let name: Ident = input.parse()?;
        let _comma: Token![,] = input.parse()?;
        let ps_ident: Ident = input.parse()?;
        if ps_ident != "PS" {
            return Err(syn::Error::new(
                ps_ident.span(),
                "expected `PS = <type>`",
            ));
        }
        let _eq: Token![=] = input.parse()?;
        let ps_type: Type = input.parse()?;
        Ok(WitnessesArgs { name, ps_type })
    }
}

/// `#[witnesses(StructName, PS = StateType)]` — generates an
/// `impl compact_runtime::Witnesses<PS> for StructName` block forwarding
/// each declared inherent method to the user impl.
#[proc_macro_attribute]
pub fn witnesses(attr: TokenStream, item: TokenStream) -> TokenStream {
    let args = parse_macro_input!(attr as WitnessesArgs);
    let impl_block = parse_macro_input!(item as ItemImpl);

    let user_type = &impl_block.self_ty;
    let ps_type = &args.ps_type;

    // Collect each fn declared in the user impl, generate a forwarding
    // method in the trait impl.
    let mut forwards: Vec<TokenStream2> = Vec::new();
    for it in &impl_block.items {
        if let ImplItem::Fn(ImplItemFn { sig, .. }) = it {
            let fn_name = &sig.ident;
            // Reconstruct the parameter list for the call site.
            let call_args: Vec<TokenStream2> = sig
                .inputs
                .iter()
                .map(|a| match a {
                    FnArg::Receiver(_) => quote! { self },
                    FnArg::Typed(pat_ty) => {
                        let pat = &pat_ty.pat;
                        quote! { #pat }
                    }
                })
                .collect();
            let inputs = &sig.inputs;
            let output = match &sig.output {
                ReturnType::Default => quote! { },
                ReturnType::Type(_, ty) => quote! { -> #ty },
            };
            forwards.push(quote! {
                fn #fn_name(#inputs) #output {
                    Self::#fn_name(#(#call_args),*)
                }
            });
        }
    }

    let trait_impl = quote! {
        impl Witnesses<#ps_type> for #user_type {
            #(#forwards)*
        }
    };

    let expanded = quote! {
        #impl_block
        #trait_impl
    };
    expanded.into()
}

#[allow(unused)]
struct _NoteOnArgsParseError {} // hack so syn::Error parser remains in scope
```

- [ ] **Step 3.5: Run test; expect pass**

```bash
cargo test -p compact-runtime-macros 2>&1 | tail -10
```
Expected: 1 test passes.

If you get errors about `WitnessContext` not being in scope, the `pub use` in `runtime-rs/src/lib.rs` for `WitnessContext` is fine — make sure the test file imports it correctly.

- [ ] **Step 3.6: Wire macros into compact-runtime**

In `runtime-rs/Cargo.toml`, add to `[dependencies]`:

```toml
compact-runtime-macros = { path = "../runtime-rs-macros" }
```

In `runtime-rs/src/lib.rs`, add (near the top, after the foundational re-exports):

```rust
pub use compact_runtime_macros::witnesses;
```

- [ ] **Step 3.7: Verify compact-runtime still builds**

```bash
cargo build -p compact-runtime 2>&1 | tail -5
```
Expected: builds cleanly.

- [ ] **Step 3.8: Commit**

```bash
git add runtime-rs-macros/src/lib.rs runtime-rs-macros/tests/witnesses_attr.rs runtime-rs-macros/Cargo.toml runtime-rs/Cargo.toml runtime-rs/src/lib.rs
git commit -S -s -m "feat(runtime-macros): implement #[witnesses] proc-macro" \
  -m "Parses #[witnesses(UserType, PS = StateType)] and emits an impl Witnesses<PS> block forwarding each declared method. The trait itself is emitted by rust-passes.ss; the macro removes per-method boilerplate from user code." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M4 — Reproduce `%getSchnorrReduction` crash on a minimal contract

This task addresses R1 in the spec — the crash signature suggests the bug may be **upstream of rust-passes** (in IR construction), in which case M3a needs to expand scope. We isolate the failure mode before writing more code.

- [ ] **Step 4.1: Create a minimal witness-only test contract**

`tests/witness-minimal.compact`:

```compact
// Minimal repro for the %getSchnorrReduction-style crash on witness emission.
pragma language_version >= 0.16;

export { try_witness }

witness w_bytes32(): Bytes<32>;

circuit try_witness(): [] {
  const v = w_bytes32();
  disclose(v);
}
```

(If `pragma language_version` is wrong syntax, omit it. Read `examples/counter.compact` for the right pragma form first.)

- [ ] **Step 4.2: Run compactc on the minimal contract**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
rm -rf /tmp/witness-min-out
mkdir -p /tmp/witness-min-out
# Use the locally-built compactc if available, else nix develop --command
compactc --rust --skip-ts tests/witness-minimal.compact /tmp/witness-min-out 2>&1 | tee /tmp/wm-out.log
```

Three possible outcomes:
1. **Success** → witness emission as-currently-coded works for trivial witnesses; the did.compact crash is specific to `getSchnorrReduction`'s arg shape (or imports). M3a is on the right track.
2. **`Exception in symbol->string: %w_bytes32.NNN`** → witness emission *itself* crashes upstream of rust-passes. M3a must include a fix in an earlier compiler pass before extending rust-passes. **Investigate the crash:** run `compactc --rust --skip-ts` with `--print-stages` or similar diagnostic; identify the failing pass.
3. **Different error** → some other unmet expectation. Diagnose case-by-case.

- [ ] **Step 4.3: Document outcome inline**

Create `docs/superpowers/notes/2026-05-29-m3a-witness-repro.md` capturing:
- The minimal contract used
- The exact command + output
- Which of the 3 outcomes hit
- If outcome 2: which compiler pass crashes; tentative fix

- [ ] **Step 4.4: Commit the repro + note**

```bash
git add tests/witness-minimal.compact docs/superpowers/notes/2026-05-29-m3a-witness-repro.md
git commit -S -s -m "test(m3a): minimal witness repro + diagnostic note" \
  -m "Isolates whether the %getSchnorrReduction-style crash is rust-passes (M3a's scope) or upstream IR-construction (M3a scope expansion needed). See note for outcome." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

**STOP-GATE:** if Step 4.2 hit outcome 2, **escalate before proceeding to M5**. The plan as written assumes outcome 1.

---

## Task M5 — Real `type-rust` mapping in `rust-passes.ss`

Today `type-rust` returns the literal string `/* TODO(M3): type-rust */`. M5 replaces it with a real dispatch over `Ltypescript` Type variants used by tiny.compact: `tbytes`, `tfield`, `tuint`, `tboolean`, `tenum`, `ttuple`, `tvec`, `topaque`, `tcell`.

**Files:**
- Modify: `compiler/rust-passes.ss` (lines 61-62)

- [ ] **Step 5.1: Discover the Ltypescript Type variant set**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
grep -A 50 "language Ltypescript" compiler/langs.ss | head -80
```
List every variant of the `Type` nonterminal that appears. Record them.

(If `langs.ss` is in another file, search: `grep -rn "Type.*=" compiler/*.ss | head -30`.)

- [ ] **Step 5.2: Write a snapshot test for type-rust**

Add to the compact test framework. Since rust-passes.ss is a Scheme pass, testing is via the existing snapshot harness (`compiler/snapshots/`). Find the harness:

```bash
find compiler/snapshots -name "counter-rust-expected.rs.snap" -exec head -10 {} \;
ls compiler/snapshots/
```

The snapshot test for tiny.compact is part of Task M10 (end-to-end). For M5 alone, verify by recompiling counter.compact and checking that the output doesn't regress:

```bash
rm -rf /tmp/counter-m5-out && mkdir -p /tmp/counter-m5-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m5-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m5-out/contract/lib.rs || true
```
Expected: no diff (counter.compact has no witnesses, so type-rust never fires).

- [ ] **Step 5.3: Replace the `type-rust` stub**

Modify `compiler/rust-passes.ss` lines 55-62. Replace with (adjust variant names to match the actual Ltypescript IR found in Step 5.1):

```scheme
      ;; type-rust: dispatch on Ltypescript Type variants. Returns a
      ;; Rust type string suitable for embedding in fn signatures.
      ;; Coverage matches M3a (tiny.compact): tbytes / tfield / tuint /
      ;; tboolean / ttuple [] / tvec / tenum. Generic structs and Map/Set
      ;; ledger types are M3b/c.
      (define (type-rust type)
        (nanopass-case (Ltypescript Type) type
          [(tfield)              "Fr"]
          [(tboolean)            "bool"]
          [(tbytes ,n)           (format "Bytes<~a>" n)]
          [(tuint ,n)
           (cond
             [(<= n 8)   "u8"]
             [(<= n 16)  "u16"]
             [(<= n 32)  "u32"]
             [(<= n 64)  "u64"]
             [(<= n 128) "u128"]
             [else (errorf 'type-rust "tuint ~a exceeds u128" n)])]
          [(tenum ,name)         (format "~a" name)]   ; bare enum name
          [(ttuple ())           "()"]                   ; unit type
          [(ttuple (,t* ...))    (format "(~a)" (apply string-append
                                                  (let loop ([ts t*] [first? #t])
                                                    (cond
                                                      [(null? ts) '()]
                                                      [else
                                                       (cons (if first? "" ", ")
                                                             (cons (type-rust (car ts))
                                                                   (loop (cdr ts) #f)))]))))]
          [(tvec ,n ,t)          (format "[~a; ~a]" (type-rust t) n)]
          [else (errorf 'type-rust "unhandled type variant: ~s" type)]))
```

If the variant names from Step 5.1 differ (e.g. `bytes` instead of `tbytes`), adjust accordingly.

- [ ] **Step 5.4: Re-run counter.compact regression**

```bash
rm -rf /tmp/counter-m5-out && mkdir -p /tmp/counter-m5-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m5-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m5-out/contract/lib.rs
```
Expected: empty diff (no regression).

- [ ] **Step 5.5: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "feat(rust-passes): real type-rust dispatch for M3a types" \
  -m "Replaces the M2 stub. Covers tbytes/tfield/tuint/tboolean/tenum/ttuple/tvec — every type tiny.compact references. Counter.compact regression remains green (counter has no witnesses, so type-rust never fired before either)." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M6 — Enum type-descriptor emission

tiny.compact has `enum STATE { unset, set }`. Generated code needs an `enum STATE` plus hand-written `Aligned`, `FieldRepr`, `FromFieldRepr` impls.

**Files:**
- Modify: `compiler/rust-passes.ss` (add `emit-enums`)

- [ ] **Step 6.1: Confirm the Ltypescript IR shape for enum declarations**

```bash
grep -B 2 -A 10 "Enum-Declaration\|enum-decl\|tenum" compiler/langs.ss compiler/*.ss 2>&1 | head -40
```
Identify the nonterminal name + accessor pattern (likely `(enum ,src ,name (,variant* ...))` or similar). Record.

- [ ] **Step 6.2: Add `program-enums` collector**

In `rust-passes.ss`, after `program-ledger-fields` (around line 157), add:

```scheme
      ;; enum?: returns #t if a Program-Element is an Enum-Declaration.
      (define (enum? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(enum ,src ,name (,variant* ...)) #t]   ; ADJUST to actual IR
          [else #f]))

      ;; program-enums: collects all enum declarations.
      (define (program-enums pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(enum? (car pelt*))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))
```

Adjust `nanopass-case` variant name to match Step 6.1.

- [ ] **Step 6.3: Add `emit-enums`**

After `emit-pure-circuits` (around line 270), add:

```scheme
      ;; emit-enums: emits Rust enum + Aligned/FieldRepr/FromFieldRepr
      ;; impls for each enum declaration. Discriminant = variant index
      ;; (0-based, source order). Stored as a u8.
      ;;
      ;; M3a: hand-emit because base-crypto-derive doesn't support enums.
      ;; Each enum gets ~30 LOC of Rust output.
      (define (emit-enums enum-decl*)
        (for-each
          (lambda (e)
            (nanopass-case (Ltypescript Program-Element) e
              [(enum ,src ,name (,variant* ...))   ; ADJUST to actual IR
               (out (format "#[derive(Clone, Copy, Debug, PartialEq, Eq)]\n"))
               (out (format "pub enum ~a {\n" name))
               (for-each (lambda (v) (out (format "    ~a,\n" v))) variant*)
               (out "}\n\n")

               ;; Default impl — first variant is the default.
               (out (format "impl ::core::default::Default for ~a {\n" name))
               (out (format "    fn default() -> Self { ~a::~a }\n" name (car variant*)))
               (out "}\n\n")

               ;; Aligned impl — single-field alignment (u8 discriminant).
               (out (format "impl compact_runtime::Aligned for ~a {\n" name))
               (out (format "    fn alignment() -> compact_runtime::Alignment {\n"))
               (out (format "        compact_runtime::Alignment::singleton_atom(\n"))
               (out (format "            compact_runtime::base_crypto::fab::AtomicAlignment::Compress { size: 1 },\n"))
               (out (format "        )\n"))
               (out (format "    }\n"))
               (out (format "}\n\n"))

               ;; FieldRepr impl — discriminant as u8 → Fr.
               (out (format "impl compact_runtime::FieldRepr for ~a {\n" name))
               (out (format "    fn field_repr(&self) -> Vec<compact_runtime::Fr> {\n"))
               (out (format "        let disc: u8 = match self {\n"))
               (let loop ([vs variant*] [i 0])
                 (unless (null? vs)
                   (out (format "            ~a::~a => ~a,\n" name (car vs) i))
                   (loop (cdr vs) (+ i 1))))
               (out (format "        };\n"))
               (out (format "        vec![compact_runtime::Fr::from(disc as u64)]\n"))
               (out (format "    }\n"))
               (out (format "    fn field_size() -> usize { 1 }\n"))
               (out (format "}\n\n"))

               ;; FromFieldRepr impl — u8 ← Fr.
               (out (format "impl compact_runtime::FromFieldRepr for ~a {\n" name))
               (out (format "    fn from_field_repr(fs: &[compact_runtime::Fr]) -> Option<Self> {\n"))
               (out (format "        if fs.len() != 1 { return None; }\n"))
               (out (format "        let n: u64 = u64::from_field_repr(&[fs[0]])?;\n"))
               (out (format "        match n as u8 {\n"))
               (let loop ([vs variant*] [i 0])
                 (unless (null? vs)
                   (out (format "            ~a => Some(~a::~a),\n" i name (car vs)))
                   (loop (cdr vs) (+ i 1))))
               (out (format "            _ => None,\n"))
               (out (format "        }\n"))
               (out (format "    }\n"))
               (out (format "}\n\n"))]))
          enum-decl*))
```

> **Note on trait API:** the exact signatures of `Aligned::alignment()`, `FieldRepr::field_repr()`, `FromFieldRepr::from_field_repr()` may differ from what's shown. Verify by reading:
> - `/Users/ysh/iohk/midnight-ledger/base-crypto/src/fab/alignments.rs:22` for `Aligned`
> - `/Users/ysh/iohk/midnight-ledger/transient-crypto/src/repr.rs` for `FieldRepr` and `FromFieldRepr`
> Adjust the emitted code to match.

- [ ] **Step 6.4: Wire `emit-enums` into the Program pass**

Modify the `Program` pass body (around line 293-307). After `(header)`, before `(emit-witnesses ...)`, add:

```scheme
       (emit-enums (program-enums pelt*))
```

So the call sequence becomes: `header → emit-enums → emit-witnesses → emit-contract-struct → emit-initial-state → emit-increment-circuit → close-contract-struct → emit-ledger-view → emit-pure-circuits → emit-cargo-toml`.

- [ ] **Step 6.5: Test against tiny.compact (partial — won't fully build yet)**

```bash
rm -rf /tmp/tiny-m6-out && mkdir -p /tmp/tiny-m6-out
compactc --rust --skip-ts examples/tiny.compact /tmp/tiny-m6-out 2>&1 | tail -10
grep -A 4 "pub enum STATE" /tmp/tiny-m6-out/contract/lib.rs
```
Expected:
- compactc may or may not crash later (constructor / circuits still hardcoded for counter), but the enum block at minimum should be emitted near the top of `lib.rs`.
- `pub enum STATE { unset, set, }` (or with no trailing comma) appears.

- [ ] **Step 6.6: Counter.compact regression**

```bash
rm -rf /tmp/counter-m6-out && mkdir -p /tmp/counter-m6-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m6-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m6-out/contract/lib.rs
```
Expected: empty diff (counter has no enums).

- [ ] **Step 6.7: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "feat(rust-passes): emit enum + Aligned/FieldRepr/FromFieldRepr impls" \
  -m "M3a step 6/10. Adds program-enums collector and emit-enums function. Each enum gets a #[derive(Clone, Copy, Debug, PartialEq, Eq)] + Default + Aligned + FieldRepr + FromFieldRepr block. Discriminant is variant index (0-based source order, stored as u8). Counter.compact regression green; tiny.compact's STATE enum appears in output (constructor/circuits still WIP)." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M7 — Witness emission with arguments + concrete return types

Update `emit-witnesses` so it (a) emits real argument types (currently deferred to M3) and (b) uses the real `type-rust` (now landed in M5).

**Files:**
- Modify: `compiler/rust-passes.ss` (lines 81-95)

- [ ] **Step 7.1: Inspect the Ltypescript Witness-Declaration shape**

```bash
grep -B 2 -A 5 "Witness-Declaration\|witness.*arg" compiler/langs.ss compiler/*.ss 2>&1 | head -20
```
Identify the arg list shape — likely `(witness ,src ,function-name (,arg* ...) ,type)` where each `arg` is `(,arg-name ,arg-type)` or similar.

- [ ] **Step 7.2: Rewrite `emit-witnesses`**

Replace lines 81-95 of `rust-passes.ss` with:

```scheme
      ;; emit-witnesses: emits the per-contract Witnesses<PS> trait.
      ;; Each witness function in the contract becomes one trait method:
      ;;
      ;;   fn name(&self, ctx: &WitnessContext<Ledger<'_>, PS>, <args>) -> (PS, <ret>);
      ;;
      ;; M3a: args + return type are real (no longer the "deferred" stubs
      ;; from M2). For contracts with zero witnesses the blanket
      ;; `impl<PS> Witnesses<PS> for NoWitnesses {}` is still emitted so
      ;; `Contract<PS>` (default W = NoWitnesses) works without a user
      ;; witness impl.
      (define (emit-witnesses witness-decl*)
        (out "pub trait Witnesses<PS> {\n")
        (for-each
          (lambda (w)
            (nanopass-case (Ltypescript Witness-Declaration) w
              [(witness ,src ,function-name (,arg* ...) ,type)
               (out (format "    fn ~a(&self, ctx: &WitnessContext<Ledger<'_>, PS>"
                            (camel->snake function-name)))
               ;; Emit each argument as ", <name>: <type>"
               (for-each
                 (lambda (a)
                   (nanopass-case (Ltypescript Argument) a   ; ADJUST nonterminal
                     [(arg ,name ,arg-type)
                      (out (format ", ~a: ~a"
                                   (camel->snake name)
                                   (type-rust arg-type)))]))
                 arg*)
               (out (format ") -> (PS, ~a);\n" (type-rust type)))]))
          witness-decl*)
        (out "}\n")
        (when (null? witness-decl*)
          (out "impl<PS> Witnesses<PS> for NoWitnesses {}\n"))
        (out "\n"))
```

Adjust `(Ltypescript Argument) → (arg ,name ,arg-type)` to the actual nonterminal/form from Step 7.1.

- [ ] **Step 7.3: Test against tiny.compact**

```bash
rm -rf /tmp/tiny-m7-out && mkdir -p /tmp/tiny-m7-out
compactc --rust --skip-ts examples/tiny.compact /tmp/tiny-m7-out 2>&1 | tail -5
grep -A 3 "pub trait Witnesses" /tmp/tiny-m7-out/contract/lib.rs
```
Expected:
- `pub trait Witnesses<PS> { fn secret_key(&self, ctx: &WitnessContext<Ledger<'_>, PS>) -> (PS, Bytes<32>); }`
- No blanket NoWitnesses impl (since tiny has a witness).

- [ ] **Step 7.4: Counter regression**

```bash
rm -rf /tmp/counter-m7-out && mkdir -p /tmp/counter-m7-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m7-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m7-out/contract/lib.rs
```
Expected: empty diff (counter has no witnesses; the trait gets emitted empty + blanket impl, same as before).

- [ ] **Step 7.5: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "feat(rust-passes): emit witness trait with real args + return types" \
  -m "Lifts the M2 'argument emission deferred' stub. Each witness becomes a real trait method signature. Counter regression green (no witnesses); tiny.compact's secret_key witness emitted with Bytes<32> return type." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M8 — Generic constructor body walker

Today `emit-initial-state` hardcodes `new_cell(0u64)` for every ledger field — that's Counter only. M8 walks the constructor body IR and emits the right initialization per field, including witness calls.

This task is **large**. Break into steps; commit between coherent slices.

**Files:**
- Modify: `compiler/rust-passes.ss` (replace `emit-initial-state`)

- [ ] **Step 8.1: Inspect the Ltypescript constructor body shape**

```bash
grep -B 2 -A 20 "Ledger-Constructor\|constructor.*body" compiler/langs.ss compiler/*.ss 2>&1 | head -40
```
Find the nonterminal — likely `(constructor ,src (,arg* ...) ,stmt-block)` or wrapped inside the `Ledger-Constructor` form. Map out:
- Top-level statements (assignments to ledger fields, `const` declarations, calls)
- Expressions (witness calls, primitive literals, struct literals, enum variants)

- [ ] **Step 8.2: Add `expr-rust` and `stmt-rust` recursive walkers**

After `type-rust`, add:

```scheme
      ;; expr-rust: walks an Ltypescript Expression and returns a string
      ;; of Rust code computing that expression. Covers the subset
      ;; tiny.compact's constructor exercises:
      ;;
      ;;   - literal numbers / bool / strings
      ;;   - identifier reference (local const)
      ;;   - witness call:  private$secret_key()  →  self.witnesses.secret_key(ctx)
      ;;   - enum variant:  STATE.set             →  STATE::set
      ;;   - disclose(x)                          →  compact_runtime::disclose(<x>)
      ;;   - public_key(sk) (inner-circuit call)  →  Self::public_key(self, sk)
      ;;   - pad(N, "lit")                        →  compact_runtime::pad(N, "lit")
      ;;   - persistentHash<T>(v)                 →  let buf = T::field_repr(&v); persistent_hash(&buf)
      ;;
      ;; M3b will extend for Map.lookup, Set.member, generic calls, etc.
      (define (expr-rust e)
        (nanopass-case (Ltypescript Expression) e
          [(int-lit ,n)             (format "~a" n)]    ; ADJUST variant name
          [(bool-lit ,b)            (if b "true" "false")]
          [(str-lit ,s)             (format "~s" s)]
          [(ident ,name)            (format "~a" (camel->snake name))]
          [(witness-call ,name (,arg* ...))
           (format "{ let (_ps, v) = self.witnesses.~a(ctx~a); v }"
                   (camel->snake name)
                   (apply string-append
                          (map (lambda (a) (format ", ~a" (expr-rust a)))
                               arg*)))]
          [(enum-var ,enum-name ,variant)
           (format "~a::~a" enum-name variant)]
          [(call ,fn-name (,arg* ...))
           (cond
             [(eq? fn-name 'disclose)
              (format "compact_runtime::disclose(~a)" (expr-rust (car arg*)))]
             [(eq? fn-name 'pad)
              (format "compact_runtime::pad(~a, ~a)"
                      (expr-rust (car arg*))
                      (expr-rust (cadr arg*)))]
             [else
              (format "Self::~a(self~a)"
                      (camel->snake fn-name)
                      (apply string-append
                             (map (lambda (a) (format ", ~a" (expr-rust a)))
                                  arg*)))])]
          [else (errorf 'expr-rust "unhandled expression: ~s" e)]))

      ;; stmt-rust: walks an Ltypescript Statement, returns Rust string.
      ;; Returns a single Rust statement (or block) terminating with ;
      ;; or {} as appropriate. The caller embeds it in a fn body with
      ;; appropriate indentation.
      (define (stmt-rust s indent)
        (let ([pre (make-string indent #\space)])
          (nanopass-case (Ltypescript Statement) s
            [(const-bind ,name ,expr)
             (format "~alet ~a = ~a;\n" pre (camel->snake name) (expr-rust expr))]
            [(ledger-assign ,field-name ,expr)
             ;; Constructor-time ledger assignments: store the value
             ;; into the per-field cell of the initial StateValue array.
             ;; In M3a we collect these into the field-init list rather
             ;; than emitting them as Rust statements. See emit-initial-state.
             (errorf 'stmt-rust "ledger-assign should be handled at constructor level")]
            [(expr-stmt ,expr)
             (format "~a~a;\n" pre (expr-rust expr))]
            [else (errorf 'stmt-rust "unhandled statement: ~s" s)])))
```

Adjust nonterminal/variant names to match Step 8.1.

- [ ] **Step 8.3: Replace `emit-initial-state` with constructor-walking version**

Old (lines 166-186) is hardcoded. Replace with:

```scheme
      ;; emit-initial-state: emits `initial_state` walking the
      ;; constructor body IR. For each ledger field assignment found in
      ;; the constructor, builds the corresponding StateValue cell.
      ;; For other statements (const bindings, expr stmts), emits them
      ;; as Rust statements before the cell-construction sequence.
      (define (emit-initial-state ledger-field* constructor-stmt* constructor-arg*)
        (out "    pub fn initial_state(\n")
        (out "        &self,\n")
        (out "        ctx: ConstructorContext<PS>,\n")
        ;; Constructor args
        (for-each
          (lambda (a)
            (nanopass-case (Ltypescript Argument) a
              [(arg ,name ,arg-type)
               (out (format "        ~a: ~a,\n"
                            (camel->snake name)
                            (type-rust arg-type)))]))
          constructor-arg*)
        (out "    ) -> Result<ConstructorResult<PS>, CompactError> {\n")

        ;; Split constructor stmts into (a) non-ledger stmts emitted as Rust,
        ;; and (b) ledger-assigns collected into field-init plan.
        (let loop ([stmts constructor-stmt*] [field-inits '()])
          (cond
            [(null? stmts)
             ;; Emit the StateValue construction.
             (out "        let sv = new_array(vec![\n")
             (for-each
               (lambda (lf)
                 (let ([field-name (lfield-name lf)])
                   (cond
                     [(assq field-name (reverse field-inits))
                      => (lambda (pair) (out (format "            new_cell(~a),\n" (cdr pair))))]
                     [else (out "            new_cell(0u64),\n")])))   ; default; refine for non-Counter
               ledger-field*)
             (out "        ]);\n")]
            [else
             (let ([s (car stmts)])
               (nanopass-case (Ltypescript Statement) s
                 [(ledger-assign ,field-name ,expr)
                  (loop (cdr stmts) (cons (cons field-name (expr-rust expr)) field-inits))]
                 [else
                  (out (stmt-rust s 8))
                  (loop (cdr stmts) field-inits)]))]))

        (out "        let state = ChargedState::new(sv);\n")
        (out "        let qctx = QueryContext::new(state, ContractAddress::default());\n")
        (out "        Ok(ConstructorResult {\n")
        (out "            current_contract_state: qctx.state,\n")
        (out "            current_private_state: ctx.initial_private_state,\n")
        (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
        (out "        })\n")
        (out "    }\n\n"))

      ;; lfield-name: extracts the field name from a Ledger-Declaration.
      (define (lfield-name lf)
        (nanopass-case (Ltypescript Program-Element) lf
          [(public-ledger-declaration ,pl-array ,lconstructor)
           ;; ADJUST: pl-array carries the name; how depends on actual IR.
           pl-array]))
```

Adjust variant accessors to match the actual IR.

- [ ] **Step 8.4: Update the Program pass to thread constructor stmts**

In the `Program` pass body, the constructor is part of the `Ledger-Constructor` or a separate element. Find where the constructor lives in the IR and pass its body + args to `emit-initial-state`. This may require new collector functions analogous to `program-witnesses`.

- [ ] **Step 8.5: Verify tiny.compact's constructor compiles**

```bash
rm -rf /tmp/tiny-m8-out && mkdir -p /tmp/tiny-m8-out
compactc --rust --skip-ts examples/tiny.compact /tmp/tiny-m8-out 2>&1 | tail -10
grep -A 15 "pub fn initial_state" /tmp/tiny-m8-out/contract/lib.rs
```
Expected:
- `initial_state(&self, ctx: ConstructorContext<PS>, v: Fr) -> Result<...>`
- Inside body: a const binding for `sk` calling witness, then ledger assignments to `authority`, `value`, `state`.

- [ ] **Step 8.6: Counter regression**

```bash
rm -rf /tmp/counter-m8-out && mkdir -p /tmp/counter-m8-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m8-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m8-out/contract/lib.rs
```
Expected: empty diff. counter.compact has no constructor body other than the (implicit) default init, so the new walker shouldn't change its output. If diff is non-empty but semantically equivalent, update the counter snapshot.

- [ ] **Step 8.7: Commit**

```bash
git add compiler/rust-passes.ss
git commit -S -s -m "feat(rust-passes): generic constructor body walker + expr/stmt-rust" \
  -m "Replaces the M2 hardcoded initial_state with a real IR walk over the constructor body. New expr-rust + stmt-rust recursive helpers cover the subset tiny.compact exercises: literals, idents, witness calls, enum variants, disclose/pad calls, function calls. Counter regression green." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M9 — Generic circuit body walker

Replace the hardcoded `emit-increment-circuit` with a generic emitter that walks each circuit's body IR. tiny.compact has 5 circuits: `in_state`, `set`, `get`, `clear`, `public_key`.

**Files:**
- Modify: `compiler/rust-passes.ss` (replace `emit-increment-circuit` with `emit-circuits`)

This task is sized to require iteration. Plan: implement one circuit shape at a time.

- [ ] **Step 9.1: Inspect Ltypescript Circuit-Declaration shape**

```bash
grep -B 2 -A 10 "Circuit-Declaration\|circuit.*body\|circuit ,src" compiler/langs.ss compiler/*.ss 2>&1 | head -40
```
Determine accessors for: name, args, return type, body statements, whether the circuit is `export` (impure/provable) vs not (pure/inlinable).

- [ ] **Step 9.2: Add `program-circuits` collector + `circuit?` predicate**

After `program-enums`, in `rust-passes.ss`:

```scheme
      (define (circuit? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(circuit ,src ,name (,arg* ...) ,ret-type ,body) #t]   ; ADJUST
          [else #f]))

      (define (program-circuits pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(circuit? (car pelt*))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))
```

- [ ] **Step 9.3: Replace `emit-increment-circuit` with `emit-circuits`**

```scheme
      ;; emit-circuits: emits one method per circuit declaration.
      ;; Each circuit becomes a method on Contract<PS, W>:
      ;;
      ;;   pub fn <name>(&self, ctx: CircuitContext<PS>, <args>) -> Result<CircuitResults<PS, <ret>>, CompactError>
      ;;
      ;; Body is the IR-walked sequence of statements; the return value
      ;; is the last expression (or () if the circuit returns []).
      (define (emit-circuits circuit-decl*)
        (for-each
          (lambda (c)
            (nanopass-case (Ltypescript Program-Element) c
              [(circuit ,src ,name (,arg* ...) ,ret-type ,body)
               (out (format "    pub fn ~a(\n" (camel->snake name)))
               (out "        &self,\n")
               (out "        ctx: CircuitContext<PS>,\n")
               (for-each
                 (lambda (a)
                   (nanopass-case (Ltypescript Argument) a
                     [(arg ,arg-name ,arg-type)
                      (out (format "        ~a: ~a,\n"
                                   (camel->snake arg-name)
                                   (type-rust arg-type)))]))
                 arg*)
               (out (format "    ) -> Result<CircuitResults<PS, ~a>, CompactError> {\n"
                            (type-rust ret-type)))
               ;; Walk body statements, accumulating the last expr as the return.
               (let ([stmts (body->stmts body)])
                 (for-each (lambda (s) (out (stmt-rust s 8))) stmts))
               ;; Default tail: return CircuitResults wrapping ().
               ;; A proper implementation tracks the body's tail expr; M3a's
               ;; tiny.compact body shapes are simple enough to assume () for
               ;; circuits with ret = [] and the last expr-stmt's value otherwise.
               (out "        Ok(CircuitResults {\n")
               (out "            result: (),                              // FIXME: tail expr\n")
               (out "            context: ctx,\n")
               (out "            gas_cost: Default::default(),\n")
               (out "        })\n")
               (out "    }\n\n")]))
          circuit-decl*))

      ;; body->stmts: extracts the statement list from a Body nonterminal.
      (define (body->stmts body)
        (nanopass-case (Ltypescript Body) body   ; ADJUST nonterminal
          [(block (,stmt* ...)) stmt*]
          [else (errorf 'body->stmts "unhandled body: ~s" body)]))
```

Adjust nonterminal/variant names to match Step 9.1.

> **Note about "tail expr":** Compact circuits can either be statements (returning `[]`/unit) or have a final expression (e.g., `circuit get(): Maybe<Field> { return ...; }`). The M3a-minimum approach: walk the body, if the body's last form is a `return` statement, emit it as the tail of `Ok(CircuitResults { result: <expr>, ... })`. If it's a series of expr-stmts, emit `result: ()`. tiny.compact has both shapes; handle both.

- [ ] **Step 9.4: Wire into Program pass**

In the `Program` pass body, replace the `emit-increment-circuit` call with:

```scheme
       (emit-circuits (program-circuits pelt*))
```

- [ ] **Step 9.5: Test against tiny.compact — expect crate to attempt build**

```bash
rm -rf /tmp/tiny-m9-out && mkdir -p /tmp/tiny-m9-out
compactc --rust --skip-ts examples/tiny.compact /tmp/tiny-m9-out 2>&1 | tail -10
cat /tmp/tiny-m9-out/contract/lib.rs | head -100
echo "---building emitted crate---"
(cd /tmp/tiny-m9-out && cargo build 2>&1 | tail -20) || true
```

Three iterations expected:
1. compactc emits but cargo build fails — collect errors, fix the codegen, retry.
2. compactc fails on some circuit shape — narrow to which one, extend expr-rust/stmt-rust.
3. Both succeed — proceed.

Iterate. **Time-box: ~3 hours of iteration; if no progress, escalate.**

- [ ] **Step 9.6: Counter regression**

```bash
rm -rf /tmp/counter-m9-out && mkdir -p /tmp/counter-m9-out
compactc --rust --skip-ts examples/counter.compact /tmp/counter-m9-out
diff -u examples/outputs/counter.compact/contract/lib.rs /tmp/counter-m9-out/contract/lib.rs
```
Expected: counter.increment now emitted via generic walker. Diff is **non-empty** (the M2 hardcoded form had specific Op sequences; the new walker may differ stylistically or in Op order). If semantics are preserved, **update the snapshot**:

```bash
cp /tmp/counter-m9-out/contract/lib.rs examples/outputs/counter.compact/contract/lib.rs
```

…then re-run the byte-parity test from `tests-e2e-rust/`:

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
cargo test -p tests-e2e-rust counter 2>&1 | tail -10
```
If byte-parity still passes, the regression is OK. If it fails, the new walker has changed the StateValue layout — investigate and fix.

- [ ] **Step 9.7: Commit**

```bash
git add compiler/rust-passes.ss examples/outputs/counter.compact/
git commit -S -s -m "feat(rust-passes): generic per-circuit body IR walker" \
  -m "Replaces the M2 hardcoded emit-increment-circuit with emit-circuits walking each Circuit-Declaration in the program. Counter.increment now emitted via the generic walker (snapshot updated); byte-parity test green. tiny.compact's 5 circuits compile end-to-end." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Task M10 — End-to-end test of tiny.compact

**Files:**
- Create: `tests-e2e-rust/tests/tiny.rs`
- Possibly modify: `tests-e2e-rust/Cargo.toml`

- [ ] **Step 10.1: Driver script — compile tiny + cargo build the emitted crate**

Add a Rust integration test:

```rust
// tests-e2e-rust/tests/tiny.rs
//
// End-to-end M3a acceptance test:
//   1. Invoke compactc on examples/tiny.compact (--rust --skip-ts).
//   2. cargo build the emitted crate.
//   3. Compile a minimal #[witnesses]-using consumer to confirm the
//      proc-macro pattern works with the emitted trait.

use std::path::PathBuf;
use std::process::Command;

fn workspace_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .parent()
        .unwrap()
        .to_path_buf()
}

#[test]
fn tiny_compiles_via_compactc_rust() {
    let root = workspace_root();
    let out = tempfile::tempdir().expect("tempdir");

    // Step 1: compactc --rust --skip-ts examples/tiny.compact <out>
    let status = Command::new("compactc")
        .args([
            "--rust",
            "--skip-ts",
            root.join("examples/tiny.compact").to_str().unwrap(),
            out.path().to_str().unwrap(),
        ])
        .status()
        .expect("compactc not on PATH (enter `nix develop` first)");
    assert!(status.success(), "compactc failed");

    // Step 2: cargo build the emitted crate.
    let status = Command::new("cargo")
        .arg("build")
        .current_dir(out.path())
        .status()
        .expect("cargo build");
    assert!(status.success(), "emitted tiny crate failed to cargo build");

    // Step 3: Read the generated lib.rs and assert key shapes are present.
    let lib_rs = std::fs::read_to_string(out.path().join("contract/lib.rs")).unwrap();
    assert!(lib_rs.contains("pub enum STATE"), "STATE enum missing");
    assert!(lib_rs.contains("pub trait Witnesses<PS>"), "Witnesses trait missing");
    assert!(lib_rs.contains("fn secret_key("), "secret_key witness signature missing");
    assert!(lib_rs.contains("pub fn set("), "set circuit missing");
    assert!(lib_rs.contains("pub fn get("), "get circuit missing");
    assert!(lib_rs.contains("pub fn clear("), "clear circuit missing");
    assert!(lib_rs.contains("pub fn in_state("), "in_state circuit missing");
    assert!(lib_rs.contains("pub fn public_key("), "public_key circuit missing");
}
```

Add `tempfile = "3"` to `tests-e2e-rust/Cargo.toml` `[dev-dependencies]`.

- [ ] **Step 10.2: Run**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
cargo test -p tests-e2e-rust tiny_compiles_via_compactc_rust 2>&1 | tail -20
```
Expected: PASS.

- [ ] **Step 10.3: Counter byte-parity regression — final check**

```bash
cargo test -p tests-e2e-rust counter 2>&1 | tail -10
```
Expected: PASS.

- [ ] **Step 10.4: Snapshot tiny's emitted output**

For repeatability + future regression detection:

```bash
mkdir -p examples/outputs/tiny.compact
compactc --rust --skip-ts examples/tiny.compact examples/outputs/tiny.compact
```

Commit the snapshot — diff on future runs is a regression signal.

- [ ] **Step 10.5: Commit**

```bash
git add tests-e2e-rust/tests/tiny.rs tests-e2e-rust/Cargo.toml examples/outputs/tiny.compact/
git commit -S -s -m "test(e2e): tiny.compact end-to-end + snapshot — M3a acceptance" \
  -m "Drives compactc --rust --skip-ts on tiny.compact, cargo-builds the emitted crate, asserts key shapes (STATE enum, Witnesses trait, all 5 circuits). Snapshot at examples/outputs/tiny.compact/ for future regression. This is the M3a acceptance gate." \
  -m "Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>"
git log --format="%h %G? %s" -1
```

---

## Wrap-up tasks (post M10)

After the M3a acceptance gate is green:

- [ ] **Step W.1: Push the branch**

```bash
cd /Users/ysh/iohk/compact/.claude/worktrees/admiring-lehmann-05e4d9
git push origin codegen-rust
```

- [ ] **Step W.2: Update the compact-side cycle docs**

In `docs/superpowers/plans/2026-05-25-rust-codegen.md`, mark M3a milestone complete. Add a note pointing at this plan + the M3a spec.

- [ ] **Step W.3: Update the cross-cycle skill memory**

In `~/.claude/skills/midnight-identity-rust/SKILL.md`, append to the decision log:

```markdown
- **<date>** — M3a complete: tiny.compact emits + builds end-to-end. `compactc --rust --skip-ts` now handles enums, multiple circuits with args, witnesses with concrete return types, constructor body walks, and stdlib helpers (Maybe, pad, disclose, persistentHash mapping). counter.compact byte-parity green. did.compact still requires M3b (Map/Set ledger ADTs + multiple structs + Opaque) and M3c (generics + module imports).
```

- [ ] **Step W.4: Brainstorm M3b** (separate session)

When you're ready to continue: switch back to `superpowers:brainstorming`, scope M3b around the next test contract (`proposal.compact` or a custom `tiny-map.compact`).

---

## Self-review (run after writing this plan)

**Spec coverage:** every M3a spec deliverable maps to a task: §6.1 (runtime helpers) → M1; §6.2 (macros crate) → M2-M3; §6.3 (enum emission) → M6; §6.3 (stdlib/type mapping) → M5; §6.3 (witness emission) → M7; §6.3 (constructor walker) → M8; §6.3 (circuit body walker) → M9; §7 (acceptance gates) → M10. Spec §11 open decisions are referenced but deferred to implementer judgment within tasks (not blocking). R1 (upstream-of-rust-passes crash) is mitigated by M4 as an explicit gate. ✓

**Placeholder scan:** zero `TBD`/`implement later`/`fill in details`. Some steps say "ADJUST to actual IR" with explicit recon commands — those are bounded investigation steps, not placeholders. The "FIXME: tail expr" in M9 step 9.3 is intentional and addressed in step 9.5's iteration loop. ✓

**Type consistency:** Witnesses trait shape matches between M3 macro spec, M7 emit-witnesses output, M10 test assertion. `Bytes<N>`, `Maybe<T>`, `pad`, `disclose`, `some`, `none` named identically across M1, M3, M5, M6, M7, M8. `Fr` consistently used for `Field`. Constructor signature in M8 matches CircuitContext signature in M9. ✓

**Known weakness:** Several tasks (M5-M9) require recon of `Ltypescript` IR variant names that I haven't pinned down — `nanopass-case` patterns are written with `ADJUST` comments. Implementer must verify these against `compiler/langs.ss` before writing code. This is unavoidable without reading hundreds of lines of Scheme into the planning context; the recon steps are explicit and bounded.
