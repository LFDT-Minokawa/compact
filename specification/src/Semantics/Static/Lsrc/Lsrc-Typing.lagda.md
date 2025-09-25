# Introduction {-} 

This document gives a specification for the static semantics of
type-level objects in Compact. The specification is based on the
abstract syntax of compact as it is defined internally in the
compiler.

The specification is written in literate, and thus can be checked to
verify that definitions are correct. Furthermore, the specification is
limited to the safe fragment of Agda, to avoid inadvertent
exploitation of paradoxes in the underlying logic.

**TODO: safe is temporary gone bc we have to postulate deceq for types.** 

```agda
{-# OPTIONS --no-qualified-instances  #-}
```

<!--
```agda

open import Data.String
  using ( String ; wordsBy )
  renaming ( _++_ to _++s_ ; _==_ to _==s_ )
open import Data.List
  using ( List ; _++_ ; [] ; _∷_ ; length ; intersperse ; foldr ; zip)
  renaming ( map to lmap )
open import Data.Bool
  using ( Bool ; T? ; if_then_else_ )
open import Data.Nat
  using ( ℕ ; suc ; zero )
open import Data.Sum
  using ( _⊎_ ; inj₁ ; inj₂ )
  renaming ( [_,_] to ⊎[_,_] )
open import Data.Maybe
  using ( Maybe ; maybe′ ; maybe )
open import Data.Product
  using ( _×_ ; _,_ ; ∃ ; ∃₂ ; proj₁ ; proj₂ ; ∃-syntax ; Σ ; -,_ ; uncurry)
open import Data.Unit
  using ( ⊤ ; tt )
open import Agda.Builtin.Char
  using ( primCharEquality )
open import Data.Empty
  using ( ⊥ )

open import Data.List.Membership.Propositional
  using ( _∈_ )
open import Data.List.Relation.Unary.All
  using ( All ; _∷_ ; [] ; lookup )
  renaming (map to amap)
open import Data.List.Relation.Unary.Any
  using ( here ; there )
open import Data.List.Relation.Binary.Pointwise
  using ( Pointwise ; _∷_ ; [] )
open import Data.List.Membership.Propositional.Properties
  using ( ∈-++⁺ʳ ; ∈-++⁺ˡ ; ∈-++⁻) 

open import Relation.Unary
  using (_⇒_ ; IUniversal)
open import Function
  using (_∘_ ; case_of_)

open import Relation.Binary.PropositionalEquality
  using (_≡_ ; refl ; trans ; sym ; cong₂)
```
--> 

The underlying syntax definition, transpiled from the corresponding
Nanopass IR, is imported from the following module:

```agda
open import Syntax.Generated.Lsrc
```

Since this file is a literate Agda file, and Agda files are
type-checked top to bottom, the specification is organized in a
bottom-up fashion, where we discuss the most basic definitions first,
which other definitions later on in the specification build on.

Concretely, this specification consists of four sections:

1. In the first section, we define the necessary preliminaries for
   describing well-formedness of types.

2. Then, in the second section, we define well-formedness of Compact
   types as a mutually-recursive family of inductive relations over
   the (type-level productions of the) generated `Lsrc` language.

3. In the third section, we define renaming and parallel substitution
   for well-formed types.

4. Finally, in the fourth section, we define some additional
   operations on well-formed syntax.

<!--
```agda
module Semantics.Static.Lsrc.Lsrc-Typing where 
```
-->


Additionally, we also use some functionality from IOG's agda prelude
library.

```agda
open import Prelude.InferenceRules
```

# Preliminaries

This section contains preliminary definitions.

## Declared Variables and Naming Conventions 

In this specification, we make extensive use of Agda's support for
generalization of declared variables. See [Agda's
documentation](https://agda.readthedocs.io/en/v2.7.0.1/language/generalization-of-declared-variables.html)
for more details.

All syntactic sorts declared in the compiler come with an associated
"metavariable" name. For example, the name `type` is used to range
over Compact types. The specification, by compulsion, adopts the
naming conventions used internally in the compiler. In the Agda syntax
definition generated from Nanopass IRs, a `variable` block is
generated for each syntactic sort that registers the metavariable name
associated with that sort as a declared variable, as well as its
deriviatives (i.e., `type₁`, `type₂`, etc ...).

Furthermore, the name `type∗` is declared to range over values of
`List Type`. In general, declared variables are postfixed with a `∗`
range over the reflexive transitive closure (i.e., `List`) of the
underlying syntactic object. 

## Finite Maps

Names are strings, and finite mappings, often from names to some type
of declaration, are defined as lists of products.

```agda
Name = String

infix 1 _↦_
-- The type of finite maps from A to B 
_↦_ : (A B : Set) → Set
A ↦ B = List (A × B)  
```

## Declarations of User-Defined Types

To describe well-formedness of types, we ought to keep track of the
user-defined types that are in scope. Importantly, we don't need to
store the whole defintion for type checking, but instead for defining
well-formedness of types it is enough to know the number of type
parameters, and whether they should be instantiated with a type or
size, whenever we reference a user-defined type.

There are two types of user-defined types, enums and structs. To check
an enum reference, we don't need to keep any more information beyond
the fact that it exists, but for structs we'll need to keep track of
it's type parameters as well.

```agda
data Decl : Set where
  enum   : Decl
  struct : List Type-Param → Decl
```

## Type Contexts

Type contexts keep track of which type-level names are bound. Type
level names can refer to: 

1. ledger types, such as `Map` or `Set`,
2. user-defined types, i.e., structs and enums, or
3. type variables bound in a module header or by a generic circuit. 

The `TypeContext` record stores for each class which names are in
scope.

```agda 
record TypeContext : Set where
  pattern
  constructor typecontext 
  field
    ledgerTypes
      : Name ↦ List Type-Param
    userTypes
      : Name ↦ Decl
    variables
      : List Type-Param
```

<!-- 
```
open TypeContext public
```
--> 

We define several operations for describing functional updates to type
contexts. First, we define an operation `[_v↦_]` that updates the
variable bindings in a type context. 

```agda 
[_v↦_]
  : TypeContext
  → List Type-Param
  → TypeContext
[ Δ v↦ vs ] = record
  { ledgerTypes = Δ .ledgerTypes
  ; userTypes   = Δ .userTypes
  ; variables   = vs
  }
```

For example the expression

  `[ Δ v↦ vs ]`

should be read as _the context `Δ`, with type variables set to `vs`. 

Similarly, the following operation updates the set of declared user
types in the type context.

```agda
[_u↦_]
  : TypeContext
  → Name ↦ Decl
  → TypeContext
[ Δ u↦ u ] = record
  { ledgerTypes = Δ .ledgerTypes
  ; userTypes   = u
  ; variables   = Δ .variables
  }
```

Finally, we have the following operation that combines updates to the
user-defined types and variables in a type context.

```agda
[_↦_∣_]
  : TypeContext
  → Name ↦ Decl
  → List Type-Param
  → TypeContext
[ Δ ↦ u ∣ vs ]
  = [ [ Δ v↦ vs ] u↦ u ] 
```

We omit the analogous operations for updating the set of known ledger
types: we assume that these will remain constant throughout the program. 

We also define operations for updating the context with a newly
defined enum or struct: 

```agda 
declareEnum
  : (name : String)
  → TypeContext
  → TypeContext
declareEnum name Δ
  = [ Δ u↦ (name , enum) ∷ Δ .userTypes ]
   
declareStruct
  : (name : Name)
  → List Type-Param
  → TypeContext
  → TypeContext 
declareStruct name type-param∗ Δ
  = [ Δ u↦ (name , (struct type-param∗)) ∷ Δ .userTypes ]
```

## Empty Type Context

```agda
εΔ[_] : Name ↦ List Type-Param → TypeContext
εΔ[_] l∗ = record
  { ledgerTypes = l∗
  ; userTypes   = []
  ; variables   = []
  }
```


<!-- 
```agda
variable
  Δ Δ₁ Δ₂ Δ₃ Δ′ : TypeContext 
  n n₁ n₂ n₃ n′ : ℕ
  name name₁ name₂ name₃ name′ : String
  msg : String
  name∗ : List String 
  d d₁ d₂ d₃ d′ : Decl
  b b₁ b₂ b₃ b′ : Bool 
```
--> 

## Argument Matching

We will frequently need to make assertions that a list of arguments
matches a list of type parameters (i.e., we should not be able to give
a type argument where a size argument is expected).

The following relations define when a type argument respectively ADT
argument match a type parameter. They are simply defined as empty if
the constructors don't align (e.g., a `nat-valued` type parameter
doesn't match with a `type`-valued type argument), and trivial if the
constructors do match. 

```agda 
Match-Param-Arg
  : Type-Param
  → Type-Argument
  → Set
Match-Param-Arg (nat-valued _) (targ-size _)
  = ⊤
Match-Param-Arg (nat-valued _) (targ-type _)
  = ⊥
Match-Param-Arg (type-valued _) (targ-size _)
  = ⊥
Match-Param-Arg (type-valued _) (targ-type _)
  = ⊤
```

These relations may be lifted to lists of parameters/arguments as
follows, where `Pointwise` is a relation transformer from Agda's
standard library that lifts a relation `R : A → B → Set` to a relation
`Pointwise R : List A → List B → Set` by relating the elements
pointwise. That is, `Pointwise R xs ys` establishes that `xs` and `ys`
have the same length, and for each `xₙ ∈ xs`, `yₙ ∈ ys` at position
`n`, we have a proof that `R xₙ yₙ`.

```agda 
Match-Param-Arg∗
  : List Type-Param
  → List Type-Argument
  → Set
Match-Param-Arg∗ type-param∗ targ∗
  = Pointwise Match-Param-Arg type-param∗ targ∗
```

## Elimination of Type Parameters

While Compact lacks an explicit kind system, we sometimes need to
reason based the kind (i.e., size or type) of a type parameters. The
following eliminator is useful in these instances. 

```agda
param[_,_]
  : ∀ {a} {A : Set a}
  → (Name → A)
  → (Name → A)
  → Type-Param
  → A 
param[ f , g ] (nat-valued name)
  = f name
param[ f , g ] (type-valued name)
  = g name
```

## Type conversion

Compact's internal syntax definition distinguishes between types
(which can occur anywhere) and ATD arguments (which are type arguments
given to a ledger ADT). Occasionally, we require conversion from
ledger ADT type arguments to "normal" types, which is done by the
`tadt` function: 

```agda 
fetch-targ
  : Match-Param-Arg∗ type-param∗ targ∗
  → type-param ∈ type-param∗
  → ∃[ targ ] targ ∈ targ∗ × Match-Param-Arg type-param targ   
fetch-targ {type-param∗ = nat-valued x ∷ _} {targ∗ = targ-size x₁ ∷ _} (tt ∷ _) (here refl)
  = targ-size _ , here refl , tt 
fetch-targ {type-param∗ = type-valued x ∷ _} {targ∗ = targ-type x₁ ∷ _} (tt ∷ _) (here refl)
  = targ-type _ , here refl , tt 
fetch-targ
  {type-param∗ = nat-valued _ ∷ _} {targ∗ = targ-size _ ∷ _} (tt ∷ m) (there px)
  with fetch-targ m px
... | targ , px′ , w = targ , there px′ , w
fetch-targ {type-param∗ = type-valued _ ∷ _} {targ∗ = targ-type _ ∷ _} (tt ∷ m)  (there px)
  with fetch-targ m px
... | targ , px′ , w = targ , there px′ , w
```

## Subtyping 

<!--
```agda

open import Relation.Binary.Structures
```
-->

Types in compact are related by a subtyping relation. For now, we just
assume this exists and is specified,  and is a preorder (i.e.,
reflexive and transitive).

```agda 
-- TODO: define subtyping
-- TODO: Use HIT for anisymmetry? 
data _⊑_ : (type₁ type₂ : Type) → Set where  
  ⊑-refl
    : type ⊑ type
  ⊑-trans
    : type₁ ⊑ type₂ → type₂ ⊑ type₃ → type₁ ⊑ type₃

instance ⊑-pre : IsPreorder _≡_ _⊑_ 
⊑-pre = record
  { isEquivalence = record
    { refl  = refl
    ; sym   = sym
    ; trans = trans
    }
  ; reflexive     = λ where refl → ⊑-refl
  ; trans         = ⊑-trans
  } 

variable ix ix₁ ix₂ ix₃ ix′ : type₁ ⊑ type₂ 

```

The following instance allows the subtype relation to be used as a
accesibility relation in a shallowly embedded modal logic of
predicates over types, providing us with several useful abstractions
for describing the static semantics of term-level objects.

```agda
open import Class.HasOrder 
open import Level
open import Class.DecEq
open import Function 
```


Sometimes, it is useful to assert that a type is equal to the maximum
of two types, which is done using the following ternary
predicate. Importantly this is *not* the same as computing a least
upper bound w.r.t. subtyping, as the maximum forces either of the two
types to be a subtype of the other.

```agda
_≡-max⟨_,_⟩ : (type type₁ type₂ : Type) → Set
type ≡-max⟨ type₁ , type₂ ⟩ =
  Σ ((type₁ ⊑ type₂) ⊎ (type₂ ⊑ type₁))
    ⊎[ (λ _ → type ≡ type₂)
    ,  (λ _ → type ≡ type₁)
    ]
```

# Well-Formedness of Type-Level Objects in Compact

We describe well-formedness of compact types by defining a
mutually-recursive family of inductive relations covering all
type-level objects in the `Lsrc` language.

The relation between syntax and typing should be 1:1. Every syntactic
sort should have an associated inductive relation describing its
well-formedness, and every constructor should have an associated
inference rule for proving well-formedness of that syntactic
construct. In other words, the typing relation should be
_syntax-directed_, or _deterministic_. There are static checks in
place to ensure coverage of typing relations, meaning type-checking of
the specification fails if typing judgments don't cover all possible
syntactic constructs in the language.

<!--

```agda
mutual
```
-->

## Argument Declaration 

 We start of with argument declarations. Argument declarations are
well-formed with respect to a type-context `Δ`.

```agda
  infix 5 _⊢arg_
  data _⊢arg_ (Δ : TypeContext)
    : Argument
    → Set where
```

The syntax of type arguments only has one (unnamed) production
rule. It is well-formed if the declared type is well-formed under `Δ`. 

```agda
    ⊢arg'
      : (Δ ⊢type type)
        ────────────────────────
        Δ ⊢arg unnamed name type 
```

## Types

Compact types are well-formed with respect to a type context `Δ`.

```agda
  infix 5 _⊢type_
  data _⊢type_ (Δ : TypeContext)
    : Type
    → Set where  
```

### Type References

Type references are well-formed if the stored reference is well-formed
under `Δ`. 

```agda
    ⊢type-tref
      : Δ ⊢tref tref
        ──────────────────
        Δ ⊢type `tref tref
```

### Boolean/Field

The `Boolean` and `Field` types are trivially well-formed. 

```agda 
    ⊢type-tboolean
      : ────────────────
        Δ ⊢type tboolean

    ⊢type-tfield
      : ──────────────
        Δ ⊢type tfield 
```

### Unsigned Integers

Unsigned integer types are well-formed if their size parameter(s)
is/are well-formed under `Δ`. 

```agda 
    ⊢type-tunsigned
      : Δ ⊢tsize tsize
        ────────────────────────
        Δ ⊢type tunsigned tsize
                     
    ⊢type-tunsigned1
      : {tsize^ : Maybe Type-Size}
      → Δ ⊢tsize tsize
      → maybe′ (Δ ⊢tsize_) ⊤ tsize^
        ───────────────────────────────
        Δ ⊢type tunsigned1 tsize tsize^ 
```

### Bytes 

A byte array type is well-formed if its size parameter is well-formed
under `Δ`.

```agda 
    ⊢type-tbytes
      : Δ ⊢tsize tsize
        ────────────────────
        Δ ⊢type tbytes tsize 

```


### Opaque Types

Opaque types are trivially well-formed. 

```agda 
    ⊢type-topaque
      : (s : String)
      → ─────────────────
        Δ ⊢type topaque s
```

### Vectors 

Vector types are well-formed if both its size and type parameter are
well-formed under `Δ`. 

```agda
    ⊢type-tvector
      : Δ ⊢tsize tsize
      → Δ ⊢type type
        ──────────────────────────
        Δ ⊢type tvector tsize type
```


### Tuples

```agda
    ⊢type-ttuple
      : All (Δ ⊢type_) type∗
        ────────────────────
        Δ ⊢type ttuple type∗
```

### Undeclared Types 

Undeclared types are trivially well-formed. 

```agda 
    ⊢type-tundeclared
      : ───────────────────
        Δ ⊢type tundeclared
```

## Type Sizes

Sizes are well-formed with respect to a type context `Δ`. 

```agda
  infix 5 _⊢tsize_
  data _⊢tsize_ (Δ : TypeContext)
    : Type-Size
    → Set where
```

Sizes can either be a qouted natural number literal, which is
trivially well-formed

```agda 
    ⊢tsize-quote′
      : (n : ℕ)
      → ────────────────────
        Δ ⊢tsize type-size n 
```

, or a reference to a type variable, which is well-formed if the
referenced name is stored as a nat-valued type variable in the context
`Δ`.

```agda 
    ⊢tsize-type-size-ref
      : nat-valued name ∈ Δ .variables 
        ──────────────────────────────
        Δ ⊢tsize (type-size-ref name)  
```


## Type Arguments

Type Arguments are well-formed with respect to a type context `Δ`. 

```agda
  infix 5 _⊢targ_
  data _⊢targ_ (Δ : TypeContext)
    : Type-Argument
    → Set where
```

A type argument can either be a quoted natural number literal, when
instantiating a size parameter, in which case it is trivially
well-formed

```agda 
    ⊢targ-size 
      : (n : ℕ) 
      → ────────────────
        Δ ⊢targ targ-size n 
```

, or a type, in which case it is well formed if said type is
well-formed under `Δ`. 

```agda 
    ⊢targ-type
      : Δ ⊢type type
        ──────────────────
        Δ ⊢targ targ-type type 
```


-- ## Type References

-- Type references are well-formed with respect to a type context `Δ`. 

```agda
  infix 5 _⊢tref_
  data _⊢tref_ (Δ : TypeContext)
    : Type-Ref
    → Set where
```

A type reference consists of a name, and a list of type arguments. It
is well-formed if the referenced name is found in `Δ`, and the given
list of type arguments is a valid instantiation of the type's expected
parameters. Furthermore, all the supplied type arguments should be
well-formed. The precise meaning of well-formedness of references is
defined by the `Ref` predicate.

```
    ⊢tref-type-ref
      : Ref Δ name targ∗
      → All (Δ ⊢targ_) targ∗ 
        ───────────────────────────
        Δ ⊢tref type-ref name targ∗
```

There are 4 types of names that we can refer to in a type:

  1. a ledger ADT, such as `Map` or `Set`,
  2. a user-defined enumeration,
  3. a user-defined struct, or 
  4. a type variable bound e.g. by a module or generic circuit.

The `Ref` data type collects these different types of references,
allowing for inspection of references by pattern matching. The precise
criteria for their well-formedness is captured in separate predicates. 

```agda
  data Ref (Δ : TypeContext) (name : Name) (targ∗ : List Type-Argument)
    : Set where
    adt
      : ADTRef Δ name targ∗    → Ref Δ name targ∗
    enum
      : EnumRef Δ name targ∗   → Ref Δ name targ∗
    struct
      : StructRef Δ name targ∗ → Ref Δ name targ∗
    var
      : VarRef Δ name targ∗ → Ref Δ name targ∗ 
```

### ADT References

A reference to a ledger ADT is well-formed, if the referenced name is
a known ledger ADT, and the associated list of expected type
parameters as stored in `Δ` matches the given list of type arguments.

```agda 
  ADTRef
    : (Δ : TypeContext)
    → (name : Name)
    → (targ∗ : List Type-Argument)
    → Set
  ADTRef Δ name targ∗ =
    ∃ λ type-param∗ →
        (name , type-param∗) ∈ Δ .ledgerTypes
      × Match-Param-Arg∗ type-param∗ targ∗
```

### Enum References

A reference to a user-defined enumeration is well-formed if the
referenced name is a known declared enumeration in `Δ`, and the list
of type arguments is empty (`Enums` have no parameters).

```agda 
  EnumRef
    : (Δ : TypeContext)
    → (name : Name)
    → (targ∗ : List Type-Argument)
    → Set
  EnumRef Δ name targ∗
    = ((name , enum) ∈ Δ .userTypes × targ∗ ≡ [])
```

### Structure References

A reference to a user-defined structure is well-formed if the
referenced name is a known declared structure in `Δ`, and the list of
type arguments matches the expected list of type parameters.

```agda 
  StructRef
    : (Δ : TypeContext)
    → (name : Name)
    → (targ∗ : List Type-Argument)
    → Set
  StructRef Δ name targ∗ =
    ∃ λ type-param∗ →
        (name , (struct type-param∗)) ∈ Δ .userTypes
      × Match-Param-Arg∗ type-param∗ targ∗
```

### Variable References 

A reference to a type variable is well-formed if the referenced name
is a known bound variable in `Δ`, and the list of type arguments is
empty (type variables never have any type arguments).

```agda 
  VarRef
    : (Δ : TypeContext)
    → (name : Name)
    → (targ∗ : List Type-Argument)
    → Set
  VarRef Δ name targ∗
    = (type-valued name ∈ Δ .variables × targ∗ ≡ []) 
```

## Type Parameters

Type parameters are typed with respect a type context `Δ`. 

```agda
  infix 5 _⊢type-param_
  data _⊢type-param_ (Δ : TypeContext)
    : Type-Param
    → Set where

```

A declared type parameter merely indicates whether at that position
the supplied type argument is expected to be a size or a type. In
either case, the parameter declaration is trivially well-formed. 

```agda
    ⊢type-param-nat
      : ─────────────────────────────
        Δ ⊢type-param nat-valued name
 
    ⊢type-param-type
      : ──────────────────────────────
        Δ ⊢type-param type-valued name
```

# Substitution and Renaming for Well-Formed Types

Now that we have a definition of well-formedness for Compact types, we
can define parallel renaming and substitution for well-formed types.

The reason that we define renaming/substitution for well-formed types
rather than the untyped syntax is twofold:

  1. By defining these operations on well-formed syntax,
  renaming/substitution operates on _typed De Bruijn indices_, rather
  than names, which avoids dealing with the usual issues associated
  with variable binding such as capture avoidance, α-renaming,
  shadowning, etc... 

  2. Syntactic soundess proofs in the style of Wright and Felleisen
  generally rely on a "substitution lemma" stating that substitution
  of well-formed terms preserves their well-formedness. With the
  definition below, this property holds by construction. 

## Renaming 

Abstractly speaking, a (typed) renaming is a transformation between
membership proofs. 

```agda
Renaming
  : {A : Set}
  → (xs ys : List A) → Set
Renaming xs ys
  = ∀[ (_∈ xs) ⇒ (_∈ ys) ] 
```

Or, in other words, a renaming converts a proof that some object is
part of some context into a proof that it is part of another context.

We define the following useful lemma witnessing that renamings can be
extended to contexts with a common prefix. 

```agda
rename-++ˡ
  : ∀ {A : Set} {vs₁ vs₂ vs : List A}
  → Renaming vs₁ vs₂
  → Renaming (vs ++ vs₁) (vs ++ vs₂) 
rename-++ˡ {_} {vs₁} {vs₂} {vs} ρ v
  with ∈-++⁻ vs v
... | inj₁ x = ∈-++⁺ˡ x
... | inj₂ y = ∈-++⁺ʳ vs (ρ y)
```

And, conversely, that renamings can be extended to contexts with a
common suffix. 

```agda 
rename-++ʳ
  : ∀ {A : Set} {vs₁ vs₂ vs : List A}
  → Renaming vs₁ vs₂
  → Renaming (vs₁ ++ vs) (vs₂ ++ vs) 
rename-++ʳ {_} {vs₁} {vs₂} {vs} ρ v
  with ∈-++⁻ vs₁ v
... | inj₁ x = ∈-++⁺ˡ (ρ x)
... | inj₂ y = ∈-++⁺ʳ vs₂ y
``` 

Since type contexts contain several lists of declarations, we require
a slightly more refined definition of renaming, that renames the bound
variables and user-defined types in for a given relation `R` over type
contexts. We exclude ledger ADTs from this definition on purpose, as
these are constant throughout every Compact program.

```agda
record RenameT (R : TypeContext → Set) : Set where
  field
    renameT
      : ∀ {vs u}
      → (ρv : Renaming (Δ .variables) vs)
      → (ρu : Renaming (Δ .userTypes) u)
      → R Δ
      → R [ Δ ↦ u ∣ vs ]
```

We make the above record publicly available as an _instance argument_: 

```agda
open RenameT ⦃...⦄ public
```

This allows us to use `renameT` to describe renamings for any
predicate for which we have an appropriate instance of the `RenameT`
class, rather than having different renaming functions for every
different syntactic object. [Agda's
documentation](https://agda.readthedocs.io/en/latest/language/instance-arguments.html)
provides more detail on instance arguments.

We implement renaming by giving a mutually-recursive collection of
instances.

The definition, for the most part, is trivial, and renaming simply
amounts to propagating the renaming down into substructures. Whenever
we encounter references, we reconstruct the syntax tree with the
updated membership proofs. 

```agda  
mutual 
  instance
    rename-arg
      : RenameT (_⊢arg arg)
  rename-arg .RenameT.renameT
    ρv ρu (⊢arg' x)
    = ⊢arg' (renameT ρv ρu x)

  instance
    rename-type
      : RenameT (_⊢type type)
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tref x)
    = ⊢type-tref (renameT ρv ρu x)
  rename-type .RenameT.renameT
    ρv ρu ⊢type-tboolean
    = ⊢type-tboolean
  rename-type .RenameT.renameT
    ρv ρu ⊢type-tfield
    = ⊢type-tfield
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tunsigned x)
    = ⊢type-tunsigned (renameT ρv ρu x)
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tunsigned1 {tsize^ = Maybe.just _} x y)
    = ⊢type-tunsigned1 (renameT ρv ρu x) (renameT ρv ρu y)
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tunsigned1 {tsize^ = Maybe.nothing} x y)
    = ⊢type-tunsigned1 (renameT ρv ρu x) tt 
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tbytes x)
    = ⊢type-tbytes (renameT ρv ρu x)
  rename-type .RenameT.renameT ρv ρu
    (⊢type-topaque s)
    = ⊢type-topaque s
  rename-type .RenameT.renameT
    ρv ρu (⊢type-tvector x y)
    = ⊢type-tvector (renameT ρv ρu x) (renameT ρv ρu y)
  rename-type .RenameT.renameT
    ρv ρu (⊢type-ttuple xs)
    = ⊢type-ttuple (renameT ρv ρu xs) 
  rename-type .RenameT.renameT
    ρv ρu ⊢type-tundeclared
    = ⊢type-tundeclared

  instance
    rename-type∗ : RenameT λ Δ → All (Δ ⊢type_) type∗
    rename-type∗ .RenameT.renameT
      ρv ρu [] = []
    rename-type∗ .RenameT.renameT
      ρv ρu (t ∷ ts) = renameT ρv ρu t ∷ renameT ρv ρu ts
    
  instance
    rename-tsize : RenameT (_⊢tsize tsize)
  rename-tsize .RenameT.renameT
    ρv ρu (⊢tsize-quote′ n)
    = ⊢tsize-quote′ n
  rename-tsize .RenameT.renameT
    ρv ρu (⊢tsize-type-size-ref x)
    = ⊢tsize-type-size-ref (ρv x)

  instance
    rename-tref
      : RenameT (_⊢tref tref)
  rename-tref .RenameT.renameT
    ρv ρu (⊢tref-type-ref (adt r) wf)
    = ⊢tref-type-ref (adt r) (renameT ρv ρu wf)
  rename-tref .RenameT.renameT
    ρv ρu (⊢tref-type-ref (enum (r , m)) wf)
    = ⊢tref-type-ref (enum (ρu r ,  m)) (renameT ρv ρu wf)
  rename-tref .RenameT.renameT ρv ρu
    (⊢tref-type-ref (struct (_ , r , m)) wf)
    = ⊢tref-type-ref (struct (_ , ρu r , m)) (renameT ρv ρu wf)
  rename-tref .RenameT.renameT ρv ρu
    (⊢tref-type-ref (var (r , refl)) wf)
    = ⊢tref-type-ref (var (ρv r , refl)) (renameT ρv ρu wf)

  instance
    rename-targ
      : RenameT (_⊢targ targ)
  rename-targ .RenameT.renameT
    ρv ρu (⊢targ-size n)
    = (⊢targ-size n)
  rename-targ .RenameT.renameT
    ρv ρu (⊢targ-type wf)
    = ⊢targ-type (renameT ρv ρu wf)

  instance
    rename-targ∗
      : RenameT λ Δ → All (Δ ⊢targ_) targ∗
  rename-targ∗ .RenameT.renameT
    ρv ρu []
    = []
  rename-targ∗ .RenameT.renameT
    ρv ρu (wf ∷ xs)
    = renameT ρv ρu wf ∷ renameT ρv ρu xs
 
  instance
    rename-type-param
      : RenameT (_⊢type-param type-param)
  rename-type-param .RenameT.renameT
    ρv ρu ⊢type-param-nat
    = ⊢type-param-nat
  rename-type-param .RenameT.renameT
    ρv ρu ⊢type-param-type
    = ⊢type-param-type
```

## Substitution

Parallel substitution replaces all free variables in a term at once
with terms typed under a different set of free variables. A
substitution for Compact types replaces the variables bound in `Δ`
with a well-formedness proof whose type depends on whether a parameter
is `nat-valued` or `type-valued`.

```agda 
SubstitutionT
  : (Δ : TypeContext)
  → (vs : List Type-Param)
  → Set
SubstitutionT Δ vs =
  ∀[ (_∈ Δ .variables)
  ⇒  param[ (λ _ → ∃ ([ Δ v↦ vs ] ⊢tsize_))
          , (λ _ → ∃ ([ Δ v↦ vs ] ⊢type_))
          ]
  ] 
```

We define the following record type capturing that a relation `R` over
type contexts and some absract set `T` supports parallel
substitution. This is presents a slight difference from how we defined
the record type witnessing that relations support renaming, which are
only indexed by a context. This is necessary, becuase unlike renaming,
substitution may change the structure of the type for which we prove
well-formedness. We have to witness this change in the type of the
substitution function, by explicitly exposing the type index in the
type of `R` and closing over the type indices of well-formedness
proofs using existentials.

```agda 
record SubstituteT (T : Set) (R : TypeContext → T → Set) : Set where
  field
    substituteT
      : ∀ {vs}
      → (σ : SubstitutionT Δ vs)
      → ∃ (R Δ)
      → ∃ (R [ Δ v↦ vs ])
```

<!-- 
```agda
open SubstituteT ⦃...⦄ public 
```
--> 

Substitution, just like renaming, is defined as a mutually-recursive
collection of instances. Again, most of the cases merely propagate the
the substitution down into sub-structures. If we encounter a type
variable reference, or a type size reference, we apply the
substitution. To define substitution, we need some auxiliary lemmas
witnessing that match proofs are preserved by substitution, these are
described in more detail below.

```agda 
mutual 
  instance
    substitute-arg
      : SubstituteT _ (_⊢arg_)
  substitute-arg .SubstituteT.substituteT
    σ (unnamed name _ , ⊢arg' x)
    = unnamed name _ , ⊢arg' (substituteT σ (_ , x) .proj₂) 

  instance
    substitute-targ
      : SubstituteT _ (_⊢targ_)
  substitute-targ .SubstituteT.substituteT σ
    (targ-size n , (⊢targ-size n))
    = targ-size n , ⊢targ-size n
  substitute-targ .SubstituteT.substituteT
    σ (targ-type x , ⊢targ-type wf)
    = targ-type (substituteT σ (_ , wf) .proj₁)
    , ⊢targ-type (substituteT σ (_ , wf) .proj₂)

  instance
    substitute-targ∗
      : SubstituteT _ λ Δ → All (Δ ⊢targ_) 
  substitute-targ∗ .SubstituteT.substituteT σ
    ([] , [])
    = [] , []
  substitute-targ∗ .SubstituteT.substituteT
    σ (x ∷ xs , px ∷ pxs)
    = let s₁ = substituteT σ (x , px) in
      let s₂ = substituteT σ (xs , pxs) in
    (s₁ .proj₁ ∷ s₂ .proj₁) , (s₁ .proj₂ ∷ s₂ .proj₂)

  

  instance substitute-type : SubstituteT _ (_⊢type_)
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tref (⊢tref-type-ref (adt (_ , px , m)) wf)) 
    = _
    , ⊢type-tref (⊢tref-type-ref
        ( adt (_ , px , match-arg-subst∗ σ m)
        ) (substituteT σ (_ , wf) .proj₂))
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tref (⊢tref-type-ref (enum (px , refl)) []))
    = _
    , ⊢type-tref (⊢tref-type-ref
        ( enum (px , refl)
        ) (substituteT σ (_ , []) .proj₂))
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tref (⊢tref-type-ref (struct (_ , px , m)) wf))
    = _
    , (⊢type-tref (⊢tref-type-ref
        ( struct (_ , px , match-arg-subst∗ σ m)
        ) (substituteT σ (_ , wf) .proj₂)))
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tref (⊢tref-type-ref (var (r , refl)) _))
    = σ r
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tboolean)
    = tboolean , ⊢type-tboolean
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tfield)
    = _ , ⊢type-tfield
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tunsigned x)
    = _ , ⊢type-tunsigned (substituteT σ (_ , x) .proj₂)
  substitute-type .SubstituteT.substituteT
    σ (tunsigned1 tsize (Maybe.just _) , ⊢type-tunsigned1 x y)
    = _
    , ⊢type-tunsigned1
       ( substituteT σ (_ , x) .proj₂
       ) (substituteT σ (_ , y) .proj₂)
  substitute-type .SubstituteT.substituteT
    σ (tunsigned1 tsize Maybe.nothing , ⊢type-tunsigned1 x tt)
    = tunsigned1 _ Maybe.nothing
    , ⊢type-tunsigned1 (substituteT σ (_ , x) .proj₂) tt
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tbytes x)
    = _ , ⊢type-tbytes (substituteT σ (_ , x) .proj₂)
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-topaque s)
    = _ , ⊢type-topaque s
  substitute-type .SubstituteT.substituteT
    σ (tvector tsize type , ⊢type-tvector x y)
    = tvector _ _
    , ⊢type-tvector
        ( substituteT σ (_ , x) .proj₂
        ) (substituteT σ (_ , y) .proj₂)
  substitute-type .SubstituteT.substituteT
    σ (ttuple type∗ , ⊢type-ttuple ts)
    = let sub = substituteT σ (type∗ , ts) in
      (ttuple (sub .proj₁)) , (⊢type-ttuple (sub .proj₂)) 
  substitute-type .SubstituteT.substituteT
    σ (_ , ⊢type-tundeclared)
    = _ , ⊢type-tundeclared


  instance
    substitute-type∗
      : SubstituteT _ λ Δ → All (Δ ⊢type_)
    substitute-type∗ .SubstituteT.substituteT
      σ ([] , [])
      = [] , []
    substitute-type∗ .SubstituteT.substituteT
      σ (type ∷ type∗ , x ∷ xs)
      = let sub₁ = substituteT σ (type , x) in
        let sub₂ = substituteT σ (type∗ , xs) in
        sub₁ .proj₁ ∷ sub₂ .proj₁
      , sub₁ .proj₂ ∷ sub₂ .proj₂
      
  instance
    substitute-tsize
      : SubstituteT _ (_⊢tsize_)
  substitute-tsize .SubstituteT.substituteT
    σ (_ , ⊢tsize-quote′ n)
    = _ , ⊢tsize-quote′ n
  substitute-tsize .SubstituteT.substituteT
    σ (_ , ⊢tsize-type-size-ref x)
    = σ x 

  instance
    substitute-type-param
      : SubstituteT _ (_⊢type-param_) 
  substitute-type-param .SubstituteT.substituteT
    σ (t , ⊢type-param-nat)
    = t , ⊢type-param-nat
  substitute-type-param .SubstituteT.substituteT
    σ (t , ⊢type-param-type)
    = t , ⊢type-param-type
```

The following lemmas witness that a proof that a (list of) type
argument(s) matches a (list of) type parameter(s) is preserved if we
apply some substitution to the (list of) type argument(s). 

```agda 
  match-arg-subst
    : ∀ {wf}
    → (σ : SubstitutionT Δ type-param∗)
    → Match-Param-Arg type-param targ
    → Match-Param-Arg type-param
        (substituteT ⦃ substitute-targ ⦄ σ (targ , wf) .proj₁)
  match-arg-subst
    {type-param = nat-valued x₁} {wf = ⊢targ-size _} _ tt
    = tt
  match-arg-subst
    {type-param = type-valued x₂} {wf = ⊢targ-type x₁} _ tt
    = tt
    
  match-arg-subst∗
    : ∀ {xs ys pxs}
    → (σ : SubstitutionT Δ type-param∗)
    → Match-Param-Arg∗ xs ys
    → Match-Param-Arg∗ xs
        (substituteT ⦃ substitute-targ∗ ⦄ σ (ys , pxs) .proj₁)
  match-arg-subst∗ {xs = []} {[]} {[]} σ []
    = []
  match-arg-subst∗ {xs = x ∷ xs} {ys = y ∷ ys} {_ ∷ _} σ (px ∷ m)
    = (match-arg-subst σ px) ∷ match-arg-subst∗ σ m
```


## Well-Formed Types

```agda
record ⊢Type (Δ : TypeContext) : Set where
  constructor mkTy 
  field
    ty               : Type
    well-formed-type : Δ ⊢type ty

record ⊢Size (Δ : TypeContext) : Set where
  constructor mkSz
  field
    sz               : Type-Size
    well-formed-size : Δ ⊢tsize sz 

open ⊢Type public
open ⊢Size public

instance rename-⊢type : RenameT ⊢Type
rename-⊢type .RenameT.renameT ρv ρu (mkTy ty wf) = mkTy _ (renameT ρv ρu wf)

variable τ τ₁ τ₂ τ₃ τ′ : ⊢Type Δ
         τ∗            : List (⊢Type Δ)
         ζ ζ₁ ζ₂ ζ₃ ζ′ : ⊢Size Δ 

arg→type∗ : All (Δ ⊢arg_) arg∗ → List (⊢Type Δ)
arg→type∗ []                = []
arg→type∗ (⊢arg' wf ∷ args) = mkTy _ wf ∷ arg→type∗ args


-- TODO: how does this definition compare against defining subtyping over well-formed types directly? 
_⊑-⊢_ : ⊢Type Δ → ⊢Type Δ → Set
τ₁ ⊑-⊢ τ₂ = τ₁ .ty ⊑ τ₂ .ty

record _≡-⊢max⟨_,_⟩ (τ τ₁ τ₂ : ⊢Type Δ) : Set where 
  field
    ⊢max : τ .ty ≡-max⟨ τ₁ .ty , τ₂ .ty ⟩ 

open _≡-⊢max⟨_,_⟩ public 

⊑-maxˡ : type ≡-max⟨ type₁ , type₂ ⟩ → type₁ ⊑ type
⊑-maxˡ (inj₁ px , refl) = px
⊑-maxˡ (inj₂ _  , refl) = ⊑-refl

⊑-maxʳ : type ≡-max⟨ type₁ , type₂ ⟩ → type₂ ⊑ type
⊑-maxʳ (inj₁ _  , refl) = ⊑-refl
⊑-maxʳ (inj₂ px , refl) = px

-- Relies on DeqEq 
postulate ⊑-⊢⇔⊏-⊢ : {x y : ⊢Type Δ} → (x ⊑-⊢ y) ⇔ ((x ⊑-⊢ y) × (x .ty ≡ y .ty → ⊥) ⊎ x ≡ y) 

-- TODO: use derivation from non-strict orders 
instance ⊢type-rel₂ : HasPreorder {A = ⊢Type Δ} {_≈_ = _≡_ }
⊢type-rel₂ = record
  { _≤_          = _⊑-⊢_
  ; _<_          = λ τ₁ τ₂ → τ₁ ⊑-⊢ τ₂ × (τ₁ .ty ≡ τ₂ .ty → ⊥)
  ; ≤-isPreorder = record
    { isEquivalence = record
      { refl  = refl
      ; sym   = sym
      ; trans = trans
      }
    ; reflexive = (λ where refl → ⊑-refl)
    ; trans = ⊑-trans
    }
  ; <-irrefl     = λ where refl (_ , f) → f refl
  ; ≤⇔<∨≈        = ⊑-⊢⇔⊏-⊢ 
  }

```

# Operations on Well-Formed Syntax 

```agda
substT : ∀ {vs} → SubstitutionT Δ vs → ⊢Type Δ → ⊢Type [ Δ v↦ vs ]
substT σ τ = uncurry mkTy $ substituteT σ (_ , τ .well-formed-type)
```

Finally, we define the following lemma, which states that if we have
well-formedness proofs for all elements in a list of type arguments,
and these type arguments match a given set of type parameters, we can
create a substitution under context `Δ`, that maps the type parameters
to their instantiation.

Intuitively, this substitution captures instantiation of parameters
bound by a module or generic circuit. This occurs, for instance at the
call site for a generic circuit, where the argument types and return
type of the circuit depend on its type parameter instantiation. The
function below describes the substitution that should be applied to
instantiate these types with the chosen type arguments.

```agda 
args-subst
  : All (Δ ⊢targ_) targ∗ 
  → Match-Param-Arg∗ type-param∗ targ∗
  → SubstitutionT [ Δ v↦ type-param∗ ] (Δ .variables) 
args-subst wf m {nat-valued _} x
  with fetch-targ m x
args-subst wf m {nat-valued _} x
  | targ-size n , px , tt
  with lookup wf px 
... | ⊢targ-size n = type-size n , ⊢tsize-quote′ n
args-subst wf m {type-valued _} x
  with fetch-targ m x
args-subst wf m {type-valued _} x
  | targ-type t , px , tt
  with lookup wf px 
... | ⊢targ-type wf′ = t , wf′
```

```agda
argt : ∃[ arg ] Δ ⊢arg arg → ⊢Type Δ
argt (unnamed _ type , ⊢arg' wf) = mkTy type wf
```

## Smart Constructors for well-formed types

```agda 
⊢ref : Δ ⊢tref tref → ⊢Type Δ
⊢ref wf = mkTy _ $ ⊢type-tref wf

⊢bool : ⊢Type Δ
⊢bool = mkTy _ $ ⊢type-tboolean

⊢field : ⊢Type Δ
⊢field = mkTy _ $ ⊢type-tfield

⊢uint₁ : ⊢Size Δ → ⊢Type Δ
⊢uint₁ s = mkTy _ $ ⊢type-tunsigned (s .well-formed-size) 

⊢uint₂ : ⊢Size Δ → ⊢Size Δ → ⊢Type Δ
⊢uint₂ s s' = mkTy _ $ ⊢type-tunsigned1 (s .well-formed-size) (s' .well-formed-size)

⊢bytes : ⊢Size Δ → ⊢Type Δ
⊢bytes s = mkTy _ $ ⊢type-tbytes (s .well-formed-size)

⊢opaque : String → ⊢Type Δ
⊢opaque x = mkTy _ $ ⊢type-topaque x

⊢vector : ⊢Size Δ → ⊢Type Δ → ⊢Type Δ
⊢vector s t = mkTy _ $ ⊢type-tvector (s .well-formed-size) (t .well-formed-type)

⊢undeclared : ⊢Type Δ
⊢undeclared = mkTy _ ⊢type-tundeclared

⊢tuple : List (⊢Type Δ) → ⊢Type Δ
⊢tuple {Δ} xs = mkTy (ttuple (go xs .proj₁)) (⊢type-ttuple (go xs .proj₂))
  where
    go : List (⊢Type _) → ∃[ τ∗ ] All (Δ ⊢type_) τ∗
    go [] = [] , []
    go (x ∷ xs) = x .ty ∷ go xs .proj₁ , x .well-formed-type ∷ go xs .proj₂

⊢quote : ℕ → ⊢Size Δ
⊢quote n = mkSz _ (⊢tsize-quote′ n)

⊢void : ⊢Type Δ
⊢void = ⊢vector (⊢quote 0) ⊢undeclared
```

## 

```agda
data _≲_ {Δ} : (τ₁ τ₂ : ⊢Type Δ) → Set where
  ≲-refl  : τ ≲ τ
  ≲-trans : τ₁ ≲ τ₂ → τ₂ ≲ τ₃ → τ₁ ≲ τ₃

instance ≲-pre : IsPreorder _≡_ (_≲_ {Δ}) 
≲-pre = record
  { isEquivalence = record
    { refl  = refl
    ; sym   = sym
    ; trans = trans
    }
  ; reflexive     = λ where refl → ≲-refl
  ; trans         = ≲-trans
  }
```


## Well-Formed Ledger Types 

**TODO: which types are valid ledger types?**

```agda
data IsLedgerType (Δ : TypeContext) : ⊢Type Δ → Set where

  is-adt-ref
    : (px : (name , type-param∗) ∈ Δ .ledgerTypes)
    → (m : Match-Param-Arg∗ type-param∗ targ∗)
    → (wf : All (Δ ⊢targ_) targ∗) 
    → IsLedgerType Δ (⊢ref (⊢tref-type-ref (adt (type-param∗ , px , m)) wf)) 

LedgerType : TypeContext → Set
LedgerType Δ = ∃[ τ ] IsLedgerType Δ τ

instance rename-ledger-type : RenameT LedgerType
rename-ledger-type .RenameT.renameT
  ρv ρu (τ , is-adt-ref px m wf) =
    renameT ρv ρu τ , is-adt-ref px m (renameT ρv ρu wf)
```

