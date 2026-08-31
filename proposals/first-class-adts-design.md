# First-class ADTs in Compact: references are keys

*Design exploration, not a CoIP. Companion to `traits-design-space.md`,
`coherent-type-landscape.md`, and `dynamic-deployment-design.md`. Citations verified
against the working trees on 2026-08-28; anything I am inferring rather than reading is
marked **INFERRED**.*

---

## 0. Summary

There is a draft proposal for this feature already — Kevin Millikin's
`proposals/XXXX-first-class-adts.md` on branch `kmillikin/first-class-adts` of
`midnight-architecture` (commit `63f8eda`, 2025-02-07). It is a source-to-source
translation that allocates every first-class ADT in a heap: a ledger `Map<Addr, T>` per
type, with the ADT's Compact value being its key. It is careful, it is complete, and — a
fact worth stating plainly because the taxonomy in the handoff brief obscures it — **it
requires no Impact VM changes at all.** Everything it emits is an ordinary `Map` lookup.

Its problem is replay, and the problem is worse than "some transactions conflict." This
document argues three things:

1. **The heap model's costs are not incidental; they are the feature.** Its only
   capabilities beyond ordinary store *composition* are sharing and rebinding — and
   sharing and rebinding are precisely what turn every pointer dereference into a read-set
   entry that pins an identity with no semantic content. Unbounded pointer-chasing, the
   thing a heap normally buys you, is inexpressible anyway: the VM has no loops, so a
   chain of length *n* costs *n* statically emitted dereferences, which is exactly what a
   nested store gives you for free with zero reads. **The delta in capability is the delta
   in cost.**

2. **The lifetime-annotation-plus-affine-types alternative answers the wrong question.**
   Affine types exist to schedule deallocation without a runtime. They are needed when you
   allocate. Remove allocation and the motivation evaporates. Separately, the proposed
   three regions (`circ@`/`tx@`/`st@`) trisect a space the machine divides in two:
   `circ@` already exists and is called `Val`; `st@` is every store there is; and `tx@`
   does not exist and cannot be added without a hard fork (§5).

3. **The right feature is smaller and stronger than either.** A store is an *indexed
   family of places*. The thing users want to pass around is not the store and not its
   contents but an *index into it*. That index is ordinary data — a `Val` — and it is
   already flowing through their circuits today as a map key. So:

   > **`&S` — a reference to a place holding a store of type `S` — is a `Val` whose
   > runtime representation is exactly the dynamic keys along the access path. The static
   > part of the path is a monomorphization argument and is erased.**

   Under this reading, references can be passed, compared, returned, put in structs and
   vectors, and stored in the ledger. There is no allocator, no reference counting, no
   garbage, and no new read-set entry for navigation. Aliasing — which the prior design
   work never addresses, and which the handoff correctly predicts is the hardest question
   — becomes a *two-level* decision that is exact rather than conservative: two references
   can alias only if monomorphization gave them the same store (a compile-time fact), and
   then they do alias iff their keys are equal (a two-constraint circuit test). A borrow
   checker would be strictly worse here, and §7 shows why that is a consequence of
   Compact's structure rather than a preference.

The relationship to `coherent-type-landscape.md`, which says flatly *"Don't make them
first class"* (L276), is not a contradiction. That document is right. **This proposal does
not make stores first class.** It observes that the kind system already has a `Val`
universe, and adds one type former that lands *in* it. The eight `Non-ADT-Type` sites keep
saying exactly what they say today — "this position requires an ordinary Compact type."
They are not relaxed. They are given something that satisfies them.

And the heap model is not banned. It is *subsumed*: §10 shows it is already expressible in
user space today, with zero compiler changes, and that the only difference between it and
the cheap case is one `observe`. The language's job is to make that difference visible in
the source, not to insert it universally behind the programmer's back.

**Impact VM changes required: none. Generated-JS changes required: none.** The work is
entirely in the compiler, and §12 enumerates it.

---

## 1. What is prohibited today, and where

The prohibition is broader than the eight sites named in the handoff. There are fourteen,
in five distinct layers, plus one silent unchecked budget. Two of the fourteen are
*inverse* checks that require an ADT.

### 1.1 The predicate

`compiler/analysis-passes/infer-types.ss:305-320`:

```scheme
(define (public-adt? type)
  (nanopass-case (Ltypes Type) (de-alias type #t)
    [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
    [else #f]))
(define (verify-non-adt-type! src type fmt . arg*)
  (when (public-adt? type)
    (source-errorf src
                    "expected ~a type to be an ordinary Compact type but received ADT type ~a"
                    (apply format fmt arg*)
                    (format-type type))))
(define-syntax Non-ADT-Type
  (syntax-rules ()
    [(_ ?type ?src ?fmt ?arg ...)
     (let ([type (Type ?type)])
       (verify-non-adt-type! ?src type ?fmt ?arg ...)
       type)]))
```

`Non-ADT-Type` is a macro wrapper around the `Type` transformer, spliced in at the
recursion point, so every structural type constructor that uses it filters its children as
it rebuilds them. `de-alias type #t` passes `nominal-too? = #t`, so a `new type Foo =
Counter` cannot smuggle an ADT past it.

Read the error text carefully. It does not say "ADTs may not be values." It says *this
position requires an ordinary Compact type*. That is a kinding rule
(`coherent-type-landscape.md` §1.2), and the proposal in §6 satisfies it rather than
weakening it.

### 1.2 The full site table

| # | Site | Mechanism | Fate under this proposal |
|---|---|---|---|
| 1 | `infer-types.ss:1033` circuit argument | `Non-ADT-Type` | **satisfied** by `&S` |
| 2 | `infer-types.ss:1036` return type | `Non-ADT-Type` | **satisfied** by `&S` |
| 3 | `infer-types.ss:1046` vector element | `Non-ADT-Type` | **satisfied** by `&S` |
| 4 | `infer-types.ss:1064` tuple element | `Non-ADT-Type` | **satisfied** by `&S` |
| 5 | `infer-types.ss:1070` struct field | `Non-ADT-Type` | **satisfied** by `&S` |
| 6 | `infer-types.ss:1053` contract-circuit arg | `Non-ADT-Type` | **kept** — ∃ boundary, §11.3 |
| 7 | `infer-types.ss:1058` contract-circuit return | `Non-ADT-Type` | **kept** — ∃ boundary |
| 8 | `infer-types.ss:1006` external-contract-circuit return | `Non-ADT-Type` | **kept** — ∃ boundary |
| 9 | `infer-types.ss:1026` export type alias | direct `public-adt?` | **kept** — no wire representation |
| 10 | `infer-types.ss:777` equality left operand | `verify-non-adt-type!` | **lifted for `&S`** — this is the *enabling* change, §7 |
| 11 | `infer-types.ss:778` equality right operand | `verify-non-adt-type!` | **lifted for `&S`** |
| 12 | `infer-types.ss:1974` tuple-literal element | `verify-non-adt-type!` | **satisfied** by `&S` |
| 13 | `expand-serialize.ss:205` not serializable | direct match on `tadt` | **kept for `S`, lifted for `&S`** — a key serializes; a store does not |
| 14 | `expand-serialize.ss:329` not deserializable | direct match on `tadt` | same |

Site 8, the ninth `Non-ADT-Type` call, is not in the handoff's list:

```scheme
1004  (External-Contract-Circuit! : External-Contract-Circuit (ir) -> * (void)
1005    [(,src ,pure-dcl ,elt-name (,[arg*] ...) ,type)
1006     (Non-ADT-Type type src "circuit ~a return" elt-name)])
```

### 1.3 The site that actually matters most

`infer-types.ss:1179-1186`, `desugar-ledger-read`:

```scheme
1179      (define (desugar-ledger-read src expr type)
1180        (nanopass-case (Ltypes Type) (de-alias type #t)
1181          [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
1182           (find-adt-op src 'read #f adt-name adt-op* '() expr '()
1183             (lambda ()
1184               (source-errorf src "incomplete chain of ledger indirects: final result must be a regular type, but received ADT type ~a"
1185                              (format-type type))))]
1186          [else (values expr type)]))
```

This is the deepest statement of the current design: **a ledger reference is not a value,
it is an obligation to terminate in a scalar-producing operation.** `Cell` and `Counter`
have `read` ops and so collapse automatically; `Map` and `Set` do not, so a bare
`ledger.myMap` is rejected here.

Under this proposal that error message becomes a *suggestion*: `ledger.myMap` still cannot
be a value, but `&ledger.myMap` is the way to say "I meant the place." The obligation is
discharged either by reading through, or by explicitly taking a reference.

### 1.4 The kind-check layer, upstream of type inference

`expand-modules-and-types.ss:256-264` rejects an ADT passed as a generic argument to a
`Type`-kinded parameter:

```scheme
256                  [(non-adt-type-valued ,src^ ,tvar-name)
257                   (Info-case info
258                     [(Info-type src type)
259                      (when (public-adt? type)
260                        (oops src src^ "non-ADT type" tvar-name))]
261                     [(Info-size src size) (oops src src^ "non-ADT type" tvar-name)]
```

with the same check in overload resolution at `:467-470`, carrying a comment that it is
"not presently reachable, since only adt definitions use type-param kind
non-adt-type-valued."

The three-point meta-kind system that drives it is `ledger.ss:206-212`:

```scheme
206               (with-syntax ([(kind ...) (map (lambda (meta-type)
207                                                (case (syntax->datum meta-type)
208                                                  [(ADT/Type) #`type-valued]
209                                                  [(Type) #`non-adt-type-valued]
210                                                  [(Nat) #'nat-valued]
211                                                  [else (syntax-error meta-type "invalid meta type")]))
```

and `midnight-ledger.ss:699` is the only declaration in the entire table that uses
`ADT/Type`:

```scheme
699  (declare-ledger-adt Map ([Type key_type] [ADT/Type value_type])
```

**That single token is the entire reason store nesting is `Map`-only.** Compare `:544`
(`Cell`), `:622` (`Set`), `:798` (`List`), `:971` (`MerkleTree`).

### 1.5 Nesting shape

`propagate-ledger-paths.ss:35-52` enforces `Map`-only nesting; `:157-171` asserts that the
only legal non-terminal step in the whole language is `lookup(key)`:

```scheme
157                                  (begin
158                                    ; nothing but Map should have gotten past check-adt-nesting!
159                                    (assert (eq? adt-name 'Map))
160                                    ; nothing but lookup with one argument (the key) should have gotten past the type checker
161                                    (assert (and (eq? ledger-op 'lookup) (fx= (length expr*) 1)))
162                                    ; and the only element of type* should be a base type
163                                    (assert (not (public-adt? (car type*))))
164                                    ; and since we're nested, nothing but a public-adt return type should have gotten past the type checker
165                                    (assert (public-adt? type))
```

Four assertions, no error messages — by construction these cannot fail.

### 1.6 The two FIXMEs

`typescript-passes/print-typescript.ss:277-291`:

```scheme
280               [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
281                ; FIXME: at present, we can assume that whenever we passs a value of some
282                ; public-adt as a query argument, it must be the result of default<public-adt>,
283                ; since that's all that can get past the type checker.  if we generalize to
284                ; allow first-class public-adt values, this code will no longer be valid.
285                (construct-query-value src
286                  (expand-vm-expr
287                    src
288                    (map cons adt-formal* adt-arg*)
289                    (vm-expr-expr vm-expr))
290                  top-level?)]
```

Note what this code does: it **discards `q`, the actual runtime expression**, and
re-derives the value from the type's `vm-expr` — its *initial value*. Under a first-class
ADT *value* this silently produces the wrong answer rather than failing. It is a
correctness landmine, not dead code.

`print-typescript.ss:2570-2574` emits the JS literal `undefined` as the default for a
`tadt`, guarded by a comment saying it "should not appear in the output at present."

There is a third, in `circuit-passes/unroll-loops.ss:104-105`, which the handoff does not
mention and which is already *correctly* implemented — `sametype?` compares `adt-name`,
arity and each argument structurally, so it is dead but sound.

**Under the proposal in §6, neither FIXME is reached.** A `&S` is a `Val` and is printed
as its key tuple; the store part has been erased by monomorphization before either of
these code paths sees anything. That is the single strongest architectural argument for
this shape over the heap model: it *retires* the FIXMEs rather than requiring them to be
resolved.

### 1.7 The silent budget

`midnight-ledger.ss:566-585`, `Cell.writeCoin`:

```scheme
573      ((idx [cached f-cached] [pushPath #t] [path (suppress-null (reverse (cdr (reverse f))))])
574       (push [storage #f] [value (state-value 'cell (car (reverse f)))])
575       ;; Reach to the context in the stack: past the two pushes above, the
576       ;; result, and 2n path items of the idx, and the effects.
577       ;; note that if `f` is longer than 5, this exceeds the limit of 15.
578       (dup [n (+ 3 (* (sub1 (length f)) 2))])
```

`dup n = 3 + 2·(len(f) − 1)`, and `Dup`'s operand is a nibble (`onchain-vm/src/ops.rs:501`,
`0x30 | *n`). At `len(f) = 7` that is exactly 15; at 8 it is 17, which **silently aliases
to `Dup { n: 1 }`** — there is no bound check in the VM, none in the `Serializable` derive
on `Op` (`ops.rs:145-153`, no `invariant =` attribute, unlike `StateValue` at
`onchain-state/src/state.rs:76`), and none in `ledger/src/verify.rs`. The comment's "5" is
conservative headroom for the interleaved stack traffic on the following lines.

Nothing in the compiler validates this. Exhaustive grep finds no `source-errorf` guarding
path length anywhere. §8 proposes fixing it, and that fix is worth doing **whether or not
this feature ships**.

---

## 2. The taxonomy: four readings, not three

The handoff brief gives three readings and classifies the heap model as reading (b),
"runtime reference — needs VM changes." That classification is wrong, and getting it right
matters, because dismissing the prior proposal on VM grounds would be dismissing it for a
reason that does not hold.

| Reading | The reference is… | Path *shape* | Path *keys* | VM change? |
|---|---|---|---|---|
| **(a) compile-time lens** | a static path | static | literal | **none** |
| **(a′) lens + index** | static path + runtime keys | static | derived in-circuit | **none** |
| **(b) dynamic path shape** | a runtime path | **dynamic** | any | **impossible** |
| **(c) copied value** | the store's contents | — | — | none, bounded stores only |
| **(d) heap address** | an allocated surrogate key | static (`heap_T`, key) | **observed from state** | **none** |

Reading (b) is the only one that needs VM changes, and it needs ones it cannot get.
`Op::Idx` carries `path: Array<Key, D>` and serializes as
(`onchain-vm/src/ops.rs:501-522`):

```rust
            Idx { cached, push_path, path } => {
                if !path.is_empty() {
                    let opcode = match (*cached, *push_path) {
                        (false, false) => 0x50, (true, false) => 0x60,
                        (false, true) => 0x70,  (true, true) => 0x80,
                    } | (path.len() as u8 - 1);
                    writer.write(&[opcode.into()]);
                    for entry in path.iter() { entry.field_repr(writer); }
                }
            }
```

Path *length* is in the low nibble of a field element that goes into the proof's public
inputs. And `Key` has exactly two variants (`ops.rs:36-45`):

```rust
pub enum Key {
    Value(AlignedValue),
    Stack,
}
```

Keys may be mixed freely at any position — the VM's stack requirement counts only the
`Stack` entries (`vm.rs:412`: `path.iter().filter(|key| **key == Key::Stack).count() + 1`),
and the shipped compiler emits mixed paths (`onchain-runtime/vendored/program_fragments.rs:149`).
But which positions are literal and which are stack is fixed in the emitted key stream,
and the `AlignedValue` encoding begins with its own length precisely so the two cannot
collide (`spec/onchain-runtime.md`). So: **`Key::Stack` makes a key dynamic; nothing makes
a path shape dynamic.** Reading (b) is closed, permanently, without a hard fork.

Reading (c) is closed by the totality invariant for unbounded stores: a `Map` has no
static size, hence no `Val` kind, hence nothing to copy into. For *bounded* stores it is
expressible, but it is a different feature — a snapshot operation — and it does not
address any of the motivating requests.

**Readings (a′) and (d) are both fully expressible on today's VM.** The whole design
question is which of them the language should make cheap and which it should make visible.

---

## 3. The prior proposal, on its own terms

`proposals/XXXX-first-class-adts.md`, branch `kmillikin/first-class-adts`. What it gets
right deserves saying, because a lot of it is right and this document keeps most of it.

**The insight it is built on is correct and important.** From the overview:

> The insight underlying the source-to-source translation is the only place (other than as
> ledger-field types themselves) where ledger ADT types can currently appear is as the
> value type in ledger `Map` ADTs. This allows us to allocate ledger ADTs in a heap (in
> the sense of a mutable memory, not the heap data structure) which is a map in the ledger.

That is exactly right, and it is a consequence of the `ADT/Type` token at
`midnight-ledger.ss:699`. It is also, read the other way, the observation that **`Map` is
already a store-of-stores former**, which is the foundation of §11's argument that most
"first-class ADT" requests are really composition requests.

Its treatment of the `Cell`-read ambiguity is right too:

> Because Compact does not currently have first-class ADTs, calls to `read` on ledger
> `Cell` types can be implicit […] In the presence of first-class ADTs these could be
> ambiguous. For this reason we consider a source language where ledger `Cell` reads and
> writes are explicit.

Any version of this feature needs that, and `coherent-type-landscape.md` §3.3 independently
arrives at the same place with `observe(...)` and `:=`.

And the translation is genuinely VM-compatible. Every construct it emits — `Map` lookup,
`Map` insert, `Cell` read/write — is in the shipped op table. That is a real and rare
virtue in this problem space, and it is why the design deserves a careful refutation rather
than a dismissal.

### 3.1 The hole at the centre: `kernel.allocate`

> We need the ability to allocate keys for these maps. We assume a nullary generic ledger
> kernel operation `allocate`, e.g. `kernel.allocate<Cell<Field>>()` will return a value of
> type `Addr`.

This operation is assumed, not specified, and specifying it is harder than it looks.

**There is no source of freshness in the VM.** The initial stack has exactly three slots
(`onchain-runtime/src/context.rs:981-988`) and slot 0 is an 8-element context array
(`:853-893`) holding `own_address`, `com_indices`, `tblock`, `tblock_err`,
`parent_block_hash`, `balance`, `caller`, `last_block_time`. Every one of those is either
constant for the contract's lifetime, constant for the whole block and therefore *shared by
every transaction in it*, or supplied by the transaction and therefore adversary-chosen.
Grepping the three onchain crates: `nonce` — zero real hits; `entropy`/`random`/`rand` —
zero outside proptest generators; `transaction_hash` — zero. `Ckpt` costs gas and marks the
guaranteed/fallible split; it bumps nothing. There is no hash opcode among the 32; the only
collision-resistant primitive is `root` on a Merkle tree.

So `allocate` has three possible implementations.

**(i) Read a counter from state and pin it.** `Cell.read` is
`dup; idx; popeq` (`midnight-ledger.ss:548-551`) — the address enters the read set.
`ResultModeVerify::process_read` (`onchain-vm/src/result_mode.rs:44-63`) then requires it
to be byte-identical at replay. Consequence: **every pair of concurrent transactions that
both allocate conflicts, and one is rejected.** Allocation serializes the contract.

**(ii) Read a counter from state and let it float.** This is the shipped
`MerkleTree_insert` idiom (`program_fragments.rs:601-616`): read `first_free`, write the
leaf there, `Addi{1}`, write back, with no `popeq` anywhere. It composes beautifully — two
concurrent inserts both succeed and land at different indices. But the circuit never learns
the index. **A first-class ADT value is by definition something the circuit holds**, so
this is not available to the feature. The exact property that makes floating allocation
safe is the property that makes it useless here.

**(iii) Derive the address in-circuit.** `persistentHash` and `transientHash` exist
(`compiler/standard-library.compact:253,86`), so a contract can compute
`H(witness_nonce)` in the ZK circuit and push it as a `Key::Value` immediate. **This
works, and it is the one option the proposal should have taken.** No state read, no
conflict. The costs are a hash in-circuit and — since immediates are field-repr'd into the
public inputs (`ledger/src/verify.rs:1944-1970`) — the address is public.

So allocation is fixable. I want to be clear about that, because it means the argument
against the heap model cannot rest on allocation. **Dereferencing is the irreducible
problem.**

### 3.2 Dereference is necessarily an observation

This is the objection as you stated it, and it is exactly right; I want to state it in the
form that makes its scope clear.

To follow a reference you must first *have* it. Under the translation, references live in
the ledger — `field0: Cell<Addr>`, `list: Map<Addr, List<Addr>>` — and getting one out is
`Cell.read` or `List.head`, both of which end in `popeq` (`midnight-ledger.ss:551`, `:878`).
`popeq` is the *only* opcode in the VM that gathers a read: `process_read` has exactly one
call site, inside `Popeq` at `onchain-vm/src/vm.rs:625-638`. So every dereference of a
stored reference is a read-set entry, and:

> **The read-set entry pins an identity, not a datum.** The transaction is rejected if the
> *address* changed, whether or not the *value at that address* changed. You pay
> conflict-fragility for a quantity that has no semantic content — its only job is to name
> a place.

Work the proposal's own examples.

*Example 1, `swap`.* `test()` reads `field0` to bind `c`, then calls `swap(c,
field1.read())`. Three `popeq`s of addresses. If any other transaction has executed
`cellToCell`-style rebinding, all three are stale.

*Example 2, `cellToCell`.* This is the circuit that makes the rebinding real:

```
export circuit cellToCell(): [] {
  cell0.write(cell1.read());
}
```

One call to this changes the address in `cell0`, invalidating every pending transaction
that had read `cell0` — including transactions that only wanted to read the *number* in it
and did not care about identity at all.

*Example 3, `swapTwo(list)`.* `List.head` popeqs the head; `pushFront` changes the head.
So **any concurrent push to the list invalidates every pending transaction that touched
its head.** This is the worst case, and it is the proposal's own motivating example for
dynamic allocation.

Compare with today. Today `list.head()` also `popeq`s — but it `popeq`s *the value you are
about to use*. The read-set entry is exactly your semantic dependency. Under the heap
model, the entry is an artifact of the representation. **The heap model does not add reads;
it decouples reads from meaning.**

### 3.3 The reference-counting comments hide a soundness hazard

The commit that produced the branch head is titled *"Describe reference counting in the
examples, as comments."* The comments describe increments and decrements on scope entry and
exit, and reclamation when a count reaches zero.

Increments and decrements are cheap: `Counter.increment` is `idx; addi; ins`
(`midnight-ledger.ss:602-606`) with no `popeq`, so it discloses nothing and does not
conflict. That part is fine.

**Reclamation is not.** Testing a count against zero requires a `branch`, and `Branch` pops
its condition from the VM stack (`onchain-vm/src/vm.rs:1056-1075`):

```rust
        let skip = 1 + match op {
            Branch { skip } => {
                let a = stack.pop().unwrap().0.as_cell()?;
                if a.value.0.len() == 1 && a.value.0[0].0.is_empty() { 0 } else { *skip as usize }
            }
            Jmp { skip } => *skip as usize,
            _ => 0,
        };
```

At replay the opcode sequence is fixed, but **the path through it is not**. Nothing in the
VM, the runtime, the ledger, or the proof records or checks which arm was taken. The
public inputs contain both arms and every recorded `popeq` immediate regardless of whether
that `popeq` executes (`verify.rs:1944-1970`); `program = &program[skip..]` at `vm.rs:1074`
removes skipped ops from execution entirely, so a `popeq` on the untaken path is simply
never checked. The guarantee the system actually provides is much weaker than "the recorded
execution is reproduced":

> *Some* execution of this fixed program against current state succeeded, produced exactly
> the declared `Effects` (`ledger/src/semantics.rs:1452-1461`), and every `popeq` it
> *happened to execute* matched its recorded immediate.

This is deliberate — `spec/contracts.md:132-139` models a transcript as a partial function,
not a diff — and it is what lets `Counter.increment` compose across concurrent
transactions. But it means that **any memory-management discipline built on state-dependent
branches can decide differently at rehearsal and at replay.** The chain will not free a
live object, because it evaluates the branch against real state. But the proof was
constructed against the other branch. The circuit's private computation and the chain's
public computation disagree, and the transaction may still commit.

The fix is to pin every reclamation decision with a `popeq` — at which point you are back in
§3.2 and every allocation-bearing transaction conflicts with every other. **Reference
counting and replay-tolerance are not compatible in this machine.** That is not a bug in
the proposal; it is a property of the substrate that the proposal was not in a position to
know, since the comments predate the current transcript semantics.

INFERRED (not read from code): I have not constructed a concrete exploit; the argument is
structural. Someone should try, because if I am right the same hazard applies to any
existing contract that branches on state to decide whether to delete.

### 3.4 The delta in capability equals the delta in cost

Set aside allocation and reclamation. Ask what the heap buys that store *composition* does
not.

Not depth. There are no loops — `skip: u32` is always added and `program = &program[skip..]`
only shrinks the slice, so Impact programs are forward-only and terminate in at most
`program.len()` steps. Following a pointer chain of length *n* costs *n* statically emitted
dereferences. But *n* statically emitted `Map` lookups is precisely what `Map<K1, Map<K2,
Cell<V>>>` gives you, in **one** `Idx` with two keys, with **zero** read-set entries.
Composition is strictly cheaper at every depth.

Not containers. `List<Cell<Field>>` — the proposal's third example — is a nested store. It
is prohibited today only because `List`'s parameter is declared `Type` rather than
`ADT/Type` at `midnight-ledger.ss:798`. That is one token, and §11 argues it is the change
those users actually want.

What is left is exactly two things: **sharing** (two paths denoting one place) and
**rebinding** (`cell0.write(cell1.read())`). And those are precisely the constructs that
make the pointer volatile, hence make its `popeq` a conflict surface, hence produce
everything in §3.2.

> **The heap model's entire capability delta over composition is its entire cost.**

That is the argument, and it is why this document does not counter-propose a repaired heap.
There is nothing left in it to repair.

---

## 4. What the prior proposal is *right* about that this one keeps

Three things, kept explicitly:

1. **Explicit `read`/`write` on `Cell`.** Implicit reads become ambiguous the moment a
   store-typed expression can be a value. `coherent-type-landscape.md` §3.3's `observe(...)`
   and `:=` is the same conclusion reached independently, and §10 leans on it hard.

2. **Heap-in-a-`Map` is the correct encoding *when you actually need identity*.** §10 keeps
   it, as a user-space pattern with a visible price, rather than as a compiler-inserted
   universal translation.

3. **`Map` as a store-of-stores is load-bearing.** §11 generalizes it rather than working
   around it.

---

## 5. The lifetime-annotation alternative

The suggestion is annotations on instantiation — `circ@Set(...)`, `tx@Set(...)`,
`st@Set(...)` — marking a store's lifetime as circuit-local, transaction-scoped, or
persistent, plus an affine or linear discipline in the style of Rust to avoid garbage
collection.

It is a coherent design and it is aimed at a real problem. It should be set aside for two
reasons.

**The middle region does not exist.** The machine has exactly one tier between
"circuit-local value" and "persistent chain state", and it is `Effects` — a struct of nine
typed collections (`onchain-runtime/src/context.rs:640-656`) projected onto the VM stack as
a nine-element `Array` of `Map`s and decoded structurally on the way out (`:776-841`,
requiring `arr.len() == 9`). It is not general-purpose scratch space:

- Its shape is fixed at nine slots and each must decode as `Nullifier` / `CoinCommitment` /
  `TokenType` / `u128` / `u64`; you cannot stash arbitrary bytes.
- It is reset **per call and per segment** — `construct.rs:790` sets
  `continuation_context.effects = Effects::default()` across the checkpoint, and
  `QueryContext::new` hardcodes `effects: Effects::default()` (`context.rs:906-913`), with a
  fresh `QueryContext` per call at `semantics.rs:1438`.
- It is not private: it is declared verbatim in the `Transcript`, equality-checked at
  replay, and hashed into the proof's binding input (`verify.rs:1988-1996`).

There is no per-transaction scratch heap, no shared memory between two calls to the *same*
contract in one transaction, and no rollback journal. The only cross-call channel is the
persistent state itself. So `tx@` is not an annotation on an existing region; it is a
**request for a new VM state tier, which is a hard fork.** Meanwhile `circ@` already exists
and is spelled `Val`, and `st@` is every store there is. The annotation trisects a space the
machine divides in two.

**Affine types solve a problem this design should not have.** Rust needs ownership because
it allocates on a heap with data-dependent lifetimes and has no runtime to reclaim. That is
the *only* reason. Compact does not need to allocate — §6 shows the feature can be built
without an allocator at all — and once you do not allocate, there is nothing to schedule the
freeing of. Adding a substructural type system to manage a heap you did not have to
introduce is a large complexity cost paid for a self-inflicted problem.

Two pieces of the idea survive and are kept:

- **Uniqueness matters even without allocation.** Two references to one place is a real
  hazard. §7 keeps the concern and drops the mechanism, because in Compact the check is
  exact and cheap at runtime, which a static discipline cannot be.
- **Explicit deallocation should be cheap and encouraged.** `bytes_deleted` is credited
  (`onchain-state/src/state.rs:817-848`; the `update` call folds
  `incremental_write_delete_costs` into gas), so freeing state is already rewarded. There is
  no rent and no per-contract state cap anywhere in the tree — exhaustive grep for
  `rent|state_size|storage_cost|max_state` returns zero hits — and the only brake on growth
  is the per-block `bytes_written` cap of 50,000 (`ledger/src/structure.rs:1270-1283`). So
  unbounded heap growth is a fee problem paid once by whoever grows the state and never
  again by anyone, with the network carrying the storage forever. That is a further argument
  against a design that allocates by default.

---

## 6. The proposal: references are keys

### 6.1 The one-sentence version

> A `Store` is an **indexed family of places**. `&S` is the type of an index into that
> family: a `Val` whose runtime representation is exactly the tuple of dynamic keys along
> the access path. The static part of the path — which ledger field, which slot indices,
> which stores are traversed — is a monomorphization argument and is erased before code
> generation.

Two immediate consequences, both of which do most of the design work:

- **Navigation costs no reads.** A reference's keys come from the circuit's own inputs, not
  from state. They are pushed as `Key::Value` immediates or as stack keys fed by `push`
  immediates. Neither is a `popeq`, so neither enters the read set.
- **References are ordinary data.** They can be compared, passed, returned, put in
  `Vector`s, tuples and structs, and stored in the ledger — because a key tuple is a `Val`
  and `Val`s can do all of those things already.

### 6.2 Admissibility

`coherent-type-landscape.md` states the criterion (L15-18, L34-42):

> **Totality invariant.** Every type has a size that is a closed term in the size algebra at
> the point of use, and every elimination is a fold over a finite index.
>
> A feature is admissible iff it preserves "size and control shape are closed terms at the
> point of use."

`&S`'s width is `Σ|Kᵢ|` over the dynamic keys in the instance's path. That is not a
constant — it varies per instantiation — but it *is* a closed term once the instance is
fixed, and instances are fixed by `expand-modules-and-types`, which runs first in the
analysis pipeline (`compiler/analysis-passes.ss:75`), long before `flatten-datatypes`
in `compiler/circuit-passes.ss:71`. **`&S` is admissible for precisely the same reason
`Vector<n,T>` is admissible: its size is a closed term at the point of use, supplied by
monomorphization.**

Take the three faces of the invariant in turn.

*A finite proving circuit exists.* ✅ — the reference contributes a fixed number of field
elements per instance; `flatten-datatypes` sees a concrete width.

*Declared gas is meaningful.* ✅ — the emitted opcode sequence per instance is
straight-line and fixed; only the key *values* vary at runtime, exactly as they do for
`m.lookup(k)` today.

*The opcode stream is a valid ZK public input.* ✅ — path length and the literal/stack
pattern are fixed per instance, which is what `ops.rs:501-522` requires.

And the invariant *rules out* the right things automatically. `&` applied to an element of
an unbounded recursive store has no closed-term width: `List` is
`[Cell<V>|Null, List<V>|Null, Cell<Uint<64>>]`, so a reference to its *n*-th element
would need *n* to be in the type. It is not, so there is no such reference. That is the same
side condition `coherent-type-landscape.md` §3.4 identifies — "μ is admissible at `Store`
provided every operation's path depth is a closed term" — falling out here without being
imposed.

### 6.3 The kind algebra

Kinds are the sorts of the type-level language. **Users never write them.** As today, a
binder's kind is determined by its position and sigil: `<T>` binds a `Val`, `<#n>` binds a
`Nat` (`doc/compact-reference.mdx:320-326`). No new sigil is introduced, because — see
§6.5 — no store parameter is ever written in the surface language.

```
κ ::= Nat | Val | Store | Extern | Iface
```

**`Val` formers.**

```
Boolean, Field, Uint<a..b>, Bytes<n>, curve points  : Val
Vector                                              : Nat → Val → Val
[T₁, …, Tₙ]                                         : Val* → Val        (tuple)
struct / enum / new type                            : Val* → Val
&                                                   : Store → Val       ← the new one
```

`&` is the only former that crosses from `Store` to `Val`.

**`Store` formers — primitive.** These are exactly the five `StateValue` shapes
(`onchain-state/src/state.rs:69-96`), and four of the five already have Compact names or
Compact syntax:

```
Null                          : Store
Cell                          : Val → Store
Map                           : Val → Store → Store
[S₁, …, Sₙ]                   : Store* → Store      (n ≤ 16; the VM's Array)
⟨bounded Merkle tree⟩         : Nat → Store         (no user-facing name; see §14)
```

**`Store` formers — library.** Definable over the primitives, and today's ADT table is
already almost entirely this. Verified from each declaration's `initial-value`:

| ADT | `initial-value` | Actually is |
|---|---|---|
| `Cell<V>` | `(state-value 'cell …)` | **primitive** |
| `Map<K,V>` | `(state-value 'map ())` (`:700`) | **primitive** |
| `Counter` | `(state-value 'cell (align 0 8))` (`:588`) | `Cell<Uint<64>>` + different ops |
| `Set<V>` | `(state-value 'map ())` (`:624`) | `Map<V, Null>` |
| `List<V>` | `'array` of 3 (`:800`) | a store tuple |
| `MerkleTree<h,V>` | `'array` of ⟨bmt h⟩ and a cell (`:971`) | a store tuple |
| `HistoricMerkleTree<h,V>` | same plus a history map | a store tuple |

**Five of the seven ledger ADTs are already library constructions**, not two.
`coherent-type-landscape.md` §3.5 identified `List` and `HistoricMerkleTree`; `Counter`,
`Set` and `MerkleTree` belong on the list too.

**Coercion.** `Val → Store` at store position, `V ↦ Cell<V>`. This already exists for
ledger fields (`expand-modules-and-types.ss:1158-1171`). Extending it to `Map`'s value
position makes `Map : Val → Store → Store` uniform, with today's `Map<K,V>` sugar for
`Map<K, Cell<V>>`. INFERRED, from the templates rather than from diffed output: this is
behaviour-preserving, because `Map<K,V>.lookup(k)` emits `dup; idx[f]; idx[k]; popeq`
(`midnight-ledger.ss:741-747`) and `Map<K,Cell<V>>.lookup(k).read()` emits
`dup; idx[f,k]; popeq` — the same opcodes with the same path.

**On naming.** `coherent-type-landscape.md` §3.5 calls the primitives `Table`, `Slots` and
`Tree`, presumably to avoid colliding with the library ADTs of the same names. The table
above shows there is no collision to avoid: Compact's `Cell` *is* the VM's `Cell` and
Compact's `Map` *is* the VM's `Map`, with no additional structure in either. Keep the
existing names. The only primitive with no Compact name is the `Array` shape, and §6.4
gives it one without inventing a word.

### 6.4 Store tuples reuse Compact's tuple syntax

The fixed-arity heterogeneous store former does not need a name, because Compact already
writes fixed-arity heterogeneous products as `[T₁, …, Tₙ]`. The tuple type is the primitive
spelling in Compact — `doc/compact-reference.mdx:913-935` defines `Vector<n,T>` as
equivalent to a tuple type, not the other way round — so the same syntax at kind `Store` is
the natural reading:

```compact
store List<V: Val> {
  rep [Cell<V> | Null, List<V> | Null, Cell<Uint<64>>] = [Null, Null, 0];

  op isEmpty(): Boolean  { return observe(rep[1] is Null); }
  op length(): Uint<64>  { return observe(rep[2]); }
  op popFront()          { rep := rep[1]; }
  op pushFront(v: V)     { rep := [v, rep, rep[2] + 1]; }
}
```

`[A, B]` at kind `Val` is a tuple of values, concatenated in the FAB alignment. `[S, T]` at
kind `Store` is a tuple of places, an `Array` in the state tree. Same syntax, same meaning
— a fixed-size heterogeneous product — differing only in kind. Projection comes for free:
Compact indexes with brackets, not dots (`expr₈ → expr₈ '[' expr ']'`;
`doc/compact-reference.mdx` §Syntax of expressions), so it is `rep[1]`, not `rep.1`.

One asymmetry to write down: `Val` tuples have no arity bound, `Store` tuples cap at 16,
because `StateValue::Array` does (`onchain-state/src/state.rs:69-96`). The bound belongs to
the VM, not to the syntax.

The `| Null` in the example is speculative — it presumes real sum types
(`coherent-type-landscape.md` reform item 2), as does `is`. Nothing in this proposal's core
depends on them; §13.

#### A store operation is not a circuit

The example above writes `op`, not `circuit`, and the difference is not cosmetic. It is
**stage**:

- A `circuit` body compiles to **circuit stage** — ZK constraints. Its escape to the VM is
  a ledger-operation call.
- A store operation body compiles to **VM stage** — opcodes. Its escape to the circuit is
  `observe(...)`.

They are duals: the same shape, opposite default stage, each with one marked bridge to the
other. `Counter.lessThan` is the case that makes it concrete
(`midnight-ledger.ss:595-601`): `idx; push threshold; lt; popeq` performs the comparison
**in the VM** and publishes only the resulting `Boolean`. Written as a circuit it would
read the counter and compare in-circuit, disclosing the count. A reader has to be able to
tell which one they are writing, and the keyword is what tells them.

Three further differences that a `circuit` keyword would hide:

1. **Arguments are necessarily public** (§9), whereas an unannotated *native* circuit
   argument is a syntax error — opposite defaults, as `traits-design-space.md` §2.6 notes.
2. **The operation carries an op-class** (`read` / `write` / `update` / `remove` /
   `update-with-coin-check`) consumed by three independent analyses:
   `check-sealed-fields.ss:58-61` (a sealed field admits only `read`),
   `print-typescript.ss:507-511` (only `read` ops get a TypeScript getter), and purity
   inference.
3. Under the reform that op-class is **derived from the body** — observes iff it contains
   `observe`, mutates iff it contains `:=` (`coherent-type-landscape.md` §3.3) — which is
   only coherent if the body has a stage discipline to derive it from.

`op` matches the compiler's own vocabulary throughout: `adt-op`, `find-adt-op`, `op-class`,
`ledger-op`. `query` is the historical alternative — the 2022 micro-ADT proposal called
these "public oracle queries" and the runtime entry point is still `queryLedgerState` — but
these mutate, so it reads wrong. Flagged as open; §14.

### 6.5 The index algebra, and what the surface actually looks like

`&` is defined by structural recursion on the store former:

```
keys(Cell<V>)        = []                 -- a Cell is one place; no index
keys(Null)           = []
keys([S₁, …, Sₙ])    = static             -- slot choice is a compile-time index
keys(Map<K, S>)      = [K, ...keys(S)]    -- the only former contributing runtime data
```

so, for the library stores:

```
&Cell<V>       -- width 0    (a top-level cell: purely compile-time)
&Counter       -- width 0
&Set<V>        -- width 0    (a Set's members are not places you can write through)
&List<V>       -- width 0    (only the whole list is a place)
&Map<K, S>     -- width |K| + width(&S)
```

**`Map` is the only former that contributes runtime width.** Everything else is static, so
in practice a reference is either zero-width — a pure compile-time lens, exactly reading
(a) — or a small tuple of map keys the circuit already holds.

#### There are no store parameters in the surface language

This is worth stating flatly, because an earlier draft of this document reached for a
`store trait` bound called `Place<V>` and it was a mistake. `&` applies to the store types
users already write in `ledger` declarations. Nothing else is needed:

```compact
ledger alice: Cell<Uint<64>>;
ledger accounts: Map<Bytes<32>, Cell<Uint<64>>>;

circuit credit(acct: &Cell<Uint<64>>, amount: Uint<64>) {
  acct.write(acct.read() + amount);
}

circuit bumpTwice(c: &Counter) { c.increment(1); c.increment(1); }

export circuit payAlice(amount: Uint<64>) {
  credit(&alice, amount);                          // width-0 reference: vanishes
}

export circuit pay(to: Bytes<32>, amount: Uint<64>) {
  credit(&accounts.lookup(to), amount);            // width-32 reference: one key
}
```

`&Counter` means *a reference to some place holding a `Counter`*. The store's identity is
existentially quantified in the surface and universally quantified — that is,
monomorphized — in the elaboration. There is nothing for the programmer to name.

Two features that an earlier draft ran together, and which should stay apart:

| | Abstracts over | Surface vocabulary | Reform item |
|---|---|---|---|
| **`&T`** (this proposal) | the **place**, store type fixed | none beyond `&` | new |
| **`store trait`** | the **store type** | `trait`, bounds | item 5 |

They compose once both exist — `circuit bump<S: Incrementable>(c: &S)` — but `&` does not
need store traits, and this proposal does not propose them.

#### Surface, elaborated, core

| Layer | `&` present? | Store parameters? | Produced by |
|---|---|---|---|
| **Surface** — what the user writes | yes, as `&T` | no | — |
| **Elaborated** — post `expand-modules-and-types` | yes, as an ordinary `Val` of key-tuple type | yes, one per `&` occurrence, monomorphized | `analysis-passes.ss:75` |
| **Core** — post `propagate-ledger-paths` | **no** | **no** | `analysis-passes.ss:87` |

The elaboration, precisely:

- each `&T` **occurrence in a signature** becomes one fresh store parameter plus one
  ordinary value parameter of type `keys(T)` — and when `keys(T)` is `[]`, that parameter
  vanishes entirely;
- each `&p` **at a call site** supplies the store argument (`p`'s field name and accessor
  skeleton, with holes where its keys go) and the value argument (`p`'s key tuple).

So `credit(&accounts.lookup(to), amount)` elaborates to a specialized
`credit__accounts(to, amount)` whose body mentions `accounts.lookup(·)` directly. By the
Core layer a reference has become what it always was: static indices at the front of a
`path-elt` list and ordinary circuit expressions in the dynamic tail
(`langs.ss:888-890`). **That is why nothing downstream — ZKIR, TypeScript, the VM — has to
change.**

Each `&T` occurrence getting its *own* store parameter is Rust's lifetime-elision rule
applied to stores, and it gives exactly the right aliasing behaviour; §7.

The `&` is required at the call site. `credit(alice, …)` remains an error from
`desugar-ledger-read` (`infer-types.ss:1184`; the reference documents it at
`doc/compact-reference.mdx:1720`), with a message that now suggests `&alice`. This gets the
prior proposal's disambiguation property without a whole-language move to explicit reads:
the ambiguity only arises where the programmer wrote `&`.

*(Spelling is a bikeshed. `&S` reads well in signatures but invites a Rust intuition this
design explicitly rejects — there is no borrow checker and no lifetime. `Ref<S>` is duller
and safer. Flagged as open; §14.)*

### 6.6 Typing rules

Place expressions, which is what `&` applies to:

```
  p ::= x                        -- a ledger field
      | p[e]                     -- Map lookup, e : K
```

Formation:

```
  Γ ⊢ p place,   p : S,   S : Store
  ─────────────────────────────────────────────────
  Γ ⊢ &p : &S_p        where S_p is p's store instance
                       and  |&S_p| = Σ |Kᵢ| over p's dynamic keys
```

Elimination — dereference is not an operation, it is where operations happen:

```
  Γ ⊢ r : &S_p,   op ∈ ops(S)
  ─────────────────────────────────────
  Γ ⊢ r.op(ē) : result-type of op
```

Nominality:

```
  &S_p = &S_q   iff   p and q are the same store instance after monomorphization
```

Two references have the same type iff they came from the same store. This is the load-bearing
rule and §7 is entirely a consequence of it.

Kinding:

```
  & : Store → Val
```

`&` is the **only** type former that crosses from `Store` to `Val`, and it does so by
projecting exactly the part of the access path that is already runtime data. That is a
satisfying place for it to sit: `coherent-type-landscape.md` §1.1 sets up `Val` and `Store`
as two universes and says keeping them apart is what lets each be clean. `&` is the one
bridge, and it is lossy in the right direction — it forgets the static part, which
monomorphization recovers.

Note the pleasing symmetry with §6.4's other bridge: **`observe` is the term-level crossing
from `Store` to `Val`, and `&` is the type-level one.** `observe` costs a `popeq` because it
moves *contents*; `&` costs nothing because it moves only an *address that the circuit
already holds*.

### 6.7 What this is *not*

It is not the heap model with better syntax. The distinction is one property:

> **A reference is *derived* if every key on its path is computable in the circuit from the
> transaction's own inputs without reading state. It is *observed* if any key must be
> obtained by `popeq`.**

Derived references cost nothing in the read set. Observed references are the heap model.
§10 shows the language should permit both and make the difference visible — but derived is
the default, and it is what `&` gives you.

### 6.8 What crosses which boundary

One criterion decides every case:

> **A `&S` may cross a boundary iff that boundary is monomorphized.**

The dynamic half of a reference is a `Val` and goes wherever `Val`s go. The static half —
the store instance — must be resolved by specialization, so the question is always whether
there is a statically-known call site that fixes it.

| Boundary | takes `&S` | returns `&S` | why |
|---|---|---|---|
| internal `circuit` | ✅ | ✅ | specialized per call site |
| exported `circuit` | ❌ | ❌ | caller is TypeScript; no store to supply |
| `witness` | ❌ | ❌ | callee is TypeScript |
| `contract` circuit | ❌ | ❌ | callee is ∃-typed; no call site to specialize |
| `op` | ✅ | ✅ **only as a path-former** | see below |

#### Circuits may return references

The returned reference's store must be a compile-time function of the circuit's own store
parameters and its body. Both of these are fine:

```compact
circuit accountOf(pk: Bytes<32>): &Cell<Uint<64>> {
  return &accounts.lookup(pk);                    // store fixed by the body
}

circuit at(m: &Map<Bytes<32>, Cell<Uint<64>>>, k: Bytes<32>): &Cell<Uint<64>> {
  return &m.lookup(k);                            // store = caller's m, composed with lookup
}
```

This one is not:

```compact
circuit pick(flag: Boolean): &Cell<Uint<64>> {
  return flag ? &alice : &bob;                    // ill-typed
}
```

— and note **it is rejected without any rule about references.** `&alice` and `&bob` are
different types by the nominality rule of §6.6, so the conditional is ill-typed exactly as
`flag ? 1 : "x"` is. *Runtime store selection is already forbidden by the type system;* this
proposal does not have to forbid it separately. (§10.1 gives the deeper reason it must stay
forbidden, and the bounded substitute.)

The elaborated signature of `at` is dependent — `∀S:Store. &S → Bytes<32> → &(S ∘ lookup)`
— and this costs no new machinery, because **Compact never typechecks a generic
definition.** `expand-modules-and-types` runs before `infer-types`
(`analysis-passes.ss:75-76`) and holds generic definitions as raw unexpanded pelts,
expanding one per instantiation (`:999-1012`). Every signature `infer-types` ever sees is
already concrete.

The same applies to references inside aggregates: a circuit may return
`struct Pair { from: &Cell<Uint<64>>, to: &Cell<Uint<64>> }`, and the store instances are
part of `Pair`'s type, so it monomorphizes per instantiation like `Vector<n,T>`.

**One asymmetry worth naming, which is about notation rather than admissibility.** In
argument position `&Cell<Uint<64>>` means *any place holding one* — the caller supplies it,
and the annotation is completed at the use. In return position it means *the specific place
my body picked* — the caller may use it but cannot substitute it, and the annotation is
completed at the definition. Two circuits with identical signatures can return references
into different stores. That is sound, since the store is statically known after
monomorphization, but the notation does not currently say which reading applies where, and
it probably should. `place-references-impl-plan.md` §12 works through this and the one place
it costs implementation effort — the alias analysis has to follow returns, not only compare
arguments at a call site.

#### Ops may take references, at a doubled depth cost

An `op` is positioned at its own path `f`, of depth d₁; an argument reference has depth d₂.
Touching both means two open paths on the stack. Since `idxp` pushes `(container, key)` at
every level (`onchain-vm/src/vm.rs:915-918`), reaching across both needs `dup n` with
`n ≥ 2(d₁+d₂)+1`, capped at 15 — so **d₁ + d₂ ≤ 7**. This is §8's budget with the two paths
summed, and `Cell.writeCoin` already sits at that limit for a *single* path
(`midnight-ledger.ss:577-578`). Nothing else is new: aliasing is §7's machinery, disclosure
is §9's.

#### Ops may return references only by composing paths — and one already does

An op body is VM-stage, and the only way VM-stage code hands a value to the circuit is
`popeq`, which reads state (§3.2). So the case splits exactly along §6.7's derived/observed
line:

- If the returned reference's keys must come **from state**, a `popeq` is required. That is
  reading (d), the heap. It should be written with `observe`, and then it is not an op
  returning a reference — it is an op returning a `Val` that the caller uses to form one
  (§10.2).
- If the keys come from **`self`'s path plus the op's own arguments**, no `popeq` is needed,
  because the reference is not *computed* at runtime; it is *composed* at compile time.

The second case already exists, for exactly one operation. **A non-terminal `Map.lookup`
compiles to zero opcodes**: `propagate-ledger-paths.ss:157-171` dissolves it into a path
element, and only a *terminal* `lookup` emits the `popeq` at `midnight-ledger.ss:741-747`.
Compact already has an op that returns a reference; it is hardcoded, for one ADT, by two
assertions (`propagate-ledger-paths.ss:159-161`).

**So `nav` should be a declared op class** — *returns a place; emits no opcodes; contributes
a path element*. Declaring it is precisely what turns those two assertions into a rule, and
it is the *same* change §11.1 wants in order to nest stores beyond `Map`. The two items
collapse into one.

It also sharpens the op taxonomy. An op is either a **navigation** (compile-time, yields a
place) or a **computation** (runtime, yields a value or mutates), and
`coherent-type-landscape.md` §3.3's two derived bits — observes? mutates? — apply only to
the second.

#### A hazard that turns out to be handled

`check-sealed-fields.ss` roots its walk at a syntactic `ledger-field-name` hashtable
(`:69-84`) and checks the op-class at the end of each accessor chain (`:49-67`). A
reference to a sealed field's interior, passed into a helper circuit that writes through it,
would appear to escape that check.

It does not. Because the store is **spliced** at `expand-modules-and-types`
(`analysis-passes.ss:75`) and sealing runs at `:82`, the specialized callee body literally
contains `accounts.lookup(·)` by the time the check sees it. The analysis is unchanged.

This generalizes the §12.2 argument about the emitted JavaScript: **because the store is
substituted rather than passed, every downstream analysis that keys on ledger field names
keeps working unmodified.** That property is worth protecting in any implementation — it is
what keeps the blast radius of this feature confined to `expand-modules-and-types`.

### 6.9 Worked examples

**Transfer between two accounts** — the handoff's motivating example:

```compact
ledger accounts: Map<Bytes<32>, Cell<Uint<64>>>;

circuit transfer(from: &Cell<Uint<64>>, to: &Cell<Uint<64>>, amount: Uint<64>) {
  assert(from != to, "transfer to self");
  const balance = from.read();
  assert(balance >= amount, "insufficient funds");
  from.write(balance - amount);
  to.write(to.read() + amount);
}

export circuit pay(recipient: Bytes<32>, amount: Uint<64>) {
  transfer(&accounts.lookup(ownPublicKey()), &accounts.lookup(recipient), amount);
}
```

Both parameters monomorphize to the same store, so `from != to` is a 32-byte equality in
circuit — two constraints. Emitted opcodes: four `Idx`es with a two-element path each
(slot index literal, key from stack), two `popeq`s for the two `read`s, two `Ins`es. **The
read set contains two balances and nothing else.** No addresses, no allocator, no counter.

**A library circuit over any counter:**

```compact
circuit bumpTwice(c: &Counter) { c.increment(1); c.increment(1); }
```

`Counter.increment` is `idx; addi; ins` (`midnight-ledger.ss:602-606`) — no `popeq`. So
this discloses nothing and conflicts with nothing, at any instantiation. Note that no
generic parameter, bound, or trait appears: `&Counter` is the whole signature.

**Mixed stores:**

```compact
circuit sweep(from: &Cell<Uint<64>>, to: &Cell<Uint<64>>) { ... }
sweep(&alice, &accounts.lookup(k));       // two DIFFERENT store instances
```

The two parameters have different types after monomorphization, so they are **statically
distinct**. No disequality assertion is required or generated. §7.

---

## 7. Aliasing

The handoff predicts this is the hardest question, and `coherent-type-landscape.md` never
addresses it — its argument at L278-280 that compile-time paths are "something better" than
`&mut T` holds only while every path is fixed at its use site, and parameterization
reintroduces exactly the problem `&mut` exists to answer.

### 7.1 What actually goes wrong

Less than one might fear. Aliasing in Compact is **not** memory-unsafe and **not**
nondeterministic. Impact is sequential, evaluation order is deterministic, and "last write
wins" is well-defined. Several sequences are simply correct when aliased: `from.decrement(n);
to.increment(n)` nets to zero, which is what a self-transfer should do; the prior proposal's
`swap` swaps a value with itself.

The hazard is a **read-after-write on locations assumed distinct**:

```compact
circuit split(a: &Cell<Uint<64>>, b: &Cell<Uint<64>>) {
  const total = a.read() + b.read();
  a.write(total / 2);
  b.write(total - total / 2);
}
```

Aliased, `total` is `2a` and the final value is `a` — the money is halved. That is a
specification hazard, and it is the shape worth detecting.

### 7.2 The two-level decision

Because the type rule in §6.6 makes `&S` nominal in its store instance:

**Level 1 — static, exact.** Two reference parameters can alias **only if
monomorphization gave them the same store instance.** That is a compile-time fact known
precisely, with no conservatism, at each instantiation. In the `sweep(&alice, &accounts.lookup(k))`
case above, the question never arises.

**Level 2 — dynamic, exact.** Given the same store, two references denote the same place
**iff their key tuples are equal**. That is ordinary `Val` equality — two constraints for a
`Bytes<32>` key.

That is the entire aliasing story, and it is *exact at both levels*. There is no
approximation anywhere.

### 7.3 Why a borrow checker would be worse

This deserves stating carefully, because "add `&mut` and a uniqueness discipline" is the
reflex, and here the reflex is wrong for a structural reason.

Rust's borrow checker works on *lvalue paths*, which are static syntax. It can prove
`x.a` and `x.b` disjoint because the field names differ. It cannot in general prove
`v[i]` and `v[j]` disjoint, and it does not try — it forces you to restructure
(`split_at_mut`) or to reach for runtime checks (`RefCell`).

In Compact, **the discriminating data is always runtime.** `accounts.lookup(a)` and `accounts.lookup(b)`
are the same store instance; only `a` and `b` distinguish them. So a static uniqueness
discipline would have to be conservative, and conservative here means rejecting
`transfer(&accounts.lookup(a), &accounts.lookup(b), amount)` — the motivating example. A borrow checker
would buy imprecision at the cost of a large new type-system feature and would reject the
programs the feature exists for.

The runtime check is available and cheap for a reason specific to this language: **because
references are keys, they are data, and data can be compared.** An opaque handle could
not. The design that makes references cheap is the same design that makes aliasing
decidable.

### 7.4 The proposed rule

Define a circuit as **alias-sensitive** iff its body contains a read of one reference
parameter sequenced after a write through another reference parameter of the same store
type. This is a syntactic analysis over the body, and by the time it runs the body has been
monomorphized and (in `circuit-passes`) inlined, so it is exact.

At a call site passing two same-typed references:

- if the compiler can see the keys are distinct literals — statically distinct, accept;
- else if the callee is alias-sensitive and the body does not already assert disequality —
  **error**, with a message naming the two parameters and suggesting `assert(from != to, …)`;
- an explicit opt-in annotation (`overlapping`, name TBD) suppresses the error and
  documents last-write-wins.

Default deny, one-line escape, no new type system. The check is worth having independently:
the same analysis catches the hazard in ordinary code today wherever two `lookup`s with
non-obviously-distinct keys are interleaved.

### 7.5 Privacy is not a complication

Keys are public (§9), so the disequality assertion leaks nothing that passing the
references had not already leaked. The two answers reinforce rather than fight.

---

## 8. Depth budgets

The handoff asks whether the budget check should happen after specialization or be encoded
as declaration-time depth indices. **Both, with the post-specialization check
authoritative.** And this section should be implemented whether or not the rest of the
proposal is, because the budget is unchecked today (§1.7).

### 8.1 The budgets, and how they compose

| Budget | Value | Source |
|---|---|---|
| `Idx` path length | ≤ 16 keys | `ops.rs:501-522`, `path.len()-1` in low nibble |
| `Ins` levels | 1..15 | `ops.rs:503-504`, `0x90 \| n` |
| `Dup` / `Swap` reach | ≤ 15 | `ops.rs:501-502` |
| store-tuple (`Array`) arity | ≤ 16 | `onchain-state/src/state.rs:69-96` |
| ledger B-tree arity | 15 | `langs.ss:851`, `maximum-ledger-segment-length` |
| coin-writing ops | **`d ≤ 5`** at the tightest | four distinct `dup` formulas; see below |

The reach budget is the binding one, and the reason is mechanical: `idxp` pushes
`(container, key)` at every level (`vm.rs:915-918`), so after descending a depth-`d` path
the stack holds `2d` items above whatever was there before. Reaching past an open path needs
`dup n` with `n ≥ 2d+1`. The shipped compiler computes exactly this
(`program_fragments.rs:147`: `Op::Dup { n: (3 + (((len - 1)) * 2)) }`).

**The bound is per-operation, and the four coin ops disagree** (`grep -n "length f"
compiler/midnight-ledger.ss` — 36 sites, five distinct formulas):

| Op | `dup` operand | Bound |
|---|---|---|
| `List.pushFrontCoin` (`:940`) | `(+ 5 (* (length f) 2))` | **d ≤ 5** |
| `Map.insertCoin` (`:781`) | `(+ 3 (* (length f) 2))` | d ≤ 6 |
| `Set.insertCoin` (`:680`) | `(+ 2 (* (length f) 2))` | d ≤ 6 |
| `Cell.writeCoin` (`:578`) | `(+ 3 (* (sub1 (length f)) 2))` | d ≤ 7 |

Note that the warning comment at `:577` — "if `f` is longer than 5, this exceeds the limit of
15" — sits on `Cell.writeCoin`, whose bound is actually 7. The operation whose bound really
is 5 is `List.pushFrontCoin`, which carries no warning. The single piece of documentation
that exists is attached to the wrong op, which is the strongest available argument for a
mechanical check rather than a symbolic one. `store-nesting-impl-plan.md`'s sibling,
`depth-check-impl-plan.md`, specifies it.

Three ways depth accumulates, and **only the first is visible in a type today**:

1. store nesting — each `Map` layer adds one;
2. the ledger B-tree prefix — `ceil(log₁₅ |fields|)` from `determine-ledger-paths.ss:24-48`;
3. under this proposal, the caller's path prefix at each store parameter.

Contribution (2) is the nasty one and it exists *now*: **adding a sixteenth ledger field
deepens every path in the contract by one**, and can push a `writeCoin` over the reach limit
with no diagnostic and no runtime error — `Dup { n: 16 }` field-reprs identically to
`Dup { n: 0 }` (`ops.rs:501`) and nothing downstream range-checks it.

### 8.2 The rule

Index `Store` types by depth, as `coherent-type-landscape.md` reform item 6 proposes
without specifying:

```
  S : Store(d)          d : Nat, the path depth of S below the state root
  & : Store(d) → Val
```

Then every budget is arithmetic in the existing `Nat` kind — the same kind that already
carries `Vector<n,T>` and `MerkleTree<h,V>`, and which `expand-modules-and-types` already
threads end-to-end as `Info-size` (`:939`, `:245`, `:128`, `:138-140`).

- **Inferred, not written.** `d` is computed, not annotated. Users never write it.
- **A declaration-site bound is optional documentation.** `circuit f(r: &Counter) where
  depth(r) ≤ 5` lets the error point at the definition rather than at a call site three
  modules away. Recommended for library circuits, not required — and note it is a bound on
  the *parameter*, not on a named store type, so it needs no store-parameter syntax.
- **The authoritative check is post-specialization**, in a new pass after
  `propagate-ledger-paths`, where the full `path-elt*` list is known and `(length f)` is the
  quantity the ADT templates actually consume (`midnight-ledger.ss:754`, `:761`, `:767`,
  `:585`).
- **Per-operation, not per-store.** `writeCoin` binds at `d ≤ 7`; `Cell.read` binds at
  `d ≤ 16`. The budget belongs to the op, so the check runs at the emission site with the
  op's own formula.

### 8.3 The standalone fix

Independent of everything else in this document: add the post-`propagate-ledger-paths`
check and turn `midnight-ledger.ss:577`'s comment into a diagnostic. It is small, it closes
a silent miscompile, and it is a prerequisite for anything that makes paths easier to
compose.

---

## 9. Disclosure

**Confirmed, and the rule is forced rather than chosen.**

Every argument to a store operation ends up inlined into the opcode stream — as a
`Key::Value` immediate in an `Idx` path, as a `push` immediate feeding a `Key::Stack`, or as
an `addi` immediate. And `ledger/src/verify.rs:1944-1970` field-reprs the entire program of
both transcripts into the proof's public inputs:

```rust
    pub fn public_inputs(&self, binding_com: Pedersen) -> Vec<Fr> {
        let mut res = vec![self.binding_input(binding_com)];
        res.push(self.communication_commitment);
        if let Some(guaranteed) = self.guaranteed_transcript.as_ref() {
            for op in guaranteed.program.iter() { op.field_repr(&mut res); }
        }
        ...
```

`Key::field_repr` (`ops.rs:67-78`) writes the `AlignedValue` for a literal and `-1` for a
stack key. So:

> **Typing rule.** `&S` is a public `Val`. Forming `&p` discloses every dynamic key in `p`.
> `track-witness-data.ss` treats `&`-formation as a disclosing coercion at exactly the
> points it already treats ledger-operation arguments as disclosing — the `""`-means-
> discloses default at `ledger.ss:148`.

This is not even a new rule, on reflection. Compact already has an explicit `disclose(e)`
expression form (`doc/compact-reference.mdx` §Syntax of expressions), and the reference's
own nested-map example writes `fld.lookup(b).lookup(n) += disclose(k)` (`:1686`). Since a
reference is nothing but the keys of such a chain, `&p` inherits the existing obligation
verbatim: **a witness-derived key inside `&p` must be wrapped in `disclose`, exactly as it
must be today when written inline.** `coherent-type-landscape.md` §3.3 (L368-374) argues
this default is "the only sound default" for store-op arguments; `&` gets it for free
because a reference *is* a bundle of store-op arguments.

Two consequences worth stating in any eventual CoIP:

- **There is no private reference.** To touch a place chosen by secret data you must either
  disclose the choice or fold over a statically bounded set of candidates. This is a
  fundamental property of the machine, not an implementation gap.
- **Reference equality is public**, which is what makes §7's assertion free.

---

## 10. Return, storage, and the `observe` boundary

The handoff expects "almost certainly no" to both. The answer is **yes to both**, and the
reason is the same one that makes the whole design work: a reference is a `Val`.

### 10.1 Returning a reference

Admissible; §6.8 works through which boundaries a reference may cross and why. In short:
`circuit findAccount(pk: Bytes<32>): &Cell<Uint<64>>` returns a key, and the store is fixed
by monomorphization and flows outward as a compile-time fact.

The restriction is that a circuit **cannot return a reference into a store chosen at
runtime**. §6.8 notes that the *surface* rejection of this is free — the two branches of
`flag ? &alice : &bob` have different types. The deeper reason it must stay rejected is that
such a thing is an existential over `Store`, and eliminating it needs a dynamic path shape,
i.e. reading (b), which `ops.rs:501-522` forecloses. This is the same conclusion
`dynamic-deployment-design.md` §2 reaches for `deploy` and `traits-design-space.md` §4
reaches for dispatch: *which* store must be a compile-time choice. Three features arriving
at the same constraint from three directions is decent evidence it is real.

The bounded form is available: a **closed sum of stores**, eliminated by `match`, emits one
static path per arm behind a forward `branch`. That is admissible and it covers the
realistic "one of these three account tables" case. It needs real sums (§13).

### 10.2 Storing a reference — and the synthesis

A reference is a `Val`, so `Cell<&Accounts>` is `Cell<Bytes<32>>` and `Map<K, Cell<&Accounts>>`
is a table of keys. All of this is expressible **today**, with no compiler change at all.

Which is the point, and it is where this proposal absorbs the prior one rather than
rejecting it:

> **Reading (d) — the heap model — is not a language feature. It is a program.** It is what
> you get when you store references in the ledger and read them back. The prior proposal's
> contribution is the observation that this encoding is complete and VM-compatible. It is.
> The error is applying it universally, behind the programmer's back, as the meaning of
> every store-typed parameter.

And the boundary between the cheap case and the expensive case is exactly one operation:

- A reference **derived** from arguments, witnesses, or literals costs nothing. It is `&`.
- A reference **read back from state** is a `popeq`. It enters the read set, pins an
  identity, and brings the whole of §3.2 with it.

`coherent-type-landscape.md` §3.3 already has the marker for this and it is called
`observe`. Under that surface, `observe(cell0)` is visibly a read and `&accounts.lookup(k)` is
visibly not. **The programmer can see the price in the source.**

So the recommendation is: permit stored references, require the observation to be written,
and document the conflict semantics at that one site. Users who genuinely need identity —
a registry, a delegation table, a linked structure — get it, at a cost they opted into and
can point at. Users who wanted `transfer(from, to, amount)` never pay it.

That is the substantive difference between this proposal and the one on the branch, and it
is a difference of *defaults and visibility*, not of expressive power.

### 10.3 Dangling references are total

Because the encoding is a map key rather than an allocated address, a stale reference is
just an absent key, and the VM's behaviour is well-defined. `Idx` into a `Map` with an
absent key returns `Null` rather than failing (`onchain-vm/src/vm.rs:178-188`:
`map.get(key)...unwrap_or(StateValue::Null)`), and `Null` is not consumable — `popeq` and
`branch` both go through `as_cell()` (`state_value_ext.rs:26-31`) and raise `ExpectedCell`.

So a dangling dereference is a **hard, deterministic transaction failure**, guardable in
advance with `member`, never silent corruption. Compare the heap model, where preventing
exactly this is what the reference counting is for — and the reference counting is what
§3.3 shows cannot be made sound.

---

## 11. How much of this is subsumed by user-defined stores?

A great deal — and separating the two is worth doing carefully, because several requests
that arrive as "we want first-class ADTs" are really requests for *composition*.

| Request | Composition | `&` | Heap |
|---|---|---|---|
| `Map<K, Counter>`, `Map<K, List<V>>`, maps of maps | ✅ **already ships**, §11.1 | — | — |
| `List<Cell<Field>>` — an *ordered* collection of stores | ⚠️ needs the `nav` op class; §11.1 | — | — |
| `Set<Counter>`, `MerkleTree<8, Counter>` | ❌ never — elements are keys / hashes | — | — |
| A user-defined `WithHistory<S>` combinator | ✅ store traits (reform item 5) | — | — |
| `transfer(from, to, amount)` | ❌ | ✅ | — |
| A generic `swap` over two cells | ❌ | ✅ | — |
| A library circuit over any counter | ❌ | ✅ (`&Counter`, no bound needed) | — |
| Pass "an account" to a helper | ❌ | ✅ | — |
| Store a pointer to another user's record | ❌ | ✅ + `observe` | ✅ (this *is* the heap) |
| Heterogeneous registry of unlike stores | ❌ | ❌ | ❌ — §12.3 |
| Walk a linked list to runtime-determined depth | ❌ | ❌ | ❌ — totality invariant |

### 11.1 Most composition already works, and the rest is not cheap

An earlier draft of this section claimed that letting other ADTs hold stores "costs one
token" — changing `List`'s parameter from `Type` to `ADT/Type` at `midnight-ledger.ss:798`.
That was wrong in both scope and magnitude. `store-nesting-impl-plan.md` is the correction
in full; the summary:

**Store nesting inside `Map` already ships.** `examples/adt/tests/map_field_list_field.compact:19`
declares `export ledger c: Map<Field, List<Field>>;`, and
`compiler/javascript-code/test1135/` contains a generated two-level
`Map<Field, Map<Field, JubjubPoint>>` artifact, `.d.ts` and `.js` both. A counter per key, a
map per key, a list per key, two levels deep — all expressible today, with generated
TypeScript.

**`Set` and `MerkleTree` cannot hold stores at all**, for reasons unrelated to kinding.
`Set<V>`'s `V` is a *key* — `Set.insert` is `push [value (state-value 'cell elem)]; push
[value (state-value 'null)]` (`:658-662`), so the element becomes the map key. `MerkleTree`'s
`V` is *hashed into a leaf*, and a store has no alignment to hash (`expand-serialize.ss:205`).

So the blocked set is **`List<S>`, and nothing else** — and the reason it is blocked is not
the meta-type. It is that **`List` has no operation whose result type could carry a place.**
`Map.lookup` is declared `(function read lookup ([key key_type]) value_type` (`:741`) —
result is the bare formal. `List.head` is `(function read head () (Maybe value_type)`
(`:843`), and `Maybe<T>` is a `struct`, kind `Val`. There is nothing to nest through; a new
operation has to be designed.

That operation is a `nav` op (§6.8), which is the same conclusion this document reached from
the opposite direction. **Generalizing nesting and letting ops return references are one
change, not two.** But it is a multi-week compiler change with a design decision at the
front, not a kinding tweak: `List`'s nesting step takes zero arguments and contributes a
*static* index, while all five hardcoded sites assume one argument contributing a *dynamic*
key. The `.js` nested-accessor generator additionally hardcodes `Map`'s existence predicate
(`state<path> === undefined`), which would silently never fire for an empty `List`, whose
head is a null `StateValue` rather than `undefined`.

What remains true from the earlier draft: §6.3 shows **five of the seven ledger ADTs are
already store compositions** — `Counter` is a `Cell`, `Set` is a `Map`, and `List`,
`MerkleTree` and `HistoricMerkleTree` are store tuples. The nesting the type system forbids
is nesting the implementation does routinely. But "the implementation already does it" is
not the same as "the compiler is one token away from letting users do it," and conflating
those was the error.

### 11.2 What only `&` solves

Every remaining row is a *parameterization* request: the same code applied at more than one
place. That is what a lens parameter is for, and no amount of store composition provides it.

### 11.3 What nothing solves

**Heterogeneous collections of stores.** A `Map<Name, SomeStore>` needs an existential over
`Store`, and its eliminator needs a path shape chosen at runtime. Ruled out by
`ops.rs:501-522` — the path length is in the opcode nibble and the literal/stack pattern is
in the key stream, both field-repr'd into the proof. `traits-design-space.md` §4 rules out
trait objects for the same reason and observes that `Op::Type` (`0x03`) carries no nominal
information — a `Counter` and a `Uint64` cell both report `0` — so even the one runtime type
test that exists cannot discriminate. The bounded substitute is a closed sum of stores
(§10.1).

**Unbounded traversal.** No loops. This is the totality invariant, and it is the reason
`List` has `pushFront`/`popFront`/`head` and no `nth(i)`.

Both should be stated as permanent, with these citations, in any eventual CoIP. They are not
"future work."

---

## 12. What changes

### 12.1 Impact VM: nothing

Zero opcodes added, zero semantics changed, no hard fork, no state migration. Every emitted
sequence is one the shipped compiler already emits: `Idx` with a mixed literal/stack path,
`Ins`, `popeq`. This is the property the prior proposal also had and it should be preserved
at all costs — `traits-design-space.md` §5.3 makes the same observation about user-defined
ADTs, and the reason is the same: **the VM has never heard of a ledger ADT.**

### 12.2 Generated JavaScript: nothing structural

`queryLedgerState(circuitContext, partialProofData, program: Op<null>[])` takes the op array
as *data* and copies it verbatim into the public transcript, back-filling only `popeq`
results. It never inspects, hashes, or caches the array. And the emitted arrays are already
not constants — a generated `Map.lookup` interpolates `_descriptor_0.toValue(key_0)` from a
function argument into a `{tag:'value'}` path element. A monomorphized store parameter
produces **byte-identical output to hand-writing the circuit at that path**.

Two upstream points need care, both in the compiler rather than the emitted JS:

- `propagate-ledger-paths.ss:130` resolves `lookup-ledger-binding` from an `eq-hashtable`
  keyed by the ledger field *name symbol*. A store parameter has no such symbol until
  substituted — so monomorphization must run before this pass. It does:
  `expand-modules-and-types` is first in `analysis-passes.ss:75`, `determine-ledger-paths`
  and `propagate-ledger-paths` are at `:86-87`. **The ordering already works.**
- `print-typescript.ss:1544`'s `(format ".asArray()[~d]" path-index)` needs a literal
  integer. Fine under monomorphization; it is one of the reasons not to attempt reading (b).

### 12.3 Compiler

The elaboration is simpler than the frob machinery suggests:

> **`&` is closure conversion for lenses.** The caller's place expression is a closure over
> its keys. A generic parameter specializes the code; lambda-lifting passes the environment
> as ordinary parameters.

Concretely, `transfer(&accounts.lookup(a), &accounts.lookup(b), amt)` becomes
`transfer<accounts.lookup(·), accounts.lookup(·)>(a, b, amt)` — two store arguments and two
ordinary value arguments. No new IR form for "a lens value" is needed anywhere, which is also
why store parameters never surface in the language (§6.5).

**Where the desugaring happens matters, and it is not where an earlier draft put it.** Two
facts settle it:

- The environment mechanism for the *store* half already exists.
  `expand-modules-and-types.ss:1196` resolves an identifier bound to `Info-ledger` into
  expression position as a ledger reference:
  ```scheme
  1195       [(Info-size src^ size) `(quote ,src ,size)]
  1196       [(Info-ledger ledger-field-name) `(ledger-ref ,src ,ledger-field-name)]
  ```
  Ledger declarations bind their names this way at `:827`. So binding a parameter name to a
  ledger field and having the callee body resolve it is existing machinery — **the
  zero-width case (`&alice`, a top-level field) needs almost nothing new**, and `:1195` is
  the precedent that a non-type generic argument can reach expression position at all.
- The *key* half cannot ride in the environment. Substituting the caller's key expression
  into the callee's body would capture caller-local variables, and the instance table cannot
  key on expressions anyway (`targ-info-equal?`, `:131-143`, compares only `sametype?` and
  numeric `=`). So the key must become a **value parameter** — which changes the callee's
  signature, and `process-frob` (`:894-895`) builds the specialized pelt by running the
  transformer over the *raw* pelt, whose parameter list is fixed.

**Therefore the `&T` → (store parameter + key parameter) desugaring belongs in
`frontend-passes`, before `expand-modules-and-types` — not inside it.** There is a direct
precedent one line above where it would go: `expand-patterns`
(`compiler/frontend-passes.ss:52`) already rewrites parameter lists, turning a destructuring
pattern in argument position into a plain parameter plus bindings
(`doc/compact-reference.mdx:985-1005`). `&T` is the same move.

This is better than the monomorphization-time substitution an earlier draft described.
`expand-modules-and-types` then needs only the new generic-parameter kind and its `Info`
variant; from its point of view a circuit with a `&` parameter is an ordinary generic circuit
with one extra value argument, and every pass downstream — `check-sealed-fields` (§6.8),
`propagate-ledger-paths`, the backends — sees nothing unusual at all.

The work, enumerated:

1. **A fourth generic-parameter kind.** `ledger.ss:206-212` maps meta-types to
   `type-valued` / `non-adt-type-valued` / `nat-valued`; add a store-valued kind, and a
   matching `Generic-Value` variant (`langs.ss:698-700` currently admits `nat | type` only).
   Touches `gv-hash` (`expand-modules-and-types.ss:78-81`), `targ-info-hash` (`:123-130`),
   `targ-info-equal?` (`:131-143`), the `Info` datatype (`:163-186`), `add-tvar-rib`
   (`:228-267`), `compatible-type-parameters?` (`:452-472`), `describe-info` (`:584-600`).
   The instance table already hashes `tadt` nodes (`:112-113`) and `Info-size` proves a
   non-type generic argument works end to end, so nothing here is novel — it is nine known
   sites.
2. **`&` as a type former** at kind `Store → Val`, with the index algebra of §6.5, and its
   width computed at instantiation.
3. **Elision** — a new `frontend-passes` pass, `expand-place-params`, sited after
   `expand-patterns` (`frontend-passes.ss:52`), rewriting each `&T` in a signature into a
   fresh store parameter plus a value parameter of type `keys(T)`, and each `&p` at a call
   site into the corresponding pair of arguments. Internal only; no surface syntax for store
   parameters is added (§6.5). This is the pass that does the real work.
4. **Fuse the two halves of a lens.** Today the `tadt` node says *what ops exist* and the
   `public-ledger` node says *where* (`langs.ss:803-804` vs `:888-890`); `f` is a free
   variable of `vm-code` filled at codegen from `path-elt*`
   (`print-typescript.ss:437-441`, `print-zkir.ss:765-767`). A reference needs those two
   facts associated. Under the elaboration above they are associated *at the call site*,
   before either node is built — which is why no new form is required.
5. **The eight satisfied sites** need `&S` to be an ordinary `Val` by the time
   `infer-types` runs. Under this elaboration it already is.
6. **Lift `verify-non-adt-type!` at `infer-types.ss:777-778`** so `&S == &S` type-checks.
   This is small and it is what makes §7 possible.
6b. **A `nav` op class** (§6.8) — returns a place, emits no opcodes, contributes a path
   element. Replaces the hardcoded `Map`/`lookup` assertions at
   `propagate-ledger-paths.ss:159-161`, and is the same change that generalizes store
   nesting (§11.1).
7. **The alias analysis** of §7.4 — a pass over monomorphized bodies.
8. **The depth check** of §8 — a pass after `propagate-ledger-paths`. Independently
   valuable.
9. **`track-witness-data`**: `&`-formation discloses (§9).
10. **`expand-serialize.ss:205/329`**: `&S` is serializable as its key tuple; `S` remains
    not.

Items 1–6 are the feature. Items 7–10 are hygiene, and 8 should ship first regardless
(§8.3).

The two FIXMEs at `print-typescript.ss:281` and `:2571` need no work, because neither is
reachable — the store part is gone before printing. Nor does `check-sealed-fields.ss`, for
the reason given in §6.8: the store is spliced at `expand-modules-and-types` (pass 1) and
sealing runs at pass 7, so it sees an ordinary accessor chain rooted at a real field name.

### 12.4 Restrictions kept, with reasons

- **`&` may not appear in an exported circuit's signature.** There is nothing at the
  TypeScript boundary to name the store, and the store has no wire representation. This is
  the same reason `expand-serialize.ss:205` refuses ADTs, and it should reuse that
  diagnostic.
- **`&` may not be passed to a witness.** Same reason. (The prior proposal explicitly wants
  witnesses to take ADTs; this document rules it out.)
- **`&` may not appear in a `contract` circuit's signature** — sites 6, 7, 8 in §1.2. A
  cross-contract call crosses an existential boundary (`coip-0002.md`;
  `coherent-type-landscape.md` §5), so there is no call site at which to monomorphize the
  callee's store parameter. `dynamic-deployment-design.md` §6.1 makes the corresponding
  point for `deploy`.

---

## 13. Prerequisites, and what stands alone

| Item | Needs `Val`/`Store` kind reform? | Needs store traits? | Needs real sums? |
|---|---|---|---|
| Depth check (§8.3) | no | no | no |
| Nesting beyond `Map` (§11.1) | helpful, not required | no | no |
| `&` for top-level fields (zero-width) | no — a fourth meta-kind suffices | no | no |
| `&` with map keys (§6) | no | no | no |
| User-written `store` declarations (§6.4) | yes | no | no |
| Store tuples with `\| Null` variants | yes | no | **yes** |
| Abstracting over store *type* (`&S` for bound `S`) | yes | **yes** | no |
| Closed sums of stores (§10.1) | yes | no | **yes** |

**The core of the proposal requires neither the kind reform nor store traits.** It requires
one new generic-parameter meta-kind alongside the three at `ledger.ss:206-212` — which is,
as `coherent-type-landscape.md` §1.2 notes, "already a stunted version" of the kind system
— and that meta-kind is internal, never written by a user (§6.5). Doing the full reform
first is better; it is not a gate.

Note what moved between drafts: an earlier version listed store traits as a prerequisite,
because it wrote store parameters into the surface language as `<#S: Place<V>>`. Once `&T`
applies directly to the store types users already write, that dependency disappears.

A sensible order: (1) the depth check, alone, now — standalone, closes a silent miscompile,
and is a prerequisite for anything that composes paths. (2) **`&`**, which already delivers
`transfer(from, to, amount)` and needs no new nesting, no new op class, and no change to
`propagate-ledger-paths`'s shape assumptions. (3) the `nav` op class and `List<S>`, costed in
`store-nesting-impl-plan.md` — larger than an earlier draft of §11.1 claimed, and easier
after `&` has established the vocabulary, since `nav` *is* "an op that returns a reference."
(4) the kind reform and user-written `store` declarations. (5) store traits, which add
abstraction over store *type* on top of `&`'s abstraction over *place*. (6) sums, which
unlock `| Null` reps and closed store sums.

Steps 2 and 3 were the other way round in an earlier draft, on the strength of the
"one token" mis-estimate that `store-nesting-impl-plan.md` §0 corrects.

---

## 14. Open questions

1. **Spelling.** `&S` vs `Ref<S>` (§6.5). `&` reads better and imports the wrong intuition;
   `Ref<S>` is duller and safer.
1b. **The store-operation keyword** (§6.4). `op` matches the compiler's internal vocabulary;
   `query` matches the 2022 documents and `queryLedgerState` but implies read-only. Either
   is better than `circuit`, which hides the stage distinction that is the whole point.
1c. **Does the bounded Merkle tree need a user-facing primitive name?** §6.3 leaves it
   nameless on the grounds that `MerkleTree<h,V>` is a library store tuple over it and is
   the only form anyone writes. That works until someone wants a different merkle-flavoured
   store, at which point they need to name the raw shape — and the obvious name is taken.
2. **Should `&` be required at the call site, or inferred?** Requiring it preserves the
   prior proposal's disambiguation property cheaply. Inferring it is friendlier and
   reintroduces the `Cell`-read ambiguity the prior proposal had to fix language-wide.
3. **Is the alias analysis default-deny too strict?** It will fire on correct code —
   `from.decrement(n); to.increment(n)` is fine when aliased. Refining "read after write" to
   "read after write that changes the answer" is a dataflow question I have not worked out.
4. **Does the §3.3 replay hazard apply to existing contracts?** Any contract that branches on
   state to decide whether to delete has the same shape. This should be checked
   independently of this feature.
5. **`&Tree<h>` — should Merkle leaves be referenceable?** The index is `Uint<h>` and the
   arithmetic works, but `Ins` into a BMT is `try_update_hash(...).rehash()`
   (`onchain-vm/src/vm.rs:1002-1046`) and the cost profile is different enough to want
   separate thought.
6. **Depth indices: inferred-only, or writable?** §8.2 recommends inferred with optional
   bounds. If they become writable they are a second `Nat`-kinded index and interact with
   whatever `coherent-type-landscape.md` reform item 6 settles.

---

## 15. References

**Prior design work.** `compact/proposals/coherent-type-landscape.md` (totality invariant
L15-18; kinds L63-69; `Val`/`Store` payoff L102-105; "Don't make them first class" L262-286;
observation-is-disclosure L288-335; depth-indexing L376-407; five primitive store formers
L409-423; store traits L483-528; existentials L571-592; reform list L596-612).
`compact/proposals/traits-design-space.md` (method-is-a-tuple L221-246; ledger ADTs as a
closed trait system L295-312; what the target forces L316-366; VM needs no changes L400-417).
`compact/proposals/dynamic-deployment-design.md` (compile-time-name-monomorphized L351-363;
provenance is data L793-810). `midnight-architecture/proposals/XXXX-first-class-adts.md`
@`kmillikin/first-class-adts` (commit `63f8eda`).
`midnight-architecture/proposals/0004-micro-adt-language.md` L152-155, which is the earliest
statement that `ledger.field.op(args)` is sugar for `ledger$op("field", args)` — the lens
reading is not a new imposition, it is the original design recovered.

**Compiler.** `infer-types.ss` :305-320, :775-778, :790-833, :994-997, :1004-1006, :1026,
:1033, :1036, :1046, :1053-1058, :1064, :1070, :1179-1186, :1226-1230, :1974.
`expand-modules-and-types.ss` :71-147, :228-267, :256-264, :418-432, :467-470, :584-600,
:685-689, :921-978, :999-1012, :1158-1171. `determine-ledger-paths.ss` :24-48.
`propagate-ledger-paths.ss` :18, :35-52, :127-172. `expand-serialize.ss` :204-205, :328-329.
`langs.ss` :698-700, :803-804, :850-855, :876-890. `ledger.ss` :148, :206-212, :299-307.
`midnight-ledger.ss` :134-139, :544-585, :590-606, :699, :741-747, :798-884, :971.
`vm.ss` :160-161. `print-typescript.ss` :277-291, :431-441, :507-511, :1540-1551, :2570-2574,
:3041-3042. `unroll-loops.ss` :104-105. `check-sealed-fields.ss` :58-61.
`analysis-passes.ss` :75-92. `circuit-passes.ss` :62-77.

**Ledger.** `onchain-vm/src/ops.rs` :36-45, :145-153, :197-211, :225-238, :239-258, :460-527.
`onchain-vm/src/vm.rs` :34-107, :178-236, :311-330, :400-441, :625-638, :794-816, :811-931,
:900-931, :933-1053, :1056-1075. `onchain-vm/src/result_mode.rs` :44-96.
`onchain-vm/src/error.rs` :41-44. `onchain-vm/src/state_value_ext.rs` :26-31.
`onchain-vm/src/cost_model.rs` :217-251. `onchain-state/src/state.rs` :69-96, :759-780,
:817-848. `onchain-runtime/src/context.rs` :309-318, :640-656, :699-705, :776-841, :853-893,
:906-913, :923-965, :981-1001. `onchain-runtime/vendored/program_fragments.rs` :47-51,
:70-102, :147, :184-192, :300, :601-641. `ledger/src/semantics.rs` :1438-1461.
`ledger/src/structure.rs` :497-504, :1270-1283, :2706-2716. `ledger/src/verify.rs` :384-399,
:1886-1903, :1944-2014. `ledger/src/construct.rs` :764-796, :863.
`spec/impact-opcodes.md` :70-79, :104-107, :317-322. `spec/contracts.md` :132-139.
`spec/cost-model.md` :319-357. `spec/onchain-runtime.md`.

**External.** The reference-as-index reading is the database distinction between a surrogate
key and a natural key; the case against surrogate keys here is that a surrogate must be
*read* to be used, and reads are the scarce resource. The elision rule in §6.5 is Rust RFC
141's shape applied to stores rather than lifetimes. The argument in §7.3 that an exact
runtime check beats a conservative static one is the same trade `RefCell` makes, with the
difference that here the check costs two constraints rather than a word of state and a
branch.
