# A coherent type landscape for Compact

*Where we'd want to end up, ignoring how to get there. Companion to
`traits-design-space.md`.*

---

## 0. One organizing principle

You gave me the principle yourself: **a surface language for Impact — nothing that
requires a backward jump.** I want to state it more precisely, because in that sharper
form it does almost all of the design work, and every construction in the landscape gets
its place by reference to it.

> **Totality invariant.** Every type has a size that is a closed term in the size algebra
> at the point of use, and every elimination is a fold over a finite index. Therefore
> every program unrolls to a straight-line instruction sequence whose length is a closed
> term.

The reason to elevate this above "no loops" is that the *same* invariant is simultaneously
responsible for three things that currently look like three separate engineering
constraints:

1. **A finite proving circuit exists.** (The reference already says this, about `for`:
   *"In Compact, in contrast to most languages, the number of iterations can always be
   determined at compile time... motivated by the need for the compiler to generate finite
   proving circuits."*)
2. **Declared gas is meaningful.** `transcript.gas` is both the budget and the claim; it
   can only be declared up front if the instruction count is fixed up front.
3. **The opcode stream is a valid ZK public input.** `verify.rs:1946-1990` field-reprs
   every opcode into the proof. A program whose shape varied at runtime would be one proof
   covering many programs, which the binding scheme forbids.

They are one property seen from three sides. Naming it once gives you an **admissibility
criterion** to test every proposed feature against:

> A feature is admissible iff it preserves "size and control shape are closed terms at the
> point of use."

Static trait resolution: admissible. Trait objects: not. Recursive `Val` types: not.
Recursive `Store` types: *admissible under a side condition*, and working out what that
condition is turns out to explain a lot (§3.4).

Note also the pleasing asymmetry between your two backends, which is where §1 comes from:

|  | Data | Code |
|---|---|---|
| **ZK circuit** | bounded (flattened to a fixed vector of field elements) | bounded, and *fully branchless* — `reduce-to-circuit` predicates everything into guarded `(= test lhs rhs)` |
| **Impact VM** | **unbounded** (a `Map` has no size limit) | bounded, straight-line, forward-only branches |

Compact is a surface for both. The intersection is the totality invariant. The
*difference* — bounded data vs unbounded data — is the kind system.

---

## 1. Two universes, one kind system

This is the structural reform I'd make first, because it converts about a dozen ad-hoc
restrictions into typing rules and it's the precondition for everything else.

### 1.1 The kinds

| Kind | Meaning | Inhabitants |
|---|---|---|
| `Nat` | index / size | literals, `#n` parameters |
| `Val` | has a statically-known FAB alignment and field-element width; is a **value** | `Boolean`, `Uint<0..n>`, `Field`, `Secp256k1Base`, points, `Bytes<n>`, `Vector<n,T>`, tuples, structs, sums |
| `Store` | lives in the state tree; extent may be unbounded; is a **place** | `Cell<V>`, `Counter`, `Map<K,S>`, `Set<V>`, `List<V>`, `MerkleTree<h,V>` |
| `Extern` | no on-chain representation at all; exists only at the TypeScript boundary | `Opaque<"string">`, `Opaque<"Uint8Array">` |
| `Iface` | an existential interface over an unknown deployed implementation | `contract C { ... }` |

`Val` is where all the type-algebra work happens. `Store` is where all the effect work
happens. Keeping them apart is what lets each be clean.

### 1.2 The ad-hoc restrictions become kinding rules

Today `infer-types.ss:305-320` defines a predicate `Non-ADT-Type` and then applies it by
hand at eight sites. Each of those is a kinding rule in disguise:

| Today (ad-hoc rejection) | Tomorrow (kinding rule) |
|---|---|
| ADT not allowed as circuit argument (`:1033`) or return (`:1036`) | circuit args/returns : `Val` or `Extern` |
| ADT not allowed as vector element (`:1046`), tuple element (`:1064`), struct field (`:1070`) | `Val` formers take `Val` arguments |
| `Cell<T>` requires an ordinary type | `Cell : Val → Store` |
| `Map`'s `value_type` is `ADT/Type`; everything else is `Type` | `Map : Val → Store → Store` |
| "ADT nesting is permitted only within Map ADTs" (`propagate-ledger-paths.ss:44`) | falls out: `Map` is the only former with a `Store` argument (today) |
| implicit `Cell` wrapping of a plain ledger field type (`expand-modules-and-types.ss:1158`) | a coercion `Val → Store` at ledger-field position |
| Merkle-tree elements rejected if they contain `Opaque` (`:807-813`) | `MerkleTree : Nat → Val → Store` where `Val` excludes `Extern` |
| "cannot export alias for ADT types from the top level" (`:1026`) | exports : `Val` |
| "type ~a (ADT) is not serializable" (`expand-serialize.ss:205`) | `serialize : Val → Bytes<n>` |
| `default<T>` undefined for `Kernel` (`:1229`) | `default` is a `Val` operation |

The 3-point meta-kind system in `ledger.ss:206-212` (`ADT/Type` → `type-valued`,
`Type` → `non-adt-type-valued`, `Nat` → `nat-valued`) is already a stunted version of this.
It's the right idea, discovered under pressure, and never generalized.

`Extern` deserves its own kind rather than being a `Val` with holes: an `Opaque` value has
no alignment, cannot be hashed, cannot be a map key, cannot go in a Merkle tree, cannot be
serialized. Every one of those is currently a separate rejection.

### 1.3 The payoff sentence

> **`Val` types are things whose size is static. `Store` types are things whose *access
> cost* is static but whose extent is not.** That one distinction generates the whole
> boundary.

---

## 2. The `Val` universe: what's actually missing is sums

### 2.1 The hole, stated precisely

Compact's `Val` algebra today is **products and nothing else**. I checked the lowering:
`flatten-datatypes.ss:82-124` builds an alignment from a type, and the entire atom
vocabulary is

```scheme
(Alignment (alignment)
  (+ (acompress) (abytes nat) (afield) (aadt) (anative zkir-type)))
```

with `ttuple` and `tstruct` both lowering to `(fold-right f a* type*)` — **concatenation**.
There is no sum, no discriminant, no branch in the alignment language.

Meanwhile the runtime encoding **already has sums**. `base-crypto/src/fab/encoding.rs:265-277`:

```rust
pub enum AlignmentSegment {
    Atom(AlignmentAtom),
    /// A disjoint union of possible alignments, with an implicit domain
    /// separator for the variant used.
    Option(Vec<Alignment>),
}
```

and `transient-crypto/src/fab.rs:322-329` pads the chosen branch to `max(field_len)`.
**Compact cannot emit this.** The capability is sitting there unused.

### 2.2 What that costs you, concretely

`Either<A,B>` in `standard-library.compact:32` is a product:

```compact
export struct Either<A, B> { is_left: Boolean; left: A; right: B; }
export circuit left<A, B>(value: A): Either<A, B> {
  return Either<A, B>{ is_left: true, left: value, right: default<B> };
}
```

So `Either<A,B>` costs `1 + |A| + |B|` field elements, always, and `left(x)` writes a
**garbage `default<B>` into the proof and into the transcript**. A real sum costs
`1 + max(|A|,|B|)`. For `Either<ZswapCoinPublicKey, ContractAddress>` — two 32-byte
structs — that's a 33% saving; for a five-variant enum with 10-element payloads it's 5×.
The same applies to `Maybe<T>`, which appears in every `sendShielded` result.

And it's not only cost. The absence of sums shows up as bugs-in-waiting: because `Either`
is untagged-in-practice, the shielded and unshielded halves of the standard library chose
*opposite polarities* — `Either<ZswapCoinPublicKey, ContractAddress>` vs
`Either<ContractAddress, UserAddress>` — so `recipient.is_left` means the *opposite thing*
in the two halves of one file, and `left<Bytes<32>, Bytes<32>>(color)` (a "sum" with both
arms identical) appears nine times.

### 2.3 The runtime is already building real sums by hand

`List.head` returns `Maybe<value_type>`, and `midnight-ledger.ss:843-878` builds it *as a
genuine tagged union in the VM*:

```scheme
(type) (push cell(align 1 1)) (eq) (branch [skip 4])
  (push [value (state-value 'cell (align 1 1))])     ; tag = 1 (Some)
  (swap [n 0])
  (concat [n (+ 2 (rt-max-sizeof value_type))])      ; tag ++ payload, sized max
  (jmp [skip 2])
(pop)
(push [value (state-value 'cell (rt-aligned-concat (align 0 1) (rt-null value_type)))])
```

That is `if tail-is-null then None else Some(head)`, with a one-byte discriminant and a
`max`-sized payload — a textbook sum. It is then `popeq`'d into a Compact `Maybe<T>` that
is a *product*. The impedance mismatch is why there's an unresolved reviewer comment two
lines above it (`"@tkerber - I don't understand this branching…"`).

**Give the surface language real sums and that opcode sequence becomes something the
compiler derives rather than something a human hand-writes and nobody can review.**

### 2.4 The unification: one nominal declaration form

You said `new type` should end up resembling Rust's enums. I'd go further — **`struct`,
`enum`, and `new type` are the same construct at three arities**, and saying so removes
three special cases:

| Today | In the unified form |
|---|---|
| `struct S { x: A, y: B }` | a **1-variant** sum whose payload is a labeled product |
| `enum E { A, B, C }` | an **n-variant** sum whose payloads are all `[]` |
| `new type Money = Uint<64>` | a **1-variant** sum with one unlabeled field |
| *(missing)* `Maybe<T>` | an **n-variant** sum with payloads |

Syntax is not the point, but for concreteness:

```compact
type Maybe<T>  = None | Some(T);
type Either<A,B> = Left(A) | Right(B);
type Point     = { x: Field, y: Field };     // sugar for a 1-variant sum
type Money     = Money(Uint<64>);            // today's `new type`
type Color     = Red | Green | Blue;         // today's `enum`
```

Three consequences worth having:

- **`new type` becomes a real instance target.** Today, `Money + Money : Money` is
  implemented by an ad-hoc rule in `arithmetic-binop` (`infer-types.ss:732-750`) that
  silently inserts a *narrowing* `downcast-unsigned` which can **fail at runtime**. That
  rule is a hand-rolled `impl Add for Money` that you can neither see nor override. With
  nominal 1-variant sums and traits, it becomes an ordinary user-visible instance, and the
  wrapping/unwrapping noise (`as Base ... as Alias`, which `examples/types/examples.compact`
  is 586 lines of) goes away.
- **Enum↔`Field` casts** (`cast-to-enum`/`cast-from-enum`) become a derived `discriminant`
  operation on any sum, rather than a cast between unrelated types.
- **Pattern matching** becomes the eliminator, and matching is where the `is_left`/`left`/
  `right` idiom and its polarity hazard die.

**Honest cost accounting.** Sums make *data* cheaper (`max` instead of `sum`) but not
*code*: a circuit-stage `match` is predicated, so it pays for every arm's constraints, and
a VM-stage `match` pays every arm's opcodes plus the branch skip (`branch n` is priced
`branch_constant + branch_coeff_arg · n` — **skipping costs in proportion to how far you
skip**). Versus today, that's strictly better: today you pay all arms in code *and* all
arms in data.

### 2.5 The numeric tower is already a refinement lattice — finish it

`Uint<0..n>` is `{x : ℕ | x < n}`, with subtyping by `n1 ≤ n2` and **interval arithmetic in
the type**: `+` gives `n1+n2`, `*` gives `n1·n2`, and exceeding `max-unsigned` is an error.
That's a small abstract interpretation embedded in the type system and it's a genuinely
nice piece of design that nobody names.

`Field`, `Secp256k1Base`, `Secp256k1Scalar`, `JubjubScalar` are `{x : ℕ | x < p}` for four
different primes (`field.ss:36-50`) — the *same* refinement shape, with **modular**
arithmetic instead of checked arithmetic.

> So `Uint<0..n>` and `Field` differ by their **instance**, not by their kind. Both are
> ℕ-refinements; one has checked-overflow ring structure, the other has modular ring
> structure.

That is the theoretical account of why the arithmetic dispatch in
`infer-types.ss:666-693` is a hand-written two-level `nanopass-case` cross-product, and why
`(field-scalar (curve-jubjub))` is simply *absent from the outer dispatch* — the reason
`JubjubScalar` has no arithmetic is a missing table row, not a design decision. A `Ring`
trait with an associated `MODULUS` makes the table a consequence of the instances.

One incoherence to fix while you're there: the reference claims `Uint<0..n> <: Field`
(`:888-889`) but `subtype?` does not implement it — it's patched up ad hoc inside the
operators and the cast table. Pick one. My preference: **no implicit subtyping between
refinement families with different ring structure**; make it a coercion with a name, since
`Uint → Field` is injective and `Field → Uint` isn't.

---

## 3. The `Store` universe: what a ledger ADT actually *is*

Here's the part I owed you from last time.

### 3.1 A `Store` self is a place, not a value

The single sentence:

> A `Val` trait method is a **function** `A → B`.
> A `Store` trait method is a **lens-indexed operation**: given a compile-time path
> focused on a value of this store type, it produces a straight-line opcode sequence.

This is exactly what `f` and `f-cached` are in the ADT DSL (`midnight-ledger.ss:94-157`
documents them as "the path to the field being operated on"). Every ADT operation is
already a function *from a path* to opcodes. There are no first-class ADT values, and the
TypeScript backend has two explicit FIXMEs anticipating that they might one day exist
(`print-typescript.ss:281-284`, `:2571-2574`).

Don't make them first class. The right move is the opposite: **make "place" a kind**, so
that "you can't put a `Map` in a struct" stops being a rejection and starts being a
kinding failure. Rust needs `&mut T` for this because it has real references; Compact
doesn't have or want runtime references, but it has something better for a total language —
*compile-time* paths. A `Store` self is a static lens.

Nesting is then lens composition: `m.lookup(k).increment(1)` is `compose(at(k), increment)`,
and `Counter.increment`'s `(ins [cached #t] [n (length f)])` unwinds both levels in one
instruction because the composed path is known statically. Today this is enforced by
`(assert (eq? adt-name 'Map))` and `(assert (and (eq? ledger-op 'lookup) ...))` in
`propagate-ledger-paths.ss:159-165`. As lens composition it's just… composition.

### 3.2 Observation is disclosure — and it's the same thing as replay-safety

I verified this and it's exact. In `midnight-ledger.ss`:

- **All 23 `read`-class operations end in `popeq`.**
- **No `update`, `write`, or `remove` operation contains a `popeq`.**

`popeq` is the *only* way a value moves from the state tree into the circuit. And its
result is simultaneously:

- a **ZK public input** (`print-zkir.ss:494-509` emits `public_input` gates for it),
- the thing the **replay checker compares** (`ResultModeVerify::process_read` — whole
  `AlignedValue` equality, value *and* alignment),
- the **read-set** of the transaction.

So three mechanisms that look independent in the codebase — the `op-class` taxonomy, the
disclosure analysis, and rehearse/replay determinism — are one distinction:

> **The set of `popeq`s is the read-set, is the public-input set, is the disclosure set.
> A transcript replays iff every observation it made still holds. "What did this
> transaction read" and "what did this transaction reveal" are the same question.**

That belongs in the type system, and it has a direct practical consequence people get
wrong today. Consider:

```
increment()               →  idx; addi 1; ins            — discloses nothing
read(); +1; write()       →  idx; popeq; …; push; ins    — discloses the counter's value
```

Semantically different, not just cheaper. So **the store algebra is not `(read, write)`.**
It is:

| Primitive | Opcode | Observes? | Mutates? |
|---|---|---|---|
| descend along a lens | `idx` | no | no |
| **observe** a cell | `popeq` | **yes** | no |
| replace at a place | `push` + `ins` | no | **yes** |
| in-place immediate arith | `addi` / `subi` | no | **yes** |
| delete a key | `rem` | no | **yes** |
| VM-stage computation | `eq lt and or neg add sub concat size member type root` | no | no |
| VM-stage forward branch | `branch` / `jmp` | no | no |

Note the middle block: **you can compute on state without observing it.** `Counter.lessThan`
does `idx; push threshold; lt; popeq` — the comparison happens *in the VM*, and only the
resulting `Boolean` becomes public. Writing it as "observe the counter, then compare"
would disclose the counter. That distinction has to be visible in the surface language or
users will leak by accident.

### 3.3 A two-stage surface language

The clean way to expose this is **explicit staging**: a VM stage (public, straight-line,
over `StateValue`s) and a circuit stage, with one boundary operator.

```compact
store Counter {
  rep Cell<Uint<64>>  = 0;                       // representation + initial value

  circuit read(): Uint<64>                { return observe(rep); }
  circuit lessThan(t: Uint<64>): Boolean  { return observe(rep < t); }   // only the bool is public
  circuit increment(n: Uint<16>)          { rep := rep + n; }            // observes nothing
  circuit decrement(n: Uint<16>)          { rep := rep - n; }
  circuit reset()                         { rep := default; }
}
```

`rep` inside a VM-stage expression denotes *the contents at that place*; `observe(-)` is
the stage boundary (`popeq`). Read the design rule off the syntax:

> **Whatever is inside `observe(...)` is what becomes public, enters the read-set, and must
> still hold at replay.** Everything else is a blind write.

Two things fall out for free:

- **The op-class is derived, not declared.** An operation *observes* iff its body contains
  `observe`; it *mutates* iff its body contains `:=`. Which reveals that today's four
  exclusive classes are really **two orthogonal bits**. `Kernel.mintShielded` is instructive:
  it does `member`/`branch`/`idx`/`add`/`ins` — it *computes on* state and mutates it, but
  never `popeq`s, so it's `update`. Under two bits it's `(observes: no, mutates: yes)`,
  and sealed-field analysis wants only the `mutates` bit, not the conflated class.
- **Disclosure defaults are forced, not lazy.** Every argument to a store operation ends
  up inlined into the opcode stream (`push [value (state-value 'cell key)]`,
  `addi [immediate …]`, path keys), and the opcode stream is field-repr'd into the public
  inputs. So *every store-operation argument is necessarily public.* The `""`-means-discloses
  default in `ledger.ss:148` isn't an oversight; it's the only sound default. Under the kind
  system this becomes a typing rule — store-operation arguments have public label — rather
  than a per-argument annotation that someone has to remember.

### 3.4 Recursive types: forbidden at `Val`, permitted at `Store` under a bound

This is my favourite consequence, because it retroactively justifies a split you already
made for other reasons.

A recursive type has no statically-known size, so **μ is inadmissible at kind `Val`** — it
violates the totality invariant directly. That's why `struct` can't be recursive
(`with-type-cycle-check`) and why there's no `Val`-level list.

But at kind `Store`, size is *not* required to be static. `List` is genuinely recursive:

```
List<V> = Slots<3>{ head: Cell<V> | Null,  tail: List<V> | Null,  len: Cell<Uint<64>> }
```

and the VM handles it because you only ever touch a bounded prefix. The admissibility side
condition is precise:

> **μ is admissible at `Store` provided every operation's path depth is a closed term.**

That is *exactly* why `List` has `pushFront`, `popFront`, `head`, `length` (all depth ≤ 2,
with `length` stored rather than computed) and **no `nth(i)`** for dynamic `i`. It's why a
self-balancing tree with rebalancing is not writable. Today that's a wall you hit by
discovering that you can't write the opcodes; under this rule the type system tells you at
declaration time.

The other resource bounds want the same treatment. `Array` length ≤ 16, `Idx` path depth
≤ 16, `Ins` levels ≤ 15, `Dup`/`Swap` reach ≤ 15 — and there's already a comment at
`midnight-ledger.ss:577` warning that the coin-writing ops break when the path exceeds
length 5. Those budgets **compose** when stores nest, and nothing tracks them. Make
`Store` types **depth-indexed** and `Map<K, Map<K2, Counter>>` gets checked where it's
declared instead of failing during expansion.

### 3.5 What the primitives should be

The five `StateValue` shapes, presented as the primitive store formers:

```
Cell<V : Val>            -- one AlignedValue,  ≤ 32 KiB
Slots<S₀ … Sₙ>           -- fixed heterogeneous array, n ≤ 16
Table<K : Val, S : Store>-- unbounded map; absent key ⇒ Null
Tree<h>                  -- bounded Merkle tree of hashes, 0 < h ≤ 32
Null                     -- the unit store / "absent"
```

`Cell`, `Counter`, `Set`, `Map`, `List`, `MerkleTree`, `HistoricMerkleTree` are then all
*library* definitions over these, which is already true — the VM has never heard of any of
them, and `List` and `HistoricMerkleTree` are already pure user-space constructions.

---

## 4. Traits over values, traits over places

Now both faces, side by side. Syntax illustrative.

### 4.1 A `Val` trait — self is a value, methods are circuits

```compact
trait Ring {                              // kind: Val -> Constraint
  const ZERO: Self;
  const ONE: Self;
  pure circuit add(a: Self, b: Self): Self;
  pure circuit neg(a: Self): Self;
  pure circuit mul(a: Self, b: Self): Self;
  pure circuit sub(a: Self, b: Self): Self { return add(a, neg(b)); }   // default
}

trait PrimeField: Ring {
  const MODULUS: Uint;
  const BYTES: Nat;                       // associated size
  pure circuit inv(a: Self): Self;
  pure circuit toBytes(a: Self): Bytes<BYTES>;
}

trait Group {                             // kind: Val -> Constraint
  type Scalar: PrimeField;                // associated type — the functional dependency
  const GENERATOR: Self;
  const IDENTITY: Self;
  pure circuit add(a: Self, b: Self): Self;
  pure circuit neg(a: Self): Self;
  pure circuit mul(p: Self, s: Scalar): Self;
  pure circuit mulGenerator(s: Scalar): Self { return mul(GENERATOR, s); }
  pure circuit x(p: Self): Scalar::Base;
  pure circuit y(p: Self): Scalar::Base;
}

impl Group for JubjubPoint { type Scalar = JubjubScalar;  ... }
impl Group for Secp256k1Point { type Scalar = Secp256k1Scalar; ... }
```

and one Schnorr instead of two signature schemes that share zero code:

```compact
export circuit schnorrVerify<P: Group, #N>(
  msg: Vector<N, Field>, sig: Signature<P>, pk: P
): Boolean {
  const c = hashToScalar<P>(sig.announcement, pk, msg);
  return mulGenerator<P>(sig.response) == add(sig.announcement, mul(pk, c));
}
```

Note what's load-bearing and it isn't the operator: it's `type Scalar` (so `mul(pk, c)`
knows `c` must be *this curve's* scalar) and `const GENERATOR` / `const MODULUS` (so the
four moduli stop living as Scheme constants in `field.ss` duplicated into
`runtime/src/constants.ts`). And it's `const GENERATOR` that forces type-attached rather
than value-attached dispatch — there's no receiver to dispatch on.

### 4.2 A `Store` trait — self is a place, methods are path-indexed operations

```compact
store trait Collection {                  // kind: Store -> Constraint
  type Elem: Val;
  circuit isEmpty(): Boolean;
  circuit size(): Uint<64>;
  circuit insert(x: Elem);
  circuit clear();
}
```

The signatures look the same. The *meaning* differs in three ways, all of which are
consequences of §3:

1. **Self is a lens**, not a value. Instantiating `Collection` at a nested position
   composes paths.
2. **Every argument is public**, forced by §3.3 — no annotation, it's a kinding
   consequence.
3. **Each method carries a derived effect** `(observes?, mutates?)`, computed from whether
   its body uses `observe` / `:=`.

And the ADTs written against it:

```compact
store Set<V: Val> : Collection {
  type Elem = V;
  rep Table<V, Null> = {};

  circuit isEmpty(): Boolean       { return observe(rep.count() == 0); }
  circuit size(): Uint<64>         { return observe(rep.count()); }
  circuit member(x: V): Boolean    { return observe(rep.has(x)); }
  circuit insert(x: V)             { rep[x] := Null; }
  circuit remove(x: V)             { drop rep[x]; }
  circuit clear()                  { rep := {}; }
}

store List<V: Val> {
  rep Slots<Cell<V> | Null, List<V> | Null, Cell<Uint<64>>> = (Null, Null, 0);

  circuit isEmpty(): Boolean  { return observe(rep.1 is Null); }
  circuit length(): Uint<64>  { return observe(rep.2); }
  circuit head(): Maybe<V>    { return observe(if rep.1 is Null { None } else { Some(rep.0) }); }
  circuit popFront()          { rep := rep.1; }
  circuit pushFront(v: V)     { rep := (v, rep, rep.2 + 1); }
}
```

That `head` is worth staring at. With **real sums** (§2) and **VM-stage `if`** (§3.3), it
compiles to essentially the hand-written opcode sequence in `midnight-ledger.ss:843-878` —
`type; push tag; eq; branch; push tag; swap; concat max-sized; jmp; pop; push` — because
that sequence *is* "build a tagged union by branching on the shape." The design isn't
inventing a lowering; it's recovering one that a human already wrote and nobody could
review.

### 4.3 The derived-store case: where the ~200 duplicated lines go

`HistoricMerkleTree` is `MerkleTree` with a root-history append pasted after five of its
six mutating operations. As a store combinator:

```compact
store WithHistory<S: MerkleLike> {
  rep Slots<S, Table<Digest, Null>> = (default, {});

  circuit insert(x: S::Elem)        { rep.0.insert(x); rep.1[rep.0.root()] := Null; }
  circuit insertHash(h: Digest)     { rep.0.insertHash(h); rep.1[rep.0.root()] := Null; }
  circuit checkRoot(r: Digest): Boolean { return observe(rep.1.has(r)); }
  circuit resetHistory()            { rep.1 := {}; }
}
```

Note `checkRoot` *changes meaning* between the two: `MerkleTree.checkRoot` is `eq` against
the current root; `WithHistory.checkRoot` is `member` in the history map. That's an
override, and it's the reason this is a trait/impl relationship rather than a macro.

Also note `resetToDefault` — currently hand-written **seven times** — becomes derivable
from the `rep`'s initial value, and `isEmpty`/`size` become default methods.

### 4.4 So: are they the same abstraction?

Same *syntax*, same resolution discipline, different *kind of self* — value vs place — and
therefore different method shape. I'd unify the surface and keep the kinds honest:
`trait` quantifies over `Val`, `store trait` over `Store`. The elaboration is shared
(§6 of the previous doc: traits as sugar over modules, dictionaries erased by
monomorphization); the typing rules are not.

---

## 5. Existentials: what `contract` types are

The last piece of the landscape, and it clicks into place cleanly:

> **A trait is a bounded universal (∀). A `contract` type is an existential (∃).**

`contract C { circuit f(A): B }` as a type means "*some* deployed contract that has an
`f : A → B`." That explains, in one stroke, every otherwise-odd property it has:

- **Structural satisfaction** (the reference says so explicitly) — existential packing
  doesn't need names.
- **Width subtyping**, more circuits ⇒ subtype — standard for records/existentials.
- **You cannot create one in Compact** — packing an existential requires a concrete
  implementation; Compact contracts *are* the implementations, packed at deploy time and
  handed in from TypeScript.
- **It's the only dynamic thing in the language** — an existential can only be eliminated
  by *using* the interface, never by inspecting it. Which is exactly the discipline the ZK
  binding requires of a cross-contract call.

So `contract` is not a rival design for traits and shouldn't be extended into one; it's the
dual, and you need both. Worth saying explicitly in CoIP-2's neighbourhood, since the two
will otherwise look like duplicated machinery.

---

## 6. The reform list

Ordered by coherence bought per unit of disruption.

| # | Change | Buys |
|---|---|---|
| 1 | **Kinds: `Nat`, `Val`, `Store`, `Extern`, `Iface`** | ~12 ad-hoc restrictions become typing rules; the ledger/circuit boundary gets a reason |
| 2 | **Real sum types**, unifying `struct` / `enum` / `new type` | `max` instead of `sum` sizing; no garbage `default<B>` in proofs; pattern matching; `new type` becomes an instance target; enum casts become `discriminant` |
| 3 | **Bounded quantification + associated types/consts/sizes** | one Schnorr; `neg`/`inv` for all four field types; `MODULUS` stops living in three languages; a third curve stops meaning ~15 hand-edited dispatches |
| 4 | **`observe` as the explicit stage boundary**; effect derived as `(observes?, mutates?)` | read-set = disclosure-set = public-input-set becomes checkable; `increment` vs `read;+1;write` becomes a visible distinction; disclosure default becomes a kinding rule |
| 5 | **`Store` traits + user-definable stores over the 5 primitives** | user-defined ledger ADTs, with *zero* VM/ledger/cost-model/replay changes; ~200 duplicated lines in `midnight-ledger.ss` become a `WithHistory` combinator |
| 6 | **Depth-indexed stores** | the nibble budgets (`Array ≤ 16`, path ≤ 16, `ins ≤ 15`, `dup ≤ 15`) get checked at declaration instead of at expansion |
| 7 | **μ admissible at `Store` under a static-depth side condition** | explains and enforces "`List` has no `nth`" as a rule rather than a wall |
| 8 | Fix `Uint <: Field` doc/impl split; make `tundeclared`/`tunknown` inference metavariables, not types | removes the two remaining places where the subtype relation isn't the subtype relation |

Items 1, 2, and 4 are the ones that make the landscape *coherent*. Items 3 and 5 are what
you actually asked for. 6–8 are hygiene that gets cheap once 1 exists.

---

## 7. Open questions I'd want your answer on

1. **"No backward jump" — do you also mean no forward branch?** Impact *has* forward
   branches and `List.head` uses one; the ZK side has none at all (everything is
   predicated). If the surface language allows VM-stage `if`, the two backends diverge in
   how they realize it (branch vs predication) and the cost models differ. If it forbids
   branches entirely, you lose `List.head`, `Kernel.balance`, and `mintShielded` as
   expressible, and sums become circuit-stage-only. I've assumed forward branches are in.

2. **Struct identity is currently name-and-shape, not declaration identity** — two
   independently-declared `struct Point { x: Field, y: Field }` are the *same* type
   (`compact-reference.mdx:575-603`). That's neither nominal nor structural. It's
   defensible as *content-addressed nominality* for a language whose types cross a
   serialization boundary, but it means two libraries silently share a `Point`, and it
   interacts badly with coherence (two crates, one instance slot). Which do you want?

3. **Where does the two-stage split live syntactically?** I've shown `observe(...)` as an
   expression-level boundary inside store operations. The alternative is two syntactic
   categories (VM expressions vs circuit expressions) with an explicit lift. The first is
   friendlier; the second is harder to get wrong.

4. **Do `Val` traits and `Store` traits share a resolution namespace?** They can't share
   instances (different kinds of self), but sharing the lookup makes error messages and
   scoping uniform. I'd share; worth deciding deliberately.

5. **Is `Extern` (`Opaque`) worth keeping as a kind, or should it become an existential at
   the `Iface` boundary?** It's currently two hardcoded strings with about six separate
   rejection sites. There may be a cleaner story where an opaque JS value is just a
   contract-like existential.
