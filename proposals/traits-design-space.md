# Type abstraction in Compact: a map of the design space

*Working notes, not a CoIP. Written to fix vocabulary before we commit to a shape.*

---

## 0. The short version

"Traits" is not one corner of the design space. Rust's `trait` bundles at least six
independent design decisions that other languages take separately, and Compact has
already, independently, landed on four of the six — in four different, mutually
incompatible mechanisms.

The three problems you named are **not the same problem**:

| Problem | Corner it actually lives in |
|---|---|
| Curve / field arithmetic (`ecAdd`, `neg`, `inv`, missing `JubjubScalar` ops) | **Type-attached ad-hoc polymorphism with associated types and constants** — the typeclass corner. `std::ops::Add` is a fair analogy, but the load-bearing part is not the operator; it's `Group::Scalar` and `Field::MODULUS`. |
| Standard library clunkiness | Three separable things: **bounds on the generics you already have**, **default methods**, and a handful of missing *value-level* abstractions (a `reverse<#n,T>`) that have nothing to do with types at all. |
| User-defined `ledger` ADTs | **Modules with abstract types and associated layouts.** Closer to an ML functor than to a Rust trait. The Impact VM needs no changes for this; the barrier is entirely in the compiler's closed macro table. |

And the target forces one answer to the most consequential axis before we start:
**everything must monomorphize.** No dynamic dispatch, no trait objects, no vtables.
That's not a preference. The Impact program is a ZK public input, and the ZK backend
inlines every circuit. Any design that implies runtime dispatch is dead on arrival.

The rest of this document is the map that gets you to those three lines.

---

## 1. The organizing question

Every abstraction mechanism in every language is answering one question:

> Given a use site `f(a, b)`, how does the compiler decide *which* `f`?

There are exactly six answers in wide use. Everything else is a variation.

| Mechanism | How the implementation is found | Canonical | Can abstract over "any type with an `f`"? |
|---|---|---|---|
| **Parametric** | There is only one. The code cannot inspect the type. | ML `'a list`, Java `<T>` | N/A — nothing to find |
| **Overloading** | Scan same-named bindings; pick the one whose parameter types accept the arguments. | C++, Java, **Compact today** | **No** |
| **Type classes / traits** | Named signature bundle; declared instances; resolution by constraint solving against an instance table. | Haskell, Rust | **Yes** |
| **Modules / functors** | You pass it explicitly. The implementation is a value. | SML, OCaml, 1ML | **Yes**, explicitly |
| **Implicits** | Like type classes, but resolution searches a lexical scope of implicit values. | Scala `given`, Agda instance args | **Yes** |
| **Subtyping / vtables** | The *value* carries its implementation. | Java `interface`, Go `interface`, **Compact `contract`** | Yes, but only for values |

The gap between row 2 and row 3 is exactly your stdlib problem. Compact's overload
resolution already picks `ecAdd` correctly for Jubjub vs secp256k1 — the *dispatch*
works fine. What's missing is that there is no **name** for "the set of types that have
`ecAdd`, `ecMul`, `ecMulGenerator`," so you cannot write

```compact
circuit schnorrVerify<P: Group, S: Scalar<P>, #N>(msg: Vector<N, Field>, sig: Sig<P,S>, pk: P): Boolean
```

and get one Schnorr body that serves both curves. `jubjubSchnorrVerify` and
`secp256k1EcdsaVerify` do structurally the same work and share zero code, purely because
`Point` and `Scalar` cannot be constrained.

**Overloading is dispatch without abstraction. Traits are dispatch *plus* the ability to
quantify over the dispatch set.** That is the single sentence version of what you'd be
buying.

---

## 2. The axes that actually matter

### 2.1 Is the implementation attached to the *value* or to the *type*?

This is the axis that decides the whole design, and it is usually the one people skip.

- **Value-attached**: Java/Go interfaces, OCaml objects, `dyn Trait`, and **Compact's
  `contract` types**. A value carries a pointer to its own methods. Buys you
  heterogeneous collections and late binding.
- **Type-attached**: Haskell classes, Rust traits (static), ML modules. The
  implementation is selected from the *static* type; no receiver needed.

For Compact, the deciding case is **nullary operations**:

```
generator()      : P            -- no argument to dispatch on
identity()       : P
zero()           : F
MODULUS          : Field-ish constant
default<T>       -- already in the language!
```

Value-attached dispatch *fundamentally cannot express these*. There is no receiver.
And note the empirical evidence in your own tree: Compact's `do-call` explicitly does
not use the return type for resolution (`infer-types.ss:380-497`), and — I think this is
not a coincidence — **there is no `generator()` or `identity()` circuit on either curve**,
for either Jubjub or secp256k1. The four field moduli live in `compiler/field.ss` as
Scheme constants, duplicated again in `runtime/src/constants.ts`, precisely because there
is no way to say `F::MODULUS`.

Meanwhile Compact *already has* a type-directed nullary operation with a per-type
implementation table: `default<T>`. It's a one-method builtin trait with a
compiler-internal instance list and explicit type application at the call site. The
syntax question for nullary trait methods is therefore already settled by precedent:
`generator<JubjubPoint>()`.

**Conclusion: type-attached. `contract` types are the wrong model to extend for this
problem**, even though they are the closest existing syntax. (They remain the right model
for cross-contract calls, which is a genuinely dynamic problem.)

### 2.2 Nominal or structural satisfaction?

- **Structural**: satisfaction is by shape; no declaration needed. Go, TypeScript,
  row-polymorphic records, and Compact's `contract` types (the reference says so
  explicitly: *"contract typing is structural, not nominal"*).
- **Nominal**: satisfaction is declared. Rust `impl`, Haskell `instance`.

Compact is currently *mixed*, in a way that will bite:

- structs are nominal — but nominal *by name-and-shape*, not by declaration identity. Two
  separately-declared `NumberAnd`s with the same fields are the same type.
- type aliases come in both flavours: `type` is transparent, `new type` is opaque to
  subtyping.
- `contract` is structural.
- ledger ADTs are nominal.

Structural satisfaction has one enormous advantage here: **no coherence problem, ever.**
It also has one disqualifying disadvantage: it cannot distinguish `new type Money =
Uint<64>` from `Uint<64>`, so you can't give `Money` its own `Add` instance — which is
half the point of having `new type` in the first place. Today every operation on a nominal
alias round-trips through `as Base ... as Alias`, and the arithmetic operators special-case
it with an ad-hoc "same nominal type in, same nominal type out" rule
(`infer-types.ss:732-750`) that silently inserts a *narrowing* `downcast-unsigned` that can
fail at runtime. That rule is a hand-rolled `impl Add for Money` with no way to opt out of
it or write a different one.

**Lean nominal, with `new type` as a first-class instance target.** That is where the
existing pain is.

### 2.3 What can be a parameter? (the kind question)

This is where the design space really opens up. Ordered by increasing power:

1. **Types.** Compact has this.
2. **Values / sizes.** Compact has this (`#n`) — ahead of most languages; Rust only got
   const generics in 2021.
3. **Bounds on 1 and 2.** Compact has *none*. `doc/compact-reference.mdx:340`: "Each
   generic argument must be a type, a natural number literal, or the type or numeric value
   of a generic parameter." Full stop.
4. **Associated types** — a type *output* of an instance. `Group::Scalar`,
   `Field::Repr`. Equivalent to ML's abstract types in signatures, or Haskell's type
   families with a functional dependency.
5. **Associated constants** — `Field::MODULUS`, `Group::GENERATOR`, `Field::MAX`.
6. **Associated *sizes*** — Compact-specific and useful: `Field::BYTES`, so
   `toBytes(x): Bytes<F::BYTES>`.
7. **Higher-kinded types** — abstracting over `Map<_,_>` vs `Set<_>` vs `List<_>` as
   type *constructors*. Needed if you want one `Container` abstraction over the ledger ADTs.
8. **Associated layouts** — not a standard corner; Compact-specific. A ledger ADT's
   `initial-value` (`(state-value 'array ((null) (null) (cell (align 0 8))))` for `List`)
   is an associated *value of the state universe* belonging to the ADT.

The curve problem needs **3, 4, 5, and 6**. Note how much of the pain is in 4 and 5 rather
than in method dispatch:

```
Group:  associated type Scalar;  associated type BaseField;
        add, neg, mul(P, Scalar), mulGenerator(Scalar), x, y, construct, GENERATOR, IDENTITY
Field:  associated const MODULUS; associated const MAX; associated size BYTES;
        add, sub, mul, neg, inv, ZERO, ONE, fromBytes, toBytes
```

`ecMul(pk, c)` needs to know that `c`'s type is *the scalar field of `pk`'s curve* — that's
a functional dependency, and today it is enforced by writing out the two instantiations by
hand and letting overload resolution fail on a mismatch.

The ledger ADT problem needs **8**, and arguably **7**.

**HKT is the one I'd flag as a scope trap.** It's tempting (`Container<E>` over
`Set`/`List`/`MerkleTree`), it's the natural generalization, and it roughly doubles the
complexity of the type checker. It is not required by either of your two motivating
problems. I'd design so it can be added later and not add it now.

### 2.4 Coherence: who may write an instance, and what if two apply?

The classic answers:

- **Haskell**: global uniqueness. One instance per (class, type) in the whole program.
  Enforced by orphan rules. Makes `Map k v` sound (you can't get two different `Ord k`).
- **Rust**: orphan rule — you may `impl` a trait for a type only if you own one of them.
  Plus specialization, still unstable after a decade, because it's genuinely hard.
- **Scala/Agda implicits**: no global uniqueness. Resolution searches lexical scope;
  ambiguity within a scope is an error; an inner scope shadows an outer one.
- **ML modules**: the question doesn't arise. You passed the implementation; there is no
  search.

**Compact has already chosen, and it chose the Scala answer.** Overload resolution
(`expand-modules-and-types.ss:503-518` + `infer-types.ss:380-497`) collects candidates
into *scope-stratified groups*, innermost contour first, and only reports ambiguity when
two candidates in the *same* contour both fit. An inner `foo(Boolean)` doesn't conflict
with an outer `foo(Field)`; the inner group is tried first and, if nothing there is
argument-compatible, resolution falls out to the next contour.

Two consequences worth being deliberate about:

1. A trait system layered on this inherits scoped, non-global coherence. That is *fine*
   for the curve problem (nobody needs two `Group JubjubPoint` instances) and it avoids
   ever having to write an orphan rule. It does mean you can't rely on global uniqueness
   for soundness — so, e.g., a hypothetical `Map<K: Ord, V>` in ledger state could in
   principle be built with one `Ord K` and read with another. Worth ruling out by
   construction rather than by rule.
2. **There is an existing hazard here.** A module body's environment rib is the *enclosing*
   rib, which is still being mutated as later top-level elements are processed, and module
   bodies are drained from a worklist afterwards. So a module body can call a top-level
   function defined textually *after* the `import`. If instances resolve the same way,
   "what's in scope" is not fixed at the point of definition. That's a coherence bug
   waiting to happen and it should be closed explicitly in any traits CoIP.

### 2.5 Runtime representation — **forced, see §4**

The menu is: monomorphize (Rust, C++), dictionary-pass (Haskell, Scala), vtable
(Java, Go), or erase (Java generics).

Compact must monomorphize. §4 explains why this isn't negotiable.

### 2.6 What travels with a method besides its signature?

This is the axis where Compact is genuinely unlike Rust, and where I think the real design
work is.

In Rust, a trait method is a function: name, argument types, return type. That's it.
In Compact, an operation carries at least four more things:

| Attribute | Where it lives today | Who consumes it |
|---|---|---|
| **purity** | `pure` keyword, *inferred and verified* by `identify-pure-circuits.ss` | `contract implements` matches it exactly; TS codegen |
| **disclosure vector** | per-argument string on each ledger op / native; default for ledger ops is `""` = *discloses* | `track-witness-data.ss` — the abstract interpreter that rejects undeclared leaks |
| **op-class** | `read` / `write` / `update` / `remove` / `update-with-coin-check i j` | sealed-field analysis, purity inference, "is this callable from the JS `ledger()` reader" |
| **code template** | a literal Impact opcode sequence, parameterized by `f` (the access path) and `f-cached` | three separate backends |

So: **a Compact "method" is not a function. It is a tuple of (signature, purity,
per-argument disclosure vector, effect class, code template).** Any trait that could be
satisfied by *either* a circuit *or* a ledger op has to abstract over all five, and the
two sides currently have *opposite* defaults — an unannotated native argument is a syntax
error, an unannotated ledger-op argument silently discloses.

If you take one thing from this document into the CoIP: **the hard part of traits in
Compact is not dispatch. It's that a method signature has to include an effect row.**
`op-class` is already, in effect, a four-valued effect annotation consumed by three
independent analyses. It's the natural hook, and it's the thing Rust's `Add` gives you no
guidance on.

### 2.7 Laws

Traits carry expected laws that the type system doesn't check: associativity, identity,
`a - b == a + neg(b)`. Usually this is a documentation problem. In a ZK language it's a
soundness problem: a wrong `Group` instance is a proof-system bug, not a wrong answer.

Three options, in increasing ambition: (a) laws as prose in the trait declaration; (b)
laws as `assert`-able circuits the toolchain can run against a test corpus; (c) laws as
obligations in the Agda spec. Worth noting that the Agda spec **already uses instance
arguments for exactly this**:

```agda
⊢expr-+ : ⦃ _ : Numeric τ₁ ⦄ → ⦃ _ : Numeric τ₂ ⦄ → ...
```

`IsNumeric` in `Lsrc.lagda.md:836-850` is a two-constructor typeclass over Compact types.
The spec has already modelled the arithmetic operators as class-constrained. Making that
real in the surface language would bring implementation and spec *closer*, not further
apart.

---

## 3. Where Compact already sits

Compact has **four** partially-overlapping abstraction mechanisms. Plotting them is the
fastest way to see what's missing.

| | Generics | Overloading | `contract` types | Ledger ADTs |
|---|---|---|---|---|
| Polymorphism kind | parametric | ad-hoc | subtype | ad-hoc |
| Attached to | nothing | name | **value** | **type** |
| Nominal/structural | — | — | structural | nominal |
| Named signature bundle? | — | **no** | **yes** | implicit |
| Bounds? | **no** | n/a | n/a | 3-point kind system (`ADT/Type`, `Type`, `Nat`) |
| Associated types? | no | no | no | **yes** (`value_type`, `key_type`) |
| Conditional instances? | no | no | no | **yes** |
| Resolution | explicit instantiation, monomorphized | scope-stratified arg subtyping | runtime, external | linear scan of the op table in the type |
| User-extensible? | yes | yes | yes | **no** |

Two entries in that table deserve to be called out.

**`contract` + `contract implements` is already a signature-checked interface mechanism.**
A `contract` type is a record of circuit signatures with real width subtyping, purity in
the signature, and an optional `implements` assertion checked by exact signature match. The
*syntax* and the *checking discipline* for a trait feature already exist in the language.
They're just pointed at deployed-contract values instead of at types.

**Ledger ADTs are already a closed trait system, complete with conditional impls.**
`langs.ss:444-445` defines an `ADT-Op-Condition`, and `midnight-ledger.ss:566` uses it:

```scheme
(when (= value_type QualifiedShieldedCoinInfo)
  (function (update-with-coin-check 0 1) writeCoin ...))
```

`Cell<T>` gains a `writeCoin` method **only when `T = QualifiedShieldedCoinInfo`**. That is
semantically `impl WriteCoin for Cell<QualifiedShieldedCoinInfo>`, resolved at
monomorphization time by `apply-ledger-ADT`. Four ADTs use it. The op set genuinely does
not exist in the instantiated type when the guard fails — which is why the docs say
"available only for QualifiedShieldedCoinInfo" rather than the runtime raising.

**So the design question is less "should Compact have traits" and more "should the trait
system Compact already has, internally and in four incompatible dialects, become one
mechanism that users can write."** That reframing is worth putting in the CoIP's
motivation section.

---

## 4. What the target forces

This is the section that collapses the design space, and it's why the answer for Compact
is genuinely different from the answer for a general-purpose language.

**(a) Everything monomorphizes, and it already does.** `expand-modules-and-types` erases
all generics before the typechecker even runs, by making one specialized copy ("frob") per
distinct instantiation, memoized in an instance table. Downstream, `inline-circuits`
inlines *every* circuit into its callers; `unroll-loops` fully unrolls `map`/`fold`;
recursion is rejected outright; `flatten-datatypes` explodes every structured value into a
vector of field-element variables. Nothing polymorphic survives to either backend.

**(b) The Impact program is a zero-knowledge public input.** `verify.rs:1946-1990`
field-reprs *every opcode* of both transcripts into the proof's public inputs. The
program is a constant the proof commits to. There is therefore no such thing as "one call
site whose target varies at runtime" — that would be one proof covering many programs,
which the binding scheme forbids by construction.

**(c) The VM has no indirect jump, no call, and no loop.** `Jmp`/`Branch` take `u32`
immediates; `skip >= 1` always and the program only ever shrinks. There is no opcode that
consumes a stack value as a jump target, no `Op::Call`, no `StateValue::Program`. Code and
data are strictly separated and only data lives in state. **A vtable is not
representable.**

**(d) Abstraction is zero-cost iff it is compile-time — and *only* then.** Cost is charged
per emitted opcode (and affinely in runtime data sizes), and the opcode count is also proof
width and transaction bytes. A compile-time abstraction that expands to N opcodes costs
exactly N: genuinely free. But runtime shape dispatch costs real money: an N-arm dispatch
chain is O(N) opcodes *in the proof* whether or not an arm runs, and `branch n` is priced
`branch_constant + branch_coeff_arg * n` — **skipping instructions costs in proportion to
how many you skip.**

**(e) There is a runtime type tag, and it is useless for this.** `Op::Type` (`0x03`) exists
and returns a 5-way structural shape tag (3 bits constructor, 5 bits arity). `List_head`
uses it for a two-arm branch. But it carries *no nominal information* — a `Counter` and a
`Uint64` cell both report `0` — and alignment is not observable at all. So even the one
runtime type test that exists cannot distinguish two Compact types.

**Net effect on the design space:**

| Ruled out | Ruled in |
|---|---|
| Trait objects / existentials | Static, monomorphized instance resolution |
| Dynamic dispatch on traits | Bounded parametric polymorphism |
| Heterogeneous collections | Associated types, constants, sizes |
| Dictionary passing at runtime | Default methods (they expand) |
| Traits in ledger state | Conditional instances (already precedented) |

That's a *narrow* space, and narrowness is good news: it means the design has fewer
degrees of freedom than a general-purpose language's, and most of the hard questions
(coherence under separate compilation, specialization, object safety) don't arise.

---

## 5. The three problems are not one problem

### 5.1 Curves and fields — the real trait case

This is the strongest case and the one I'd build the CoIP around. The evidence:

- The field arithmetic table is a literal hand-written two-level `nanopass-case`
  cross-product in `infer-types.ss:666-693`. `(field-scalar (curve-jubjub))` is simply
  *absent from the outer dispatch*, which is the entire reason `JubjubScalar` has no
  arithmetic. That's not a design decision; it's a missing row.
- `neg` and `inv` exist for `Secp256k1Base` and `Secp256k1Scalar` and for nothing else —
  four `declare-native-entry` rows differing only in `Base`↔`Scalar`.
- Point accessors are name-mangled for no reason: `jubjubPointX` vs `secp256k1PointX`.
  Overload resolution would happily accept both being called `pointX`; the mangling is
  historical accident, and the docs now have to explain the inconsistency.
- `standard-library-aliases.ss:56-60` is the smoking gun. Adding a *second* curve forced a
  rename of the entire single-curve API (`NativePointX` → `jubjubPointX`,
  `constructNativePoint` → `constructJubjubPoint`) and left a permanent alias table behind.
  With a `Group` trait, `Point::x` would not have needed renaming when the second instance
  arrived.
- Adding a *third* curve today means editing, by my count, **nine** hand-written
  dispatches in `print-typescript.ss` alone, plus `infer-types.ss` in four places,
  `flatten-datatypes.ss`, `check-types-Lflattened.ss`, both zkir backends, and three
  TypeScript runtime files.
- `jubjubSchnorrVerify` and `secp256k1EcdsaVerify` share zero code.

What it needs: bounds (`<P: Group>`), associated types (`P::Scalar`), associated constants
(`F::MODULUS`), associated sizes (`F::BYTES`), and nullary methods
(`generator<P>()`). Notably it does *not* need HKT, trait objects, or operator
overloading — operators are nice-to-have sugar on top; the abstraction is what matters.

### 5.2 Stdlib clunkiness — three different missing things

Decompose before designing:

**(i) Genuinely traits.** The families above.

**(ii) Default methods.** Eight circuits in `standard-library.compact` implement one
shape twice:

```compact
blockTimeGte(t)  = !blockTimeLt(t)
blockTimeLte(t)  = !blockTimeGt(t)
unshieldedBalanceGte(c,a) = !unshieldedBalanceLt(c,a)
unshieldedBalanceLte(c,a) = !unshieldedBalanceGt(c,a)
```

That's not abstraction over *types*; it's "derive `Gte` from `Lt`." Default methods on a
trait give it to you, but so would much less machinery. `resetToDefault` is hand-written
**seven** times across the ledger ADTs; `isEmpty` three times; `size`/`length` three
times.

**(iii) Not a type-abstraction problem at all.** 42% of `zkir-v3-library.compact` — 64 of
154 lines — is two hand-unrolled 32-element byte reversals. What's missing there is a
generic `reverse<#n, T>(v: Vector<n,T>)`, which needs no trait and no bound. It needs a
way to *build* a vector by indexed generation. `for` exists but there's no
vector-comprehension form. **Do not let this get folded into the traits CoIP** — it will
inflate the proposal and it's independently shippable.

Similarly: `upcastQualifiedCoin`/`downcastQualifiedCoin` and the `*Immediate` adapter
circuits exist because `ShieldedCoinInfo` and `QualifiedShieldedCoinInfo` differ by one
field and there's no record subtyping. That's a coercion/row-polymorphism question, a
different corner again.

### 5.3 User-defined ledger ADTs — the module case, and a pleasant surprise

The pleasant surprise: **the Impact VM needs no changes.** I went looking for the barrier
and it isn't where you'd expect:

- The VM has no notion of a ledger ADT at all. `Cell`, `Counter`, `Map`, `Set`, `List`,
  `MerkleTree`, `HistoricMerkleTree` are compile-time macros in *your* compiler that expand
  to opcode sequences over five structural `StateValue` shapes.
- The cost model is keyed on opcode × shape × runtime size. A new ADT built from existing
  shapes is priced automatically and *correctly*.
- The replay checker compares `AlignedValue`s. It has no ADT awareness and needs none.
- The WASM boundary exposes exactly the `StateValue` universe and takes `&[Op]`.
- `List` and `HistoricMerkleTree` are *already* pure user-space constructions — a cons list
  as a 3-array with `type`/`branch` dispatch, and a `[BMT, u64, Map]` composite with
  hand-maintained invariants. Existence proofs.
- Rust system contracts (`ledger/src/dust.rs`, `zswap/src/verify.rs`) consume the generated
  ADT macros exactly as a Compact contract would. Nothing downstream knows their names.

The barrier is that `declare-ledger-adt` is a **Chez Scheme macro `include`d into the
compiler at build time**, plus roughly a dozen hardcoded ADT-name and op-name sites:
`Map`-only nesting, nesting is assumed to be exactly `lookup(key)`, `serialize-adt`'s
closed `case` in the contract-info writer, and a name protocol where `read`/`write`/
`increment`/`decrement`/`resetToDefault`/`iter` have hardwired meanings.

**Shape of the abstraction that fits:** a ledger ADT is *(state layout, kind signature,
set of operations each carrying an op-class + disclosure vector + code template)*. That is
an ML structure with an abstract type, or equivalently a trait with an associated layout
and associated constant. It is **not** the same abstraction as `Group`, and I would be
suspicious of any design that claims to be both without saying so explicitly.

Two real constraints to design against:

- **No loops in the VM.** Any ADT operation whose opcode count depends on runtime data is
  inexpressible. This is why `List` has `pushFront`/`popFront`/`head` but no `nth`. A
  user-defined balanced tree with rebalancing, or a resizable vector, cannot be written.
  This restriction should be *visible in the type system*, not a downstream expansion
  failure — that's a real design problem.
- **Nibble budgets.** `Array` length ≤ 16, `Idx` path depth ≤ 16, `Ins` levels ≤ 15,
  `Dup`/`Swap` reach ≤ 15. There's already a comment in `midnight-ledger.ss:577` warning
  that the coin-writing ops break when the access path exceeds length 5. These budgets
  *compose* when ADTs nest, and nothing currently tracks them.

The other question this raises: do you want users writing raw Impact stack code? Today
that code is hand-verified against three separate opcode tables plus the Rust `FieldRepr`
impl. Letting users write it is a foot-cannon. **Deriving the opcode sequence from a
high-level body is the ambitious-but-right answer**, and it's a much bigger project than
traits. Worth separating in the roadmap even if both end up in one CoIP series.

---

## 6. Three coherent designs

### Design A — Bounded generics + traits over types

```compact
trait Group {
  type Scalar: Field;
  const GENERATOR: Self;
  const IDENTITY: Self;
  pure circuit add(a: Self, b: Self): Self;
  pure circuit neg(a: Self): Self;
  pure circuit mul(a: Self, s: Scalar): Self;
  pure circuit mulGenerator(s: Scalar): Self { return mul(GENERATOR, s); }  // default
}

impl Group for JubjubPoint {
  type Scalar = JubjubScalar;
  const GENERATOR = ...;
  circuit add(a, b) = ecAdd;      // or native binding
  ...
}

export circuit schnorrVerify<P: Group, #N>(msg: Vector<N, Field>, sig: Sig<P>, pk: P): Boolean { ... }
```

- **Pro:** matches how people expect the feature to look; call sites stay clean
  (`add(a,b)`, or `a + b` with operator sugar); reuses the existing `contract` syntax
  vocabulary and the existing overload machinery for resolution; conditional impls already
  precedented.
- **Con:** introduces coherence questions Compact hasn't had to answer; needs real
  constraint checking at instantiation (today `import EcGroup<Secp256k1Point>` would fail
  *deep inside the body* at each unresolvable call, with "no compatible candidate" rather
  than a bound violation); associated types add a type-level equality solver, however
  small; doesn't obviously extend to ledger ADTs.

### Design B — Module signatures + module-typed parameters (ML functors)

```compact
signature Group {
  type Point;
  type Scalar;
  circuit add(a: Point, b: Point): Point;
  circuit mulGenerator(s: Scalar): Point;
}

module Jubjub : Group { type Point = JubjubPoint; ... }

module Schnorr<G: Group> {
  export circuit verify<#N>(msg: Vector<N, Field>, sig: Sig, pk: G.Point): Boolean {
    return G.mulGenerator(response) == G.add(announcement, G.mul(pk, c));
  }
}
import Schnorr<Jubjub>;
```

- **Pro:** **no coherence problem ever** — you passed the implementation. Multiple
  implementations per type are free (two `Ord` orders on one type: fine). It's the natural
  fit for ledger ADTs, which really *are* structures with an abstract type and an
  associated layout. And critically: **the implementation is already shaped like this.**
  Generic module instantiation is already functor application under the hood — a tvar rib
  plus a memoized instance table — so this is arguably the smaller change.
- **Con:** verbose at every use site (`G.add(a,b)`, never `a + b`); no operator
  overloading; doesn't help the "I just want `neg` to work on all four field types"
  ergonomic complaint at all, which is the complaint you actually have.

### Design C — Traits as sugar over modules

Traits are the surface; a module/dictionary is the elaboration target; instance resolution
is implicit module search. This is Dreyer–Harper–Chakravarty *Modular Type Classes* (POPL
2007), and it's what Scala, 1ML, and (informally) Rust all converge on.

- **Pro:** one underlying mechanism, two ergonomics. Ledger ADTs use the module face,
  curve arithmetic uses the trait face. Since everything monomorphizes, the "dictionary"
  never exists at runtime — it's purely an elaboration device, so you pay nothing for the
  indirection.
- **Con:** most design work up front; the elaboration has to be specified carefully or the
  Agda spec gets much harder.

**My read:** C is where you want to end up, and A is what you should specify first, in a
way that doesn't foreclose it. The tell is that Compact's monomorphizer already builds
"specialized environment + memoized instance table" — which is a dictionary in everything
but name. Writing the traits CoIP with an explicit elaboration-to-modules story costs
little now and buys the ledger-ADT story later.

---

## 7. Things I'd rule out early, and say so in the CoIP

- **Trait objects / `dyn` / existentials.** Not representable (§4b, §4c).
- **Higher-kinded types.** Not needed by either motivating problem; large cost. Design so
  it's addable.
- **Traits over `contract` types.** `contract` is the *value-attached, dynamic* corner and
  it's correctly designed for cross-contract calls, which are genuinely late-bound. Don't
  merge them. Do steal the syntax.
- **Global coherence / orphan rules.** Compact's existing overloading is scope-stratified;
  inheriting that is cheaper and consistent. But *do* close the scope-leakage hole where a
  module body can see top-level definitions that come after it.
- **User-written raw Impact opcode sequences.** Even if user-defined ledger ADTs ship,
  hand-written stack code hand-synced against three opcode tables is not a user-facing
  feature.
- **Return-type-only inference.** Compact requires explicit generic arguments everywhere
  and has no unification anywhere in the typechecker — `sametype?`/`subtype?` are two
  structural predicates and that's the whole story. Keep it that way; nullary methods get
  explicit type application, exactly like `default<T>` already does.

---

## 8. Questions I can't answer for you

1. **Does `+` become overloadable, or do traits only cover named circuits?** Operator
   overloading is the most visible win and the biggest semantic commitment (the `Uint`
   bound arithmetic in `arithmetic-binop` is subtle and has real range-tracking behaviour
   that a user `impl Add` would have to either inherit or opt out of). It's separable from
   the rest.

2. **How much of the effect story goes in the trait signature?** Purity is currently
   *inferred* and only *checked* against declarations. Disclosure is a per-argument vector
   with opposite defaults on the two sides. `op-class` is consumed by three analyses. Does
   a trait method declare all of these, or only purity? I think this is the highest-risk
   unresolved question in the design.

3. **Do traits and the ledger ADT extension ship as one CoIP or two?** They want different
   mechanisms (§5.3) but a shared elaboration (§6C). CoIP-2 and CoIP-3 set a precedent for
   a language CoIP with a separate compiler-implementation companion document, which may be
   the right container.

4. **Is the `new type` narrowing rule** (`Money + Money : Money` with an implicit
   `downcast-unsigned` that can fail at runtime) **something a user `impl Add for Money`
   should be able to replace?** If yes, traits become load-bearing for existing semantics
   and the backwards-compatibility section gets interesting.

5. **What's the migration story for the alias table?** `standard-library-aliases.ss`
   already carries two renaming waves plus the multi-curve rename. If `pointX` becomes a
   trait method, that's a third. Better to plan it than to accrete it.

---

## Appendix: reference index

| Concern | File | Lines |
|---|---|---|
| Monomorphization, module expansion, scope | `compiler/analysis-passes/expand-modules-and-types.ss` | `Info` 163-186; `make/register-frob` 418-432; `lookup-fun` 444-575; `apply-ledger-ADT` 921-978 |
| Typechecker: subtyping, overloading, operators, casts | `compiler/analysis-passes/infer-types.ss` | `sametype?`/`subtype?` 118-304; `do-call` 380-498; arithmetic 636-750; relational 751-774; equality 775-789; `find-adt-op` 790-849; `contract-implements!` 878-934; casts 1796-1946 |
| Ledger ADT DSL, conditional ops | `compiler/ledger.ss` | 44-222 |
| Ledger ADT table | `compiler/midnight-ledger.ss` | Cell 544; Counter 587; Set 622; Map 699; List 798; MerkleTree 971; HistoricMerkleTree 1127; conditional ops 566, 669, 768, 917 |
| Native/overload registration tables | `compiler/midnight-natives.ss`, `compiler/zkir-v3-natives.ss` | 20 + 12 rows |
| Field moduli (associated constants, by hand) | `compiler/field.ss` | 36-50 |
| Alias table (the rename scar) | `compiler/standard-library-aliases.ss` | 28-60 |
| Disclosure analysis | `compiler/analysis-passes/track-witness-data.ss` | 860-880 |
| Pass pipeline | `compiler/passes.ss`, `analysis-passes.ss`, `circuit-passes.ss` | — |
| Agda: instance-argument typing of `+` | `specification/.../Lsrc.lagda.md` | `IsNumeric` 836-850; `⊢expr-+` 1265-1288 |
| Impact `StateValue` (5 shapes) | `midnight-ledger/onchain-state/src/state.rs` | 69-96 |
| Impact opcodes (32) | `midnight-ledger/onchain-vm/src/ops.rs` | 156-260 |
| Forward-only control flow | `midnight-ledger/onchain-vm/src/vm.rs` | 1056-1071 |
| Program as ZK public input | `midnight-ledger/ledger/src/verify.rs` | 1946-1990 |
| Replay check | `midnight-ledger/onchain-vm/src/result_mode.rs` | 44-58 |
| Cost model | `midnight-ledger/onchain-vm/src/cost_model.rs` | 59-260 |
| CoIP template & process | `coips/coip-template.md`, `coips/coip-0001.md`, `coips/coip-0002.md` | — |

**External references worth citing in the CoIP:**

- Wadler & Blott, *How to make ad-hoc polymorphism less ad hoc* (POPL 1989) — the original
  dictionary-passing elaboration; the argument for why overloading isn't enough.
- Dreyer, Harper, Chakravarty, *Modular Type Classes* (POPL 2007) — classes elaborated to
  modules; the Design C reference.
- Jones, Jones & Meijer, *Type classes: an exploration of the design space* (1997) — still
  the best single survey of the axes in §2.
- Chakravarty et al., *Associated Type Synonyms* (ICFP 2005) — `Group::Scalar`.
- Odersky et al., *Simplicitly / Implicit Function Types* — the scoped-coherence
  alternative Compact's overloading already resembles.
- Rust RFC 1210 (specialization) — cautionary tale on "most specific instance wins."
