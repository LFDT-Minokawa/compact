# Implementation plan: store nesting beyond `Map`

*Companion to `first-class-adts-design.md` §11.1. Written because the claim in that section
— that letting other ADTs hold stores "costs one token" — was wrong in both magnitude and
scope, and the correction is worth writing down properly. Citations verified against the
working trees on 2026-08-28; inferences marked **INFERRED**.*

---

## 0. The correction

`first-class-adts-design.md` §11.1 said:

> `List<Cell<Field>>` is rejected today only because `List`'s parameter is declared `Type` at
> `midnight-ledger.ss:798` […] Changing `List`, `Set` and `MerkleTree` to admit `Store`
> arguments is a kinding change, and the machinery beneath it already works.

Three things are wrong with that.

**Wrong scope, part 1: `Map<K, S>` already works.** Store nesting inside `Map` is not a
future feature; it ships. `examples/adt/tests/map_field_list_field.compact:19` is

```compact
export ledger c: Map<Field, List<Field>>;
```

and `compiler/javascript-code/test1135/` contains a fully generated two-level
`Map<Field, Map<Field, JubjubPoint>>` artifact, `.d.ts` and `.js` both. So "nested tables,"
"a counter per key," "a list per key," and "a map of maps" are all expressible today. Most
of what §11.1's table attributes to a *future* composition feature is available now.

**Wrong scope, part 2: `Set` and `MerkleTree` cannot hold stores at all**, for reasons that
have nothing to do with kinding.

- `Set<V>`'s `V` is a **key**, not a place. `Set.insert` is
  `push [value (state-value 'cell elem)]; push [value (state-value 'null)]`
  (`midnight-ledger.ss:658-662`) — the element becomes the map key and the value is `Null`.
  A set of places is not a meaningful type.
- `MerkleTree<h, V>`'s `V` is **hashed into a leaf**. A store has no alignment and cannot be
  hashed — that is the same property `expand-serialize.ss:205` refuses, and
  `infer-types.ss:807-813` already rejects even `Opaque` values in Merkle inserts for the
  weaker version of this reason.

So the blocked set is not "every ADT except `Map`." It is **`List<S>`, and nothing else.**

**Wrong magnitude: `List` has no operation that could do the nesting.** This is the real
finding. Nesting requires an op whose result type *is* the ADT parameter, so that the
accessor chain can continue through it. `Map.lookup` is declared

```scheme
741  (function read lookup ([key key_type]) value_type
```

— result type is the bare `value_type` formal. **`List` has no such op.** `List.head` is

```scheme
843  (function read head () (Maybe value_type)
```

and `Maybe<T>` is a `struct` — kind `Val` — which can never carry a place. There is nothing
to nest *through*. A new operation has to be designed, and designing it turns out to expose
the general shape of the feature.

---

## 1. What the change really is

Not a kinding change. It is: **implement the `nav` op class** (`first-class-adts-design.md`
§6.8) and give `List` an instance of it.

The design document arrived at `nav` from the opposite direction — asking whether an `op`
can return a reference — and concluded that a non-terminal `Map.lookup` already is one,
compiling to zero opcodes because `propagate-ledger-paths.ss:157-171` dissolves it into a
path element. This plan is the same conclusion reached from implementation: the thing
standing between `List` and store nesting is that "an operation may yield a place" is
hardcoded to one ADT and one op name.

**Total hardcoded `Map`/`lookup` surface in the compiler: five lines in three files.**

| Location | Code | Role |
|---|---|---|
| `propagate-ledger-paths.ss:44` | `(unless (eq? adt-name 'Map) (source-errorf src "ADT nesting is permitted only within Map ADTs"))` | the gate |
| `propagate-ledger-paths.ss:159` | `(assert (eq? adt-name 'Map))` | re-asserts the gate |
| `propagate-ledger-paths.ss:161` | `(assert (and (eq? ledger-op 'lookup) (fx= (length expr*) 1)))` | shape assumption, IR |
| `print-typescript.ss:1557-1559` | `(assert (and (eq? ledger-op 'lookup) (fx= (length type*) 1) (not (public-adt? (car type*)))))` | shape assumption, codegen |
| `extract-contract-info.ss:52` | `[(Map) (list (cons "key" …) (cons "value" …))]` | JSON writer — **already has `List`; no change** |

Five lines is genuinely small. What is not small is that every one of them encodes the same
assumption — **a nesting step takes exactly one argument and contributes a dynamic key** —
and `List`'s nesting step takes **zero** arguments and contributes a **static index**.

---

## 2. Phase 0 — the design decision that has to come first

`List` needs a `nav` op. Proposed:

```
(function nav first () value_type
  "Focuses the first element of this List.  Fails if the List is empty; guard with isEmpty."
  (path-element (align 0 1)))
```

Four points about that declaration, each of which is a decision:

**(a) A `nav` op has a path contribution, not a VM-code body.** It emits no opcodes, so
giving it a `(vm-instruction ...)` list would be misleading and would force
`propagate-ledger-paths` to *infer* the path contribution by pattern-matching the body. A
new DSL clause `(path-element …)` states it directly. This is the cleanest form of the
change and it also retro-fits `Map.lookup`, whose contribution is "the single argument, as a
dynamic key."

**(b) `nav` is partial, and partiality is the caller's problem.** `List.first` on an empty
list navigates to slot 0, which holds `Null`; a subsequent operation then fails with
`ExpectedCell` (`onchain-vm/src/state_value_ext.rs:26-31`). This is **exactly** the existing
behaviour of `Map.lookup` on an absent key — `idx` returns `StateValue::Null`
(`onchain-vm/src/vm.rs:178-188`) and the next op fails. The discipline is unchanged: guard
with `isEmpty()` as you today guard with `member()`. Document it; do not try to fix it.

**(c) `head` and `first` coexist, conditionally.** `head(): Maybe<V>` remains correct and
useful when `V : Val`; `first(): V` is the `nav` form when `V : Store`. The op table already
supports conditional operations — `ADT-Op-Condition` (`langs.ss:444-445`) and
`midnight-ledger.ss:566`'s `(when (= value_type QualifiedShieldedCoinInfo) …)`, which is how
`Cell<QualifiedShieldedCoinInfo>` gains `writeCoin` that other cells lack. **The condition
language must be extended from type equality to a kind predicate** (`(when (val? value_type)
…)` / `(when (store? value_type) …)`). That is a small, well-precedented extension and it is
the mechanism the whole `Val`/`Store` reform will want anyway.

**(d) Two head-like operations is a surface wart.** It is the honest cost of `Maybe` being a
product type. If real sums land (`coherent-type-landscape.md` reform item 2) it does not go
away either — `Maybe<&S>` is a fine `Val`, but a `Maybe` of a *place* is not a place, so the
`nav` form is still needed. Accept the wart.

---

## 3. The work, phased

### Phase 1 — the `nav` op class (the bulk)

1. **`compiler/ledger.ss`** — add `nav` to the op-class vocabulary parsed by
   `declare-ledger-adt` (`:197-221`), and add the `(path-element …)` clause form as an
   alternative to `(vm-instruction …)`. Reject a `nav` op that has both, or neither.
2. **`compiler/langs.ss`** — `ADT-Op` (`:882-885`) carries `vm-code`; a `nav` op needs to
   carry a path contribution instead. Either widen `vm-code` or add a variant. Extend
   `ADT-Op-Condition` (`:444-445`) with kind predicates.
3. **`compiler/analysis-passes/propagate-ledger-paths.ss`** — the heart of it.
   - `check-adt-nesting!` (`:35-52`): replace the `'Map` gate at `:44` with "the parent ADT
     declares a `nav` op whose result type is this store." Keep the `'Kernel` veto at
     `:47-48` — that one is a genuine special case, not an artifact.
   - The fold (`:127-172`): replace the asserts at `:159-161` with a dispatch on the nav
     op's declared path contribution, building either a `path-index` or a
     `(src type expr)` element (`langs.ss:888-890` already has both variants).
   - `:163` `(assert (not (public-adt? (car type*))))` becomes vacuous for a zero-argument
     nav op; guard it.
4. **`compiler/analysis-passes/infer-types.ss`** — `find-adt-op` (`:790-833`) already
   resolves ops generically by name. `desugar-ledger-read` (`:1179-1186`) collapses a
   dangling ADT by finding a `read` op; a `nav` op must **not** satisfy that search, or
   `ledger.myList` would silently become `ledger.myList.first()`. Add the exclusion.

### Phase 2 — the `List` declaration (mechanical, once Phase 1 lands)

All in `compiler/midnight-ledger.ss`:

5. `:798` — `(declare-ledger-adt List ([Type value_type])` → `([ADT/Type value_type])`.
   *This is the one token.*
6. Add `first` as above, conditional on `value_type : Store`.
7. Make `head` (`:843-878`) conditional on `value_type : Val`.
8. `pushFront` (`:885-914`) pushes the element wrapped in a cell:
   ```scheme
   (push [storage #t] [value (state-value 'array ((state-value 'cell value)
                                                  (state-value 'null)
                                                  (state-value 'null)))])
   ```
   For a store element this must become `(state-value 'ADT value value_type)`, mirroring
   `Map.insert` at `:750`. Conditional on kind.
9. Add `pushFrontDefault`, mirroring `Map.insertDefault` (`:755-761`). This is not optional:
   with a store element, the only callable argument to `pushFront` is `default<S>` — which
   is precisely why `Map` has both forms, and why the reference's own nested example writes
   `fld.lookup(b).insert(disclose(n), default<Counter>)` (`doc/compact-reference.mdx:1678`).
10. `pushFrontCoin` (`:916-…`) is conditional on `value_type = QualifiedShieldedCoinInfo`,
    which is a `Val`, so it is unaffected — but check the condition still resolves once the
    formal's kind can be `Store`.

### Phase 3 — TypeScript `.js` codegen (contained but fiddly)

All in `compiler/typescript-passes/print-typescript.ss`, `adt-op-body-Q` `:1552-1577`:

11. `:1557-1559` — the `'lookup`/arity-1 assert becomes a dispatch on the nav op's declared
    contribution.
12. `:1560-1562` — currently *unconditionally constructs* a dynamic path element from
    `(car var-name*)`. With a zero-argument nav op, `(car var-name*)` errors. Branch on the
    contribution kind and append a `path-index` in the static case.
13. `:1564-1570` — the existence guard is `state<path> === undefined`, which is `StateMap.get`
    semantics. **A `List` head on an empty list is a null `StateValue`, not `undefined`**, so
    the guard would silently never fire. Each nestable ADT needs to declare its existence
    predicate: `=== undefined` for `Map`, `.type() == "null"` for `List` (the shape `List.iter`
    already tests at `:810`). INFERRED, from the initial value at `:800-802` and the iterator
    body; worth confirming against a built artifact.
14. `:1568` — the literal `` `Map value undefined for ${…}` `` error string is parameterized
    by the same declaration.

### Phase 4 — TypeScript `.d.ts` codegen

15. **No change.** `op-signature-Q` (`:636-644`) recurses structurally on any `tadt` and has
    no `'lookup` assert — unlike its `.js` twin. Its one constraint, `:631`
    `(assert (not (public-adt? type)))` on arguments, is satisfied by a zero-argument op.
    Add a golden test to keep it that way.

### Phase 5 — the `iter` regression

16. `List.iter` (`:803-818`) does `${value_type}.fromValue(head.asCell().value)` — wrong for
    a store element, since there is no descriptor for an ADT
    (`prepare-for-typescript.ss:175-192` skips `(public-adt? type)`).
    It is **already handled, by deletion**: the `remp` filter at `print-typescript.ss:1527-1538`
    (and its `.d.ts` twin at `:682-693`) drops every js-only op when *any* `adt-arg` of the
    enclosing ADT is a store. Verified empirically — `Map<Bytes<32>, Counter>` generates no
    `[Symbol.iterator]` (`fee-mint/contract/index.d.ts:63-70`) while `Map<Field, JubjubPoint>`
    does (`test1135/contract/index.d.ts:22-28`).

    So `List<Counter>` compiles, and `for (const x of ledger().myList)` silently disappears.
    That is a user-visible regression relative to `List<Field>`. Two options: accept and
    document, or write a store-aware iterator that yields nested accessor objects rather
    than decoded values. The second is **new work, not a `Map` un-hardcoding** — the filter
    is already ADT-name-agnostic.

### Phase 6 — tests

17. `compiler/test.ss` holds golden `.d.ts`/`.js` fixtures (see `:77605-77677` for the
    existing `Map<Boolean, Map<…>>` and `Map<Boolean, Counter>` cases). ADT table changes
    ripple through these broadly.
18. `examples/adt/tests/` needs `list_counter.compact`, `list_map_field_field.compact`, and a
    negative test that `Set<Counter>` and `MerkleTree<8, Counter>` are still rejected —
    with a *good* message, not the generic kind error.

---

## 4. What needs no change at all

Worth listing, because it is the part that makes this tractable rather than open-ended.

| Component | Why it is fine |
|---|---|
| **The Impact VM, runtime, cost model, replay checker** | The VM has never heard of a ledger ADT. A `List` of stores is an `Array` of whatever. |
| `path-chain-Q` (`print-typescript.ss:1540-1551`) | Already handles both `Path-Element` variants — `.asArray()[~d]` and `.asMap().get(…)`. |
| `construct-vm-instructions` (`:437-441`) | Same, for VM ops. |
| `is-runtime-op?` (`:507-511`), `has-read?` (`:493-498`) | Keyed on `op-class`, not ADT name. |
| The `remp` js-only filters (`:682`, `:1527`) | Keyed on `adt-arg*`, not ADT name. |
| `extract-contract-info.ss:43-60` | Closed case over ADT names, but `List` (`:55`) and `Cell` (`:48`) are already in it, and the recursion at `:273` is ungated. |
| `expand-modules-and-types.ss:256-263` | Kind check is generic; only the declared meta-type changes. |
| `check-sealed-fields.ss:49-67` | `read-op?` walks accessor chains and pulls nested `adt-op*` out of each op's return type, generically. |
| `determine-ledger-paths.ss` | Concerns only the top-level B-tree. |

---

## 5. Sizing, sequencing, and risks

**Sizing.** Phase 1 is the project; Phases 2–4 are a day or two each once it lands; Phase 6
is larger than it looks because ADT-table changes churn golden files broadly. This is a
multi-week compiler change with a design decision at the front, not a one-line kinding
tweak. My §11.1 estimate was off by more than an order of magnitude.

**Sequencing.** The depth check from `first-class-adts-design.md` §8.3 should land **first**,
independently. `List` nesting adds a path level, `pushFront` already emits
`ins [n (add1 (length f))]` (`midnight-ledger.ss:914`), and the reach budget is silently
unchecked today (`midnight-ledger.ss:577`, and nothing in the VM range-checks the nibble —
`Dup { n: 16 }` field-reprs identically to `Dup { n: 0 }`). Making paths easier to compose
without first making the budget checkable is the wrong order.

**Risks.**

- *The existence-predicate change (item 13) is the one that can ship a silent bug.* A guard
  that never fires produces a confusing runtime failure deep in `queryLedgerState` instead of
  a clear `CompactError`. Test the empty-list case explicitly.
- *`nav` interacts with `desugar-ledger-read`.* If a `nav` op is accidentally reachable by
  the `read` search at `infer-types.ss:1182`, `ledger.myList` starts meaning
  `ledger.myList.first()`. That is a quiet semantic change to existing programs.
- *Kind-conditional ops are new.* `ADT-Op-Condition` today tests type equality. Kind
  predicates are a small extension, but they are the first place the compiler will need a
  kind *judgement* rather than a meta-type *tag* — which is the `Val`/`Store` reform arriving
  through the back door. That may be an argument for doing the reform first rather than
  bolting a predicate on.

---

## 6. Recommendation

**Do not do this first.** The corrected scope changes the priority ordering in
`first-class-adts-design.md` §13.

The reasoning: `Map<K, S>` already composes, and it covers the great majority of what users
mean by "let me build structures out of ledger types" — a counter per key, a map per key, a
list per key, two levels deep, all shipping today with generated TypeScript. What `List<S>`
adds on top is **ordered collections of stores with push/pop and no index management**. That
is real, and it is narrow.

Meanwhile `&` (`first-class-adts-design.md` §6) needs none of this machinery: it introduces
no new nesting, no new op class, no change to `propagate-ledger-paths`'s shape assumptions,
and no change to the `.js` nested-accessor generator. It delivers
`transfer(from, to, amount)` — the request that actually motivated the whole inquiry — on
its own.

So the revised order is:

1. The depth check (§8.3). Standalone, closes a silent miscompile, prerequisite for anything
   that composes paths.
2. **`&`.** Self-contained; delivers the motivating use case.
3. The `nav` op class and `List<S>` — this document. Larger than it looked, and it becomes
   easier once `&` has established the vocabulary, because `nav` *is* "an op that returns a
   reference."

Items 2 and 3 were listed the other way round in §13. That was a consequence of the same
mis-estimate this document corrects.
