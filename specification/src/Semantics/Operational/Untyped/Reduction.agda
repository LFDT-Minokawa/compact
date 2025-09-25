-- This file is part of Compact.
-- Copyright (C) 2025 Midnight Foundation
-- SPDX-License-Identifier: Apache-2.0
-- Licensed under the Apache License, Version 2.0 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at
-- 
-- 	http://www.apache.org/licenses/LICENSE-2.0
-- 
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.



{-# OPTIONS --safe #-} 

open import Syntax.Generated.Lsrc

open import Data.Unit
open import Data.Sum hiding (map ; reduce)
open import Data.Bool renaming (not to notᵇ)
open import Data.Nat renaming (_+_ to _ℕ+_ ; _*_ to _ℕ*_)
open import Data.List using (List ; _∷_ ; [] ; head ; tail ; reverse ; _++_ ; foldr) renaming (map to mapᴸ ; and to andᴸ)
open import Data.Maybe hiding (map ; zipWith)
open import Data.Product using (uncurry ; _,_ ; _×_ ; proj₁ ; proj₂ ; Σ)
open import Data.String using (String) renaming (_==_ to _==s_)


open import Data.List.Relation.Unary.All hiding (map)
open import Relation.Binary.PropositionalEquality using (refl ; _≡_)

open import Function 

open import Prelude.InferenceRules

open import Data.List.Membership.Propositional

module Semantics.Operational.Untyped.Reduction (𝓟 : Set) where

open import Semantics.Operational.Untyped.State 𝓟
open import Semantics.Operational.Untyped.Value 𝓟
open import Semantics.Operational.Untyped.Context 𝓟 
open import Semantics.Operational.Untyped.Substitution

variable Φ Φ′ Ψ Ψ′ : State
variable n m k : ℕ

[_‼_] : ∀ {a} {A : Set a} → List A → ℕ → Maybe A
[ []     ‼ _     ] = nothing
[ x ∷ _  ‼ zero  ] = just x
[ _ ∷ xs ‼ suc n ] = [ xs ‼ n ]

heads : ∀ {a} {A : Set a} → List (List A) → Maybe (List A)
heads [] = just []
heads ([] ∷ xss) = nothing
heads ((x ∷ _) ∷ xss) = do
  rec ← heads xss
  just (x ∷ rec)

tails : ∀ {a} {A : Set a} → List (List A) → Maybe (List (List A))
tails [] = just []
tails ([] ∷ xss) = nothing
tails ((_ ∷ xs) ∷ xss) = do
  rec ← tails xss
  just (xs ∷ rec)

transpose
  : ∀ {a} {A : Set a}
  → List (List A)
  → Maybe (List (List A))
transpose {A = A} [] = nothing
transpose {A = A} (xs ∷ xss) = do
  v ← go [] xs xss
  just $ reverse v
  where
    go : List (List A) → List A → List (List A) →  Maybe (List (List A))
    go yss [] _ = just yss
    go yss (x ∷ xs) xss = do
      hds′ ← heads xss
      tls′ ← tails xss
      go ((x ∷ hds′) ∷ yss) xs tls′

module _ (𝓔 : EvaluationContext) where 

  -- Shadow the values in the 1st list with the values in the 2nd list
  shadow : List New-Field → List New-Field → Maybe (List New-Field)
  shadow xs [] = just xs
  shadow xs (y ∷ ys) = do
    xs′ ← try-update y xs
    shadow xs′ ys
    where
      try-update : New-Field → List New-Field → Maybe (List New-Field)
      try-update (spread x) xs = nothing
      try-update (positional x) xs = nothing
      try-update (named x expr) [] = just []
      try-update nf′@(named x expr) (nf@(named y expr′) ∷ xs)
        = case x ==s y of λ where
            false → do
              nf∗ ← try-update nf′ xs
              just (nf ∷ nf∗)
            true → just (nf′ ∷ xs) 
      try-update (named x expr) _ = nothing
  
  mutual

    -- Evaluation relation, That reduces the leftmost-outermost redex
    -- one single step. 
    data ⟪_⟫_⊢─→_⟪_⟫ (Φ : State) : Expression → Expression → State → Set where 

      step-expr 
        : ⟪ Φ ⟫ expr₁ ──→ expr₂ ⟪ Ψ ⟫
          ─────────────────────────────────────────
          ⟪ Φ ⟫ E ·[ expr₁ ] ⊢─→ E ·[ expr₂ ] ⟪ Ψ ⟫


    -- Reflexive transitive closure of the evaluation relation,
    -- describing repeated reduction of the leftmost-outermost redex
    -- in an expression tree.
    data ⟪_⟫_⊢─↠_⟪_⟫ (Φ : State) : Expression → Expression → State → Set where 

      ⊢─↠-expr-refl
        : ─────────────────────────
          ⟪ Φ ⟫ expr ⊢─↠ expr ⟪ Φ ⟫

      ⊢─↠-expr-trans
        : ⟪ Φ ⟫ expr₁ ⊢─→ expr₂ ⟪ Φ′ ⟫
        → ⟪ Φ′ ⟫ expr₂ ⊢─↠ expr₃ ⟪ Ψ ⟫
          ────────────────────────────
          ⟪ Φ ⟫ expr₁ ⊢─↠ expr₃ ⟪ Ψ ⟫ 
      
    
    -- Reduction relation for expressions.
    --
    -- This relation defines all the possible redexes that can occur
    -- at the root of an expression tree.
    --
    -- It is perfectly possible that the the root of an expression
    -- tree is not a redex (e.g., an if-expression whose conditional
    -- is not a boolean value). However, such congruence is handled by
    -- the evaluation context and corresponding relations defined
    -- above. 
    data ⟪_⟫_──→_⟪_⟫ (Φ : State) : Expression → Expression → State →  Set where
  
      ──→-if-true
        : ──────────────────────────────────────────────
          ⟪ Φ ⟫ if (b· true) expr₁ expr₂ ──→ expr₁ ⟪ Φ ⟫
    
      ──→-if-false
        : ───────────────────────────────────────────────
          ⟪ Φ ⟫ if (b· false) expr₁ expr₂ ──→ expr₂ ⟪ Φ ⟫

      -- elt ref, elt call?

      ──→-proj
        : [ expr∗ ‼ n ] ≡ just expr 
        → ──────────────────────────────────────────────
          ⟪ Φ ⟫ tuple-ref (tuple expr∗) n ──→ expr ⟪ Φ ⟫
    
      ──→-+
        : ───────────────────────────────────────────
          ⟪ Φ ⟫ + (n· n) (n· m) ──→ n· (n ℕ+ m) ⟪ Φ ⟫
    
      ──→--
        : ──────────────────────────────────────────
          ⟪ Φ ⟫ - (n· n) (n· m) ──→ n· (n ∸ m) ⟪ Φ ⟫
    
      ──→-*
        : ───────────────────────────────────────────
          ⟪ Φ ⟫ * (n· n) (n· m) ──→ n· (n ℕ* m) ⟪ Φ ⟫
    
      ──→-or-false
        : ───────────────────────────────────────
          ⟪ Φ ⟫ or (b· false) expr ──→ expr ⟪ Φ ⟫
          
      ──→-or-true
        : ─────────────────────────────────────────
          ⟪ Φ ⟫ or (b· true) expr ──→ b· true ⟪ Φ ⟫
    
      ──→-and-false
        : ────────────────────────────────────────────
          ⟪ Φ ⟫ and (b· false) expr ──→ b· false ⟪ Φ ⟫
          
      ──→-and-true
        : ───────────────────────────────────────
          ⟪ Φ ⟫ and (b· true) expr ──→ expr ⟪ Φ ⟫
    
      ──→-not
        : ∀ {x} → 
          ──────────────────────────────────────
          ⟪ Φ ⟫ not (b· x) ──→ b· (notᵇ x) ⟪ Φ ⟫
    
      ──→-<
        : ───────────────────────────────────────────
          ⟪ Φ ⟫ < (n· n) (n· m) ──→ b· (n <ᵇ m) ⟪ Φ ⟫
    
      ──→-<=
        : ───────────────────────────────────────────
          ⟪ Φ ⟫ <= (n· n) (n· m) ──→ b· (n ≤ᵇ m) ⟪ Φ ⟫
    
      ──→->
        : ───────────────────────────────────────────
          ⟪ Φ ⟫ > (n· n) (n· m) ──→ b· (m <ᵇ n) ⟪ Φ ⟫
    
      ──→->=
        : ────────────────────────────────────────────
          ⟪ Φ ⟫ >= (n· n) (n· m) ──→ b· (m ≤ᵇ n) ⟪ Φ ⟫
    
      ──→-==
        : (v₁ : IsValue expr₁)
        → (v₂ : IsValue expr₂)
        →  ─────────────────────────────────────────────────────── 
          ⟪ Φ ⟫ == expr₁ expr₂ ──→ b· (compare-value v₁ v₂) ⟪ Φ ⟫ 
    
      ──→-!=
        : (v₁ : IsValue expr₁)
        → (v₂ : IsValue expr₂)
        → ────────────────────────────────────────────────────────────── 
          ⟪ Φ ⟫ != expr₁ expr₂ ──→ b· (notᵇ $ compare-value v₁ v₂) ⟪ Φ ⟫
  
  
      -- This rule has an implicit premise that all the argument vectors
      -- to the map expression are of equal length. Currently, this
      -- assumption is (partly) encoded by the `transpose` function,
      -- which is partial and returns no result if it fails to construct
      -- a tranposition.
      --
      -- Alternatively---and this would arguably be the more
      -- "Agda-esque" way of doing it---we could add an explicit premise
      -- and make `transpose` a total function that takes some proof
      -- object witnessing that its input lists have the same length.
      ──→-map
        : ∀ {expr∗∗ expr∗∗′}
        → transpose (expr∗ ∷ expr∗∗) ≡ just expr∗∗′
        → ─────────────────────────────────────────────────────────────────────────────────────────
          ⟪ Φ ⟫ map fun (tuple expr∗) (mapᴸ tuple expr∗∗) ──→ tuple (mapᴸ (call fun) expr∗∗′) ⟪ Φ ⟫
  
      ──→-fold-init
        : ∀ {expr∗∗}
        → ──────────────────────────────────────────────────────
          ⟪ Φ ⟫ fold fun expr₁ (tuple []) expr∗∗ ──→ expr₁ ⟪ Φ ⟫
  
      ──→-fold-step
        : ∀ {expr∗∗ expr∗∗′ expr∗′}
        → heads expr∗∗ ≡ just expr∗′
        → tails expr∗∗ ≡ just expr∗∗′
        → ──────────────────────────────────────────────────────────────────────────────────
          ⟪ Φ ⟫ fold fun expr₁ (tuple (expr ∷ expr∗)) (mapᴸ tuple expr∗∗)
          ──→   call fun (fold fun expr₁ (tuple expr∗) (mapᴸ tuple expr∗∗′) ∷ expr ∷ expr∗′)
          ⟪ Φ ⟫
  
      ─→-call
        : ⟪ Φ ⟫call fun >< expr∗ ──→ expr ⟪ Ψ ⟫
        → ─────────────────────────────────────
          ⟪ Φ ⟫ call fun expr∗ ──→ expr ⟪ Ψ ⟫

      -- Requires that the spread expression is the last field
      -- expression in the struct literal.
      --
      -- TODO: what are the well-formedness requirements of vector
      -- literals with spread expressions?
      ──→-spread
        : ∀ {fields fields′}
        → All IsNFValue new-field∗ 
        → shadow new-field∗ fields ≡ just fields′
          ───────────────────────────────────────────────────────────────────────────────────────
          ⟪ Φ ⟫ new tref (new-field∗ ++ spread (new tref fields) ∷ []) ──→ new tref fields′ ⟪ Φ ⟫  

      ──→-seq
        : ────────────────────────────────────────────────────────────
          ⟪ Φ ⟫ Expression.seq (mapᴸ proj₁ value∗) expr ──→ expr ⟪ Φ ⟫

      ──→-cast
        : ────────────────────────────────────────────────────────────────
          ⟪ Φ ⟫ cast type (value .proj₁) ──→ castv type value .proj₁ ⟪ Φ ⟫

      ──→-disclose
        : ──────────────────────────────────
          ⟪ Φ ⟫ disclose expr ──→ expr ⟪ Φ ⟫ 

      -- TODO: what if the assert fails? 
      ──→-assert-true 
        : ∀ {msg} 
        → ───────────────────────────────────────
          ⟪ Φ ⟫ assert (b· true) msg ──→ u· ⟪ Φ ⟫ 
  

    data ⟪_⟫call_><_──→_⟪_⟫ (Φ : State)
      : (fun : Function) (expr∗ : List Expression) → Expression → State → Set where

      ──→-call-mono-witness 
        : (w : List Expression → 𝓟 → 𝓟 × Expression)
        → (name , w) ∈ 𝓔 .witnesses
        → let (𝓹 , r) = w expr∗ (Φ .priv) in
          ──────────────────────────────────────────────────────── 
          ⟪ Φ ⟫call fref name >< expr∗ ──→ r ⟪ << Φ .publ ∙ 𝓹 >> ⟫

      ──→-call-mono-circuit
        : ∀ {x y σ}
        → (name , circuit x y name [] parg∗ type stmt) ∈ 𝓔 .circuits
        → σ-parg parg∗ expr∗ ≡ just σ
        → ⟪ Φ ⟫stmt substitute-stmt σ stmt ⊢─↠ return expr ⟪ Ψ ⟫
          ────────────────────────────────────────────────────── 
          ⟪ Φ ⟫call fref name >< expr∗ ──→ expr ⟪ Ψ ⟫

      -- Can witnesses be polymorphic, and should this be reflected in
      -- their embedded type (e.g. taking the type arguments also)
      ──→-call-poly-witness
         : (w : List Expression → 𝓟 → 𝓟 × Expression)
         → (name , w) ∈ 𝓔 .witnesses
         → let (𝓹 , r) = w expr∗ (Φ .priv) in
           ─────────────────────────────────────────────────────────────── 
           ⟪ Φ ⟫call fref1 name targ∗ >< expr∗ ──→ r ⟪ << Φ .publ ∙ 𝓹 >> ⟫

      ──→-call-poly-circuit
        : ∀ {x y σ}
        → (name , circuit x y name [] parg∗ type stmt) ∈ 𝓔 .circuits
        → σ-parg parg∗ expr∗ ≡ just σ
        → ⟪ Φ ⟫stmt substitute-stmt σ stmt ⊢─↠ return expr ⟪ Ψ ⟫
          ──────────────────────────────────────────────────────
          ⟪ Φ ⟫call fref1 name targ∗ >< expr∗ ──→ expr ⟪ Ψ ⟫

      ─→-call-anonymous-circuit
        : ∀ {σ}
        → σ-parg parg∗ expr∗ ≡ just σ 
        → ⟪ Φ ⟫stmt substitute-stmt σ stmt ⊢─↠ return expr ⟪ Ψ ⟫
          ─────────────────────────────────────────────────────────  
          ⟪ Φ ⟫call circuit parg∗ type stmt >< expr∗ ──→ expr ⟪ Ψ ⟫ 

    infix 4 _⨟_
    _⨟_ : Statement → List Statement → Statement
    stmt ⨟ stmt∗ = block (stmt ∷ stmt∗)

    data ⟪_⟫stmt_⊢─↠_⟪_⟫ (Φ : State) : Statement → Statement → State → Set where

      ⊢─↠-stmt-refl
        : ⟪ Φ ⟫stmt stmt ⊢─↠ stmt ⟪ Φ ⟫

      ⊢─↠-stmt-trans
        : ⟪ Φ ⟫stmt stmt₁ ⊢─→ stmt₂ ⟪ Φ′ ⟫
        → ⟪ Φ′ ⟫stmt stmt₂ ⊢─↠ stmt₃ ⟪ Ψ ⟫
          ──────────────────────────────── 
          ⟪ Φ ⟫stmt stmt₁ ⊢─↠ stmt₃ ⟪ Ψ ⟫ 

    data ⟪_⟫stmt_⊢─→_⟪_⟫ (Φ : State) : Statement → Statement → State → Set where
    
      step-stmt
        : ⟪ Φ ⟫ expr₁ ──→ expr₂ ⟪ Ψ ⟫
          ───────────────────────────────────────────────
          ⟪ Φ ⟫stmt S ·[ expr₁ ]S ⊢─→ S ·[ expr₂ ]S ⟪ Ψ ⟫

      reduce-statement
        : stmt₁ ─stmt─→ stmt₂
          ───────────────────────────────
          ⟪ Φ ⟫stmt stmt₁ ⊢─→ stmt₂ ⟪ Φ ⟫ 

    infix 3 _─stmt─→_
    data _─stmt─→_ : Statement → Statement → Set where

      ──→-stmt-expr
        : IsValue expr 
          ─────────────────────────────────────────────────────
          statement-expression expr ⨟ stmt∗ ─stmt─→ block stmt∗ 

      ──→-stmt-const
        : ∀ {vars}
        → IsValue expr
        → match pat expr ≡ just vars
          ───────────────────────────────────────────────────
            Statement.const pat type expr ⨟
            stmt∗
          ─stmt─→
            substitute-stmt ⟪ vars , idsubst ⟫∗ (block stmt∗)

      ──→-stmt-if-true
        : ────────────────────────────
            if (b· true) stmt₁ stmt₂ ⨟
            stmt∗
          ─stmt─→
            stmt₁ ⨟
            stmt∗

      ──→-stmt-if-false
        : ─────────────────────────────
            if (b· false) stmt₁ stmt₂ ⨟
            stmt∗
          ─stmt─→
            stmt₂ ⨟
            stmt∗
          

      ──→-stmt-for-nil
        : ──────────────────────────── 
            for name (tuple []) stmt ⨟
            stmt∗
          ─stmt─→
            block stmt∗

      ──→-stmt-for-cons
        : ────────────────────────────────────────
            for name (tuple (expr ∷ expr∗)) stmt ⨟
            stmt∗
          ─stmt─→
            stmt [ name ∷= expr ] ⨟
            (for name (tuple expr∗)
            stmt ∷ stmt∗)
