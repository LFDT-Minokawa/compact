# Implementation plan: `&` — place references

*Companion to `first-class-adts-design.md` §6. Siblings: `depth-check-impl-plan.md` (do that
first) and `store-nesting-impl-plan.md` (do that after). Citations verified against the
working trees on 2026-08-28; inferences marked **INFERRED**.*

---

## 0. Assumptions this plan makes

Two open questions from `first-class-adts-design.md` §14 are answered here by decision, not
by argument. Both are cheap to revisit later; neither is load-bearing for the architecture.

1. **`&` is required at the call site.** `credit(alice, …)` stays an error; `credit(&alice, …)`
   is how you pass a place. This preserves the disambiguation property the Millikin proposal
   needed a whole-language move to explicit `Cell` reads to get, at the cost of one sigil.
2. **The alias analysis defaults to deny**, with a one-line escape (`assert(from != to, …)`,
   or an explicit opt-in annotation for last-write-wins).

3. **Argument and return position are built together.** An earlier draft deferred return
   position on the grounds that it needs inference Compact deliberately lacks. That was
   wrong — §12 retracts it and gives the corrected analysis. The one genuine cost of return
   position lands in the alias analysis (§7), not in the elaboration.

---

## 1. The change, in one paragraph

`&T` in a signature desugars, in the front end, into a **store type-parameter** plus an
**ordinary value parameter** carrying the access path's dynamic keys. `&p` at a call site
desugars into the matching pair of arguments: the place's static skeleton as a generic
argument, its key expressions as ordinary arguments. Monomorphization then does what it
already does. By the time any analysis pass runs, `&` does not exist, and what remains is a
generic circuit with one extra tuple argument.

```
circuit credit(acct: &Cell<Uint<64>>, amount: Uint<64>) { acct.write(acct.read() + amount); }
credit(&accounts.lookup(to), amount);

    ⇓  expand-place-params

circuit credit<%S>(acct__keys: keys(%S), amount: Uint<64>) { … }
credit<accounts.lookup(·)>([to], amount);
```

---

## 2. The evidence this rests on

Three facts, verified, that make the shape above the right one.

**(a) The environment can already bind a name to a ledger field and resolve it in expression
position.** `expand-modules-and-types.ss:1195-1196`:

```scheme
1195       [(Info-size src^ size) `(quote ,src ,size)]
1196       [(Info-ledger ledger-field-name) `(ledger-ref ,src ,ledger-field-name)]
```

Ledger declarations bind their names this way at `:827`. So a store parameter is a variation
on a mechanism that exists, and `:1195` proves a non-type generic argument can reach
expression position at all. **The zero-width case (`&alice` on a top-level field) is nearly
free.**

**(b) The key half cannot ride in the environment.** Substituting the caller's key expression
into the callee body would capture caller-local variables — the callee is still a separate
top-level definition at this stage, not yet inlined (`inline-circuits` is in
`circuit-passes.ss:65`, five passes and a whole pass-group later). And the instance table
cannot key on expressions: `targ-info-equal?` (`:131-143`) compares `sametype?` and numeric
`=`, nothing else. So the keys must be **values**, passed as arguments.

**(c) Therefore the desugaring must precede monomorphization, because it changes the
callee's signature.** `process-frob` (`:894-895`) is
`(Program-Element (frob-pelt frob) (frob-p frob) (frob-id frob))` — it runs the transformer
over the *raw* pelt, whose parameter list is fixed. Adding a parameter during specialization
would mean rewriting the pelt, not extending an environment.

The precedent for a signature-rewriting front-end pass sits one line above where this one
goes. `expand-patterns` (`frontend-passes.ss:52`, `Lsingleconst → Lnopattern`) turns a
destructuring pattern in argument position into a plain parameter plus bindings
(`doc/compact-reference.mdx:985-1005`), generating fresh names as
`__compact_pattern_tmp~a` (`expand-patterns.ss:20-24`).

---

## 3. Phase A — surface syntax

### A1. Lexer: the token is free

`compiler/lexer.ss:138` and `:282-283`:

```scheme
138          [#\& (seen-ampersand)]
…
282        (define-state-case seen-ampersand c
283          [#\& (return-token 'binop "&&")]
```

`seen-ampersand` accepts only a second `&`. **A bare `&` is currently a lex error, so the
token is unclaimed.** Add an else-branch returning a `&` token. One line, no ambiguity with
`&&`, no possibility of breaking existing programs.

### A2. Parser

`&` as a prefix operator at `expr₈` — binding *looser* than member access and call, so that

```
&accounts.lookup(to)   parses as   &(accounts.lookup(to))
```

which is the reading we want. `compiler/lparser.ss`. Also admit `&T` in type position.

### A3. Grammar (`compiler/langs.ss`)

Four additions to the source language, three of which are deleted again by Phase B:

| Addition | Where | Lifetime |
|---|---|---|
| `(tref src type)` — the type `&T` | `Type` | source → `expand-place-params` |
| `(place-ref src expr)` — the expression `&E` | `Expression` | source → `expand-place-params` |
| `(targ-place src place-skeleton)` | `Type-Argument`, alongside `(targ-size src nat)` / `(targ-type src type)` at `:306-308` | source → `expand-modules-and-types` |
| `(Place-Skeleton)` — a ledger field name plus a list of `(op-name . arity)` | new nonterminal | as above |
| `(tkeys src tvar-name)` — "the key-tuple type of store parameter S" | `Type` | introduced by Phase B, resolved in Phase C |
| `(place-valued src tvar-name)` | `Type-Param`, alongside `(nat-valued …)` / `(type-valued …)` at `:206-208` | introduced by Phase B, consumed in Phase C |

`Place-Skeleton` is deliberately *not* an expression. It is a symbol plus a list of
`(symbol . nat)` — trivially hashable and comparable, which is exactly what the instance
table needs and exactly what an expression could not have provided. **The split between
skeleton and keys is what makes monomorphization possible at all.**

**INFERRED:** `place-valued` type parameters are compiler-generated and never written by a
user, so the parser's `gparams` handling should not need to know about them
(`doc/compact-reference.mdx:320-334` gives the surface form as `#name | name` only). Verify
before relying on it.

---

## 4. Phase B — `expand-place-params`, the new front-end pass

### B1. Placement

`compiler/frontend-passes.ss`, between `eliminate-boolean-connectives` and
`prepare-for-expand`:

```scheme
    (eliminate-statements            Lexpr)
    (eliminate-boolean-connectives   Lnoandornot)
    (expand-place-params             Lnoplace)      ; new
    (prepare-for-expand              Lpreexpand))
```

Rationale: after `expand-patterns` so parameter lists are plain `var-name`s
(`langs.ss:211-213`); after expression simplification so there is less syntax to walk; before
`prepare-for-expand`, whose output `Lpreexpand` is what `expand-modules-and-types` consumes
(`analysis-passes.ss:75`).

### B2. The pass is purely syntactic, and that is fine

**It cannot know whether `accounts` is a ledger field.** `ledger-ref` does not exist at this
level — `langs.ss:602` *adds* it in a later language and `:838-841` replaces it with
`public-ledger` in a later one still. At source level `accounts.lookup(to)` is an ordinary
member-call chain, `(elt-call src expr elt-name expr* ...)` (`langs.ss:240`).

That does not matter, because **`&` is syntactically marked**. The pass processes whatever is
under the `&` and defers every validity question — is this a ledger field? does that op
exist? is the value type right? — to `expand-modules-and-types` and `infer-types`.
`expand-patterns` works the same way.

### B3. What it does

**Signature rewrite.** For each argument `(src var-name (tref src T))`:

- emit a fresh type-param `(place-valued src %Sₙ)` — naming convention
  `__compact_place~a`, following `expand-patterns.ss:20-24`;
- replace the argument with `(src var-name__keys (tkeys src %Sₙ))`;
- record `var-name ↦ (%Sₙ, var-name__keys)` for the body rewrite.

Each `&T` occurrence gets its own parameter. That is the elision rule of
`first-class-adts-design.md` §6.5, and it is what makes §7's aliasing story two-level.

**Body rewrite.** Uses of `var-name` become uses of the store parameter — which, after Phase
C, resolve to the reconstituted accessor chain with holes filled from `var-name__keys`.

**Call-site rewrite.** `f(&p, e…)` becomes `f<skeleton(p)>(keys(p), e…)` where
`skeleton(p)` strips every argument out of the chain and `keys(p)` collects them in order.
The `call` form is `(call src fun expr* ...)` (`langs.ss:263`) with generic arguments carried
on `fun`.

**Hoisting.** Key expressions move from place-position to argument-position, which reorders
evaluation relative to the other arguments. `propagate-ledger-paths` already faces this and
solves it with `bind-if-complex` (`:152-156`). Do the same: hoist any non-trivial key to a
temporary at its original position.

### B4. Diagnostics live here

Because `&` is gone after this pass, **every error about `&` must be produced by this pass**,
in surface terms. Downstream errors would be phrased in terms of a desugared form the user
never wrote. Reject, with messages:

- `&` on an **exported circuit's** parameter or return type — there is nothing at the
  TypeScript boundary to name a store, and a store has no wire representation. Reuse the
  register of `expand-serialize.ss:205`.
- `&` on a **witness** parameter or return — same reason; the callee is TypeScript.
- `&` in a **`contract` circuit** signature, in either position — the callee is
  existentially typed (`coip-0002.md`), so there is no call site at which to resolve the
  store parameter. `first-class-adts-design.md` §12.4. The grammar makes the return
  direction especially clear: `External-Contract-Circuit` is
  `(src pure-dcl function-name (arg* ...) type)` in every intermediate language — a
  signature with **no body field**. Monomorphization computes a returned place from the
  callee's body; across a `contract` boundary there is no body to compute it from, in this
  compilation or any other. A returned `&Counter` could only be a runtime value naming a
  path in *another contract's* state — which is the heap model, and its replay problem,
  with a cross-contract address space that does not exist on top.
- `&E` where `E` is not a syntactic chain of member calls rooted at an identifier.
- `&` nested inside `&`.

**Implementation status — three of these are specified but not yet produced.** Only the
exported-circuit *parameter* case and the `&E`-not-a-chain case emit their own message today
(nested `&` correctly reuses the latter's). The `contract` case, the witness case, and an
*exported* circuit's return type all fall through to the blanket `Type`-transformer message,
"a place reference type (&T) may appear only as the type of a circuit parameter". For the
first two that message is actively wrong: the `&` **is** in a parameter position, so the
reader is told to do the thing they just did. For the third it is wrong in the other
direction — the circuit-level check reports "not yet implemented", promising a future that
§12.4 rules out permanently.

Which exposes a structural problem with the diagnostics as a set: one message is carrying
three different meanings. They should be split by *reason*, because the reasons have
different lifetimes:

| Reason | Cases | Lifetime |
|---|---|---|
| The ledger holds runtime values | a ledger field's type, and therefore any type argument inside it — a `Map` key, a `Cell`'s content | permanent |
| The other side is TypeScript | exported circuit signature (parameters *and* return), witness signature, ledger constructor parameters | permanent |
| The callee is deployed separately | `contract` circuit signature, `contract implements` | permanent |
| Coherent, not built | an internal circuit's return type; a place nested in a circuit's parameter or return type — `[&Counter, Field]`, `Vector<3, &Counter>`, a struct field; a type alias; a local's declared type | temporary |

A user who hits a permanent restriction should be told the shape is impossible, not that it
is pending — and, just as importantly, the reverse.

**Compound types are "not yet", not "never" — an earlier draft of this table got this
wrong.** `f(x: [&Counter, Field])` is not blocked by anything representational. The place sits
at a statically known position in the tuple, so it could be hoisted to its own generic
parameter exactly as a bare parameter is today, leaving the tuple to carry the `Field` and the
key tuple. The same goes for `Vector<3, &Counter>` and for a struct field. What these
additionally need, and what is not designed yet, is two rules:

- **Every projection out of the compound must land at a statically known position.** `v[i]`
  for a runtime `i` would select a coordinate at runtime, which is the heap model again. This
  is the same rule that rules out `b ? &alice : &bob`, and it is a property of *uses*, not of
  the type.
- **A struct holding a place must have its own uses confined**, since such a struct can no
  longer reach the ledger or the TypeScript boundary. That is an infectious property a
  nominal type does not currently carry.

So the honest boundary is not "bare or nothing." It is: **a place may appear wherever its
compile-time coordinate can be monomorphized away, and nowhere that the coordinate would have
to survive as runtime data.** Circuit signatures satisfy the first; the ledger, the TypeScript
boundary and a separately deployed contract all fall under the second. Compound types in a
circuit signature satisfy it too — they are unbuilt, not excluded.

---

## 5. Phase C — `expand-modules-and-types`

### C1. The new kind and its `Info`

- Extend `Type-Param` handling for `(place-valued src tvar-name)` — the kind checks at
  `:245`, `:252`, `:261` and `:459` each gain an arm.
- New `Info` variant beside `Info-ledger` (`:172`):
  ```scheme
  (Info-place src ledger-field-name op-skeleton key-var-name)
  ```
- Resolve it in expression position, immediately beside `:1195-1196`: a name bound to
  `Info-place` expands to the accessor chain named by `op-skeleton`, rooted at
  `(ledger-ref src ledger-field-name)`, with each hole filled by the corresponding element of
  `key-var-name`.

### C2. Instance-table support

Seven sites, the same list `first-class-adts-design.md` §12.3 enumerates:
`gv-hash` (`:78-81`), `targ-info-hash` (`:123-130`), `targ-info-equal?` (`:131-143`), the
`Info` datatype (`:163-186`), `add-tvar-rib` (`:228-267`), `compatible-type-parameters?`
(`:452-472`), `describe-info` (`:584-600`).

None is hard, because a `Place-Skeleton` is a symbol plus a list of `(symbol . nat)`.
Hashing and equality are structural and total. `Info-size` (`:939`, `:128`, `:138-140`) is
the working precedent for a non-type generic argument threaded end to end.

### C3. Resolving `(tkeys src %S)` — spiked; it does not go here

An earlier draft put this resolution in `expand-modules-and-types` and flagged it as the
riskiest item in the plan. **`tkeys-spike.md` settles it: it belongs in `infer-types`, and
there it is easy.** Summary of that document:

- It cannot go here. `Info-ledger` carries only the field's id (`:825-831`); the type stays
  in the pelt and is expanded later as a frob, so at binding time the field's expanded type
  does not exist yet.
- It need not go here. `infer-types` already registers every ledger field's expanded `tadt`
  via `set-idtype!` (`:999`), does so in a **prepass** that runs over all program elements
  before any is transformed (`:962-963`), and already destructures op argument and result
  types in `find-adt-op` (`:801`). Resolution is a fold over the skeleton using all three.
- So `expand-modules-and-types` only has to **substitute** the store argument into the
  `tkeys` form, carrying it forward with a concrete skeleton. It needs no ADT tables.

`tkeys` therefore lives in exactly one language: introduced by Phase B into `Lexpanded`,
eliminated by `infer-types`, which is the next pass (`analysis-passes.ss:75-76`).

### C4. Validity checks

`expand-modules-and-types` is where `&p`'s claims are finally tested: the root name must
resolve to `Info-ledger`; each op in the skeleton must exist on the ADT at that position and
must be a nesting-capable op (today: `Map.lookup`; after
`store-nesting-impl-plan.md`, any `nav` op). Report at the original `&`'s source location,
which Phase B must preserve.

---

## 6. Phase D — type checking: no change

This is the payoff of desugaring early, and it is stronger than
`first-class-adts-design.md` §12.3 originally claimed.

`infer-types` never sees `&`. It sees a generic circuit with a tuple argument and a body
containing ordinary accessor chains. So:

- the eight `Non-ADT-Type` sites (`:1033`, `:1036`, `:1046`, `:1053`, `:1058`, `:1064`,
  `:1070`, `:1026`) see a tuple type — **not satisfied by a new rule, simply never
  challenged**;
- `desugar-ledger-read` (`:1179-1186`) sees a complete chain, so the "incomplete chain of
  ledger indirects" path is not reached;
- `verify-non-adt-type!` on equality operands (`:777-778`) sees two tuples, so **even the
  one lift §12.3 listed as required is not required** — `from != to` is ordinary tuple
  equality;
- `expand-serialize.ss:205`/`:329` see a tuple, which is serializable.

The whole of `infer-types`, `propagate-ledger-paths`, `determine-ledger-paths`,
`check-sealed-fields`, `track-witness-data` and all three backends are untouched. §8.

---

## 7. Phase E — the alias analysis

### E1. What it decides

Two place-derived parameters can alias **only if monomorphization gave them the same store
argument** — a compile-time fact, decided exactly by `targ-info-equal?`, no conservatism.
Given the same store, they alias **iff their key tuples are equal** — ordinary `Val`
equality, two constraints for a `Bytes<32>` key.

### E2. The check

A circuit is **alias-sensitive** iff its body contains a read through one place parameter
sequenced after a write through another with the same store argument. At a call site passing
two same-store references:

- keys visibly distinct literals → accept;
- callee alias-sensitive and no disequality assertion in the body → **error**, naming both
  parameters and suggesting `assert(from != to, …)`;
- an explicit opt-in annotation suppresses it and documents last-write-wins.

### E3. Placement

A new pass in `analysis-passes.ss`, after `infer-types` (`:76`) because it needs op-class to
tell reads from writes, and in the neighbourhood of `check-sealed-fields` (`:82`), which is
the same kind of analysis over the same shapes.

### E4. The honest caveat

Default-deny will fire on correct code — `from.decrement(n); to.increment(n)` is fine when
aliased. `first-class-adts-design.md` §14.3 flags refining "read after write" to "read after
write that changes the answer" as unresolved. **Ship default-deny with the escape hatch and
collect the false positives**; do not attempt the dataflow refinement in v1.

### E5. The write-pair table: enumerable, but not a commutativity table

E2 suppresses the `a.decrement(n); b.increment(n)` false positive by asking whether two
writes commute. Two corrections to that framing, both found while implementing it.

**The set is finite.** Kernel is not reachable at the end of a place path; the other seven
ADTs hold 32 write ops between them, giving **96 unordered pairs** including self-pairs. A
complete enumeration is entirely feasible.

**But a pair table cannot express commutation.** Two reasons:

- Commutation depends on arguments, not just ops. `Cell.write(v1)` and `Cell.write(v2)`
  agree iff `v1 = v2` — a run-time condition. A table keyed on op names has to be
  conservative everywhere arguments matter.
- **`Counter.increment` and `Counter.decrement` do not commute.** `decrement` errors below
  zero and that partiality is observable: on a counter holding 1, `inc(1); dec(2)` succeeds
  while `dec(2); inc(1)` aborts.

So what the implementation carries is **a whitelist of pairs we have decided not to complain
about**, and increment/decrement is on it because E4 requires that case be accepted — not
because it commutes. The code says so at the definition; the distinction matters because a
reader who "corrects" the entry to be semantically accurate would reintroduce E4's false
positive.

**The principled version is reachable.** Every op is a short straight-line VM sequence in
`midnight-ledger.ss` — `Counter.increment` is three instructions — and the ADT set is closed
and compiler-defined. A symbolic execution over ≤10 instructions per op could *derive* all 96
entries, partiality included, and regenerate them whenever an op is added. That replaces a
hand-maintained whitelist with a computed fact and removes the standing risk of the table
drifting from the ops it describes.

But it does not settle E4. A derived table reports the truth — that increment and decrement do
not commute — and so reintroduces the false positive the whitelist exists to avoid. §15.5 works
through why, and what removes both at once.

### E6. Where the disequality assertion lives

**E2's escape hatch is unusable as specified.** It says a disequality assertion "in the body"
suppresses the error, but a callee cannot name its own places' keys — there is no syntax for
"the key of place `a`". The assertion a user would naturally write is `assert(j != k, …)` at
the **call site**, which is a different body from the accesses. Nothing in today's language
can trigger the in-body check.

Fixing this splits the pass in two, and the split is worth having on its own merits because it
also moves the diagnostic to where the user can act on it.

**Phase 1, per specialized circuit.** Instead of erroring on a hazard, record a *summary*: the
set of unordered place-name pairs that are hazardous, each with its two source locations and
its reason. Store it in a hashtable keyed by the circuit's `function-name` id — the same shape
`check-sealed-fields` uses for `function-ht`.

**Phase 2, per call site.** For each `(call src f expr* ...)` whose callee has a non-empty
summary:

1. Map each hazardous place name to an argument index, by scanning `f`'s `arg*` for the
   argument whose id carries that `place-name`.
2. Take the actual key expressions from the corresponding actual arguments — they are `tuple`
   nodes built by `expand-place-params`.
3. Search the *calling* body, before the call in source order, for
   `(assert _ (!= _ _ e1 e2) _)` whose operands match those two key expressions.
4. If absent, error at the call site, naming the actual key expressions rather than the
   callee's parameters.

Each call site is checked independently, which is correct: one specialization can be reached
from several calls and only some of them may be safe.

**Cost and limits.** Roughly 100 lines, no language changes. Operand matching is `eq?` on ids
for the `(var-ref j)` case and conservative failure for computed keys — a key the user
computes inline will not match its own assertion, and will still be reported. Requiring the
assertion to precede the call is a deliberate v1 simplification, consistent with how E2 already
approximates ordering by source position.

**Status: implemented.** `check-place-aliasing` now collects one event stream per body
(accesses, asserted disequalities, calls), computes hazards from the accesses of every circuit,
and only then judges call sites against the callees' hazards — a call cannot be judged before
its callee is analysed, and the callee may be defined later in the file. Errors report at the
call, naming both places, the callee, and the two access locations inside it.

§15.3 gives the exit: the restriction and the treatment of `if` arms are the same missing
flow sensitivity.

### E7. Definite aliases — implemented, and not the way this section first specified

`move(&alice, &alice)` passes the same location twice. That is not a *possible* alias to be
excused by an assertion — it is a certainty, and no assertion can make it false.

**What this section originally proposed, and why it was wrong.** The plan said: detect the
repeated argument syntactically in `expand-place-params`, which sees both place expressions of
a call in one node, then carry the pair forward and let the alias pass decide, because the
front end has no ADT information and so cannot tell whether the callee is alias-sensitive.
That decomposition was built and then backed out. Two things are wrong with it.

The first is that the front end cannot decide *anything* here, not merely that it lacks ADT
op classes. `expand-place-params` runs before `expand-modules-and-types`, so an `fref` need not
resolve to a definition it can see at all — the callee may come from a module that has not been
expanded yet. There is no version of the syntactic check that can consult the callee.
A front-end check is therefore unconditional, and unconditionally rejecting a repeated place
argument rejects two things the rest of the design says are correct: a read-only callee
(`both(&alice, &alice)`, which this section itself said "must not be rejected"), and
`move(&alice, &alice)` with the body `a.decrement(n); b.increment(n)`, which is E4's canonical
correct-when-aliased case and is on the `writes-commute?` list precisely so it is accepted.

The second is that the premise — "it cannot be caught in the alias pass" — was true only
because of a gap that turned out to be worth closing on its own terms.

**The actual finding: zero-key places were invisible to the whole analysis.**
`check-place-aliasing` attributes a ledger access to the place it came from by looking at the
access's *key* expressions: `expand-modules-and-types` rebuilds a place's path as
`(tuple-ref (var-ref <keys parameter>) i)`, and stamps the keys parameter's id with the place
name. A place whose path contains no Map lookup has no keys, so it produces no such expression:
`&alice` used as `a.increment(1)` becomes exactly `alice.increment(1)`. `record-access!` found
no provenance and dropped the access — so not only was the definite-alias case invisible, so
was every hazard in any circuit whose places are whole ledger fields. E2 and E5 did not apply
to them at all.

**The fix is provenance on the root reference, and then E7 needs no rule of its own.**
`expand-modules-and-types` records the place name against the source object of the `ledger-ref`
it generates; `combine-ledger-declarations` passes that same object through as the `src` of the
resulting `public-ledger` node, so the alias pass can read it as a fallback when no key carries
provenance. A ledger access the user wrote directly has no entry, which is what keeps
hand-written `alice.increment(1); alice.read()` from being read as two places that alias — the
discrimination the front end could not make.

With that in place a definite alias is just an ordinary may-alias with the keys removed.
`move(&alice, &alice)` creates a specialization in which both places are the same field, so its
two accesses share a field and a (possibly empty) navigation prefix and differ only in
provenance — exactly the shape `may-alias?` already tests, judged by exactly the hazard rules
already in the pass. A read-only callee is not a hazard and is not reported. Commuting writes
are not a hazard and are not reported. `f(&alice, &alice)` around
`b.increment(1); a.read()` is reported, and correctly.

Two smaller consequences:

- **The E6 escape hatch is unreachable rather than specially refused.** The plan expected to
  have to disable it for definite aliases, since no assertion can separate them. It disables
  itself: `separated?` compares key expressions, and a zero-key place has none.
- **The message changes wording, not machinery.** When both key lists are empty the location is
  settled by the specialization alone, so the report says "this call passes one location" and
  advises passing two different places, rather than "may pass" and advising an assertion that
  there are no keys to write. A definite alias that still carries keys —
  `f(&m.lookup(k), &m.lookup(k))` — keeps the possible-alias wording, because the keys are what
  the analysis compares and it does not evaluate them.

**Cost of the carrier.** The provenance is a side table keyed on source objects, defined at the
top of `expand-modules-and-types.ss` and cleared per program, rather than a field on
`ledger-ref`. A field would have to be threaded through three languages and every pass between
the two — `infer-types`, `remove-tundeclared`, `combine-ledger-declarations`,
`discard-unused-functions`, `reject-recursive-circuits`, `recognize-let`,
`check-sealed-fields` — none of which has anything to do with places. The table's key is the
`src` of the reference the pass generated, which is unique to that use of the place parameter
in the callee body and is the same object in every specialization, so the entry is written once
per specialization with the same value each time. If that key ever stops identifying the
reference, the E7 tests fail loudly rather than silently accepting. §15.2 gives the exit.

**Note a related gap found while specifying this.** A place parameter cannot currently be
forwarded to another circuit: `&acct` where `acct` is itself a place resolves through
`Type-Argument->info` to `Info-place`, not `Info-ledger`, and is rejected with "expected `acct`
to name a ledger field but it names a place". Whether forwarding should be supported is a
separate question from aliasing, but it is the reason the definite-alias check need only
consider places rooted at ledger fields. (§13 takes this up.)


---

## 8. What needs no change at all

| Component | Why |
|---|---|
| **Impact VM, onchain-runtime, cost model, replay checker** | Emitted opcodes are byte-identical to hand-writing the circuit at that path. |
| **The generated JavaScript and the JS runtime** | `queryLedgerState` takes the op array as data; the emitted arrays are already built at runtime with interpolated keys. |
| `infer-types`, `expand-serialize` | §6 — they never see `&`. |
| `determine-ledger-paths`, `propagate-ledger-paths` | See ordinary accessor chains rooted at real field names. |
| `check-sealed-fields` | Same reason; `first-class-adts-design.md` §6.8 works through the hazard and why the splice closes it. |
| `track-witness-data` | Keys are ordinary ledger-op arguments; `disclose(…)` applies as today (`doc/compact-reference.mdx:1686`). |
| `print-typescript.ss:281` and `:2571` FIXMEs | Unreachable — the store is gone before printing. |

---

## 9. Tests

1. **Zero-width**: `credit(&alice, n)` — assert the emitted opcodes are identical to
   `alice.write(alice.read() + n)` inlined. This is the strongest correctness statement
   available and it should be a golden test.
2. **One key**: `credit(&accounts.lookup(k), n)` — same, against the hand-written form.
3. **Two instantiations**: the same circuit called at two different stores; assert two
   specializations and that neither is dead.
4. **Aliasing**: `transfer(&accounts.lookup(a), &accounts.lookup(b), n)` without an assertion
   → error; with `assert(from != to, …)` → accepted; `sweep(&alice, &accounts.lookup(k))` →
   accepted with no assertion (different stores).
5. **Rejections**, each with its own message: `&` on an exported circuit, on a witness, in a
   `contract` circuit signature, doubled, and applied to a non-place.
6. **Disclosure**: a witness-derived key without `disclose` → the existing error, phrased in
   terms of the user's `&p`.
7. **Depth**: a `&` parameter whose caller path pushes a `writeCoin` past its bound → the
   `depth-check-impl-plan.md` diagnostic, pointing at the call site.

### Writing the `(oops …)` position by hand

An `(oops …)` check compares `condition-irritants` by `equal?`, and the first irritant is the
formatted source position — `"testfile.compact line N char M"`. `test.ss` writes the string
list to the file joined by `\n` with no trailing newline, so **line N is the Nth string** and
**char M is a 1-based column**.

Which token M lands on is decided by `make-src` (`parser.ss:315-323`), which takes `line` and
`column` from `bsrc` — the start of *that production's own* parse. For most productions that
is the first thing written:

| production | `src` points at |
|---|---|
| `place reference :: src #\& expr7` | the `&` |
| `type-place :: src #\& type` | the `&` |
| `typed-pattern :: src pattern #\: type` | the parameter name (and `expand-patterns` preserves it) |
| `circuit-definition :: src (OPT export) … (KEYWORD circuit) …` | `export`, or `circuit` when not exported |

**The exception is a left-recursive production**, where the left operand has already been
consumed before this production begins, so `bsrc` is the *operator* token:

| production | `src` points at |
|---|---|
| `element call :: src expr8 #\. id #\( … #\)` | the `.`, **not** the receiver |

So for `credit(&accounts.lookup(k, k));` indented two spaces, the accessor-arity error is at
char 19 (the dot), not char 11 (the `a` of `accounts`). The same caution applies to the binop
and `tuple-ref` productions, which are left-recursive in the same way.

When a position is wrong the driver prints the actual `(oops …)` form in paste-ready
indentation, and also appends it to `replacement-results.ss`. Prefer pasting that over
recounting by hand.

---

## 10. Sequencing and sizing

**Do `depth-check-impl-plan.md` first.** `&` makes paths compose across call boundaries, and
the budget is silently unchecked today.

Within this plan: A is a day. **B is the project**; C is smaller than this plan first
estimated, per `tkeys-spike.md`. D is zero. E is roughly a week including the diagnostic,
and is where return-position support adds its cost (§12). G (folded into B) is a day.
Tests are substantial — item 1's
"identical to the hand-written form" harness is worth building carefully, because it is the
regression net for everything else.

Overall: comparable to `store-nesting-impl-plan.md`, and it should land first, because it
delivers the motivating use case and because `nav` is easier to specify once `&` has
established what "an operation that yields a place" means.

---

## 11. Risks

1. ~~**`(tkeys …)` resolution (§5.3)**~~ — **spiked and downgraded; see `tkeys-spike.md`.**
   Moving the resolution to `infer-types` makes it a fold over a skeleton using an existing
   linear scan, in a pass that already keeps the table it needs and already runs a prepass so
   forward references work. Two small residuals: split the `infer-types` prepass so ledger
   declarations are registered before circuit signatures are transformed (two lines,
   precedented at `propagate-ledger-paths.ss:87`), and test overload resolution on two
   unresolved `tkeys` argument types.
2. **Error messages must be in surface terms** despite the early desugaring (§4.4). Easy to
   get wrong, and getting it wrong makes the feature feel broken.
3. **Evaluation-order reordering** when keys are hoisted (§4.3). Follow `bind-if-complex`.
4. **Default-deny aliasing false positives** (§7.4). Expect complaints; the escape hatch has
   to be discoverable from the error message.
5. **Following returned references through the alias analysis** (§12). This is the piece of
   return-position support that is genuinely additional work, and it is the one to watch when
   estimating Phase E.

---

## 12. Return position: build it together with argument position

An earlier draft of this section deferred `&` in return position on the grounds that it
needs **inference**, which Compact deliberately lacks, citing `traits-design-space.md` §7.
That argument does not hold, for three reasons, and the recommendation is withdrawn.

**The citation is about a different thing.** The passage is the bullet headed
*"Return-type-only inference"* (`traits-design-space.md:584-586`), and it rules out using an
expected return type to **select a trait instance from a candidate set** — a search problem
with coherence consequences. Computing a circuit's return store from its body is not a
search. There is no candidate set, no unification variable, and the answer is unique or the
program is ill-typed.

**Argument position already does the same kind of inference.** The elision rule — each `&T`
introduces an implicit store parameter, filled in from context — *is* inference: `&T` is a
partial annotation, completed by the compiler. It cannot be "no inference" when the
information flows from the call site and "the compiler's first inference" when it flows from
the body. If anything the body direction is the easier one: one definition instead of N call
sites, a unique answer instead of a chosen one.

**Deferring returns does not buy a simpler type-level language.** The apparent extra cost of
return position is that its store is an *expression* — a parameter's store composed with ops
— rather than a concrete skeleton. But argument position needs exactly that as soon as a
derived place is passed onward:

```compact
circuit outer(m: &Map<Bytes<32>, Cell<Uint<64>>>, k: Bytes<32>) {
  credit(&m.lookup(k), 5);        // store argument = outer's %S_m, composed with lookup
}
```

So store expressions with composition are required either way. Splitting the work means
designing that machinery twice.

**And the traversal it needs already exists.** ~~`reject-recursive-circuits.ss:18-43` walks the
call graph depth-first ... So the compiler already visits circuits in dependency order.~~
**Struck — this was checked and it is wrong.** See *The ordering premise is false* below.

### The ordering premise is false

The claim above was that the compiler already visits circuits in dependency order, so computing
each circuit's result place is a matter of using a traversal that exists. Both citations fail.

**`reject-recursive-circuits` runs later.** It is 6th in `analysis-passes`;
`expand-modules-and-types` is 1st. It proves the call graph is a DAG *after* monomorphization
has already finished. It cannot supply an order to a decision made during monomorphization.

**The frob worklist is a queue, not a demand-driven evaluator.** `make/register-frob`
(`expand-modules-and-types.ss:507`) creates the frob, conses it onto `frob*`, and returns the
specialization's **id** — its name, nothing more. The body is transformed only when
`process-frob-worklist` pops it, which is after the caller that registered it has finished. So at
the moment a caller resolves a call, the callee's body has not been looked at and nothing about
its result is known. "Drains to fixpoint" is true of the queue and irrelevant to ordering.

So a returned place cannot be learned by asking the callee's specialization for it. Three ways
out, and the third is the one to build.

**(a) Force the frob.** Have the caller drive `process-frob` re-entrantly to completion when it
needs a result place. The cycle guard for it already exists in the right shape —
`cycle-checker` at `:482` is a combinator, instantiated twice as `with-module-cycle-check` and
`with-type-cycle-check`, and a third instance would work. But `process-frob` mutates pass-level
state (`frob*`, `seqno.pelt*`) and the output order is stabilized by an `sp<?` sort for test
comparability, so re-entrancy needs auditing, and recursive circuits would start being reported
by a different pass with a different message.

**(b) Iterate to a fixpoint.** Re-run the worklist until result places stop moving. Needs a
termination argument and makes the pass's cost non-obvious. No.

**(c) Compute the result place symbolically in the frontend, instantiate it at registration.**
The observation that makes this work: a result place does not need the callee's *body*, only its
*shape*. For

```compact
circuit at(m: &Map<Field, Counter>, k: Field): &Counter { return &m.lookup(k); }
```

the result is "the place bound to place parameter `m`, extended by `lookup`, with keys
`m`'s keys ++ (k)". That is a syntactic fact about the definition, and `expand-place-params`
already computes exactly this shape: `parse-place` yields `(var-name, elt-name*, key*)`, and
`place-param*` already distinguishes a parameter-rooted place from a field-rooted one — that is
how §13's forwarding works. So the frontend can record, as part of the desugared signature, a
*result place expression* rooted at a place parameter rather than a ledger field.

Instantiating it needs nothing new either. `make/register-frob` has `info*` — the specialization's
type arguments — in hand, so the parameter's `Info-place` is available at registration time, and
composing it with the recorded extension is the arm `targ-place` resolution already has:

```scheme
[(Info-place place-src ledger-field-name elt-name^*)
 (Info-place src ledger-field-name (append elt-name^* elt-name*))]
```

No forcing, no re-entrancy, no ordering problem: the result place is known when the
specialization's *name* is known, which is exactly when the caller needs it.

**What (c) costs is expressiveness, and the restriction should be stated up front.** The returned
place must be syntactically derivable from the parameters. `return &m.lookup(k)` and
`return &alice` are fine. A place chosen by control flow — `return c ? &alice : &bob` — is not,
and should be rejected with its own diagnostic rather than silently mis-analysed; that is a
genuine restriction on the feature, not an implementation detail, and it belongs in §12's
statement of what `&` in return position means. A returned place that is itself a call —
`return g(&m, k)` — composes `g`'s recorded expression with this one, which is a fixpoint over
the call graph computed in the frontend, where nothing has yet proved the graph acyclic; that
needs its own visited-set guard in `expand-place-params`.

**Consequence for the sizing in §10.** E was estimated at "roughly a week including the
diagnostic, and is where return-position support adds its cost." That estimate assumed the cost
was Phase E following returns. Under (c) the cost moves earlier — a result-place expression in the
frontend, carried through the signature, instantiated at registration — and Phase E's part
shrinks, because a returned place arrives at the call site already resolved to a field and an
accessor chain, which is what its existing comparison consumes.

### What actually remains

Three things, all smaller than what the earlier draft claimed, and none of them a reason to
defer:

1. **The return type cannot name the place. This is a deliberate choice, not an oversight.**
   In argument position the place gets a binder for free: writing `acct: &Counter` introduces
   the name `acct`, and the desugaring makes that literal — `acct` becomes a `place-valued`
   generic parameter, so the signature does mention the place. In return position there is no
   binder. `(): &Counter` gives the store type and stops; the static half is not merely
   unwritten but *unwritable*. Two circuits with identical signatures can return references
   into different stores. That is not unsound — the store is still statically known after
   monomorphization — but the signature is not a complete interface.

   This is not ordinary variance. `f(x: Field): Field` has the caller supply one and the body
   produce the other and needs no second spelling, because `Field` fully describes its value.
   `&Counter` describes half of one.

   The only notation that would repair it is a **place-expression return type**, naming the
   parameter the result derives from:

   ```compact
   circuit at(m: &Map<Field, Counter>, k: Field): &m[_]
   circuit home(): &alice
   ```

   A bare mode marker — `&T` for "caller supplies" against some `&!T` for "body determined" —
   is not worth considering. It restates what the reader already knows from the position and
   says nothing about *which* place.

   **Decision: no new syntax.** `&T` stays a single form in both positions and the cost is
   paid in the analysis instead. See the recommendation below for what that costs and what
   would reopen it.
2. **Legibility.** With an argument you read the store off the call. With a return you read
   it off the body, and if the reference came from a nested call, off that body instead.
3. **The aliasing analysis widens (§7) — and this is item 1 over again.** A returned
   reference can alias a parameter, so the analysis has to follow returns rather than only
   comparing arguments at a call site. **This is the real cost**, and it lands in Phase E
   rather than anywhere in A–D.

   Items 1 and 3 are one question, not two. A place-expression return type would make aliasing
   *local*: if the signature says the result lies under `m`, two returned references are
   comparable at the call site — same root, so the question reduces to key disequality, which
   is exactly what is already answered for `move(&accounts.lookup(a), &accounts.lookup(b))`.
   Declining the notation is what forces the analysis to be whole-program. One decision buys
   or spends both.

### Recommendation

Build both positions, and — per item 1 — **without a return-type notation**. `&T` stays one
form; the alias analysis goes whole-program.

The trade, as this section first stated it: every returned reference is opaque at its call site,
so Phase E has to follow returns through bodies to learn a result's root — and the traversal for
that was claimed to already exist. It does not; see *The ordering premise is false*.

Under mechanism (c) the trade is different and better. A returned place is *not* opaque at its
call site: the frontend records the result as a place expression rooted at a place parameter,
and `make/register-frob` instantiates it from the specialization's own type arguments, so the
call site sees a resolved field and accessor chain — the same thing an argument-position place
gives it. Phase E needs no new traversal at all. What is paid instead is a restriction on what a
`&T`-returning body may do: the returned place must be syntactically derivable from the
parameters, so a place chosen by control flow is rejected. So the open question is no longer
whether the analysis can follow returns; it is whether that restriction is one users trip over.

That reframes what would reopen item 1's notation. It was "does Phase E reject programs that are
actually fine?" — imprecision in a whole-program analysis. Under (c) it is sharper and easier to
answer: **does a real contract need to return a place chosen by control flow?** A
place-expression return type (`&m[_]`) would not lift that restriction either — it constrains
the result the same way — so the answer bears on whether return position is worth having at all
in the form (c) allows, not on which notation to use. Item 1's argument stays on file, but this
is no longer the question it answers.

**Status: not built.** `&` in return position is rejected as `not-yet`, contrary to this
section's recommendation; see §15.4.

---

## 13. Forwarding a place

A circuit that takes a place cannot currently pass it on:

```compact
circuit inner(acct: &Counter): [] { acct.increment(1); }
circuit outer(acct: &Counter): [] { inner(&acct); }   // rejected today
```

`Type-Argument->info` resolves the root of a place expression and insists it be an
`Info-ledger`; `acct` is an `Info-place`, so this fails with "expected `acct` to name a ledger
field but it names a place". That leaves an obvious hole: places can be created and consumed
but not threaded, so any decomposition of a circuit that operates on a place is blocked at one
level deep.

**This is not double-`&`.** `&e` reads as *the place of e*. A ledger field denotes its own
place, and a place variable denotes the place it is bound to, so `&acct` is a single `&`
applied to a place-valued variable — an identity, not a reference-to-a-reference. `&&` remains
what it is today: the logical-and token, and `& &x` still fails in `parse-place`. Keeping the
`&` marker at the call site is what makes every place argument visible as one, and it keeps
`&acct` and `&acct.lookup(k)` the same construct.

### 13.1 It needs no language change

`targ-place src var-name (elt-name* ...)` is already general: the production takes any name, and
only the resolution clause requires a ledger field. Forwarding is one extra `Info-case` arm:

```scheme
[(targ-place ,src ,var-name (,elt-name* ...))
 (let ([info (lookup p src var-name)])
   (Info-case info
     [(Info-ledger ledger-field-name) (Info-place src ledger-field-name elt-name*)]
     ; forwarding: the root is itself a place, so extend its chain rather than start one
     [(Info-place place-src ledger-field-name elt-name^*)
      (Info-place src ledger-field-name (append elt-name^* elt-name*))]
     [else ...]))]
```

One arm covers both cases. `inner(&acct)` appends nothing and forwards the place unchanged;
`inner(&acct.lookup(k))` appends `lookup` and forwards a place one level deeper. Downstream
needs nothing: `tkeys` resolution already walks a `(field, chain)` pair, and the appended chain
is exactly the right one, so the key tuple type comes out correct with no edit.

### 13.2 The work is on the keys side

The dynamic half does need care. A fresh place's keys are the keys written at the call site; a
forwarded place's keys are **the caller's keys followed by any new ones**. `Tuple-Argument`
already has a `spread` production, so this is direct:

```scheme
; fresh:      &accounts.lookup(k)  ->  (tuple (single k))
; forwarded:  &acct                ->  (tuple (spread __compact_place_keys_acct))
; extended:   &acct.lookup(k)      ->  (tuple (spread __compact_place_keys_acct) (single k))
```

`expand-place-params` decides which by asking whether the root names one of the enclosing
circuit's own place parameters — a set it already computes, since it is the pass that rewrites
them. The set has to be in scope while the body is traversed, which today it is not: the
`Circuit-Definition` clause calls `(Expression expr)` after the parameter loop, so the names
need to be carried into it.

### 13.3 Sizing and the one thing to check

Roughly 25 lines in `expand-place-params` and 3 in `expand-modules-and-types`. No new
production, no new language, no change to `infer-types`.

**Shadowing: checked, and it needs no handling.** `reject-duplicate-bindings` only rejects
duplicates within a single binding list, and Compact does permit a local to shadow an outer
binding — `test.ss` has a reference example relying on it. So the syntactic root test does
guess "forward" wrongly at a shadowed use site.

That guess is *outcome-equivalent*, not merely safe. Guessing "fresh" wrongly cannot happen,
because the set being tested against is the parameter list itself. Guessing "forward" wrongly
changes only the keys expression, and at such a site `Type-Argument->info` rejects the **root**
— it resolves to the shadowing `Info-var` — a decision that depends on the binding in scope and
not on which keys were emitted. The keys are well formed either way and are discarded along
with the failed resolution. Both guesses therefore produce the same diagnostic from the same
place, and tracking `let*`, `block` and `for` binders in the frontend would buy nothing.

A test pins this: search `test.ss` for "A local shadowing a place parameter".

Two further notes. Recursion through forwarded places is already handled —
`reject-recursive-circuits` proves the call graph acyclic before any of this runs. And
forwarding composes with specialization exactly as direct places do: two forwards that resolve
to the same `(field, chain)` share one instance, because `targ-info-equal?` compares the
resolved `Info-place`, not the syntax that produced it.

---

## 14. Witness-derived Map keys are not disclosed — resolved: a gap

**Not caused by `&`.** Recorded because the end-to-end tests surfaced it and because §9's own
test list assumes the opposite. The audit below settles what was left open: no pass imposes the
obligation, so this is a genuine gap rather than a check happening elsewhere. Fixing it is a
breaking change and needs a versioning decision.

### What was observed

The first end-to-end place test failed on a disclosure error, correctly: `n` is a parameter of
an exported circuit reaching `Counter.increment`, a ledger update, so Compact requires the
disclosure be declared. Adding `disclose(n)` fixed it, and the no-place control test needs the
identical `disclose` — so this is ordinary discipline, not a place-specific obligation.

What is odd is what was *not* reported. In

```compact
export circuit deposit(k: Bytes<32>, n: Uint<16>): [] {
  credit(&accounts.lookup(k), disclose(n));
}
```

`k` is equally a parameter of an exported circuit, and it equally reaches a ledger operation —
as the key of `Map.lookup`. It was not reported.

### Why

Verified, not inferred:

- `track-witness-data.ss:860` matches
  `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[* abs*] ...)`.
  `path-elt*` is bound **without a catamorphism**, and the pass contains no `Path-Element`
  transformer at all. Only `abs*` — the ADT op's trailing arguments — is walked, paired with
  `discloses?*`.
- By the time the pass runs, `propagate-ledger-paths` has already converted a `Map.lookup`
  key into a path element. So the key is in `path-elt*`, outside what the analysis inspects.
- This is identical for `&accounts.lookup(k)` and for hand-written `accounts.lookup(k)`. **`&`
  changes nothing here**, which is what the control test pins down.

### Why it might matter

A dynamic key is not a compile-time immediate — it has to reach the VM as data, and the VM's
state and transcript are public. So a witness-derived key plausibly does become public, and
"which key did you touch" is exactly the kind of fact the disclosure discipline exists to make
explicit. If that reasoning holds, path keys should be tracked and today are not.

### The mechanism, resolved

An earlier draft of this section listed the disclosure mechanism as not understood. It is now
understood, and it makes the case stronger rather than weaker.

`parse-disclosure` (`ledger.ss:146-151`):

```scheme
[() ""]                              ; no annotation -> "", which is TRUTHY
[((discloses nothing)) #f]           ; the explicit opt-out
[((discloses what)) ... #'what]      ; a description
```

**Every op argument discloses by default.** An absent annotation yields `""`, not `#f`, so
`track-witness-data`'s `(when discloses? ...)` fires. That is why `Counter.increment`'s amount
and `Set.member`'s element are both tracked despite carrying no annotation in
`midnight-ledger.ss`.

It follows that `Map.lookup`'s key is *also* marked as disclosing. The analysis intends to
check it. It never gets the chance, because the key has already been moved into `path-elt*`.

### The discriminator is path-vs-argument, and it is observable

Demonstrated by two circuits over the same contract:

```compact
export circuit isMember(x: Field): Boolean { return members.member(x); }        // REJECTED
export circuit balanceOf(k: Field): Uint<64> { return counters.lookup(k).read(); }  // accepted
```

`Set.member` is terminal, so its argument stays in `abs*` and is checked — this one needs
`disclose(x)`. `Map.lookup` is a navigation step, so `propagate-ledger-paths` folds its key
into the access path and nothing checks it. Same kind of value, same kind of exposure,
opposite treatment.

Note that the deciding factor is not op class: both are `read` ops. Nor is it the annotation.
It is purely whether the op survived as an op or became a path element.

### Why this now looks like a gap rather than a design choice

A key used to navigate reveals exactly what a key used in a terminal op reveals: which slot was
touched. The ADT table marks both as disclosing. The analysis is written to check both. One is
checked and the other is not, and the difference is an artifact of a representation change made
two passes earlier for unrelated reasons.

### The audit is done: nothing imposes the obligation

The one reason this was not asserted as a defect was that the passes before
`track-witness-data` had not been checked for whether any of them imposes the obligation
earlier. They do not.

`discloses?` appears in five passes before `track-witness-data` —
`expand-modules-and-types:1042,1061`, `infer-types:803,1084`, `check-sealed-fields:58`,
`propagate-ledger-paths:96,144`, `check-ledger-budgets:114` — and in every one of them it is
pattern-carrying only: destructured from the `ADT-Op` production and rebuilt unchanged. No pass
before `track-witness-data` reads it as a predicate.

In `track-witness-data` itself the mechanism is visible in one clause
(`track-witness-data.ss:860`):

```scheme
[(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[* abs*] ...)
```

`abs*` — the terminal op's arguments — are zipped against `discloses?*` and checked.
`path-elt*` is bound and dropped. And the pass has **no `Path-Element` processor at all**: its
analysis processors are `-> *`, so nothing is auto-generated either, and the expression inside a
path element is never visited by the disclosure analysis.

Note also what `propagate-ledger-paths` does on the way: `bind-if-complex` hoists any
non-trivial key into a `let*` temp, so by the time the path element exists it holds a bare
`var-ref`. The witness data reaching that temp *is* tracked — binding a witness to a local is
not a leak — it is simply never consulted, because the use that would consult it is a path
element.

So: **a gap, not a deliberate choice and not an obligation imposed elsewhere.**

### The fix, and why it is not ours to make

One clause, and the rule needs no new IR field. Every path element that is not a `path-index`
came from a `Map.lookup` key, and the ADT table already marks that key as disclosing — so
"every dynamic path element discloses" is exactly the right rule. The change is to run the
`Expression` processor over each path element's expression in the clause above and record a leak
when it has witnesses.

What makes it not a drive-by fix is that it is **breaking**: every contract that today reaches a
ledger slot with a witness-derived key and no `disclose` would stop compiling. The
`stage-javascript` contract in `test.ss` is a live example of the asymmetry — `isMember` needs
`disclose(x)` for `Set.member` while `viaPlace` needs nothing for `Map.lookup` on the same kind
of value — so the blast radius is real and includes user code. That wants a decision about
language versioning, not a patch.

What this plan can settle is the smaller question it raised: §9 item 6's test **cannot be
written as specified**, because the error does not occur. Strike it, or replace it with a test
that asserts the current behaviour and references this section, until the versioning question is
answered.

### The test this blocks

§9 item 6 of this plan lists, as a test to write:

> **Disclosure**: a witness-derived key without `disclose` → the existing error, phrased in
> terms of the user's `&p`.

It cannot be written as specified, because the error does not occur — and now we know it does
not occur anywhere. Strike it, or replace it with a test that pins the current behaviour and
points here.

---

## 15. The compromises, and how each one comes out

Six things in the implemented feature are weaker than they should be. Four are named in this
plan already; two were forced during implementation and are named here for the first time. This
section exists so that none of them is load-bearing by accident: each is listed with the reason
it is there and the specific thing that removes it.

Ranked by exit cost, cheapest first. 15.1 is closed; the rest stand.

### 15.1 `assert(k != k, …)` silences the alias check — closed

**What it was.** `separated?` compared the asserted disequality's two sides against the two
places' key expressions with `expr-equal?`. A caller who wrote `assert(k != k, "…")` before the
call satisfied that match at every position where both places used `k`, so the compile-time
error disappeared and the contract aborted at run time instead.

**What closed it, and why not what this section first proposed.** The proposal was to reject a
tautological assertion where `note-assertion!` records it. That would have worked for the case
above but is both too broad and too narrow. Too broad, because a pass named
`check-place-aliasing` would be issuing a general diagnostic about always-false assertions,
newly rejecting programs that have nothing to do with places. Too narrow, because filtering
tautologies is not the property that matters. Consider a two-key path where the first key is
shared and the second differs:

```
peek(&regions.lookup(r).lookup(j), &regions.lookup(r).lookup(k))
```

An assertion about `r` — tautological or not — must never separate these, because position 0
holds the same expression on both sides and therefore carries no information. Only an assertion
about `j` and `k` can separate them. Filtering tautologies would not have said that.

So the guard went where the property lives: **a key position whose two expressions are the same
expression is never the separating position, whatever was asserted about it.** One clause in
`separated?`. `assert(k != k)` then fails to excuse anything, not as a special case but as a
consequence.

**And the case became definite.** `keys-identical?` reports two places as certainly one location
when every key position holds the same expression — vacuously true when there are no keys, which
is E7's case, and true of `f(&m.lookup(k), &m.lookup(k))` as well. A definite alias is checked
before `ne*` is consulted at all, so it cannot be excused, and it reads with E7's wording rather
than "may pass … assert that the two keys differ", which was unhelpful advice for a caller who
cannot make the keys differ.

**What is deliberately not done.** Whether Compact should diagnose an always-false assertion in
general is a real question and a separate one; `report-unreachable` is its natural home, not
this pass. Once 15.3 exists it generalizes further, to "the accumulated path condition is
unsatisfiable".

### 15.2 Place provenance rides a side table, not the IR

**Not previously named.** E7 assumed the provenance could be stamped where the specialization
is created. It cannot: the alias pass works on the specialized *body*, and a place with no keys
leaves nothing in the body to attribute. So `expand-modules-and-types` records the place name in
a table keyed on (source path, beginning file position) and `check-place-aliasing` reads it as a
fallback when no key carries provenance.

**Exit.** Put the field in the IR: a `(maybe place-name)` on `ledger-ref` in `Lexpanded`,
`Ltypes` and `Lnotundeclared`, and on `public-ledger` in `Loneledger` and `Lnodca`, dropped
where the later language rewrites `public-ledger` into its path form. About ten explicit clause
sites across `infer-types`, `remove-tundeclared`, `combine-ledger-declarations`,
`discard-unused-functions`, `reject-recursive-circuits`, `recognize-let` and
`check-sealed-fields`. Nothing subtle. The only reason to defer is that it touches seven passes
with no stake in `&`; the reason to do it is that the side table's key is an invariant nothing
enforces.

### 15.3 The assertion must precede the call, and both `if` arms are treated as taken

**E6 names the first; the second is not previously named.** Both are the same missing thing:
`check-place-aliasing` collects a flat event list, sorts it by source position, and scans it
linearly. Source order stands in for execution order, so an assertion after a call cannot excuse
it, and a branch is approximated by pretending both arms run. The approximation over-reports
rather than under-reports, which is the safe direction, but it is an approximation the plan
never discussed.

**Exit.** A flow-sensitive walk of the caller body: a path condition at each call site, joined
over branches, carrying forward a set of pairs known to be distinct. For syntactic
disequalities this is a standard propagation problem with no solver involved. Widening
`expr-equal?` from var-refs to structural equality over pure expressions comes free with the
same rewrite. Cost is a dataflow framework the pass does not currently have.

### 15.4 Return position is not built

**§12 names this.** `&` in return position is rejected as `not-yet`, though §12 argued for
building it alongside argument position.

**Exit.** §12 already contains the analysis of what remains; this is deferred work with a
written plan, not an open question.

### 15.5 `writes-commute?` accepts a pair that does not commute

**Not previously named, and the one real soundness compromise.** The original plan had a single
hazard rule, read-after-write. The write/write rule was added during implementation because
read-after-write alone misses

```
const v = a.read(); b.increment(v); a.resetToDefault();
```

which ends at zero when `a` and `b` alias. But E4 requires that
`a.decrement(n); b.increment(n)` be accepted, and a table keyed on operation *names* cannot
distinguish that from `dec(2); inc(1)` on a counter holding 1. So `increment`/`decrement` sits
on the accept list even though the pair does not commute: `decrement` is partial below zero and
the partiality is observable, since `inc(1); dec(2)` succeeds where `dec(2); inc(1)` aborts.
The analysis knowingly accepts a genuinely order-dependent pair. The comment on
`writes-commute?` says so, and says it is a whitelist rather than a commutativity table
precisely so a later reader does not "correct" it into being wrong.

**Two exits, and they are not equivalent.**

*Derive the table from the VM code (E5).* Mechanical, and it removes the unsoundness: each op's
Impact opcode sequence is in `midnight-ledger.ss`, the composite effect of the arithmetic ops is
an affine function of the cell value plus a guard, and composing two of them in both orders and
comparing the resulting (function, guard) pairs is decidable. It will also correctly report that
`increment` and `decrement` do not commute — which reintroduces E4's false positive. This route
trades unsoundness for imprecision; it does not remove the compromise.

*Summarize the body's net effect.* The reason `move` is safe under aliasing was never that its
two operations commute. It is that the body's net effect on the place is identity. That is a
property of the whole body, not of a pair of ops, and checking it needs a symbolic summary of
each place's delta: for the arithmetic ADTs, a signed affine expression over the circuit's
parameters together with a guard. Small abstract domain, decidable, and it accepts `move`
*because* it is net-zero while rejecting `dec(2); inc(1)` because it is not. This is the exit
that actually removes the compromise, and the only item in this section that is design work
rather than engineering.

This is also the point where the concurrency-control literature is directly applicable rather
than merely analogous: Weihl's and Herlihy's commutativity-based concurrency control derives
commutativity from operation *specifications* rather than from operation names, which is exactly
the move from the current table to either exit above.

**The irreducible residue.** Some pairs agree only under a run-time condition:
`Cell.write(v1)` and `Cell.write(v2)` agree iff `v1 = v2`. No table keyed on names, and no
table keyed on effects either, decides that. The best available is to require the arguments be
syntactically equal and otherwise report. That residue does not disappear with a solver, and in
general is undecidable.

### 15.6 Not on this list

Two things that look like compromises and are not.

**E4's false positives.** Named in the plan from the start, and the deliberate stance of the
whole analysis: report a possible alias and give the author an assertion to discharge it. 15.5
is a different matter — that is accepting a hazard, not reporting a non-hazard.

**E5 covering a handful of the 96 write pairs.** Also the plan's stated position, and the safe
direction: an unlisted pair is treated as hazardous.

---

## 16. The expressiveness ceiling, and where it actually comes from

This section exists because §12's mechanism (c) rejects `return c ? &alice : &bob`, and that
rejection was first described as though it were forced. It is not. It follows from a
representation choice made in Phase B and never written down as a choice.

### The choice

A place is carried as a **generic argument**. `acct: &Counter` becomes a `place-valued` type
parameter plus a keys parameter; monomorphization substitutes the coordinate and erases it. A
place therefore has no runtime existence, and everything downstream follows:

- it cannot be stored in the ledger,
- it cannot cross the TypeScript boundary,
- it cannot be an element of a compound type,
- and its coordinate cannot be selected by a runtime condition.

B4 classified the first three as `never`. That was wrong in kind, and the diagnostic has been
reworded: the reason is now `no-runtime-rep`, and the message says "this design gives it no
runtime representation" rather than asserting a place has none. The four-way classification
exists so a user can tell a restriction that will lift from one that will not; a reason that is
really "not under this representation" must not be spelled "never".

### What the machinery below actually objects to: nothing

Worth establishing, because it is easy to assume the VM or the runtime is the obstacle.

The generated JavaScript builds the Impact op array as a **plain literal at call time**, with
values interpolated, and passes it to `queryLedgerState`
(`compiler/javascript-code/test1119/contract/index.js:158-168`). The compiler does not emit a
branching transcript program — it emits the ops for the path actually taken. So a conditional
ledger access is ordinary JavaScript control flow, and neither Impact's instruction set nor the
runtime has any objection to a place whose coordinate is chosen at run time. (An earlier note
here reached for Impact's `Branch`/`Jmp`; those exist, but they are not how this compiler emits
conditional access, and they are not the constraint.)

### Two more expressive designs

**(d) Branch duplication.** Push the consumer into the arms:

```compact
credit(c ? &alice : &bob, n);     //  ->  if (c) credit(&alice, n); else credit(&bob, n);
```

A frontend rewrite. No runtime notion of a place, no change to monomorphization — each arm is an
ordinary place argument. This covers the motivating example exactly, and it is close to free.

Its limit is that the consumer has to be visible. A place *returned* out of a circuit has its
consumer in the caller, so the branch would have to be lifted across the call boundary — which
means inlining, or (e). So (d) is a real widening of §12's mechanism (c) for argument position
and does nothing for return position.

**(e) Place as a value.** A place becomes `(tag, keys)`, where `tag` indexes the program's
finite set of coordinate skeletons. Places are then genuinely first class: storable, returnable,
nestable in compound types, selectable by a condition. Each *use* of a place becomes an n-way
dispatch on the tag.

This is the design that removes the ceiling rather than raising it. An earlier version of this
section said its cost is "n arms' worth of constraints at every use site" and left it there.
That is true in form and misleading in framing; §16.1 works the numbers.

### 16.1 What (e) actually costs

Two facts about how this compiler works decide it, and they pull in opposite directions.

**The circuit is predicated; the JavaScript is not.** `reduce-to-circuit` compiles `if` by
emitting *both* arms as guarded statements — `add-test` (`reduce-to-circuit.ss:75`) computes
`t1 = c && test` and `t2 = !c && test`, and every `Lcircuit Statement` is `(= test var-name rhs)`
with a ledger access as an ordinary `Rhs`. So the circuit contains every arm. The TypeScript
back end takes a different branch of the pipeline and keeps real control flow — `if` becomes a
JavaScript ternary (`print-typescript.ss:2585`) — so the op array handed to `queryLedgerState`
contains only the path actually taken.

Consequences, for a place selected three ways:

```compact
ledger reserve: Counter;   ledger treasury: Counter;   ledger burned: Counter;

circuit sink(kind: Uint<2>): &Counter {          // (e) only
  if (kind == 0) { return &reserve; }
  if (kind == 1) { return &treasury; }
  return &burned;
}
export circuit route(kind: Uint<2>, n: Uint<16>): [] {
  sink(disclose(kind)).increment(disclose(n));
}
```

**Gas is unchanged.** Whichever arm runs, the transcript is
`idx[pushPath #t] · addi · ins` — the three Impact ops of `Counter.increment`, one path. On-chain
cost is identical to `reserve.increment(n)`.

**Circuit cost equals the hand-written branch, exactly.** The three guarded accesses plus the
guard algebra are what `reduce-to-circuit` emits for the version a user writes today under (c):

```compact
if (kind == 0) { reserve.increment(disclose(n)); }
else if (kind == 1) { treasury.increment(disclose(n)); }
else { burned.increment(disclose(n)); }
```

So (e) is not buying circuit cost. It is buying the ability to *name* the place instead of
duplicating the consumer — which means the comparison that matters is not (e) against (c), it is
**(e) against (d)**, and there (e) wins. (d) duplicates the consumer per arm: a 200-statement
`settle(acct: &Counter)` selected three ways is 600 statements. (e) duplicates only the accesses
*inside* the consumer: if `settle` touches its place twice, that is six guarded accesses and one
copy of the other 194 statements.

**Where (e) does explode.** Two places, and they are the ones to design against:

- **Composition is multiplicative.** A place selected 3 ways, passed to a circuit that selects 3
  ways again, is 9 coordinates at the innermost use. Nesting multiplies.
- **Ledger storage makes n global.** `ledger m: Map<Bytes<32>, &Counter>` — read a place back out
  and n is no longer bounded by anything syntactic; it is every coordinate skeleton the program
  can store. Every use of a loaded place dispatches over the whole set, and
  `check-ledger-budgets` and the depth check lose any per-path static bound.

**And guarded is not free.** `missing-guard-workarounds.ss` exists because zkir operators are not
conditional: predicated code needs extra remediation statements that the same code unguarded does
not. So each arm costs slightly more than its unguarded equivalent, on top of there being n of
them.

**So the honest cost statement is:** (e) restricted to *branching and returning* places is
roughly free — it costs what hand-writing the branch costs, and less than (d). (e) *with ledger
storage* is where the cost is unbounded, and that is the sub-decision worth separating out. The
ceiling is not "place as a value"; it is "place as a **stored** value".

### The constraint that survives every design

**A runtime-selected place discloses its selector.** The public transcript names the path
actually executed, so which arm ran is on chain. `c` in `c ? &alice : &bob` is therefore public
data, and the `disclose` discipline applies to it.

**This is already implemented.** `track-witness-data` carries `control-witness*` and reports a
ledger operation under a witness-dependent branch as a disclosure that must be declared —
"performing this ledger operation might disclose the boolean value of the witness value / via
this path through the program: the conditional branch at …" (`test.ss:33881` and others). So
(e) needs no new rule here; the existing one already covers it, which is why `disclose(kind)`
appears in the example above.

It sits directly next to §14, which is the same thing one level down: a key that selects a slot
is equally visible in the transcript, and today is *not* required to be disclosed.

### Recommendation

Revised in light of §16.1. (d) is no longer the obvious cheap win it looked like: it duplicates
the consumer, where (e) duplicates only the access, so (d) is the *more* expensive of the two
wherever the consumer is non-trivial. Its only advantage is that it needs no runtime notion of a
place.

So the ordering to consider is (c) → **(e) without ledger storage** → (e) with storage, and the
last step is the one to hold. A place that can branch and be returned but not stored keeps n
bounded by the syntax at each use site and costs what the hand-written branch costs; a place that
can be stored in the ledger loses any local bound on n and takes the budget and depth checks with
it. That is the sub-decision to make explicitly, and it is a different and smaller question than
"should places be first class".

The thing to avoid is letting (e) be foreclosed by accident. The diagnostics are the mechanism
by which that would happen: a compiler that tells users a place "may not" be stored, with a
reason phrased as a property of places, is documentation. Hence the rewording above. If (e) is
built later, the `no-runtime-rep` positions become legal and the message becomes obsolete, which
is the correct relationship between a design decision and its error messages.
