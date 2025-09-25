# Introduction 

This file gives a formal specification of well-formedness of
term-level objects (such expressions) in Compact. It is a literate
Agda file, and thus can be type-checked to verify that the defintions
are correct.

The specification uses no known unsafe features of Agda. 

**TODO: safe temporarily gone bc type-level spec is unsafe** 

```agda
{-# OPTIONS --no-qualified-instances --allow-unsolved-metas  #-}
```

<!--
```agda
open import Data.List
  using (List ; _∷_ ; [] ; _++_ ; foldr ; [_] ; zip ; concat ; replicate)
  renaming (map to lmap)
open import Data.String
  using ( String ; wordsBy )
  renaming ( _++_ to _++s_ ; _==_ to _==s_ )
open import Data.Bool
  using ( Bool ; T? ; if_then_else_ )
open import Data.Nat
  using ( ℕ ; suc ; zero )
open import Data.Sum
  using ( _⊎_ ; inj₁ ; inj₂ )
  renaming ( [_,_] to ⊎[_,_] )
open import Data.Maybe
  using ( Maybe ; maybe′ ; just ; nothing)
open import Data.Product
  using ( _×_ ; _,_ ; ∃ ; ∃₂ ; proj₁ ; proj₂ ; ∃-syntax ; Σ-syntax ; Σ ; -,_ ; uncurry ; map₂)
open import Data.Unit
  using ( ⊤ ; tt )
open import Agda.Builtin.Char
  using ( primCharEquality )
open import Data.Empty
  using ( ⊥ )
open import Data.Fin
  using (Fin)
  renaming (toℕ to Ftoℕ)

open import Data.List.Membership.Propositional
  using ( _∈_ )
open import Data.List.Relation.Unary.All
  using ( All ; _∷_ ; [] ; reduce ; head ; tail)
  renaming (map to amap)
open import Data.List.Relation.Unary.Any
  using ( here ; there ; lookup )
open import Data.List.Relation.Binary.Pointwise
  using ( Pointwise ; _∷_ ; [] )
open import Data.List.Membership.Propositional.Properties
  using ( ∈-++⁺ʳ ; ∈-++⁺ˡ ; ∈-++⁻) 

open import Relation.Binary.PropositionalEquality
  using ( _≡_ ; refl ; trans ; sym ; subst)
open import Relation.Unary
  using ( Satisfiable ; IUniversal ; _⇒_ )

open import Function
  using ( _∘_ ; case_of_ ; id ; _$_ )
```
-->

First, we ought to make sure the following modules are imported. There
are many other imports, but most of these are from Agda's standard
library and merely used for structuring the specification. 

```agda
-- Defines the static semantics (or, well-formedness) of type-level
-- objects in Compact.
open import Semantics.Static.Lsrc.Lsrc-Typing

-- Contains the abstract syntax of Compact, as it's defined and used
-- internally in the compiler.
open import Syntax.Generated.Lsrc

-- Imports tooling to statically enforce coverage of typing relations.
open import Semantics.Static.Coverage

--
open import Class.MonotonePredicate
 
open import Prelude.InferenceRules
```

<!-- 
```agda
module Semantics.Static.Lsrc.Lsrc where



toℕ : ∀ {a} {A : Set a} {x : A} {xs} → x ∈ xs → ℕ
toℕ (here refl) = 0
toℕ (there px)  = suc (toℕ px)

```
--> 

# Preliminary definitions

We start by giving a precise description of the contextual information
and auxiliary definitions under which term-level ojects in Compact are
typed. The context is used to make sure that information such as
declared variables or types is available when describing
well-formedness of terms. It also allows us to describe how contextual
information changes, for example before and after a struct or enum is
declared.

## Type Context Extension 

The following operation denotes extension of type contexts with a list
of newly bound type variables. 

```agda
_⋊_  : List Type-Param → TypeContext → TypeContext
v∗ ⋊ Δ = [ Δ v↦ v∗ ++ Δ .variables ]
```
We should read `v∗ ⋊ Δ` as `Δ` extended with type variables `v∗`. 

```agda
subst-⋊
  : ∀ v∗
  → SubstitutionT [ Δ v↦ v∗ ] (Δ .variables)
  → SubstitutionT (v∗ ⋊ Δ) (Δ .variables)
subst-⋊ {Δ} v∗ σ x = ⊎[ σ , cvar ] (∈-++⁻ _ x)
  where
    cvar
      : type-param ∈ Δ .variables
      → param[ (λ _ → ∃[ n ]    Δ ⊢tsize n)
             , (λ _ → ∃[ type ] Δ ⊢type type)
             ] type-param
    cvar {nat-valued name} x
      = type-size-ref name , ⊢tsize-type-size-ref x
    cvar {type-valued name} x
      = (`tref (type-ref name []))
      , ⊢type-tref (⊢tref-type-ref (var (x , refl)) [])


⋊[_] : ∀ {v∗} → SubstitutionT [ Δ v↦ v∗ ] (Δ .variables) → ⊢Type (v∗ ⋊ Δ) → ⊢Type Δ  
⋊[ σ ] τ = substT (subst-⋊ _ σ) τ

⋊[_]∗ : ∀ {v∗} → SubstitutionT [ Δ v↦ v∗ ] (Δ .variables) → List (⊢Type (v∗ ⋊ Δ)) → List (⊢Type Δ)
⋊[ σ ]∗ = lmap ⋊[ σ ]
```


```agda

```

## Callable Objects

_Callable objects_ are the function-like objects in Compact: circuits,
witnesses, etectera. An object `Callable Δ` describes the type of a
function under type context `Δ`, and consists of three parts.

  1. `params`, describing the type parameters of the callable,
     carrying for each type-parameter a proof that it is well-formed.

  2. `returns`, describing the type returned by the callable, together
     with a proof that it's well-formed. 

  3. `pargs`, describing the pattern arguments of the callable,
     together with proofs that their types are well-formed. Crucially,
     the types of a callable's arguments are typed with respect to
     type context `Δ` _extended with the type parameters bound by the
     callable_.

```agda 
record Callable (Δ : TypeContext) : Set where
  constructor callable
  field
    params
      : ∃[ xs ]
          ∀ x → x ∈ xs
              → Δ ⊢type-param x  
    returns
      : ⊢Type (params .proj₁ ⋊ Δ)
      
    args
      : List (⊢Type (params .proj₁ ⋊ Δ))

mono : ⊢Type Δ → List (⊢Type Δ) → Callable Δ
mono τ τ∗ .Callable.params = [] , λ _ ()
mono τ τ∗ .Callable.returns = τ
mono τ τ∗ .Callable.args = τ∗

```

We use `𝓌`, `ω`, and `κ` to range over callable objects (respectively,
witnesses, circuits, and un-specified). 

<!--
```agda 
open Callable public
```

```agda
variable
  κ κ₁ κ₂ κ₃ κ′
    : Callable Δ
  𝓌 𝓌₁ 𝓌₂ 𝓌₃ 𝓌′
    : Callable Δ
  ω ω₁ ω₂ ω₃ ω′
    : Callable Δ 
```
--> 

## Contexts

Contexts store the contextual information needed to describe
well-formedness of term-level objects in Compact. 

We define the following alias to describe variable bindings with well
formed types, simply by having a finite mapping from names to a tuple
consisting of a type and a proof that it is well-formed under `Δ`.

There

1. definitions of user-defined types, such as structs and enums,

2. declared witnesses that are in scope,

3. declared circuits that are in scope,

4. available kernel operations, i.e., ADT operations and operations
   that interact with the ZSwap ledger,

5. external contracts that the contract may interact with, and

6. variables bound by `const` expressions or in a circuit header. 


To simplify the definition of the typing rules at least somewhat,
we'll require as much as possible that this contextual information is
well-formed wherever applicable.

### Variables 

Sets of bound variables are represented by a finite mapping between
names and a tuple of a type and a proof that it is well-formed under
type context `Δ`.

```agda 
Variables
  : TypeContext
  → Set
Variables Δ
  = Name ↦ ⊢Type Δ 


rename-vars
  : ∀ {vs us}
  → Renaming (Δ .variables) vs
  → Renaming (Δ .userTypes) us
  → Variables Δ → Variables [ Δ ↦ us ∣ vs ]
rename-vars ρv ρu [] = []
rename-vars ρv ρu ((name , t) ∷ vs) = (name , renameT ρv ρu t) ∷ rename-vars ρv ρu vs

rename-map
  : ∀ {K vs us} {P : TypeContext → Set}
  → ⦃ RenameT P ⦄
  → Renaming (Δ .variables) vs
  → Renaming (Δ .userTypes) us
  → K ↦ P Δ → K ↦ P [ Δ ↦ us ∣ vs ]
rename-map ρv ρu [] = []
rename-map ρv ρu ((k , v) ∷ xs) = (k , renameT ρv ρu v) ∷ rename-map ρv ρu xs

variable v∗ v∗₁ v∗₂ v∗′ : Variables Δ 
```

### Kernel Operations 

Kernel operations (i.e., that interact with the ZSwap ledger or ledger
ADTs) are given by a `Callable` object (which itself stores
well-formedness proofs about the signature). For ADT operations, to
retrieve the callable(s) of a given ADT we must supply a proof that it
is a declared ledger type in `Δ`.

Along with the callables corresponding with the operations on that
ADT, we get a proof that the type parameters of the ADT match the type
parameters of the returned callable. For instance, the `insert`
function of the `Set` ADT is returned as a generic circuit with one
type parameter corresponding to the type of values stored in the set.

```agda
record Kernel (Δ : TypeContext) : Set where
  field
    kernel
      : Name ↦ Callable Δ
    adt-ops
      : ∀ adt → adt ∈ Δ .ledgerTypes
              → Name ↦
                  Σ[ κ ∈ Callable Δ ] κ .params .proj₁ ≡ adt .proj₂
```
<!-- 
```agda 
open Kernel public
```
--> 

### User-Defined Types 

Which information we need to store for a user-defined type depends on
whether it is a structure or an enum.

```agda 
Usertype
  : TypeContext
  → Decl
  → Set
Usertype Δ enum
  = List  String
Usertype Δ (struct type-param∗)
  = Variables (type-param∗ ⋊ Δ) 
```

For enums, we keep a list of names, describing the elements in the
enum. For structs, we keep a set of variables, storing the names and
types of the fields of the struct. The fields of a struct should be
well-formed with respect to the surrounding type context `Δ` extended
with the generic type parameters of the struct, since their types may
refer to type variables bound in the structs header.


We define the following structure for storing a collection of
user-defined types. User types are typed with respect to the global
type context to ensure that structure fields can refer to e.g. ledger
ADTs. While the definition of `UTypes` permits cyclic dependencies in
theory, in practice they cannot arise because the context of
user-declared types is constructed in a sequential manner, and there
is no typing rule that allows the definition of a struct whose field
types include a forward reference.

```agda 
data UTypes (Δ : TypeContext)
  : (u : Name ↦ Decl) → Set where
  
  ∅
    : UTypes Δ []

  _∷_
    : ∀ {u}
    → Usertype Δ d
    → UTypes Δ u
    → UTypes Δ ((name , d) ∷ u)
```

**TODO: do we want to witness the inability to create forward
  references constructively in the defintion of UTypes?**.


The set of user types under a type context `Δ` is given by a
`Usertype` for each declared type in `Δ`.

```agda 
Usertypes
  : TypeContext
  → Set
Usertypes Δ
  = UTypes Δ (Δ .userTypes)
```


Finally, we define the following operation that retreives the set of
fields associated with a declared structure type.

```
fields
  : ∀ u
  → (name , (struct type-param∗)) ∈ u
  → UTypes Δ u
  → Variables (type-param∗ ⋊ Δ)
fields (_ ∷ _) (here refl) (field∗ ∷ _)
  = field∗
fields (_ ∷ _) (there px) (x ∷ U)
  = fields _ px U

```

### Contexts 

To bundle all the different kinds of contextual information, we define
contexts as a predicate over type contexts. This allows us to witness,
at the type level, that a context is typed with respect to a
particular type context. This happens, for example, when sequencing
statements, in which case the context may change following a `const`
declaration, but the type context will remain the same.

```agda

record Env (Δ : TypeContext) : Set where
  constructor <<_,_,_,_,_,_>>  
  field
    utypes    : Usertypes Δ
    witnesses : Name ↦ Callable Δ 
    circuits  : Name ↦ Callable Δ
    builtin   : Kernel Δ 
    ext       : Name ↦ (Name ↦ Callable Δ)
    ledger    : Name ↦ LedgerType Δ 

open Env public 

variable nv : Env Δ 

Env′ = ∃ Env

variable η η₁ η₂ η₃ η′ : Env′  

record IsContext (Δ : TypeContext) : Set where
  constructor context 
  field
    env  : Env Δ
    vars : Variables Δ
```

<!-- 
```agda 
open IsContext public
```
-->

In other scenarios it is useful to bundle contexts with their type
context, in which case we use the following alias for the existential
closure of the `IsContext` predicate.

```agda 
Context = ∃ IsContext 
```

### Empty Contexts 

```agda 
εΓ[_·_] : (l∗ : Name ↦ List Type-Param) → (κ : Kernel εΔ[ l∗ ]) → Context
εΓ[ l∗ · κ ] = εΔ[ l∗ ]  , context << ∅ , [] , [] , κ , [] , [] >> [] 
```

We use the following projections to project respectively the type
level and term level contextual information from a bundled context.

```agda 
Δ⟨_⟩
  : Context
  → TypeContext
Δ⟨_⟩
  = proj₁

Δ[_] : Env′ → TypeContext
Δ[_] = proj₁

nv[_] : (η : Env′) → Env Δ[ η ]
nv[_] = proj₂ 

𝓒⟨_⟩
  : (Γ : Context)
  → IsContext Δ⟨ Γ ⟩
𝓒⟨_⟩
  = proj₂

η⟨_⟩ : Context → Env′
η⟨ Γ ⟩ = Δ⟨ Γ ⟩ , 𝓒⟨ Γ ⟩ .env 

```


```agda
<_↦_∣_> : (Γ : IsContext Δ) → Variables Δ → Usertypes Δ → IsContext Δ  
< 𝓒 ↦ vs ∣ U > =
  context << U
          ,  𝓒 .env .witnesses
          ,  𝓒 .env .circuits
          ,  𝓒 .env .builtin
          ,  𝓒 .env .ext
          ,  𝓒 .env .ledger
          >> vs 

<_v↦_> : (Γ : IsContext Δ) → Variables Δ → IsContext Δ
< 𝓒 v↦ vs > = < 𝓒 ↦ vs ∣ 𝓒 .env .utypes > 
```

## Operations on Contexts

We must define several operations on contexts to make sure that they
can be appropriately updated in light of the declaration of new (type)
variables or user types. 

### Renaming 

We start by defining renaming or callable objects. This allows us to
refer to callable objects in a context where additional type variables
or user-declared types are in scope.

```agda
instance
  rename-callable
    : RenameT Callable
rename-callable .RenameT.renameT
  ρv ρu (callable params (mkTy _ wf) args)
  = callable
      (   (params .proj₁)
        , λ x y →
            renameT ρv ρu (params .proj₂ x y) ) 
      (   mkTy _ $
          renameT (rename-++ˡ ρv) (rename-++ˡ ρu) wf )
      (   Data.List.map (λ where (mkTy _ wf) → mkTy _ $ renameT (rename-++ˡ ρv) (rename-++ˡ ρu) wf) args ) 
```

As `Callable` simply store the types and well-formedness proofs of the
callable's argument and return types, renaming proceeds by renaming
the stored proofs. Note that we need to extend the renaming to account
for any type parameters bound by the callable.

Next, we define renaming for the Kernel, which allows kernel
operations to be referenced in contexts with additonal bound
variables, such as the body of a generic circuit. Since kernel
operations are defined as `Callable` objects, we define kernel
renaming by referring to the `Callable` renaming instance defined
above.

```agda 
instance
  rename-kernel
    : RenameT Kernel
rename-kernel .RenameT.renameT
  ρv ρu K
  = record
  { kernel
      = Data.List.map
          ( λ (name , κ) →
              name , renameT ρv ρu κ
          ) ( K .kernel )
  ; adt-ops
      = λ x y →
          Data.List.map
            (λ where
              (name , (κ , refl)) →
                name , renameT ρv ρu κ , refl 
            ) ( K .adt-ops x y )
  }
```

Then, the variables bound in the context may also be renamend. As we
store bound variables with their well-formedness proof, we proceed by
renaming the associated proof for each variable.

And, finally, we also define renaming for user-declared types. 

```agda

instance
  rename-usertype
    : RenameT λ Δ → Usertype Δ d
rename-usertype {enum}     .RenameT.renameT
  ρv ρu xs
  = xs
rename-usertype {struct _} .RenameT.renameT
  ρv ρu v∗
  = rename-vars (rename-++ˡ ρv) (rename-++ˡ ρu) v∗
      
instance
  rename-utypes
    : ∀ {u} → RenameT (λ Δ → UTypes Δ u) 
rename-utypes .RenameT.renameT
  ρv ρu ∅
  = ∅
rename-utypes .RenameT.renameT
  ρv ρu (ut ∷ u)
  = renameT ρv ρu ut ∷ renameT ρv ρu u
```

It is not possible to define general renaming for contexts. The reason
for this is that such as renaming may also add new user types to the
type context, but since the context stores a definition for each
declared user type, this would require us to "invent" definitions for
the user types that are added to the context by a renaming. Luckily,
we do not need renaming for context anywhere.

It is possible, on the other hand, to define a weaker operation that
weakens a context w.r.t. an extension of only the bound type
variables. This operation is used, for example, in defining
well-formedness of module declarations, where the context that
surrounds the module should be propagated into the module, but
extended with any type variables bound in the module header.

```agda
weaken-context : IsContext Δ → IsContext (type-param∗ ⋊ Δ)
weaken-context {type-param∗ = type-param∗}
  (context nv vs) =
  context
    << renameT (∈-++⁺ʳ _) id $ nv .utypes
    ,  (lmap (λ (name , w) → name , renameT ((∈-++⁺ʳ _)) id w) (nv .witnesses) )
    ,  (lmap (λ (name , w) → name , renameT ((∈-++⁺ʳ _)) id w) (nv .circuits) )
    ,  renameT (∈-++⁺ʳ _) id (nv .builtin)
    ,  (lmap (λ (name , xs) → name , lmap (λ (name , e) → name , renameT (∈-++⁺ʳ _) id e) xs) (nv .ext))
    ,  (lmap (λ (name , w) → name , renameT ((∈-++⁺ʳ _)) id w) (nv .ledger) )
    >> (rename-vars(∈-++⁺ʳ _) id vs) 

wk : ∀ type-param∗ → Context → Context
wk type-param∗ Γ = _ , weaken-context {type-param∗ = type-param∗} 𝓒⟨ Γ ⟩ 

```

### Type Declarations

Another important operation on contexts is extension with a newly
declared user type. We define a generic operation for exttending a
context with a newly declared user type, which we later specialize to
separate operations for enum and structure declarations for
convenience.

After declaring a new user type, the type context is extended with a
new user type declaration, as witnessed in the type of
`declareUType`. Declaration proceeds by extending the list of user
declared types, and renaming the other declarations correspondingly. 

```agda 
declareUType
  : (name : Name)
  → Usertype Δ d
  → IsContext Δ
  → IsContext [ Δ u↦ (name , d) ∷ Δ .userTypes ] 
declareUType name ut (context nv vs) =
  context
    << renameT id there (ut ∷ nv .utypes)
    ,  rename-map id there (nv .witnesses)
    ,  rename-map id there (nv .circuits)
    ,  renameT id there (nv .builtin)
    ,  lmap (λ (name , v) → name , rename-map id there v) (nv .ext)
    ,  rename-map id there  (nv .ledger) 
    >> (rename-vars id there vs)
```

Then, the following operations describes the extension of a context
with a new enum type, given by a name (the name of the enum type), and
a list of names (the names of the elements). 

```agda
defineEnum
  : Name
  → List Name
  → (Context → Context) 
defineEnum name elt-name∗
  = λ Γ →
        declareEnum name Δ⟨ Γ ⟩
      , declareUType name elt-name∗ 𝓒⟨ Γ ⟩
```



Similarly, we define an operation `defineStruct` that describes the
extension of a context with a newly declared structure type. It relies
on the following auxiliary operation that converts a set of
well-formed arguments to variables.

```agda 
argToVars
  : (wf : ∀ arg → arg ∈ arg∗ → Δ ⊢arg arg)
  → Variables Δ
argToVars {[]} wf
  = []
argToVars {arg@(unnamed name type) ∷ arg∗} wf
  with wf arg (here refl)
... | ⊢arg' x
  = (name , mkTy type  x) ∷ argToVars λ a → wf a ∘ there
```

Then, to define a new struct, we must supply several pieces of information:

* a list of type parameters bound by the structure type,

* a list of arguments (or, fields), and

* a set of proofs that the fields' types are well-formed.

Crucially, the types of the struct's fields must be well-formed with
respect to the input type context, extended with the type parameters
bound by the structure declaration.

```agda 
defineStruct 
  : Name
  → ( type-param∗ : List Type-Param )
  → ( arg∗        : List Argument )
  → ( Γ           : Context )
  → ( wf          : ∀ arg → arg ∈ arg∗
                          → (type-param∗ ⋊ Δ⟨ Γ ⟩) ⊢arg arg ) 
  → Context 
defineStruct name type-param∗ arg∗ Γ wf
  = declareStruct name type-param∗ Δ⟨ Γ ⟩
  , declareUType name (argToVars wf) 𝓒⟨ Γ ⟩
```

### Adding Binders

Beyond user-defined types, there are several other types of binders
that a context may be extended with:

* variables bound by a `const` declaration,
* declared circuits, or
* declared witnesses.

```agda 
bindVar
  : (Name × ⊢Type Δ)
  → (IsContext Δ → IsContext Δ)
bindVar v
  = λ 𝓒 →
      context
        << (𝓒 .env .utypes)
        ,  (𝓒 .env .witnesses)
        ,  (𝓒 .env .circuits)
        ,  (𝓒 .env .builtin)
        ,  (𝓒 .env .ext)
        ,  (𝓒 .env .ledger)
        >> (v ∷ 𝓒 .vars) 

bindVars
  : Variables Δ
  → (IsContext Δ → IsContext Δ)
bindVars v∗ 𝓒
  = context (𝓒 .env) (v∗ ++ 𝓒 .vars) 

bindCircuit
  : (Name × Callable Δ)
  → (IsContext Δ → IsContext Δ)
bindCircuit ω 
  = λ 𝓒 →
      context
        << (𝓒 .env .utypes)
        ,  (𝓒 .env .witnesses)
        ,  (ω ∷ 𝓒 .env .circuits)
        ,  (𝓒 .env .builtin)
        ,  (𝓒 .env .ext)
        ,  (𝓒 .env .ledger)
        >> (𝓒 .vars) 

bindWitness
  : (Name × Callable Δ)
  → (IsContext Δ → IsContext Δ)
bindWitness w
  = λ 𝓒 →
      context
        << (𝓒 .env .utypes)
        ,  (w ∷ 𝓒 .env .witnesses)
        ,  (𝓒 .env .circuits)
        ,  (𝓒 .env .builtin)
        ,  (𝓒 .env .ext)
        ,  (𝓒 .env .ledger)
        >> (𝓒 .vars) 

bindLDecl
  : (Γ : Context)
  → (Name × LedgerType Δ⟨ Γ ⟩)
  → Context
bindLDecl Γ l
  = let 𝓒 = 𝓒⟨ Γ ⟩ in
    Δ⟨ Γ ⟩ ,
      context
        << 𝓒 .env .utypes
        ,  𝓒 .env .witnesses
        ,  𝓒 .env .circuits
        ,  𝓒 .env .builtin
        ,  𝓒 .env .ext
        ,  (l ∷ 𝓒 .env .ledger)
        >> (𝓒 .vars) 
```

Additionally, we have the following operation that binds a collection
of well-formed arguments in a context.

```agda

_⟨⋊⟩_
  : (∀ arg → arg ∈ arg∗ → Δ ⊢arg arg)
  → IsContext Δ
  → IsContext Δ
wf ⟨⋊⟩ 𝓒
  = context (𝓒 .env) (lmap argToType (⊢-enumerate wf) ++ 𝓒 .vars) 
  where
    argToType
      : ∃[ arg ] Δ ⊢arg arg
      → Name × ⊢Type Δ 
    argToType (unnamed name type , ⊢arg' wf)
      = name , mkTy type  wf

    ⊢-enumerate
      : {A : Set}
      → {P : A → Set}
      → {xs : List  A}
      → (∀ x → x ∈ xs → P x)
      → List  ∃⟨ P ⟩ 
    ⊢-enumerate {xs = []}     wf
      = []
    ⊢-enumerate {xs = x ∷ xs} wf
      = (x , wf x (here refl)) ∷ ⊢-enumerate λ x y → wf x (there y)
```

<!--
```agda 
variable 
  K₁ K₂ K₃ K′    : Kernel Δ 
  𝓒₁ 𝓒₂ 𝓒₃ 𝓒 𝓒′ : IsContext Δ
  Γ₁ Γ₂ Γ₃ Γ Γ′  : Context

map-∈
  : {A B : Set}
  → (xs : List A)
  → ((x : A) → x ∈ xs → B)
  → List B 
map-∈ [] f
  = []
map-∈ (x ∷ xs) f
  = f x (here refl) ∷ map-∈ xs λ x → f x ∘ there

pos : ∀ {a}{A : Set a}{x : A}{xs} → x ∈ xs → ℕ
pos (here refl) = 0
pos (there x)   = suc (pos x)
```
--> 

## Numeric Types

Compact has a notion of "numeric" types that subsume several other
types. It is the class of types that supports arithmetic operations,
such as addition. 

### Definition

Numeric types can be fields or unsigned integers. The inductive
relation `IsNumeric` witnesses that it's type index is a numeric type.

```agda
data IsNumeric {Δ} : (τ : ⊢Type Δ) → Set where
  isField : IsNumeric ⊢field 
  isUint  : IsNumeric (⊢uint₁ ζ)
  -- TODO: other unsigned integer type 
```

We wrap proofs that a type is numeric in the folling record, to be
able to assert numeric constraints using instance arguments.

```agda 
record Numeric (τ : ⊢Type Δ) : Set where
  field
    isNum
      : IsNumeric τ
```

<!-- 
```agda 
open Numeric ⦃...⦄
```
--> 

Additionally, the following predicate asserts that a type is a
well-formed unsigned integer type, but not a field.

```agda 
data UIntType (Δ : TypeContext) : (τ : ⊢Type Δ) → Set where

  isUint
    : ─────────────────────
      UIntType Δ (⊢uint₁ ζ)

  isUint1
    : ∀ {ζ^}
    → ────────────────────────
      UIntType Δ (⊢uint₂ ζ ζ^) 
```

### Computing Bounds 

When performing arithmetic operations on numeric types, if the type is
an unsigned integer type, the size bounds of the value change. The
following operations calculate the numeric type resulting from
combining two numeric types with arithmetic operations.


**TODO: define bound computation** 

Sketch: 

* Field + anything = Field
* Uint + Uint = Unit, with updated bounds
* How do we combine the differnt uints? 


```agda
_⟨+⟩_
    : (τ₁ τ₂ : ⊢Type Δ)
    → ⦃ Numeric τ₁ ⦄
    → ⦃ Numeric τ₂ ⦄
    → ⊢Type Δ
_ ⟨+⟩ _ = ⊢undeclared  
    
_⟨*⟩_
  : (τ₁ τ₂ : ⊢Type Δ)
  → ⦃ Numeric τ₁ ⦄
  → ⦃ Numeric τ₂ ⦄
  →  ⊢Type Δ
_ ⟨*⟩ _ = ⊢undeclared 

_⟨-⟩_
  : (τ₁ τ₂ : ⊢Type Δ)
  → ⦃ Numeric τ₁ ⦄
  → ⦃ Numeric τ₂ ⦄
  → ⊢Type Δ 
_ ⟨-⟩ _ = ⊢undeclared

```

### Type Casts

Compact supports two types of casts between values of different types. 

1. If `type₁ ⊑ type₂`, then we can cast a term of type `type₁` to a
   term of type `type₂` using the `as` construct. Furthermore, in some
   places, an implicit cast is inserted if we provide a term that has
   a sub-type of the expected type at that position. For example, when
   creating a vector literal of type `Vector[ n , T ]`, we must supply
   `n` expressions `exprᵢ : Tᵢ` where `Tᵢ ⊑ T` for `0 ≤ i ≤ n`.

2. Compact allows some casts between types that are not necessarily
   related by the subtyping relation. These must be explicityly cast
   using the `as` construct.


The `Castable` relation defines which types can be cast outside the
subtyping relation. Note if `T₁ ⊑ T₂` then `T₁` is automatically
castable to `T₂`.

**TODO: convert the casting table in the language ref to the relation
  below**.

```agda
data Castable (τ₁ τ₂ : ⊢Type Δ) : Set where

  cast-⊑
    : τ₁ ⊑-⊢ τ₂
      ──────────────
      Castable τ₁ τ₂ 
```

_Note: we could consider also allowing "downcasting" along the
subtyping relation. Assuming a `Set` semantics of types and
interpretation of subtyping as section/retraction pairs, there should
always be a well-defined partial function from a type to all its
sub-typed_.

### Sequencing of Judgments

Several judments in the typng relation have the form `Γ ⊢ <TERM> ⊣
Γ′`, where `Γ` and `Γ′` capture the contextual information
respectively before and after some term-level object `<TERM>`. For
example, when declaring a new circuit the context after the circuit is
updated to include the newly-declared circuit. This way, other program
elements that succede the circuit declaration can reference it. 

The `Sequence` relation transformer provides a general way of
sequencing judgments that describe a context transformation,
transforming a relation over some index `I` (with two additional
positions for the before- and after-context) into a relation over a
list of `I`s. Given a judgment `P : Context → I → Context → Set`,
where a proof `P Γ i Γ′` witnesses that `i` is well-formed under
context `Γ` and updates to context `Γ′`, a proof `Sequence P xs Γ Γ′`
witnesses that all `i ∈ xs` are well-formed w.r.t. `P` under context
`Γ` and updating to context `Γ′`.

```agda
Sequence
  : {I : Set} 
  → (P : Context → I → Context → Set)
  → List I
  → (Γ Γ′ : Context)
  → Set
Sequence P [] Γ Γ′
  = Γ ≡ Γ′ 
Sequence P (i ∷ []) Γ Γ′
  = P Γ i Γ′
Sequence P (i ∷ j ∷ xs) Γ Γ′
         = ∃ λ Γ′′ → P Γ i Γ′′ × Sequence P (j ∷ xs) Γ′′ Γ

```

Well-formedness of such sequence is witnessed by having a sequence of
proofs of `P`, where the "intermediate" contexts are existentially
quantified and required to match. That is, we prove `Sequence P [ i₁ ,
i₂ ] Γ Γ′` by showing that there exists some `Γ′′` such that `P Γ i₁
Γ′′` and `P Γ′′ i₂ Γ′` both hold. The definition of `Sequence` above
generalizes this principle to sequences of arbitrary length.



```agda
Struct
  : Context → Set
Struct Γ
  = ∃[ name ] ∃[ type-param∗ ] (name , struct type-param∗) ∈ Δ⟨ Γ ⟩ .userTypes

getParams : ∃[ Γ ] Struct Γ → List Type-Param
getParams (_ , name , type-param∗ , px) = type-param∗
```

<!--
```agda
mutual  
```
-->




# Typing Rules

Before setting out to define the typign rules of term-level objects in
Compact, we highlight the use of modal possibility to capture the
pattern where sub-terms can have _any subtype_ of some type, rather
than being restricted to some _exact_ type. That is, we write `◇ P
type` to indicate that we have a proof `P type′` for any `type′ ⊑
type`. This so-called _diamond_ or _possibility_ modality for
predicates over types unfolds as follows.

  `◇ P type ≜ ∃ type′ . P type′ ∧ type′ ⊑ type`
  
By using the possibility modality to declare where subtypes are
allowed results in an _algorithmic_ presentation of the typing rules,
in the sense that the rules are explict about when implicit casts from
sub-types to super-types are inserted. The benefit of this is that we
can maintain a _syntax-directed_ or _deterministic_ definition of the
type system, meaning that for every syntactic construct there is at
most one inference rule that could be used at the root of the proof
tree. The alternative would be to have a separate rule for subtype
casting. While this would be an equivalent formulation of the system,
it simultaneously makes it harder to relate the type system to the
untyped syntax as well as leaving it unclear where subtype casts ought
to be inserted.

## Pattern Argument Declaration

Pattern argument
declarations are well-formed with respect to a type context `Δ`.

```agda
  infix 5 _⊢parg_⦂_
  data _⊢parg_⦂_ (η : Env′)
    : Pattern-Argument
    → ⊢Type Δ[ η ] × Variables Δ[ η ]
    → Set where

    ⊢parg'
      : ∀ v∗
      → η ⊢pat pat ⦂ (τ , v∗) 
        ──────────────────────────────────────
        η ⊢parg unnamed pat (τ .ty) ⦂ (τ , v∗)

  record PatArg (η : Env′) : Set where
    pattern 
    constructor mkPatArg
    field
      pat-arg                           : Pattern-Argument
      pat-type                          : ⊢Type Δ[ η ]
      boundVars                    : Variables Δ[ η ] 
      well-formed-pattern-argument : η ⊢parg pat-arg ⦂ (pat-type , boundVars) 

  variable ψ ψ₁ ψ₂ ψ₃ ψ′ : PatArg η
           ψ∗ : List (PatArg η) 

  collect-vars : (Γ : Context) → List (PatArg η⟨ Γ ⟩) → Variables Δ⟨ Γ ⟩
  collect-vars _ = foldr (λ ψ → ψ .PatArg.boundVars ++_) []

  bindPats : (Γ : Context) → List (PatArg η⟨ Γ ⟩) → Context
  bindPats Γ ψ∗ = Δ⟨ Γ ⟩ , bindVars (collect-vars Γ ψ∗) 𝓒⟨ Γ ⟩

  pat-erase : PatArg η → Pattern-Argument
  pat-erase = PatArg.pat-arg

  pat-erase∗ : List (PatArg η) → List (Pattern-Argument)
  pat-erase∗ = lmap pat-erase

  pat→type : PatArg η → ⊢Type Δ[ η ] 
  pat→type = PatArg.pat-type

  pat→type∗ : List (PatArg η) → List (⊢Type Δ[ η ])
  pat→type∗ = lmap pat→type

```

## Expressions

### Well-Formed Expressions



```agda
  record ⊢Expr (Γ : Context) (τ :  ⊢Type Δ⟨ Γ ⟩) : Set where
    inductive 
    constructor mkEx 
    field
      ex                     : Expression 
      well-formed-expression : Γ ⊢expr ex ⦂ τ 

  ↓[_]  : ∀ {τ : ⊢Type Δ′} {f : ⊢Type Δ′ → ⊢Type Δ⟨ Γ ⟩ } → ◇ (⊢Expr Γ ∘ f) τ → Expression 
  ↓[_] = ⊢Expr.ex ∘ px

  ↓[_]∗ : ∀ {τ∗ : List (⊢Type Δ′)} {f : ⊢Type Δ′ → ⊢Type Δ⟨ Γ ⟩ } → All (◇ (⊢Expr Γ ∘ f)) τ∗ → List Expression 
  ↓[_]∗ = reduce ↓[_]

  h = head
  t = tail 

  variable ε₁ ε₂ ε′ ε : ⊢Expr Γ τ 
```

Compact expresions are well-formed with respect to a context `Γ`, and
the type of the expression.

```agda
  data _⊢expr_⦂_ (Γ : Context)
    : Expression
    → ⊢Type Δ⟨ Γ ⟩ 
    → Set where
```

### Literals

Literals in compact can be booleans, fields or byte vectors. They are
trivially well-formed.

```agda
    ⊢expr-quote′
      : ───────────────────────────────────────
        Γ ⊢expr quote′ (inj₂ Bool.true) ⦂ ⊢bool
```

### Variable References

A variable references are well-formed if the referenced name points to
a well-formed type in the variable set stored in `Γ`.

```agda
    ⊢expr-var-ref
      : (name , τ) ∈ 𝓒⟨ Γ ⟩ .vars
        ────────────────────────
        Γ ⊢expr var-ref name ⦂ τ 
```

### Default Values

Default expressions are well-formed if the referenced ADT type is
well-formed under the type context associated with `Γ`.

```agda
    ⊢expr-default
      : (τ : ⊢Type Δ⟨ Γ ⟩) 
      → ───────────────────────────
        Γ ⊢expr default (τ .ty) ⦂ τ 
```

### Conditionals (if-then-else)

A conditional expression `if <expr> then <expr> else <expr>` is
well-formed if

* the condition expression has type boolean,
* the branches are well-formed with types `type₁` and `type₂`
  respectively, and
* `type₁`, `type₂`, and their maximum are well-formed types.

The type of the conditional expression is the maximum of `type₁` and
`type₂`. Or, in other words, it must be the case that `type₁ ⊑ type₂`
or `type₂ ⊑ type₁`, with the type of the expression being either
`type₁` or `type₂` depending on which holds.

```agda                     
    ⊢expr-if
      : Γ ⊢expr expr ⦂ ⊢bool
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → τ .ty ≡-max⟨ τ₁ .ty , τ₂ .ty ⟩ 
        ───────────────────────────────
        Γ ⊢expr if expr expr₁ expr₂ ⦂ τ 
```
### TODO 

```agda
    -- TODO: what are these? 
    ⊢expr-elt-ref         : Γ ⊢expr elt-ref expr name ⦂ τ
    ⊢expr-elt-call   : Γ ⊢expr elt-call expr name expr∗ ⦂ τ 
```

## Assignment Expressions

There are three types of assignment, "normal" assignment, increment
assignment, and decrement assignment.

```agda
    ⊢expr-=′ : Γ ⊢expr =′ expr₁ expr₂ ⦂ ⊢tuple []

    ⊢expr-+= : Γ ⊢expr += expr₁ expr₂ ⦂ ⊢tuple []

    ⊢expr--= : Γ ⊢expr -= expr₁ expr₂ ⦂ ⊢tuple [] 
```

### Vector Literals 

A vector literal expression is well-formed if the type of stored
values, `type`, is well-formed, and we have `n` well-formed
expressions with a sub-type of `type` where `n` is the length of the
vector.

```agda
    ⊢expr-tuple
      : ( ε∗ : All (◇ (⊢Expr Γ)) τ∗ ) 
      → ──────────────────────────────────
        Γ ⊢expr tuple ↓[ ε∗ ]∗ ⦂ ⊢tuple τ∗
```

```agda
    ⊢expr-vector
      : ( ε∗ : All (◇ (⊢Expr Γ)) (replicate n τ) )
      → ─────────────────────────────────────────────
        Γ ⊢expr tuple ↓[ ε∗ ]∗ ⦂ ⊢vector (⊢quote n) τ
```

### Vector Indexing 

A vector index expression is well-formed if the indexed expression is
well-formed with a vector type whose value type and size are
well-formed.

**TODO: static bounds checking?**

```agda 
    ⊢expr-tuple-ref
      : (ε : ⊢Expr Γ (⊢tuple τ∗))
      → (px : τ ∈ τ∗)   
      → ────────────────────────────────────────────
        Γ ⊢expr tuple-ref (ε .⊢Expr.ex) (toℕ px) ⦂ τ

    ⊢expr-vector-ref
      : (ε : ⊢Expr Γ (⊢vector (⊢quote n) τ))
      → (i : Fin n) 
      → ────────────────────────────────────────────
        Γ ⊢expr tuple-ref (ε .⊢Expr.ex) (Ftoℕ i) ⦂ τ
```

### Arithmetic Operations

The typing rules for addition, subtraction, and multiplication
expressions all follow the same pattern. They are well-formed if

1. the types of both sub-expressions are numeric types,
2. the types of both sub-expressions are well-formed, and
3. both sub-expressions are well-formed.

The type of the resulting expression depends on the input types, and
which operation we use. That is, when operating on unsigned integer
types, the size bound of the resulting expression depends on which
operation we used. For example, when adding two unsigned integers, we
take the sum of their size bounds. 

```agda
    ⊢expr-+
      : ⦃ _ : Numeric τ₁ ⦄
      → ⦃ _ : Numeric τ₂ ⦄
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂ 
        ───────────────────────────────────
        Γ ⊢expr + expr₁ expr₂ ⦂ (τ₁ ⟨+⟩ τ₂) 
        
    ⊢expr--
      : ⦃ _ : Numeric τ₁ ⦄
      → ⦃ _ : Numeric τ₂ ⦄
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂ 
        ───────────────────────────────────
        Γ ⊢expr - expr₁ expr₂ ⦂ (τ₁ ⟨-⟩ τ₂)
        
    ⊢expr-*
      : ⦃ _ : Numeric τ₁ ⦄
      → ⦃ _ : Numeric τ₂ ⦄
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂ 
        ───────────────────────────────────
        Γ ⊢expr * expr₁ expr₂ ⦂ (τ₁ ⟨*⟩ τ₂)
```

### Boolean Operations 

All boolean expressions are well-formed with the boolean type if their
sub-expression(s) are also well-formed with the boolean type.

```agda
    ⊢expr-or
      : Γ ⊢expr expr₁ ⦂ ⊢bool
      → Γ ⊢expr expr₂ ⦂ τ
      → tboolean ⊑ τ .ty 
        ──────────────────────────
        Γ ⊢expr or expr₁ expr₂ ⦂ τ 
        
    ⊢expr-and
      : Γ ⊢expr expr₁ ⦂ ⊢bool
      → Γ ⊢expr expr₂ ⦂ τ
      → tboolean ⊑ τ .ty 
        ───────────────────────────────
        Γ ⊢expr and expr₁ expr₂ ⦂ τ
        
    ⊢expr-not
      : Γ ⊢expr expr ⦂ ⊢bool
        ────────────────────────
        Γ ⊢expr not expr ⦂ ⊢bool
```

### Comparison Operations 

All typing rules for comparison operators that compare for inequality
follow the same pattern. Both sub expressions are required to be
well-formed w.r.t. some well-formed unsigned integer
type. Furthermore, we must be able to relate the types of the
sub-expressions using the subtyping relation. Comparison operations
have the boolean type.

```agda
    ⊢expr-<
      : UIntType (Δ⟨ Γ ⟩) τ₁
      → UIntType (Δ⟨ Γ ⟩) τ₂
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂ 
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
      → ─────────────────────────────
        Γ ⊢expr < expr₁ expr₂ ⦂ ⊢bool
        
    ⊢expr-<=
      : UIntType (Δ⟨ Γ ⟩) τ₁
      → UIntType (Δ⟨ Γ ⟩) τ₂ 
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
        ─────────────────────────────────
        Γ ⊢expr <= expr₁ expr₂ ⦂ ⊢bool
        
    ⊢expr->
      : UIntType (Δ⟨ Γ ⟩) τ₁
      → UIntType (Δ⟨ Γ ⟩) τ₂ 
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
        ─────────────────────────────
        Γ ⊢expr > expr₁ expr₂ ⦂ ⊢bool 
        
    ⊢expr->=
      : UIntType (Δ⟨ Γ ⟩) τ₁
      → UIntType (Δ⟨ Γ ⟩) τ₂ 
      → Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
        ──────────────────────────────
        Γ ⊢expr >= expr₁ expr₂ ⦂ ⊢bool 
```

When comparing two expressions for equality, both sub-expressions must
be well-formed w.t.r. a well-formed typed. Furthermore, we must be
able to relate the types of the sub-expressions using the subtyping
relation. The resulting expression has the boolean type. 

```agda 
    ⊢expr-==
      : Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
        ──────────────────────────────
        Γ ⊢expr == expr₁ expr₂ ⦂ ⊢bool 
        
    ⊢expr-!=
      : Γ ⊢expr expr₁ ⦂ τ₁
      → Γ ⊢expr expr₂ ⦂ τ₂
      → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ )
        ──────────────────────────────
        Γ ⊢expr != expr₁ expr₂ ⦂ ⊢bool  
```

### Map Expressions

Map expressions allow us to apply a circuit to all elements in a
vector. Map expressions in Compact furthermore allow a multi-argument
circuit to be mapped over a series of vectors, whose value type should
match the corresponding argument type of the circuit. 

A map expression of the form `map <fun> <expr> <expr*>` is well-formed if:

* the function object `fun` is well-formed w.r.t. the context `Γ` and
  whose number of arguments matches the number of vector expressions
  (`wf₁` and `eq`),
  
* `tsize` is a well-formed size-expression (`wf₂`), and

* for each argument of the function object, we have a well-formed
  expression with a vector type with length `tsize` whose value type
  is a well-formed _sub-type_ of the expected argument type at that
  position when substituting for free occurences of type variables
  bound by the function object `fun` (`wf₃`). 

The resulting expression has a vector type with size `tsize` and value
type given by the return type of the function object `fun` with free
occurences of type variables bound by the circuit substituted for
their instantiation.

```agda
    ⊢expr-map
      : ( fn  : ⊢Fun Γ )
      → ( ε₁ : ◇ (⊢Expr Γ ∘ ⊢vector ζ) τ₁ )
        ( ε∗ : All (◇ (⊢Expr Γ ∘ ⊢vector ζ)) τ∗ )
      → argsT fn ≡ τ₁ ∷ τ∗ 
        ─────────────────────────────────────────────────────────────
        Γ ⊢expr map f[ fn ] ↓[ ε₁ ] ↓[ ε∗ ]∗ ⦂ ⊢vector ζ (returnT fn)
```

We enforce that the amount and type of sub-expressions of a map
expression match the "shape" of the function object that we are
mapping with constructively. That is, the vector sub-expressions of a
map expressions are defined to be the (untyped) expressions we get by
projecting out of the proof object `wf₃`, which witnesses that we have
a matching well-formed vector-expression for each of the arguments 
`fun`.

### Fold Expressions 

Fold expressions allow us to aggregate the values in a vector or
series of vectors using a given function object. A fold epxression
takes a function object that describes how results should be
aggregated, a base expression describing a seed or initial value
(i.e., how to aggregate the results in an empty vector), and one or
more vector, depending on the type signature of the function we are
folding with.

A fold expression in Compact is well-formed if:

* `fun` is a well-formed function object under the context `Γ` (`wf₁`),

* `tsize` is a well-formed vector expression (`wf₂`),

* `fun` has at least 2 arguments (`eq₂`),

* for each argument to `fun`, except the 1st one, we have a
  well-formed expression with a vector type with length `tsize` whose
  value type is a well-formed _sub-type_ of the expected argument type
  at that position when substituting for free occurences of the
  variables bound by `fun` (`wf₃`),

* the expression corresponding to the initial value of the
  computation, `expr′`, is well-formed w.r.t. the context `Γ` and has
  a sub-type of the return type of `fun` with its type variables
  instantiated (`wf₄`),

* The first argument of `fun` matches its return type (`eq₂`). 

The resulting expression has the return type of `fun`, with a
substitution applied to instantiate any type variables bound by `fun`. 

```agda
    ⊢expr-fold
      : ( fn     : ⊢Fun Γ )
        ( ε-init : ◇ (⊢Expr Γ) (returnT fn) )
        ( ε₁     : ◇ (⊢Expr Γ ∘ ⊢vector ζ) τ )
        ( ε∗     : All (◇ (⊢Expr Γ ∘ ⊢vector ζ)) τ∗ )
      → argsT fn ≡ returnT fn ∷ τ ∷ τ∗ 
        ──────────────────────────────────────────────────────────────
        Γ ⊢expr fold f[ fn ] ↓[ ε-init ] ↓[ ε₁ ] ↓[ ε∗ ]∗ ⦂ returnT fn
```

Again, we ensforce that the input vector(s) match the argument types
of `fun` by projecting the untyped syntax out of the well-formedness
proof `wf₃`.


### "Function" Calls 

Compact supports a uniform syntax for invoking different kinds of
"function-like" objects, such as witnesses, circuits, or ADT
operations. A call to a "function-like" object is well-formed if

* the referenced function object, `fun`, is well-formed under context
  `Γ` (`wf₁`), and

* For each argument to `fun`, we have a well-formed expression with a
  sub-type of the expected type at that position (`wf₂`) with a
  substitution applied that instantiates any type variables bound by
  the function object.



```agda
    ⊢expr-call
      : ( fn : ⊢Fun Γ )
        ( ε∗ : All (◇ (⊢Expr Γ)) (argsT fn) ) 
      → ──────────────────────────────────────────
        Γ ⊢expr call f[ fn ] ↓[ ε∗ ]∗ ⦂ returnT fn
```

The argument expressions are defined by projecting from the
well-formedness proof `wf₂`.


### Structure Creations

In Compact, values of structure types can be created by supplying an
expression for each field of the struct. Additionally, we must supply
instantiations for any type variables bound by the struct.

A `new` expression (creating a new value of a structure type) is
well-formed if:

* the referenced structure name is a known declared struct (`px`)

* the given type arguments (`targ∗`) match the type parambers bound by
  the structure (`m`),

* for each type argument in `targ∗`, we have a proof that it is
  well-formed (`wf`), and

* we have a set of well-formed arguments matching with the
  fields of the struct (`args`) .

The arguments can be supplied either by giving named or positional
arguments corresponding to each field of the struct, or through a
spread expression. The precise meaning of these is defined in the
`StructArgs` and `Spread` predicates, which we will discuss later.


```agda
    ⊢expr-new
      : ( τ?∗ : List (Maybe (⊢Type Δ⟨ Γ ⟩)))
      → ( px : (name , struct type-param∗) ∈ Δ⟨ Γ ⟩ .userTypes )
      → ( m  : Match-Param-Arg∗ type-param∗ targ∗ )
      → ( wf : All (Δ⟨ Γ ⟩ ⊢targ_) targ∗ ) 
      → let σ = args-subst wf m in
        --      ^ a substitution that describes the instantiation of
        --        type paramters bound by the structure.
        ( args : All (⊢New-Field (Γ , name , type-param∗ , px)) τ?∗)
        -- TODO: well-formedness of argument list wrt struct type 
      → ────────────────────────────────────────────────────────────────
        Γ ⊢expr new (type-ref name targ∗) ↓[ args ]nf∗
            ⦂ ⊢ref (⊢tref-type-ref (struct (type-param∗ , (px , m))) wf) 
```

### Sequencing

Expressions can be sequenced for their effects. A sequence of
expressions is well-formed if all expressions in the sequence are
well-formed, with the same type.

-- TODO: should this be the same type or can it be a sub-type? 

```agda
    ⊢expr-seq
      : (ε∗ : All (◇ (⊢Expr Γ)) (replicate n τ)) 
      → Γ ⊢expr expr ⦂ τ
        ──────────────────────────────────────── 
        Γ ⊢expr seq ↓[ ε∗ ]∗ expr ⦂ τ
```

### Explicit Casts 

A cast expression is well-formed if the source and target types are
well-formed, as well as the expression we want to cast. Furthermore,
the source and target types should be related by the `Castable`
relation, which defines which types, that are not in the sub-type
relation, can be casted.

**TODO: do we allow casting along the subtype relation here as well?**

```agda
    ⊢expr-cast
      : Γ ⊢expr expr ⦂ τ′
      → Castable τ′ τ
        ─────────────────────────────
        Γ ⊢expr cast (τ .ty) expr ⦂ τ
```

### Disclose

```agda
    ⊢expr-disclose
      : Γ ⊢expr expr ⦂ τ
        ─────────────────────────
        Γ ⊢expr disclose expr ⦂ τ
```

### Assert 

An assert expression is well-formed if the given expression is
well-formed with the `tboolean` type.

```agda
    ⊢stmt-assert
      : ∀ msg
      → (ε : ⊢Expr Γ ⊢bool)
      → ──────────────────────────────────────────── 
        Γ ⊢expr assert (ε .⊢Expr.ex) msg ⦂ ⊢tuple [] 
```

## Patterns

```agda
  data _⊢pat_⦂_ (η : Env′)
    : Pattern
    → ⊢Type Δ[ η ] × Variables Δ[ η ]
    → Set where
```

```agda
    ⊢pattern-var
      : ───────────────────────────────────────────
        η ⊢pat var-name name ⦂ (τ , [ name , τ ])
```

```agda
    ⊢pattern-tuple
      : ∀ pat?∗ v∗s
      → (wf : Pointwise
                (λ pat? (τ , v∗) → maybe′ (η ⊢pat_⦂ (τ , v∗)) ⊤ pat?)
                pat?∗ (zip τ∗ v∗s))
      → ─────────────────────────────────────────────────────────────
       η ⊢pat tuple pat?∗ ⦂ (⊢tuple τ∗ , concat v∗s)
```


```agda
    ⊢pattern-struct
      : ( px : (name , struct type-param∗) ∈ Δ[ η ] .userTypes )
      → ( m  : Match-Param-Arg∗ type-param∗ targ∗ )
      → ( wf₁ : All (Δ[ η ] ⊢targ_) targ∗ )
      → let σ = args-subst wf₁ m in
        --      ^ a substitution that describes the instantiation of
        --        type paramters bound by the structure.
        ( wf₂ : List
                  ( ∃₂ λ pat name →
                      ∃[ τ ]
                          ((name , τ) ∈ fields _ px (nv[ η ] .utypes))
                        × ∃[ v∗ ] (η ⊢pat pat ⦂ (substT (subst-⋊ _ σ) τ , v∗))
                  ))
      → ──────────────────────────────────────────────────────────────────────
        η ⊢pat struct (lmap (λ (pat , name , _) → pat , name) wf₂)
          ⦂ (⊢ref (⊢tref-type-ref (struct (type-param∗ , px , m)) wf₁)
          , concat (lmap (λ (_ , _ , _ , _ , v∗ , _) → v∗) wf₂))
```




## New Fields

When constructing a value of a structure type in Compact, we have to
supply a set of field expressions. These can be either a named or
positional argument corresponding to a particular field, or a spread
expression.

Field expressions are typed under a tuple of a context `Γ` and struct
type `T` (the struct for which we are supplying fields), and maybe a
type. That is, in case of a named or positional field expression, the
judgment records the type of the expression, which coincides with the
type of the corresponding field. For spread expressions, we only need
the type of the struct we are constructing.

```agda
  data _⊢new-field_⦂_ (Γ×T : ∃[ Γ ] Struct Γ)
     : New-Field
     → Maybe (⊢Type Δ⟨ Γ×T .proj₁ ⟩)
     → Set where
```

### Spread expressions

A spread field expression is well-formed if we have a well-formed
expression with a struct type that matches with the struct associated
with the field expression, and whose type arguments match the type
parameters of this struct.

```agda
    ⊢new-field-spread
      : ( m   : Match-Param-Arg∗ (Γ×T .proj₂ .proj₂ .proj₁) targ∗)
      → ( wf₁ : All (_ ⊢targ_) targ∗)   
      → let struct-type =
              ⊢ref (⊢tref-type-ref
                 (struct ( Γ×T .proj₂ .proj₂ .proj₁
                         , Γ×T .proj₂ .proj₂ .proj₂
                         , m )
                         ) wf₁) in
        --  ^ the (well-formed) type of the struct type we are
        --  consructing
        (ε : ⊢Expr (Γ×T .proj₁) struct-type  ) 
      → ───────────────────────────────────────────────
        Γ×T ⊢new-field (spread (ε. ⊢Expr.ex)) ⦂ nothing 
```

### Named and positional fields

Named and positional field expressions are well-formed if we have a
well-formed expression whose type matches the expected type for the
field in question.

```agda
    ⊢new-field-positional
      : (ε : ⊢Expr (Γ×T .proj₁) τ)
      → ─────────────────────────────────────────────────
        Γ×T ⊢new-field (positional (⊢Expr.ex ε)) ⦂ just τ 

    ⊢new-field-named
      : (ε : ⊢Expr (Γ×T .proj₁) τ)
      → ─────────────────────────────────────────────────
        Γ×T ⊢new-field (named name (⊢Expr.ex ε)) ⦂ just τ
```

```agda
  record ⊢New-Field (Γ×T : ∃[ Γ ] Struct Γ ) (τ? : Maybe (⊢Type Δ⟨ Γ×T .proj₁ ⟩)) : Set where
    inductive
    constructor mkNF
    field
      nf : New-Field
      well-formed-new-field : Γ×T ⊢new-field nf ⦂ τ?

  ↓[_]nf : ∀ {Γ×T τ?} → ⊢New-Field Γ×T τ? → New-Field
  ↓[_]nf = ⊢New-Field.nf

  ↓[_]nf∗ : ∀ {Γ×T xs} → All (⊢New-Field Γ×T) xs → List New-Field
  ↓[_]nf∗ = reduce ↓[_]nf 
```

## Structure Construction

To describe the set of arguments given when constructing a new value
of a structure type, we define two predicates:

* `StructArgs`, describing a list of well-formed field expressions
  that contains exactly one name or positional field expression for
  each field in the structure type, and

* `Spread`, describing a list of well-formed field expressions that
  starts with a spread expression, following by a tail that has at
  most one named or positional field expression for each field of the
  struct.

## Ledger Constructors

Ledger constructors initialize the contract state. As the ledger
constructor is a "program element" (i.e., a top level declaration), we
maintain the same shape of judgment as for other program elements,
which are typed w.r.t. a "before" and "after" context that capture how
a program element changes the context. While ledger constructors don't
change the context, we maintain the shape of the judgment for
uniformity of the presenatation. 

**TODO: is it true that ledger constructrs don't alter the global
  context?**

**TODO: should we force that there is at most 1 ledger constructor per
  contract?**

```agda
  data _⊢lconstructor_⊣_ (Γ : Context)
    : Ledger-Constructor
    → (Γ′ : Context)
    → Set where
```

A ledger constructor is well-formed if all its arguments are
well-formed, and its body is a well-formed statement (block) returning
`tvoid`.

**TODO: should there return type of a ledger constructor forced to be
  void?** 

```agda
    ⊢constructor
      : (ψ∗ : List (PatArg η⟨ Γ ⟩)) 
      → (bindPats Γ ψ∗ , ⊢void) ⊢stmt stmt ⊣ v∗
        ─────────────────────────────────────────────────────
        Γ ⊢lconstructor constructor′ (pat-erase∗ ψ∗) stmt ⊣ Γ
```

## External Contract Circuits 

** TODO: should the externally-declared circuit be available to call
   after the declaration?**

```agda
  data _⊢edecl-circuit_⊣_ (Γ : Context)
    : External-Contract-Circuit
    → (Γ′ : Context)
    → Set where

    ⊢edecl-circuit
      : All (Δ⟨ Γ ⟩ ⊢arg_) arg∗ 
        ─────────────────────────────────────────────
        Γ ⊢edecl-circuit unnamed b name arg∗ type ⊣ Γ
```

## Statements

Well-formedness of statements in Compact is defined w.r.t. a tuple
`Γ×R` consisting of the context of all declarations in scope together
with the return type of the current statement block, as well as an
"updated" term level context that is typed under the same type context
as the input context `Γ`. The updated context contains additional
binders that may be added to the context after some statements, such
as `const` declarations. 

```agda
  data _⊢stmt_⊣_ (Γ×R : ∃[ Γ ] ⊢Type Δ⟨ Γ ⟩)
    : Statement
    → Variables Δ⟨ Γ×R .proj₁ ⟩ 
    → Set where
```

### Expression Statements 

All Compact expressions can be used in place where a statement is
expected. This has the result of enacting the effects of evaluating
the expression, while discarding the value that it evaluates to. An
expression statement is well-formed if the expression is well-formed
w.r.t. some well-formed type. A statement expression has the unit
return type (i.e., a vector of length 0); if we intend to return the
result of the expression, we should explicitly use the `return`
keyword instead.

```agda
    ⊢stmt-expr
      : (ε : ⊢Expr (Γ×R .proj₁) τ)
      → Γ×R .proj₂ .ty ≡ tvector (type-size 0) tundeclared --> unit type 
        ─────────────────────────────────────────────────────
        Γ×R ⊢stmt statement-expression (⊢Expr.ex ε) ⊣ [] 
```

### Return Statement

A return statement is well-formed if the returned expression is
well-formed, and the type of the returned expression is a sub-type of
the expected return type as dictated by the surrounding context. 

```agda
    ⊢stmt-return
      : (ε : ◇ (⊢Expr $ Γ×R .proj₁) (Γ×R .proj₂))
      → ─────────────────────────────────────────
        Γ×R ⊢stmt return ↓[ ε ] ⊣ [] 
```



### Constant Binding

A constant binding (or, local variable) is well-formed if

1. the given ADT type (`adt-type`) of the binding is well formed, and

2. the given expression is well-formed w.r.t. the ADT type's
   conversion to a compact type.

After a `const` statement, the term level context is updated to bind a
new variable with the given name and type.

```agda
    ⊢stmt-const
      : ∀ v∗ 
      → η⟨ Γ×R .proj₁ ⟩ ⊢pat pat ⦂ (τ , v∗)
      → (ε : ⊢Expr (Γ×R .proj₁) τ)
      → ──────────────────────────────────────────────
        Γ×R ⊢stmt const pat (τ .ty) (ε .⊢Expr.ex) ⊣ v∗ 
```

### If-then-else Statement

An if-then-else statement is well-formed if the conditional expression
is well-formed with type `tboolean`, and both branches are well-formed
statements.

Both branches of an if-then-else stament may result in (diffrent)
updates to the surrounding context. None of these updates propagate to
surrounding context of the if-then-else statement, since any variables
bound in either of the branches will be out of scope outside the
respective branch.

```agda
    ⊢stmt-if
      : (ε : ⊢Expr (Γ×R .proj₁) ⊢bool) 
      → (𝓢₁ : ⊢Stmt Γ×R v∗₁)
      → (𝓢₂ : ⊢Stmt Γ×R v∗₂) 
      → ───────────────────────────────────────────────────────
        Γ×R ⊢stmt if (ε .⊢Expr.ex) ↓[ 𝓢₁ ]stmt ↓[ 𝓢₂ ]stmt ⊣ []
```

### For Loop

A for-loop is well-formed if the scrutinee is well-formed with a
`tvector` type (with well-formed value type and size expression), and
the body is a well-formed statement with the iteration variable `name`
bound to an unsigned integer type bounded by the size of the vector
expression. The body of the loop may update the term-level context
arbitrarily, but these changes are ignored in the surrounding context.

```agda
    ⊢stmt-for
      : ∀ name 
      → (ε : ⊢Expr (Γ×R .proj₁) (⊢vector ζ τ)) 
      → (𝓢 : ⊢Stmt ((-, bindVar (name , ⊢uint₁ ζ) 𝓒⟨ Γ×R .proj₁ ⟩) , Γ×R .proj₂) v∗) 
      → ───────────────────────────────────────────────────────────────────────────────
        Γ×R ⊢stmt for name (ε .⊢Expr.ex) ↓[ 𝓢 ]stmt ⊣ [] 
```

### Statement Block 

A block of statements is well-formed if all statements in the block
are well-formed, with matching in- and output contexts.

```agda
    ⊢stmt-block
      : (b : Block Γ×R v∗)
      → ────────────────────────────────
        Γ×R ⊢stmt block ↓[ b ]block ⊣ v∗
```

The shape of judgments that define well-formedness of statements is
slightly assymetric, in the sense that the "input" context has an
additional value for the type of values returned by the statement, and
the "output" context is only the projection of the term-level
bindings. This means that we cannot pass the judgment directly to the
`Sequence` transformer, but rather we have to include an additional
equality proof that witnesses that the type context remains invariant
throughout the sequence.

```agda
  record ⊢Stmt (Γ×R : ∃[ Γ ] ⊢Type Δ⟨ Γ ⟩) (v∗ : Variables Δ⟨ Γ×R .proj₁ ⟩) : Set where
    inductive
    constructor mkStmt
    field
      statement : Statement
      well-formed-statement : Γ×R ⊢stmt statement ⊣ v∗

  data Block (Γ×R : ∃[ Γ ] ⊢Type Δ⟨ Γ ⟩) (v∗ : Variables Δ⟨ Γ×R .proj₁ ⟩) : Set where
    empty : Block Γ×R v∗
    cons  : ⊢Stmt Γ×R v∗₁ → Block ((-, bindVars v∗₁ 𝓒⟨ Γ×R .proj₁ ⟩) , Γ×R .proj₂) v∗ → Block Γ×R v∗ 

    
  ↓[_]block : ∀ {Γ×R v∗} → Block Γ×R v∗ → List Statement
  ↓[ empty ]block = []
  ↓[ cons x b ]block = x .⊢Stmt.statement ∷ ↓[ b ]block

  ↓[_]stmt : ∀ {Γ×R v∗} → ⊢Stmt Γ×R v∗ → Statement
  ↓[_]stmt = ⊢Stmt.statement
```

## Structure Definitions

A structure definition is well-formed with respect to input and output
contexts `Γ` and `Γ′`. 

**TODO: the defined structure should be exported based on the boolean
  flag. **

```agda
  data _⊢structdef_⊣_ (Γ : Context)
    : Structure-Definition
    → (Γ′ : Context)
    → Set where
```

The structure definition is then well-formed if

* all declared type parameters are well-formed (`wf₁`), and

* all declared fields are well-formed under the surrounding type
  context extended with the type parameters bound by the structure
  (`wf₂`).

```agda
    ⊢structdef
      : ( wf₁ : ∀ type-param → type-param ∈ type-param∗
                             → Δ⟨ Γ ⟩ ⊢type-param type-param )
      → ( wf₂ : ∀ arg → arg ∈ arg∗
                      → (type-param∗ ⋊ Δ⟨ Γ ⟩) ⊢arg arg )
      → ──────────────────────────────────────────────────────
        Γ ⊢structdef struct b name type-param∗ arg∗
                   ⊣ defineStruct name type-param∗ arg∗ Γ wf₂ 
```

The declared structure type is bound in the output context. 

## Ledger Declarations

A ledger declaration adds a new field to the contract's internal
state. A ledger delcaration is well-formed if the declared type is a
well-formed ADT type. 

**TODO: how do the values of the boolean flags affect the semantics?**

```agda
  data _⊢ldecl_⊣_ (Γ : Context)
    : Ledger-Declaration
    → (Γ′ : Context)
    → Set where
    
    ⊢ldecl
      : (l : LedgerType Δ⟨ Γ ⟩) 
      → ──────────────────────────────────────────────────────────────── 
        Γ ⊢ldecl public-ledger-declaration b₁ b₂ name (l .proj₁ .ty)
          ⊣ bindLDecl Γ (name , l) 
```

## Import Declarations

An import declaration is well-formed if the supplied type arguments
for the module are all well-formed.

**TODO: should the static semantics reflect a requirement that the
  module is in scope? **

**TODO: import declarations should bring exported names from the
  imported module into scope.**

**TODO: should there be a requirement that the the supplied type
  arguments match the modules signature?**

```agda
  data _⊢idecl_⊣_ (Γ : Context)
    : Import-Declaration
    → (Γ′ : Context)
    → Set where
    
    ⊢idecl
      : ( iname : Γ ⊢import-name import-name) 
      → ( ∀ targ → targ ∈ targ∗ → Δ⟨ Γ ⟩ ⊢targ targ )
        ─────────────────────────────────────────────
        Γ ⊢idecl import′ import-name targ∗ name′ ⊣ Γ

```

## Import Names

```agda

  data _⊢import-name_ (Γ : Context)
    : Import-Name
    → Set where

    ⊢import-module
      : ───────────────────────────────
        Γ ⊢import-name module-name name  

    ⊢import-file
      : ────────────────────────
        Γ ⊢import-name file name

```

## Functions reference

Well-formedess of function-like objects is defined with respect to the
surrounding term-level context `Γ`.

```agda
  record ⊢Fun Γ : Set where
    inductive
    constructor mkFun 
    field
      f                    : Function
      well-formed-function : Γ ⊢fun f 

  f[_] : ⊢Fun Γ → Function
  f[ fn ] = ⊢Fun.f fn 
  
  data _⊢fun_ (Γ : Context)
    : Function
    → Set where
```

Syntactically, we distinguish 3 types of function-like objects:

1. references to monomorphic callables (i.e., with 0 generic type
   parameters),

2. references to generic callables (i.e., with 1 or more generic type
   parameters), and

3. anonymous circuits (which are always monomorphic).

The `FRef` predicate (defined below) defines the different ways in
wich we can refer to callable objects in the context.

### Monomorphic Functions 

A reference to a monomorphic callable object is well-formed if the
referenced name maps to a callable `κ` in the context, and this
callable has exactly 0 type parameters.

```agda
    ⊢fun-mono
      : Fun name (𝓒⟨ Γ ⟩ .env) (callable ([] , (λ _ ())) τ τ∗) 
        ─────────────────────────────────────────────
        Γ ⊢fun fref name
```


### Generic Circuits

A reference to a generic callable object is well-formed if the
referenced name maps to a callablew `κ` in the context, the list of
supplied type arguments matches the type parameters of the generic
callable, and all type arguments are well-formed.

```agda
    ⊢fun-gen
      : Fun name (𝓒⟨ Γ ⟩ .env) κ
      → Match-Param-Arg∗ (κ .params .proj₁) targ∗
      → All (Δ⟨ Γ ⟩ ⊢targ_) targ∗ 
        ─────────────────────────────────────────
        Γ ⊢fun fref1 name targ∗ 
```

### Anonymous Circuits 

An anonymous circuit declaration is well-formed if the arguments it
binds (given by the list `arg∗`) are all well-formed, the declared
return type `type` is well-formed, and the body of the circuit is
well-formed with respect to the surrounding context `Γ` extended with
the arguments bound by the circuit declaration.

```agda
    ⊢fun-circuit
      : (ψ∗ : List (PatArg η⟨ Γ ⟩))
      → (τ  : ⊢Type Δ⟨ Γ ⟩ )
      → (𝓢 : ⊢Stmt (bindPats Γ ψ∗ , τ) v∗ )
      → ─────────────────────────────────────────────────
        Γ ⊢fun circuit (pat-erase∗ ψ∗) (τ .ty) ↓[ 𝓢 ]stmt
```

### Function References

There are five different ways we can refer to a callable object in the context:

1. Witness declarations,
2. Circuit declarations,
3. Circuits declared in an external contract,
4. Kernel operations (e.g., `checkpoint()`), or
5. ADT operations (e.g., `Counter.increment()`).

The predicate `FRef` captures these different kinds of references to callable objects. 

```agda

  data Fun (name : Name) (nv : Env Δ) (κ : Callable Δ) : Set where
    fun-witness : (name , κ) ∈ nv .witnesses →  Fun name nv κ
    fun-circuit : (name , κ) ∈ nv .circuits → Fun name nv κ
    -- todo: call to external declaration
    fun-kernel : (name , κ) ∈ nv .builtin .kernel → Fun name nv κ
    
    fun-adt-op
      : ∀ adt 
      → (name , κ , refl) ∈ nv .builtin .adt-ops (name , κ .params .proj₁) adt
      → ∃[ targs ] ∃[ m ] (name′ , _ , is-adt-ref {targ∗ = targ∗} adt m targs) ∈ nv .ledger
      → Fun name nv κ
```

```agda
  κ⟨_⟩ : Γ ⊢fun fun → Callable Δ⟨ Γ ⟩
  κ⟨ fn ⟩ = getc-subst fn .proj₁


  σ⟨_⟩ : (fn : Γ ⊢fun fun) → SubstitutionT [ Δ⟨ Γ ⟩ v↦ κ⟨ fn ⟩ .params .proj₁ ] (Δ⟨ Γ ⟩ .variables)
  σ⟨ fn ⟩ = getc-subst fn .proj₂ 

  returnT : (_ : ⊢Fun Γ) → ⊢Type (Δ⟨ Γ ⟩) 
  returnT fn = ⋊[ σ⟨ fn .⊢Fun.well-formed-function ⟩ ] (κ⟨ fn .⊢Fun.well-formed-function  ⟩ .returns) 

  inst : (fn : Γ ⊢fun fun) → _ 
  inst fn = ⋊[ σ⟨ fn  ⟩ ]

  argsT : (_ : ⊢Fun Γ) → List (⊢Type Δ⟨ Γ ⟩)
  argsT fn = lmap (inst (fn .⊢Fun.well-formed-function )) $ κ⟨ fn .⊢Fun.well-formed-function  ⟩ .args 
```

### Argument Manipulation 

When defining well-formedness of language constructs that interact
with callables, we often need to mediate between matching listst of
parameters and arguments. To aid this, we define several auxiliary
functions.

First, the `fetch-param` allows us to retrieve the matching type
argument for a given type parameter from a list of matching arguments.

```agda
  fetch-param
    : ∀ type-param
    → type-param ∈ type-param∗
    → Match-Param-Arg∗ type-param∗ targ∗
    → ∃[ targ ] targ ∈ targ∗
  fetch-param
    {type-param∗ = nat-valued _ ∷ _} {targ∗ = targ-size _ ∷ _}
    type-param (here refl) (tt ∷ m)
    = _ , here refl
  fetch-param
    {type-param∗ = type-valued _ ∷ _} {targ∗ = targ-type _ ∷ _}
    type-param (here refl) (tt ∷ m)
    = _ , here refl
  fetch-param
    type-param (there px) (x∼y ∷ m)
    with fetch-param _ px m
  ... | targ , px′ = targ , there px′
```

Next, we have the following proofs that if we know that a type
parameter is `nat-valued` or `type-valued`, the corresponding type
argument in a matching list of arguments will have the right shape, in
that it is a quoted natural number if the parameter is `nat-valued`
and a type if it is `type-valued`. 

```agda
  fetch-kind-♯
    : (x : nat-valued name ∈ type-param∗)
    → (m : Match-Param-Arg∗ type-param∗ targ∗)
    → ∃[ n ] fetch-param (nat-valued name) x m .proj₁ ≡ targ-size n  
  fetch-kind-♯ (here refl) (_∷_ {y = targ-size n} tt _)
    = n , refl
  fetch-kind-♯ (there px) (_ ∷ m)
    = fetch-kind-♯ px m
    
  fetch-kind-★
    : (x : type-valued name ∈ type-param∗)
    → (m : Match-Param-Arg∗ type-param∗ targ∗)
    → ∃[ type ] fetch-param (type-valued name) x m .proj₁ ≡ targ-type type 
  fetch-kind-★ (here refl) (_∷_ {y = targ-type t} tt _)
    = t , refl
  fetch-kind-★ (there px) (_ ∷ m)
    = fetch-kind-★ px m
```

Then, the following function retrieves a list of applied type
arguments from a function-like object.

```agda
  get-targ∗
    : (fun : Function)
    → List Type-Argument
  get-targ∗ (fref _)
    = []
  get-targ∗ (fref1 _ targ∗)
    = targ∗
  get-targ∗ (circuit _ _ _)
    = []
```

Finally, the `getc-subst` function takes a well-formedness proof for a
function-like object, and returns the corresponding callable object,
together with a type-level substitution that captures the
instantiation of type variables bound by the function object.

This substitution is necessary to describe, e.g., well-formedness of
function calls. For example, when calling a generic circuit, the type
of the whole expression is the return type of the circuit. But since
any generic type variables bound by the circuit can be referenced in
its return type, we must apply a substitution first that instantiates
the free occurcences of the type parameters of the circuit with the
type argument instantiation for these parameters at that particular
call-site.

```agda
  convert
    : (x : type-param ∈ type-param∗)
    → (m : Match-Param-Arg∗ type-param∗ targ∗)
    → Δ ⊢targ fetch-param type-param x m .proj₁
    → param[ (λ _ → ∃[ size ] Δ ⊢tsize size)
           , (λ _ → ∃[ type ] Δ ⊢type  type)
           ] type-param 
  convert {nat-valued x₁} x m
    with fetch-kind-♯ x m
  ... | n , eq rewrite eq
    = λ where (⊢targ-size m) → (type-size n) , ⊢tsize-quote′ n
  convert {type-valued x₁} x m
    with fetch-kind-★ x m
  ... | type , eq rewrite eq =
    λ where
    (⊢targ-type wf) → type , wf

  getc-subst
    : (wf : Γ ⊢fun fun)
    → Σ[ κ ∈ Callable Δ⟨ Γ ⟩ ] SubstitutionT [ Δ⟨ Γ ⟩ v↦ κ .params .proj₁ ] (Δ⟨ Γ ⟩ .variables)
  getc-subst (⊢fun-mono {τ = τ} {τ∗ = τ∗} _)
    = callable ([] , λ _ ()) τ τ∗ , λ ()
  getc-subst (⊢fun-gen {κ = κ} _ m wf)
    = κ , λ where
            {param} x →
               convert x m (Data.List.Relation.Unary.All.lookup wf (fetch-param _ x m .proj₂) )
  
  getc-subst (⊢fun-circuit ψ∗ τ wf)
    = callable ([] , λ _ () ) τ(pat→type∗ ψ∗) , λ() 
```

## Module Definitions

Module definitions are well-formed with respect to input and output
contexts `Γ` and `Γ′`.

** TODO: modules should collect only the names exported by the program
   elements within.  Currently, no declared names are visible **

```agda
  data _⊢mdefn_⊣_ (Γ : Context)
    : Module-Definition
    → (Γ′ : Context)
    → Set where
```

A module definition is well-formed if all declared type parameters are
well-formed, and the body of the module is a well-formed sequence of
program elements w.r.t. the surrounding context `Γ` extended with type
variables bound in the module header.

**TODO: how should the boolean flag `b` affect the semantics`?**
**TODO: bind module in context?** 

```agda
    ⊢mdefn
      : All (Δ⟨ Γ ⟩ ⊢type-param_) type-param∗
      → Sequence _⊢pelt_⊣_ pelt∗ ((type-param∗ ⋊ Δ⟨ Γ ⟩) , weaken-context 𝓒⟨ Γ ⟩) Γ′ 
        ────────────────────────────────────────────────────────────────────────────
        Γ ⊢mdefn module′ b name type-param∗ pelt∗ ⊣ Γ′
```

## Includes

**TODO: what is the difference between an include and import statement?**
**TODO: what (if any?) declarations does this bring into scope?** 

```agda
  data _⊢incld_⊣_ (Γ : Context)
    : Include
    → (Γ′ : Context)
    → Set where
    
    ⊢incld
      : ─────────────────────────
        Γ ⊢incld include name ⊣ Γ
    
```

## Export Declarations

Export declarations mark a list of names for export. Since we don't
model named imports/exports yet, its well-formedness is trivial.

```agda
  data _⊢xdecl_⊣_ (Γ : Context)
    : Export-Declaration
    → (Γ′ : Context)
    → Set where
    
    ⊢xdecl
      : ─────────────────────────
        Γ ⊢xdecl export name∗ ⊣ Γ
```


## External Declarations

**TODO: the declared name should be added to the context**

```agda
  data _⊢edecl_⊣_ (Γ : Context)
    : External-Declaration
    → (Γ′ : Context)
    → Set where
```

An extenrnal circuit declaration is well-formed if

* all type parameters are well-formed, 
* all arguments are well-formed, and
* the declared return type is well-formed. 

```
    ⊢edecl-external
      : All (Δ ⊢type-param_) type-param∗
      → All (λ arg → Δ ⊢arg arg) arg∗
      → Δ⟨ Γ ⟩ ⊢type type
        ───────────────────────────────────────────────────
        Γ ⊢edecl external b name type-param∗ arg∗ type ⊣ Γ
```


## Circuit Definitions

**TODO: this does not model purity check yet. **

```agda
  data _⊢cdefn_⊣_ (Γ : Context)
    : Circuit-Definition
    → (Γ′ : Context)
    → Set where
```

A circuit definition is well-formed if

* all type parameters are well-formed (`wf₁`),

* the return type is well-formed under the type context extended with
  the circuit's type parameters (`wf₂`),

* the arguments are well-formed under the type context extended with
  the circuit's type parameters (`wf₃`), and

* the circuit's body is a well-formed statement (`wf₄`).

```agda
    ⊢cdefn
      : ( wf₁ : ∀ type-param → type-param ∈ type-param∗
                             → Δ⟨ Γ ⟩ ⊢type-param type-param )
      → ( τ : ⊢Type (type-param∗ ⋊ Δ⟨ Γ ⟩))
      → ( ψ∗ : List (PatArg η⟨ wk type-param∗ Γ ⟩) )
      → ( wf₄ : (bindPats (wk _ Γ) ψ∗ , τ) ⊢stmt stmt ⊣ v∗ ) 
      → let ω = callable (-, wf₁) τ (pat→type∗ ψ∗) in
        --  ^ bundles well-formedness proofs for the type parameters,
        --    arguments, and return types into a callable.
        ───────────────────────────────────────────────────────────────── 
        Γ ⊢cdefn circuit b₁ b₂ name type-param∗ (pat-erase∗ ψ∗) type stmt
               ⊣ (-, bindCircuit (name , ω) 𝓒⟨ Γ ⟩)     
```

A callable corresponding to the defined circuit is bound in the output
context.

## Witness Declarations

```agda
  data _⊢wdecl_⊣_ (Γ : Context)
    : Witness-Declaration
    → Context
    → Set where
```

A witness declaration is well-formed if

* all type parameters are well-formed (`wf₁`),

* the return type is well-formed under the type context extended with
  the circuit's type parameters (`wf₂`),

* the arguments are well-formed under the type context extended with
  the circuit's type parameters (`wf₃`), and

```agda
    ⊢wdecl-witness
      : ( wf₁ : ∀ type-param → type-param ∈ type-param∗
                             → Δ⟨ Γ ⟩ ⊢type-param type-param )
      → ( wf₂ : (type-param∗ ⋊ Δ⟨ Γ ⟩) ⊢type type)
      → ( wf₃ : All ((type-param∗ ⋊ Δ⟨ Γ ⟩) ⊢arg_) arg∗ ) 
      → let w = callable (-, wf₁) (mkTy _ wf₂) (arg→type∗ wf₃) in
        --  ^ bundles well-formedness proofs for the type parameters,
        --    arguments, and return types into a callable.
        ──────────────────────────────────────────────────────
        Γ ⊢wdecl witness b name type-param∗ arg∗ type
               ⊣ (-, bindWitness (name , w) 𝓒⟨ Γ ⟩)
```

## External Contract Declarations

```agda
  data _⊢ecdecl_⊣_ (Γ : Context)
    : External-Contract-Declaration
    → (Γ′ : Context)
    → Set where
```

An external contract declaration is well-formed if the stored list of
external circuit declarations, `ecdecl-circuit*` is a well-formed
sequence of program elements.

**TOTO: the declared name should be bound in the output context. **

```agda 
    ⊢ecdecl
      : Sequence _⊢edecl-circuit_⊣_ ecdecl-circuit∗ Γ Γ′
        ───────────────────────────────────────────────────────
        Γ ⊢ecdecl external-contract b name ecdecl-circuit∗ ⊣ Γ′
```

## Enum Definitions

**TODO: conditions on the names, e.g., no shadowing or duplicates? ** 

```agda
  data _⊢enumdef_⊣_ (Γ : Context)
    : Enum-Definition
    → (Γ′ : Context)
    → Set where
```

An enum definition is trivially well-formed (as we don't impoose any
restrictions on names yet). The declared enumeration is bound in the
output context.

```agda  
    ⊢enumdef
      : ────────────────────────────────────────────────────────────
        Γ ⊢enumdef enum b name name₁ name∗ ⊣ defineEnum name name∗ Γ
```

## Program Elements

Program elements are the top-level declarations that can occur in
compact programs. They can be

* an include statement,
* a module definition,
* an import declaration,
* an export declaration,
* a ledger declaration,
* a ledger constructor,
* a circuit definition,
* an external declaration,
* a witness declaration,
* an external circuit declaration,
* a structure definition, or 
* an enumeration definition. 

Well-formedness of program elements is defined by referring to the
corresponding judgment for that element.

```agda
  data _⊢pelt_⊣_ (Γ : Context)
    : Program-Element
    → (Γ′ : Context)
    → Set where
    
    ⊢pelt-incld
      : Γ ⊢incld incld ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `incld incld ⊣ Γ′
        
    ⊢pelt-mdefn
      : Γ ⊢mdefn mdefn ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `mdefn mdefn ⊣ Γ′
        
    ⊢pelt-idecl
      : Γ ⊢idecl idecl ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `idecl idecl ⊣ Γ′
        
    ⊢pelt-xdecl
      : Γ ⊢xdecl xdecl ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `xdecl xdecl ⊣ Γ′
        
    ⊢pelt-ldecl
      : Γ ⊢ldecl ldecl ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `ldecl ldecl ⊣ Γ′
        
    ⊢pelt-lconstructor
      : Γ ⊢lconstructor lconstructor ⊣ Γ′
        ───────────────────────────────────────
        Γ ⊢pelt `lconstructor lconstructor ⊣ Γ′

    ⊢pelt-cdefn
      : Γ ⊢cdefn cdefn ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `cdefn cdefn ⊣ Γ′

    ⊢pelt-edecl
      : Γ ⊢edecl edecl ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `edecl edecl ⊣ Γ′

    ⊢pelt-wdecl
      : Γ ⊢wdecl wdecl ⊣ Γ′
        ─────────────────────────
        Γ ⊢pelt `wdecl wdecl ⊣ Γ′

    ⊢pelt-ecdecl
      : Γ ⊢ecdecl ecdecl ⊣ Γ′
        ───────────────────────────
        Γ ⊢pelt `ecdecl ecdecl ⊣ Γ′ 
                         
    ⊢pelt-structdef
      : Γ ⊢structdef structdef ⊣ Γ′
        ─────────────────────────────────
        Γ ⊢pelt `structdef structdef ⊣ Γ′
        
    ⊢pelt-enumdef
      : Γ ⊢enumdef enumdef ⊣ Γ′
        ─────────────────────────────
        Γ ⊢pelt `enumdef enumdef ⊣ Γ′ 
```

## Programs

Programs (i.e., a sequence of program elements) are well-formed
w.r.t. a before and after context, the latter representing definitions
that have been added to the program.

```agda
  data _⊢p_⊣_ (Γ : Context)
    : Program
    → (Γ′ : Context)
    → Set where
```

A program is well-formed if we have a well-formed sequence of program
elements, with matching in- and output contexts `Γ` and `Γ′`. 

```
    ⊢p-program
      : Sequence _⊢pelt_⊣_ pelt∗ Γ Γ′ 
        ─────────────────────────────
        Γ ⊢p program pelt∗ ⊣ Γ′
```


# Enforcing Coverage

As a sanity check, we enforce the typing relation to be
syntax-directed, meaning that there should be a one-to-one
correspondence between the untyped syntax of `Lsrc` and its typing
rules. This is to force synchronization between the static semantic
specification and internal syntax of the compiler. We identify three
meaningful ways in which the syntax can change that would require the
static semantic specification to be updated.

1. new syntax is added to the language,

2. existing syntax is deleted from the language, or

3. existing syntax is changed (i.e., constructor arguments are added,
   removed, changed, or re-ordered).

Changes (2) and (3) will automatically prompt any corresponding typing
rules to become ill-typed, so they are easily caught by re-checking
the specification once the language is updated. Catching missing rules
is more tricky, as Agda's type checker will take no offence if a
relation does not cover all possible constructors of it's index
type. To still force a static error if one of the typing rules is
missing, we make use of Agda's reflection to manually check that all
syntax of the language is covered.

To force coverage of a (collection of) typing relation(s) is a
two-step process.

1. First we must collect all judgments and "register" them as being a
   mutually-defined family of judgments that defines typing for a
   langauge (in this case `Lsrc`). 

2. Then, we run a meta-program to check that this family of judments
   covers all syntax in the language. This program fails if one or
   more rules are missing, pointing for each incomplete relation for
   which constructors in the untyped syntax it was unable to locate a
   corresponding typing rule. 

## Register Typing Relations

To register a typing relation for the `Lsrc` language, we define an
instance of the `HasTyping` class. This requires us to provide a
judgment relation for each syntactic sort in the language. If we fail
to supply a judgment for one or more syntactic sorts this manifests as
a type error.

```agda 
instance lsrc-typing : HasTyping Lsrc
lsrc-typing .rels =
    inj₂ (-, (-, _⊢parg_⦂_)) 
  ∷ inj₁ (-, _⊢arg_)
  ∷ inj₁ (-, _⊢import-name_)
  ∷ inj₁ (-, _⊢type_)
  ∷ inj₂ (-, -, _⊢new-field_⦂_)
  ∷ inj₂ (-, -, _⊢lconstructor_⊣_)
  ∷ inj₂ (-, -, _⊢edecl_⊣_)
  ∷ inj₂ (-, -, _⊢wdecl_⊣_) 
  ∷ inj₁ (-, _⊢tsize_)
  ∷ inj₂ (-, -, _⊢expr_⦂_) 
  ∷ inj₂ (-, -, _⊢p_⊣_)
  ∷ inj₂ (-, (-, _⊢pat_⦂_))
  ∷ inj₂ (-, -, _⊢edecl-circuit_⊣_)
  ∷ inj₂ (-, -, _⊢stmt_⊣_)
  ∷ inj₂ (-, -, _⊢structdef_⊣_)
  ∷ inj₂ (-, -, _⊢pelt_⊣_)
  ∷ inj₂ (-, -, _⊢ldecl_⊣_)
  ∷ inj₂ (-, -, _⊢idecl_⊣_)
  ∷ inj₁ (-, _⊢targ_)
  ∷ inj₁ (-, _⊢fun_)
  ∷ inj₂ (-, -, _⊢mdefn_⊣_)
  ∷ inj₂ (-, -, _⊢incld_⊣_)
  ∷ inj₁ (-, _⊢type-param_)
  ∷ inj₂ (-, -, _⊢xdecl_⊣_)
  ∷ inj₁ (-, _⊢tref_)
  ∷ inj₂ (-, -, _⊢cdefn_⊣_)
  ∷ inj₂ (-, -, _⊢ecdecl_⊣_ )
  ∷ inj₂ (-, -, _⊢enumdef_⊣_)
  ∷ []

```

## Coverage check 

Finally, we invoke the `checkRels` meta-program (defined in
`Coverage.agda`) to check that the registered typing relation for the
Lsrc syntax actually covers all syntactic elements in the language.

This means that if there is a constructor in one of the data types of
`Lsrc` for which there is no typing rule in the corresponding
judgment, a type error is thrown that indicates that a rule seems to
be missing. If more than one constructor of the `Lsrc` language is not
covered, the meta program points out all constructors for which a
typing rule is missing.

```agda 
-- Performs a check that the typing relations registered above are covering
-- for the Lsrc syntax tree 
unquoteDecl
 = checkRels (getTyping Lsrc) []
```

For instance, if we comment out some typing rules in this file and
attempt to type-check it, we might get an error like this:

```text

  Discovered missing rule(s) while checking coverage of relation _⊢lconstructor_⊣_
    ---> No typing rule found for constructor constructor′
  
  Discovered missing rule(s) while checking coverage of relation _⊢expr_⦂_
    ---> No typing rule found for constructor >
    ---> No typing rule found for constructor >=
  
  Discovered missing rule(s) while checking coverage of relation _⊢stmt_⊣_
    ---> No typing rule found for constructor +=
    ---> No typing rule found for constructor -=
```

## Smart Constructors

```agda

open ⊢Expr public 

⊢default
  : (τ : ⊢Type Δ⟨ Γ ⟩)
  → ⊢Expr Γ τ
⊢default τ
  = mkEx _ (⊢expr-default τ)

⊢or
  : (ε₁ : ⊢Expr Γ ⊢bool)
  → (ε₂ : ⊢Expr Γ τ)
  → tboolean ⊑ τ .ty
  → ⊢Expr Γ τ
⊢or ε₁ ε₂ ι
  = mkEx _ ( ⊢expr-or
      (ε₁ .well-formed-expression)
      (ε₂ .well-formed-expression) ι )  


⊢false ⊢true : ⊢Expr Γ ⊢bool
⊢false = mkEx _ ⊢expr-quote′
⊢true = mkEx _ ⊢expr-quote′ 

⊢and
  : (ε₁ : ⊢Expr Γ ⊢bool)
  → (ε₂ : ⊢Expr Γ τ)
  → tboolean ⊑ τ .ty
  → ⊢Expr Γ τ
⊢and ε₁ ε₂ ι 
  = mkEx _ ( ⊢expr-and
      (ε₁ .well-formed-expression)
      (ε₂ .well-formed-expression) ι ) 

⊢not : (ε : ⊢Expr Γ ⊢bool) → ⊢Expr Γ ⊢bool
⊢not ε = mkEx _ (⊢expr-not (ε .well-formed-expression))

⊢< ⊢> ⊢<= ⊢>= 
  : (ε₁ : ⊢Expr Γ τ₁) (ε₂ : ⊢Expr Γ τ₂)
  → UIntType Δ⟨ Γ ⟩ τ₁ → UIntType Δ⟨ Γ ⟩ τ₂
  → ( τ₁ ⊑-⊢ τ₂ ⊎ τ₂ ⊑-⊢ τ₁ ) → ⊢Expr Γ ⊢bool
⊢<  ε₁ ε₂ x y z
  = mkEx _ (⊢expr-<  x y (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) z)
⊢>  ε₁ ε₂ x y z
  = mkEx _ (⊢expr->  x y (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) z)
⊢<= ε₁ ε₂ x y z
  = mkEx _ (⊢expr-<= x y (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) z)
⊢>= ε₁ ε₂ x y z
  = mkEx _ (⊢expr-<= x y (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) z)

⊢== ⊢!= : (ε₁ : ⊢Expr Γ τ₁) (ε₂ : ⊢Expr Γ τ₂) → (τ₁ ⊑-⊢ τ₂) ⊎ (τ₂ ⊑-⊢ τ₁) → ⊢Expr Γ ⊢bool
⊢== ε₁ ε₂ px = mkEx _ (⊢expr-== (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) px) 
⊢!= ε₁ ε₂ px = mkEx _ (⊢expr-!= (ε₁ .well-formed-expression) (ε₂ .well-formed-expression) px) 

⊢if : (ε : ⊢Expr Γ ⊢bool) (ε₁ : ⊢Expr Γ τ₁) (ε₂ : ⊢Expr Γ τ₂) → τ ≡-⊢max⟨ τ₁ , τ₂ ⟩ → ⊢Expr Γ τ
⊢if ε ε₁ ε₂ px
  = mkEx _ ( ⊢expr-if
      (ε .well-formed-expression)
      (ε₁ .well-formed-expression)
      (ε₂ .well-formed-expression) (px .⊢max) )

⊢mktuple : All (◇ (⊢Expr Γ)) τ∗ → ⊢Expr Γ (⊢tuple τ∗) 
⊢mktuple ε∗ = mkEx _ (⊢expr-tuple ε∗)

⊢proj : ⊢Expr Γ (⊢tuple τ∗) → (i : τ ∈ τ∗) → ⊢Expr Γ τ 
⊢proj ε i = mkEx _ (⊢expr-tuple-ref ε i)

⊢mkvector : All (◇ (⊢Expr Γ)) (replicate n τ) → ⊢Expr Γ (⊢vector (⊢quote n) τ)
⊢mkvector ε∗ = mkEx _ (⊢expr-vector ε∗)

⊢vref : ⊢Expr Γ (⊢vector (⊢quote n) τ) → (i : Fin n) → ⊢Expr Γ τ
⊢vref ε i = mkEx _ (⊢expr-vector-ref ε i)

⊢call : (fn : ⊢Fun Γ) → All (◇ (⊢Expr Γ)) (argsT fn) → ⊢Expr Γ (returnT fn)  
⊢call fn ε = mkEx _ (⊢expr-call fn ε)

⊢new
  : ∀ τ?∗
  → ( px : (name , struct type-param∗) ∈ Δ⟨ Γ ⟩ .userTypes)
  → ( m  : Match-Param-Arg∗ type-param∗ targ∗ )
  → ( wf : All (Δ⟨ Γ ⟩ ⊢targ_) targ∗ )
  → let σ = args-subst wf m in
        --      ^ a substitution that describes the instantiation of
        --        type paramters bound by the structure.
    All (⊢New-Field (Γ , name , type-param∗ , px)) τ?∗ 
  → ⊢Expr Γ (⊢ref (⊢tref-type-ref (struct (type-param∗ , (px , m))) wf))
⊢new τ?∗ px m wf args = mkEx _ (⊢expr-new τ?∗ px m wf args) 

open ⊢Fun

⊢map
  : (fn : ⊢Fun Γ)
  → ∀ {τ₁ τ∗}
  → ◇ (⊢Expr Γ ∘ ⊢vector ζ) τ₁
  → All (◇ (⊢Expr Γ ∘ ⊢vector ζ)) τ∗
  → argsT fn ≡ τ₁ ∷ τ∗ 
  → ⊢Expr Γ (⊢vector ζ (returnT fn))
⊢map
  fn ε₁ ε∗ eq
  = mkEx _ (⊢expr-map fn ε₁ ε∗ eq) 

⊢fold
  : (fn : ⊢Fun Γ) 
  → ◇ (⊢Expr Γ) (returnT fn)
  → ◇ (⊢Expr Γ ∘ ⊢vector ζ) τ
  → All (◇ (⊢Expr Γ ∘ ⊢vector ζ)) τ∗
  → argsT fn ≡ returnT fn ∷ τ ∷ τ∗ 
  → ⊢Expr Γ (returnT fn)
⊢fold
  fn ε-init ε ε∗ eq
  = mkEx _ (⊢expr-fold fn ε-init ε ε∗ eq)

⊢seq
  : (ε∗ : All (◇ (⊢Expr Γ)) (replicate n τ))
  → (ε : ⊢Expr Γ τ)
  → ⊢Expr Γ τ
⊢seq ε∗ ε
  = mkEx _ (⊢expr-seq ε∗ (ε .well-formed-expression)) 

⊢cast
  : Castable τ₁ τ₂
  → ⊢Expr Γ τ₁
  → ⊢Expr Γ τ₂
⊢cast px ε
  = mkEx _ (⊢expr-cast (ε .well-formed-expression) px)

⊢disclose 
  : ⊢Expr Γ τ
  → ⊢Expr Γ τ
⊢disclose ε
  = mkEx _ (⊢expr-disclose (ε .well-formed-expression)) 


⊢mono : Fun name (𝓒⟨ Γ ⟩ .env) (callable ([] , (λ x ())) τ τ∗) → ⊢Fun Γ 
⊢mono fn = mkFun _ (⊢fun-mono fn) 

⊢gen : Fun name (𝓒⟨ Γ ⟩ .env) κ → Match-Param-Arg∗ (κ .params .proj₁) targ∗ → All (Δ⟨ Γ ⟩ ⊢targ_) targ∗ → ⊢Fun Γ
⊢gen fn m xs = mkFun _ (⊢fun-gen fn m xs)

⊢circuit : (parg∗ : List (PatArg η⟨ Γ ⟩)) → (τ : ⊢Type Δ⟨ Γ ⟩) → ⊢Stmt (bindPats Γ parg∗ , τ) v∗ → ⊢Fun Γ
⊢circuit parg∗ τ body = mkFun _ (⊢fun-circuit parg∗ τ body)

```

```agda
⋊[_]vars : ∀ {v∗} → SubstitutionT [ Δ v↦ v∗ ] (Δ .variables) → Variables (v∗ ⋊ Δ) → Variables Δ
⋊[ σ ]vars = lmap (map₂ ⋊[ σ ])

⋊[_]size : ∀ {v∗} → SubstitutionT [ Δ v↦ v∗ ] (Δ .variables) → ⊢Size (v∗ ⋊ Δ) → ⊢Size Δ
⋊[ σ ]size ζ = mkSz _ $ substituteT (subst-⋊ _ σ) (_ , ζ .well-formed-size) .proj₂
```


```agda
var-pat : Name → ⊢Type Δ[ η ] → PatArg η
var-pat name τ = mkPatArg (unnamed (var-name name) (τ .ty)) τ ((name , τ) ∷ []) (⊢parg' _ ⊢pattern-var)
```
