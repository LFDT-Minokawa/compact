# Spike: resolving `keys(S)` for a store parameter

*Answers the question `place-references-impl-plan.md` §11.1 flagged as needing a spike
before Phase C could be estimated. Verified against the working tree on 2026-08-28.
Result: the concern was misplaced — the resolution does not belong in
`expand-modules-and-types` at all, and where it does belong, everything it needs already
exists.*

---

## 1. The question

`&T` desugars to a store parameter plus a value parameter carrying the access path's
dynamic keys. That value parameter's type depends on the *store argument*, not on `T`:
`&Cell<Uint<64>>` is width 0 at `alice` and 32 bytes at `accounts.lookup(k)`. So the plan
introduced a type form `(tkeys src %S)` — "the key-tuple type of store parameter `%S`" —
to be resolved at instantiation.

§5.3 assumed that resolution happened in `expand-modules-and-types`, and §11.1 flagged it
as the item most likely to be underestimated, because it needs ADT operation signatures at
a point in that pass which is otherwise manipulating types. It also observed there was no
cheap fallback: the front-end pass cannot compute the key type syntactically.

## 2. Why it cannot go in `expand-modules-and-types`

Confirmed, and for a sharper reason than "it would be awkward."

When a ledger declaration is bound into the environment
(`expand-modules-and-types.ss:825-831`):

```scheme
825                  [(public-ledger-declaration ,src ,exported? ,sealed? ,ledger-field-name ,type)
826                   (let ([id (make-source-id src ledger-field-name)])
827                     (let ([info (Info-ledger id)])
828                       (env-insert! p src ledger-field-name info)
829                       (set! frob* (cons (make-frob (reverse seqno) pelt p id) frob*))
```

`Info-ledger` carries **only the id**. The field's `type` stays in the pelt, which is
enqueued as a frob and expanded later by `process-frob`. So at the moment the field's name
enters the environment, its type has not been expanded and the `Info` does not carry it.
Resolving `tkeys` there would mean either extending `Info-ledger` to carry the unexpanded
type plus its environment (the shape `Info-type-alias` uses) and expanding on demand, or
forcing ledger frobs to drain before any circuit frob. Both are real changes to how the
pass is structured.

Neither is necessary.

## 3. Where it belongs: `infer-types`

Three facts, each verified, and together they make this easy.

**(a) `infer-types` already keeps a ledger-field type table.** `:999`:

```scheme
994    [(public-ledger-declaration ,src ,ledger-field-name ,[type])
995     (unless (public-adt? type)
996       (source-errorf src "expected ADT-type for ledger declaration after expand-modules-and-types, received ~a"
997                          (format-type type)))
998     (check-secp256k1 type)
999     (set-idtype! ledger-field-name (Idtype-Base type))]
```

`set-idtype!`/`get-idtype` is an `eq-hashtable` on id records (`:32-43`). `ledger-ref`
resolution already reads it back at `:1147-1156`. So given a field id, its fully-expanded
`tadt` is one lookup away.

**(b) That table is populated by a prepass, so forward references work.** `Program`
(`:952-981`) runs the type-registering sweep over *every* program element before
transforming any of them:

```scheme
962     (for-each Set-Program-Element-Type! unused-pelt*)
963     (for-each Set-Program-Element-Type! pelt*)
...
972         (let* ([pelt* (maplr Program-Element pelt*)]
```

`Set-Program-Element-Type!` (`:982`, `-> * (void)`) is where `:999` lives. **By the time
any circuit body is transformed, every ledger field's expanded type is registered.**

**(c) The op signatures are right there.** `find-adt-op` (`:790-833`) destructures an
`ADT-Op` as

```scheme
801                [(,ledger-op ,op-class ((,var-name* ,type^* ,discloses?*) ...) ,type ,vm-code)
```

`type^*` is the declared argument types, already substituted for this instantiation, and
`type` is the result type. That is exactly what a key-type walk needs: for `Map.lookup` at
`Map<Bytes<32>, Cell<Uint<64>>>`, `type^*` is `[Bytes<32>]` and `type` is `Cell<Uint<64>>`,
which is the store to continue from.

### The resolution, in full

```
keys(field, [op₁ … opₙ]) =
  t ← (get-idtype src field)                    -- an Idtype-Base holding a tadt
  for each opᵢ:
    find opᵢ in t's adt-op* list                -- the same linear scan find-adt-op does
    emit its argument types into the accumulator
    t ← opᵢ's result type
  the accumulated types, as a tuple
```

A fold over the skeleton using machinery already in the file. No new access to the ADT
table, no reordering of the frob worklist, no change to `Info-ledger`.

## 4. What this changes in the plan

**`expand-modules-and-types` gets much less work than §5.3 assumed.** It only has to
*substitute* the store argument into the `tkeys` form — carrying `(tkeys src <skeleton>)`
forward with the skeleton made concrete. It needs no ADT tables at all. The instance-table
work (§5.2) is unaffected, and is the easy part: a `Place-Skeleton` is a symbol plus a list
of `(symbol . nat)`, so hashing and equality are structural and total.

**`tkeys` lives in exactly one language.** It is introduced into `Lexpanded` by the
front-end desugaring and eliminated by `infer-types`, which is the very next pass
(`analysis-passes.ss:75-76`). `fixup-analysis-passes` (`:93-95`) runs the same pair. So
nothing else ever sees it.

**Resolution goes in `infer-types`'s `Type` transformer**, which is also where
`Non-ADT-Type` wraps — so a resolved `tkeys` (a tuple) passes the existing kinding check
with no special case, exactly as §6 of the plan predicted.

## 5. The one hazard this creates, and its fix

`Set-Program-Element-Type!` transforms circuit *argument types* during the prepass —
`,[arg*]` at `:987` is nanopass auto-recursion through `Argument`, which runs the `Type`
transformer. And `:963` sweeps `pelt*` in source order. So a circuit that appears **before**
the ledger declaration it references would hit an unresolved `tkeys` while the field's type
is not yet registered.

The fix is to split the prepass: sweep ledger declarations first, then everything else. Two
lines, and there is an exact precedent in the adjacent pass —
`propagate-ledger-paths.ss:87-88` does precisely this, for precisely this reason:

```scheme
87     (for-each record-ledger-binding! pelt*)
88     `(program ,src ... ,(map Program-Element pelt*) ...)])
```

## 6. Verdict

**Not a risk. Downgrade it.**

The item `place-references-impl-plan.md` §11.1 called "most likely to be underestimated"
turns out to be the opposite: the work is a fold over a skeleton using an existing linear
scan, in a pass that already maintains the table it needs and already runs a prepass to
make forward references work. The apparent difficulty came entirely from assuming the
resolution had to happen in `expand-modules-and-types`, where the field's type genuinely is
not available yet.

Two residual items, both small:

1. **Split the `infer-types` prepass** (§5). Two lines, precedented.
2. **Overload resolution on `tkeys`.** `lookup-fun` partitions candidates with
   `compatible-type-parameters?` (`expand-modules-and-types.ss:452-472`), comparing argument
   types. Two circuits differing only in a `tkeys` argument would be compared before
   resolution. Almost certainly unreachable in practice — the store parameters would differ
   too — but worth a test rather than an assumption.

**Phase C is smaller than the plan estimated, not larger.** The remaining unknown in
`place-references-impl-plan.md` is Phase B, the front-end desugaring itself, which is
ordinary syntax-directed work, and Phase E, the alias analysis.
