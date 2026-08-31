# Implementation plan: checking ledger access-path budgets

*Companion to `first-class-adts-design.md` §8. This is a standalone bug fix — it has no
dependency on first-class ADTs, store nesting, or the `Val`/`Store` reform, and it should
land before any of them. All citations verified against the working trees on 2026-08-28.*

---

## 1. The bug

Ledger ADT operations emit `dup`, `swap`, `ins` and `idx` whose operands are computed from
the access-path length at macro-expansion time. Those operands are **nibbles**. Nothing
anywhere checks that they fit.

`Cell.writeCoin`, `compiler/midnight-ledger.ss:566-585`:

```scheme
573      ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
574       (push [storage #f] [value (state-value 'cell (car (reverse f)))])
575       ;; Reach to the context in the stack: past the two pushes above, the
576       ;; result, and 2n path items of the idx, and the effects.
577       ;; note that if `f` is longer than 5, this exceeds the limit of 15.
578       (dup [n (+ 3 (* (sub1 (length f)) 2))])
```

The author knew. The comment is the only enforcement that exists.

**Why it is silent.** `Dup` serializes as `0x30 | n` (`onchain-vm/src/ops.rs:501`), so
`Dup { n: 16 }` produces the same field element as `Dup { n: 0 }` and `Dup { n: 20 }` the
same as `Dup { n: 4 }`. There is no range check:

- not in the VM — `vm.rs:794-807` indexes the stack directly with `*n as usize`;
- not in the serializer — `Op`'s `Serializable`/`Storable` derives carry no `invariant =`
  attribute (`ops.rs:145-153`), unlike `StateValue` at `onchain-state/src/state.rs:76`;
- not in the ledger — `ledger/src/verify.rs` normalizes transcripts only for
  `FallibleWithoutCheckpoint` (`:1886-1891`) and adjacent `Noop`s (`:1898-1903`);
- not in the compiler — exhaustive grep finds no `source-errorf` guarding path length.

So an over-long path does not fail to compile and does not fail at runtime. It emits a
*different, valid* opcode that reads the wrong stack slot. The proof commits to it
(`verify.rs:1944-1970` field-reprs every op), so the transaction is well-formed. **This is a
silent miscompile that produces a signed, on-chain-valid wrong answer.**

**How a user reaches it without doing anything unusual.** Path depth has three sources and
only one is visible in a type:

1. store nesting — each `Map` layer adds one;
2. **the ledger B-tree prefix** — `determine-ledger-paths.ss:24-48` packs ledger fields into
   a ≤15-ary tree, so depth is `ceil(log₁₅ |fields|)`;
3. (future) a caller's path prefix at a `&` parameter (`first-class-adts-design.md` §6).

Source 2 is the trap. **Adding a sixteenth ledger field deepens every path in the contract
by one**, and can push a `writeCoin` over the limit in a circuit nobody touched.

---

## 2. Scope: every budget, and who owns it

| Budget | Limit | Encoding site | Owner |
|---|---|---|---|
| `Dup` reach | ≤ 15 | `ops.rs:501` `0x30 \| n` | VM |
| `Swap` reach | ≤ 15 | `ops.rs:502` `0x40 \| n` | VM |
| `Ins` levels | 1..15 | `ops.rs:503-504` `0x90 \| n`, `0xa0 \| n` | VM |
| `Idx` path length | ≤ 16 keys | `ops.rs:501-522`, `\| (path.len() - 1)` | VM |
| `Array` / store-tuple arity | ≤ 16 | `onchain-state/src/state.rs:69-96` | VM |
| ledger B-tree arity | 15 | `langs.ss:851` `maximum-ledger-segment-length` | compiler |
| Merkle depth | 2..32 | `langs.ss:103-104`; enforced at `infer-types.ss:1079-1086` | **already checked** |

Only the last is enforced today. Note also `langs.ss:850`'s standing FIXME —
`; FIXME: maximum-ledger-segment-length should be defined by the ledger` — which is the same
complaint one level up: the compiler holds a private copy of a VM constant.

---

## 3. Design: check the artifact, not a model of it

The tempting implementation is to re-derive a maximum path depth per operation
symbolically — "`writeCoin` needs `2d+1 ≤ 15`, so `d ≤ 7`." **Don't.** The operand formulas
live inside the ADT DSL as arbitrary Scheme, and there are **36 sites and five distinct
formulas**, verified by `grep -n "length f" compiler/midnight-ledger.ss`:

| Formula | Sites | Bound implied |
|---|---|---|
| `(dup [n (+ 5 (* (length f) 2))])` | `:940` `List.pushFrontCoin` | **d ≤ 5** |
| `(dup [n (+ 3 (* (length f) 2))])` | `:781` `Map.insertCoin` | d ≤ 6 |
| `(dup [n (+ 2 (* (length f) 2))])` | `:680` `Set.insertCoin` | d ≤ 6 |
| `(dup [n (+ 3 (* (sub1 (length f)) 2))])` | `:578` `Cell.writeCoin` | d ≤ 7 |
| `(ins [n (+ (length f) 2)])` | `:1338` | d ≤ 13 |
| `(ins [n (add1 (length f))])` | `:914`, `:968`, `:1052`, `:1084`, `:1229`, `:1255`, `:1274`, `:1300`, `:1327` | d ≤ 14 |
| `(ins [n (length f)])` | 12 sites | d ≤ 15 |
| `(ins [n (suppress-zero (sub1 (length f)))])` | 9 sites | d ≤ 16 |

Note what this table shows about the comment at `:577`. It sits on `Cell.writeCoin` and says
"if `f` is longer than 5, this exceeds the limit of 15" — but that op's actual bound is
**7**. The op whose bound really is 5 is `List.pushFrontCoin` at `:940`, which carries no
warning at all. **The one piece of documentation that exists is attached to the wrong
operation.** That is the strongest possible argument for a mechanical check.

Re-deriving these duplicates them, and the duplicate will drift. Worse, it fails at exactly
the moment it matters: the realistic way this bug gets introduced is *someone adds an ADT
operation and gets its `dup` arithmetic subtly wrong*, and a symbolic model keyed on
op-class would not notice.

So: **expand the operation's VM code with the concrete path, then range-check every emitted
operand.** That checks what is actually emitted. It is automatically correct for any op
anyone adds later, including ops with formulas nobody anticipated.

The machinery already exists and is **backend-neutral**, which resolves the one structural
question this plan had. `expand-vm-code` (`compiler/vm.ss:160-172`):

```scheme
(define (expand-vm-code src f f-cached arg-alist code)
  (define expand-vm-expr (make-expand-vm-expr (cons* (cons 'f f) (cons 'f-cached f-cached) arg-alist)))
  (define (expand-vm-instruction i)
    (syntax-case i ()
      [(op [x e] ...)
       (make-vminstr
         (symbol->string (datum op))
         (map cons (map symbol->string (datum (x ...))) (map expand-vm-expr #'(e ...))))]))
  ...)
```

It returns `vminstr` records — an op name as a string plus an alist of operand-name to value
— and each backend prints that structure. It is a plain function in `compiler/vm.ss` with no
backend context threaded in. **An analysis pass can call it directly; no factoring is
needed.** Three backends already do: `print-typescript.ss:435`, `print-zkir.ss:548`,
`reduce-to-zkir.ss:622`.

**One implementation detail to get right.** `arg-alist` maps the operation's *arguments* to
values, and in the backends those are `vmref`s wrapping already-emitted JS or ZKIR. An
analysis pass has no such thing. It does not need them — every budget formula depends on
`(length f)` alone, never on an argument — but `expand-vm-code` maps eagerly over all
instructions, so an operand it cannot expand aborts the whole expansion. Two options:

- pass placeholder values that satisfy the DSL's `insist` predicates (`vm.ss:186-190`), or
- add a mode in which unexpandable operands yield a sentinel instead of raising.

There is precedent for calling it with a degenerate context: `print-typescript.ss:2599`
passes `#f` for both `f` and `f-cached` when expanding an `emit`. Check that path before
choosing.

---

## 4. Where it goes

A new analysis pass, `check-ledger-budgets`, inserted in
`compiler/analysis-passes.ss` immediately after `propagate-ledger-paths`:

```scheme
    (determine-ledger-paths          Lwithpaths0)
    (propagate-ledger-paths          Lwithpaths)
    (check-ledger-budgets            Lwithpaths)     ; new; identity on the IR
    (track-witness-data              Lwithpaths)
```

That position is forced, and it is the only one that works:

- **After `propagate-ledger-paths`** (`:87`), because that is where the full `path-elt*`
  list is assembled — `:156` builds `(,path-index* ... (,path-src* ,path-type* ,path-expr*) ...)`,
  concatenating the static B-tree prefix with one element per traversed `lookup`. Before this
  pass the depth is not known.
- **After `expand-modules-and-types`** (`:75`), so every generic is monomorphized and each
  site has a concrete path. This is free — it is four passes earlier.
- **Before the backends**, so the diagnostic is a compile error rather than a
  wrong-code-generation event.

The pass is a pure checker: it walks `public-ledger` nodes, runs the expansion, reports, and
returns the IR unchanged. `Lwithpaths → Lwithpaths`, no grammar change.

---

## 5. What it does, per `public-ledger` node

```
(public-ledger src ledger-field-name sugar? (path-elt ...) src^ adt-op expr* ...)
```

1. **Path length.** `(length path-elt*)` ≤ 16, since a single `Idx` carries at most 16 keys
   (`ops.rs:501-522`). If the emitted code splits the path across several `idx` ops this is
   generous; the emitted-operand check below is the authoritative one.
2. **Expand.** Call `expand-vm-code` with `f = path-elt*` and the op's arguments, exactly as
   `print-typescript.ss:431-441` does. Symbolic key expressions do not need evaluating — only
   `(length f)` is consumed by the arithmetic, and the elements themselves are opaque to it.
3. **Range-check every emitted operand:**
   - `dup n`, `swap n` → `0 ≤ n ≤ 15`
   - `ins n` → `1 ≤ n ≤ 15`
   - `idx path` → `1 ≤ (length path) ≤ 16`
   - `noop n` → `n ≥ 1` (an `n: 0` noop field-reprs to nothing, `ops.rs:466`)
4. **Report** at `src^` — the source location of the `.` before the terminal operation, which
   `propagate-ledger-paths` preserves for exactly this purpose (`langs.ss:877-879`).

**The error message is most of the value.** A bare "path too deep" is not actionable, because
the user did not choose most of the depth. Decompose it:

```
error: ledger operation `writeCoin` exceeds the VM's stack-reach limit at this path depth
  --> contract.compact:42:18
   |
   |   accounts.lookup(a).lookup(b).writeCoin(coin, recipient)
   |                               ^^^^^^^^^^
   |
   = path depth is 8: 6 from the ledger field layout, 2 from Map nesting
   = `writeCoin` emits `dup 17`; the limit is 15
   = the contract declares 84 ledger fields, which requires a 2-level field tree;
     reducing to 15 or fewer top-level fields would remove 1 level
```

The last line matters. The B-tree contribution is invisible in the source, and "you have too
many ledger fields" is a fix the user would otherwise never find.

---

## 6. Second-order items worth doing in the same change

**(a) Bound the static-index predicate against the real constant.** `langs.ss:852-855`:

```scheme
851  (define maximum-ledger-segment-length 15)
852  (define (path-index? x)
853    (and (fixnum? x) (fx>= x 0) (fx< x maximum-ledger-segment-length)))
```

One constant does two jobs — B-tree arity and the `[0,15)` terminal predicate — so widening
one silently widens the other. Split them, and resolve the `:850` FIXME by deriving the
value from the ledger crate rather than restating it.

**(b) Run it over the existing corpus first.** Before shipping the error, run the check in
warn-only mode across `compiler/test.ss` fixtures, `examples/`, and any contracts in
`midnight-contracts` / `compact-contracts`. That answers the question this plan cannot: **is
this bug theoretical or live?** If something already violates a budget, that is an incident,
not a lint. Do this first — it is an afternoon and it sets the urgency for everything else.

**(c) Consider a VM-side invariant too.** Adding an `invariant =` attribute to `Op`'s
`Storable` derive (`ops.rs:145-153`), matching `StateValue`'s at `state.rs:76`, would make
out-of-range nibbles unrepresentable rather than merely uncompiled. That is a
`midnight-ledger` change and would need care about whether it is consensus-affecting for
already-accepted transcripts — **almost certainly it is, so treat it as a separate
conversation**, not part of this change. The compiler-side check is the part that is free.

---

## 7. Tests

1. **Golden negative tests**: a contract with enough ledger fields to force a 2-level B-tree
   plus two levels of `Map` nesting, calling `writeCoin`. Assert the error and its text.
2. **Boundary tests** at exactly the limit and one past it, for each of `dup`, `swap`, `ins`,
   `idx`.
3. **The B-tree cliff**: two contracts differing only in having 15 vs 16 ledger fields, where
   the second fails. This is the regression that documents the surprising interaction.
4. **A positive test** that deep-but-legal paths still compile, so the check is not
   over-eager — `Map<K1, Map<K2, Map<K3, Counter>>>` with `increment`, whose `ins n` is
   `(length f)` rather than `2·(length f)`, should be fine well past where `writeCoin` fails.

---

## 8. Sizing

Small. One new pass, no grammar change, no backend change, no ledger change. The pass body is
a walk plus a call into existing expansion machinery, which §3 confirms is backend-neutral
and directly callable. The error message is more work than the check.

Item 6(b) — running it warn-only over the corpus — is the highest-value hour in the whole
plan, because it converts a hypothesis into either "closed a latent bug" or "found a live
one." Do that first. Given the table in §3, the query to run first is: **does any contract
call `List.pushFrontCoin`, `Map.insertCoin` or `Set.insertCoin` at a path depth above 5?**
Those three are the tight bounds, and they are the coin-writing operations — so a violation
would be a silent miscompile in exactly the code that moves value.
