```agda 
module Semantics.Operational.Typed.State where

open import Syntax.Generated.Lsrc
open import Semantics.Static.Lsrc.Lsrc-Typing
open import Semantics.Static.Lsrc.Lsrc

open import Data.List
open import Data.List.Relation.Unary.All renaming (lookup to resolve) 

open import Data.Product
open import Data.Sum
open import Data.Bool

open import Class.MonotonePredicate
```

```agda

Contract : (Γ : Context) → Set


Contract Γ = ∃[ p ] Γ ⊢p p ⊣ Γ
```

A `LedgerValue` represents a value in the contract's internal state,
that is stored publically on the ledger. 

```agda
postulate TEnv : TypeContext → Set 

LedgerValue : TEnv Δ → Name × LedgerType Δ → Set
LedgerValue
  δ (name , .(⊢ref (⊢tref-type-ref (adt (_ , px , m)) wf)) , is-adt-ref px m wf)
  = {!!} --resolve (ltypes δ) px (targ→param∗ m (⟦ wf ⟧targ∗ δ)) .carrier 
```

The program state, or memory, consists of an array of ledger values,
whose shape is given by `Λ`. The shape of ledger values (and thus the
contract's internal state), are typed with respect to a type context
`Δ`. The reason for this is that a contract's type context contains

  * the "signatures" of the available ledger ADTs, and
  * the user-declared types that may be stored in the ledger.

In a similar fashion, the ledger values themselves are typed with
respect to the reflection of `Δ` as pointed sets with decidable
equality, which contains an interpretation of ledger ADTs and
user-declared types.

This is all to say that the definition of "contract state" is
independent of which ledger ADTs and user-declared types it may
contain, as well as their respective reflection in `Set`. 

```agda
module _ where

  record ContractState (Γ : Context) (δ : TEnv (Δ⟨ Γ ⟩)) : Set₁ where
    field
      mem : All (LedgerValue δ) (𝓒⟨ Γ ⟩ .env .ledger) 

  open ContractState 
```

TODO: what stuff in Γ do we need to keep track of dynamically also?

* Definition of user types
* Witnesses
* Circuits in scope
* Kernel operations
* Declared Ledger fields --> Contract State

