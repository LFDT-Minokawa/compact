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



module Semantics.Static.Lsrc.Specialize where 

open import Semantics.Static.Lsrc.Renaming
open import Semantics.Static.Lsrc.Substitution

open import Semantics.Static.Lsrc.Lsrc-Typing
open import Semantics.Static.Lsrc.Lsrc
open import Syntax.Generated.Lsrc

open import Data.List.Membership.Propositional
open import Data.List.Membership.Propositional.Properties
open import Data.Product 
open import Relation.Unary hiding (_∈_)
open import Data.Sum
open import Data.Unit using (⊤ ; tt)
open import Data.Maybe

open import Data.List.Relation.Unary.All renaming (map to amap ; lookup to resolve)
open import Data.List hiding (or) renaming (map to lmap)
open import Data.List.Relation.Binary.Pointwise hiding (refl) renaming (map to pmap)
open import Data.List.Properties

open import Function

open import Relation.Binary.PropositionalEquality

open import Class.MonotonePredicate


open import Axiom.Extensionality.Propositional

postulate
  funext : ∀ {a b} → Extensionality a b


++-sing
  : ∀ {a} {A : Set a} (x :  A) xs
  → (x ∷ []) ++ xs ≡ (x ∷ xs)
++-sing {a} {A} x xs = refl

  
subst-[]
  : (σ : SubstitutionT Δ type-param∗)
  → [] ≡ ⋊[ σ ]vars []
subst-[] σ = refl 

subst-bool
  : (σ : SubstitutionT Δ type-param∗)
  → ⋊[ σ ] ⊢bool ≡ ⊢bool
subst-bool σ = refl 

subst-vec
  : (σ : SubstitutionT Δ type-param∗)
  → ⋊[ σ ] (⊢vector ζ τ) ≡ ⊢vector (⋊[ σ ]size ζ) (⋊[ σ ] τ)
subst-vec {typecontext _ _ []} σ
  = refl
subst-vec {typecontext _ _ (_ ∷ _)} σ
  = refl

subst-uint
  : (σ : SubstitutionT Δ type-param∗)
  → ⋊[ σ ] (⊢uint₁ ζ) ≡ ⊢uint₁ (⋊[ σ ]size ζ)
subst-uint {typecontext _ _ []} σ
  = refl
subst-uint {typecontext _ _ (_ ∷ _)} σ
  = refl

subst-var
  : (σ : SubstitutionT Δ type-param∗)
  → ⋊[ σ ]vars ((name , ⊢uint₁ ζ) ∷ []) ≡ ((name , ⋊[ σ ] (⊢uint₁ ζ)) ∷ [])
subst-var {typecontext _ _ []} σ
  = refl
subst-var {typecontext _ _ (_ ∷ _)} σ
  = refl

subst-unit
  : (σ : SubstitutionT Δ type-param∗)
  → ⋊[ σ ] (⊢vector (⊢quote 0) ⊢undeclared) ≡ ⊢vector (⊢quote 0) ⊢undeclared
subst-unit {typecontext _ _ []} σ
  = refl
subst-unit {typecontext _ _ (_ ∷ _)} σ
  = refl

≲-subst
  : (σ : SubstitutionT Δ type-param∗)
  → τ₁ ≲ τ₂
  → ⋊[ σ ] τ₁ ≲ ⋊[ σ ] τ₂ 
≲-subst σ ≲-refl
  = ≲-refl
≲-subst σ (≲-trans sub sub₁)
  = ≲-trans (≲-subst σ sub) (≲-subst σ sub₁)

open ≡-Reasoning

foldr-++′
   : ∀ {a} {A B : Set a} (f : A → List B) xs ys
   → foldr (λ x xs′ → f x ++ xs′) xs ys ≡ foldr (λ x xs′ → f x ++ xs′) [] ys ++ xs
foldr-++′ f xs ys
  = sym $ foldr-fusion (_++ xs) [] (λ x → λ xs → ++-assoc (f x) xs _) ys

ctx-eq₁
  : ∀ Γ ψ∗ v∗
  → bindVars v∗ 𝓒⟨ bindPats Γ ψ∗ ⟩ ≡ bindVars (collect-vars Γ (lmap (uncurry var-pat) v∗ ++ ψ∗)) 𝓒⟨ Γ ⟩
ctx-eq₁ Γ ψ∗ v∗ =
  begin
    bindVars v∗ 𝓒⟨ bindPats Γ ψ∗ ⟩
  ≡⟨⟩ 
    bindVars v∗ (bindVars (collect-vars Γ ψ∗) 𝓒⟨ Γ ⟩ )
  ≡⟨ cong (context (𝓒⟨ Γ ⟩ .env)) (sym $ ++-assoc v∗ (collect-vars Γ ψ∗) (𝓒⟨ Γ ⟩ .vars)) ⟩
    bindVars (v∗ ++ collect-vars Γ ψ∗) 𝓒⟨ Γ ⟩
  ≡⟨ cong (λ ● → bindVars (● ++ collect-vars Γ ψ∗) 𝓒⟨ Γ ⟩) (id-is-foldr _) ⟩
    bindVars (foldr _ [] v∗ ++ collect-vars Γ ψ∗) 𝓒⟨ Γ ⟩ 
  ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ Γ ⟩) (sym $ foldr-++′ _ (collect-vars Γ ψ∗) v∗) ⟩
    bindVars (foldr _ (collect-vars Γ ψ∗) v∗) 𝓒⟨ Γ ⟩ 
  ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ Γ ⟩) (sym $ foldr-map _ (uncurry var-pat) (collect-vars Γ ψ∗) v∗) ⟩ 
    bindVars (foldr (λ ψ → ψ .PatArg.boundVars ++_) (collect-vars Γ ψ∗) (lmap (uncurry var-pat) v∗)) 𝓒⟨ Γ ⟩ 
  ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ Γ ⟩) (sym $ foldr-++ (λ ψ → ψ .PatArg.boundVars ++_) [] (lmap (uncurry var-pat) v∗) ψ∗) ⟩ 
    bindVars (collect-vars Γ (lmap (uncurry var-pat) v∗ ++ ψ∗)) 𝓒⟨ Γ ⟩
  ∎


module _ (Γ : Context) where 
  mutual
 
    ⋊[_]p
      : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables)
      → PatArg η⟨ wk type-param∗ Γ ⟩
      → PatArg η⟨ Γ ⟩
    ⋊[ σ ]p (mkPatArg _ τ vs (⊢parg' .vs pat))
      .PatArg.pat-arg = _
    ⋊[ σ ]p (mkPatArg _ τ vs (⊢parg' .vs pat))
      .PatArg.pat-type = ⋊[ σ ] τ
    ⋊[ σ ]p (mkPatArg _ τ vs (⊢parg' .vs pat))
      .PatArg.boundVars = ⋊[ σ ]vars vs
    ⋊[ σ ]p (mkPatArg _ τ vs (⊢parg' .vs pat))
      .PatArg.well-formed-pattern-argument = ⊢parg' _ (specialize-pat σ (_ , pat) .proj₂)
  
    ⋊[_]p∗
      : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables)
      → List (PatArg η⟨ wk type-param∗ Γ ⟩)
      → List (PatArg η⟨ Γ ⟩) 
    ⋊[ σ ]p∗ []
      = []
    ⋊[ σ ]p∗ (ψ ∷ ψ∗)
      = ⋊[ σ ]p ψ ∷ ⋊[ σ ]p∗ ψ∗
  
    specialize-stmt
      : ∀ {τ v∗} ψ∗
      → (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
      → ⊢Stmt (bindPats (wk type-param∗ Γ) ψ∗ , τ) v∗
      → ⊢Stmt (bindPats Γ (⋊[ σ ]p∗ ψ∗) , ⋊[ σ ] τ) (⋊[ σ ]vars v∗)
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-expr ε refl))
      = {!!} {- subst (⊢Stmt _) (subst-[] σ)
          (mkStmt _ (⊢stmt-expr (specialize-expr ψ∗ σ ε) (subst-unit σ))) -}
    specialize-stmt ψ∗ σ (mkStmt e ⊢stmt-=′)
      = subst (⊢Stmt _) (subst-[] σ) (mkStmt e ⊢stmt-=′)
    specialize-stmt ψ∗ σ (mkStmt e ⊢stmt-+=)
      = subst (⊢Stmt _) (subst-[] σ) (mkStmt e ⊢stmt-+=)
    specialize-stmt ψ∗ σ (mkStmt e ⊢stmt--=)
      = subst (⊢Stmt _) (subst-[] σ) (mkStmt e ⊢stmt--=)
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-return ◇⟨ ι , ε ⟩))
      = {!!} {- subst (⊢Stmt _) (subst-[] σ)
          (mkStmt _
            (⊢stmt-return
              ◇⟨ ≲-subst σ ι , (specialize-expr ψ∗ σ ε) ⟩)) -} 
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-assert msg ε))
      = subst (⊢Stmt _) (subst-[] σ)
          (mkStmt _
            (⊢stmt-assert msg
              (subst (⊢Expr _) (subst-bool σ)
                (specialize-expr ψ∗ σ ε))))
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-const _ x ε))
      = mkStmt _ (⊢stmt-const _
          (specialize-pat σ (_ , x) .proj₂)
            (specialize-expr ψ∗ σ ε))
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-if ε 𝓢₁ 𝓢₂))
      = subst (⊢Stmt _) (subst-[] σ)
          (mkStmt _
            (⊢stmt-if
              (subst (⊢Expr _) (subst-bool σ) (specialize-expr ψ∗ σ ε))
              (specialize-stmt ψ∗ σ 𝓢₁)
              (specialize-stmt ψ∗ σ 𝓢₂)))
    specialize-stmt  {τ = τ} ψ∗ σ (mkStmt _ (⊢stmt-for  {ζ = ζ} {v∗ = v∗} name ε 𝓢))
      = subst (⊢Stmt _) (subst-[] σ)
        (mkStmt _
          (⊢stmt-for name
            (subst (⊢Expr _) (subst-vec σ) (specialize-expr ψ∗ σ ε))
            (subst (λ 𝓒 → ⊢Stmt ((Δ⟨ Γ ⟩ , 𝓒) , ⋊[ σ ] τ) (⋊[ σ ]vars v∗))
               ( begin
                   𝓒⟨ bindPats Γ ((⋊[_]p σ (var-pat name (⊢uint₁ ζ))) ∷ ⋊[ σ ]p∗ ψ∗) ⟩
                 ≡⟨⟩ 
                   bindVars (collect-vars Γ (⋊[ σ ]p∗ (var-pat name (⊢uint₁ ζ) ∷ ψ∗))) 𝓒⟨ Γ ⟩
                 ≡⟨⟩
                   bindVars (⋊[_]p σ (var-pat name (⊢uint₁ ζ)) .PatArg.boundVars ++ collect-vars Γ (⋊[ σ ]p∗ ψ∗)) 𝓒⟨ Γ ⟩
                 ≡⟨⟩
                   bindVars (⋊[ σ ]vars ((name , (⊢uint₁ ζ)) ∷ []) ++ collect-vars Γ (⋊[ σ ]p∗ ψ∗)) 𝓒⟨ Γ ⟩
                 ≡⟨ cong (λ ● → bindVars (● ++ collect-vars Γ ((⋊[ σ ]p∗ ψ∗))) 𝓒⟨ Γ ⟩) (subst-var σ) ⟩
                   bindVars ((name , ⋊[ σ ] ((⊢uint₁ ζ))) ∷ collect-vars Γ (⋊[ σ ]p∗ ψ∗)) 𝓒⟨ Γ ⟩
                 ≡⟨ cong (λ ● → bindVars ((name , ● ) ∷ _) 𝓒⟨ Γ ⟩) (subst-uint σ) ⟩
                   bindVars ((name , ((⊢uint₁ (⋊[ σ ]size ζ)))) ∷ collect-vars Γ (⋊[ σ ]p∗ ψ∗)) 𝓒⟨ Γ ⟩ 
                 ≡⟨⟩
                   bindVar (name , ⊢uint₁ (⋊[ σ ]size ζ)) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ 
                 ∎ )
               (specialize-stmt (var-pat name _ ∷ ψ∗) σ 𝓢))))
      where open ≡-Reasoning
    specialize-stmt ψ∗ σ (mkStmt _ (⊢stmt-block b))
      = mkStmt _ (⊢stmt-block (specialize-block ψ∗ σ b))
  
    specialize-block
      : ∀ ψ∗ (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
      → Block (bindPats (wk type-param∗ Γ) ψ∗ , τ) v∗
      → Block (bindPats Γ (⋊[ σ ]p∗ ψ∗) , ⋊[ σ ] τ) (⋊[ σ ]vars v∗)
    specialize-block ψ∗ σ empty = empty
    specialize-block {type-param∗} {τ} {v∗ = v∗} ψ∗ σ (cons {v∗₁ = v∗₁} 𝓢 b)
      rewrite (ctx-eq₁ (wk _ Γ) ψ∗ v∗₁) = cons
          (specialize-stmt ψ∗ σ 𝓢)
          (subst
            (λ 𝓒 → Block ((Δ⟨ Γ ⟩ , 𝓒) , ⋊[ σ ] τ) (⋊[ σ ]vars v∗))
            (ctx-eq₂ ψ∗ v∗₁ σ) (specialize-block (lmap (uncurry var-pat) v∗₁ ++ ψ∗) σ b))
  
    ctx-eq₂
      : ∀ (ψ∗ : List (PatArg η⟨ wk type-param∗ Γ ⟩)) v∗
        (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
      → 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗ ++ ψ∗)) ⟩ ≡ bindVars (⋊[ σ ]vars v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ 
    ctx-eq₂ ψ∗ v∗ σ =
      begin
        𝓒⟨ bindPats Γ ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗ ++ ψ∗))) ⟩
      ≡⟨⟩ 
        bindVars (collect-vars Γ ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗ ++ ψ∗)))) 𝓒⟨ Γ ⟩
      ≡⟨ cong (λ ● → bindVars (collect-vars Γ ●) 𝓒⟨ Γ ⟩) (⋊[]p∗-++ (lmap (uncurry var-pat) v∗) ψ∗ σ) ⟩
        bindVars (collect-vars Γ (⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗) ++ ⋊[ σ ]p∗ ψ∗)) 𝓒⟨ Γ ⟩
      ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ Γ ⟩) (foldr-++ (λ ψ → ψ .PatArg.boundVars ++_) [] ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗))) (⋊[ σ ]p∗ ψ∗)) ⟩
        bindVars (foldr (λ ψ → ψ .PatArg.boundVars ++_) (collect-vars Γ (⋊[ σ ]p∗ ψ∗)) (⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗))) 𝓒⟨ Γ ⟩
      ≡⟨ (cong (λ ● → bindVars ● 𝓒⟨ Γ ⟩) $ foldr-++′ _ (collect-vars Γ ((⋊[ σ ]p∗ ψ∗))) ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗)))) ⟩
        bindVars (foldr (λ ψ → ψ .PatArg.boundVars ++_) [] ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗))) ++ collect-vars Γ ((⋊[ σ ]p∗ ψ∗))) 𝓒⟨ Γ ⟩
      ≡⟨ cong (context _) (++-assoc _ (collect-vars Γ ((⋊[ σ ]p∗ ψ∗))) (𝓒⟨ Γ ⟩ .vars)) ⟩
        bindVars (foldr (λ ψ → ψ .PatArg.boundVars ++_) [] ((⋊[ σ ]p∗ (lmap (uncurry var-pat) v∗)))) (bindVars (collect-vars Γ ((⋊[ σ ]p∗ ψ∗))) 𝓒⟨ Γ ⟩)
      ≡⟨ (cong (λ ● → bindVars (foldr _ _ ●) _) (trans (⋊[]p∗-map (lmap (uncurry var-pat) v∗) σ) (sym $ map-∘ _) )) ⟩
        bindVars (foldr (λ ψ → ψ .PatArg.boundVars ++_) [] (lmap (⋊[ σ ]p ∘ uncurry var-pat) v∗)) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ 
      ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ ) (foldr-map (λ ψ → ψ .PatArg.boundVars ++_) (⋊[ σ ]p ∘ uncurry var-pat) [] v∗) ⟩
        bindVars (foldr (λ (name , τ) v∗ → ⋊[ σ ]vars ((name , τ) ∷ []) ++ v∗) [] v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩
      ≡⟨ cong (λ ● → bindVars (foldr (λ v v∗ → ● (v ∷ []) ++ v∗) [] v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ ) (⋊[]vars-is-map Γ σ) ⟩ 
        bindVars (foldr (λ (name , τ) v∗ → (name , ⋊[ σ ] τ) ∷ v∗) [] v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ 
      ≡⟨ cong (λ ● → bindVars ● 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ ) (sym $ map-is-foldr v∗) ⟩
        bindVars (lmap (λ (name , τ) → name , ⋊[ σ ] τ) v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩  
      ≡⟨ cong (λ ● → bindVars (● v∗) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ ) (sym $ ⋊[]vars-is-map Γ σ) ⟩ 
        bindVars ((⋊[ σ ]vars v∗)) 𝓒⟨ bindPats Γ (⋊[ σ ]p∗ ψ∗) ⟩ 
      ∎
      where
        ⋊[]p∗-++
          : ∀ (ψ∗₁ ψ∗₂ : List (PatArg η⟨ wk type-param∗ Γ ⟩ ))
            (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
          → ⋊[ σ ]p∗ (ψ∗₁ ++ ψ∗₂) ≡ ⋊[ σ ]p∗ ψ∗₁ ++ ⋊[ σ ]p∗ ψ∗₂
        ⋊[]p∗-++ []        ψ∗₂ σ
          = refl
        ⋊[]p∗-++ (x ∷ ψ∗₁) ψ∗₂ σ
          = cong (_ ∷_) (⋊[]p∗-++ ψ∗₁ ψ∗₂ σ)
  
        ⋊[]p∗-map
          : ∀ (ψ∗ : List (PatArg η⟨ wk type-param∗ Γ ⟩))
          → (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
          → ⋊[ σ ]p∗ ψ∗ ≡ lmap ⋊[ σ ]p ψ∗ 
        ⋊[]p∗-map [] σ
          = refl
        ⋊[]p∗-map (_ ∷ ψ∗) σ
          = cong (_ ∷_) (⋊[]p∗-map ψ∗ σ)
  
        foldr-concat
          : ∀ {a} {A B : Set a}
            (f : A → List B) (xs : List A)
          → foldr (λ x → f x ++_) [] xs ≡ concat (lmap f xs)
        foldr-concat f []
          = refl
        foldr-concat f (x ∷ xs)
          = cong (f x ++_) (foldr-concat f xs)
  
        ⋊[]vars-is-map
          : ∀ Γ 
          → (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
          → ⋊[ σ ]vars ≡ lmap λ (name , τ) → name , ⋊[ σ ] τ
        ⋊[]vars-is-map {[]} _ σ
          = {!!} --funext (sym ∘ map-id) 
        ⋊[]vars-is-map {x ∷ type-param∗} _ σ
          = refl
     
    specialize-pat
      : ∀ {τ}{v∗} (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
      → ∃⟨ η⟨ wk type-param∗ Γ ⟩ ⊢pat_⦂ (τ , v∗) ⟩
      → ∃⟨ η⟨ Γ ⟩ ⊢pat_⦂ (⋊[ σ ] τ , ⋊[ σ ]vars v∗) ⟩
    specialize-pat {type-param∗ = []} σ (_ , ⊢pattern-var)
      = _ , ⊢pattern-var
    specialize-pat {type-param∗ = x ∷ type-param∗} σ (_ , ⊢pattern-var)
      = _ , ⊢pattern-var
    specialize-pat {type-param∗ = []} σ (_ , ⊢pattern-tuple pat?∗ v∗s wf)
      = {!!} --_ , ⊢pattern-tuple pat?∗ v∗s wf
    specialize-pat {type-param∗ = x ∷ type-param∗} σ (_ , ⊢pattern-tuple {τ∗} pat?∗ v∗ wf)
      = _ ,
        let foo = ⊢pattern-tuple
                    _
                    (lmap ⋊[ σ ]vars v∗)
                    (specialize-pointwise τ∗ v∗ (pat?∗ , wf) .proj₂) in {!!}
      where
        specialize-pointwise
          : ∀ τ∗ v∗
          → (∃ λ pat?∗ →
               Pointwise
                 (λ pat? (τ , v∗) → maybe′ (η⟨ wk _ Γ ⟩ ⊢pat_⦂ (τ , v∗)) ⊤ pat?)
                 pat?∗
                 (Data.List.zip τ∗ v∗))
          → (∃ λ pat?∗ →
              Pointwise
                (λ pat? (τ , v∗) → maybe′ (η⟨ Γ ⟩ ⊢pat_⦂ (τ , v∗)) ⊤ pat?)
                pat?∗
                (Data.List.zip (⋊[ σ ]∗ τ∗) (lmap ⋊[ σ ]vars v∗)))
        specialize-pointwise [] [] (_ , [])
          = _ , []
        specialize-pointwise [] (_ ∷ _) ([] , [])
          = _ , []
        specialize-pointwise (x ∷ τ∗) [] ([] , [])
          = _ , []
        specialize-pointwise (x ∷ τ∗) (v ∷ v∗) (just pat ∷ pat?∗ , wf ∷ pw)
          = (just _ ∷ _)
          , (specialize-pat σ (pat , wf) .proj₂
             ∷ specialize-pointwise τ∗ v∗ (pat?∗ , pw) .proj₂)
        specialize-pointwise (_ ∷ τ∗) (_ ∷ v∗) (nothing ∷ pat?∗ , tt ∷ pw)
          = (nothing ∷ _) , (tt ∷ specialize-pointwise τ∗ v∗ (pat?∗ , pw) .proj₂)
  
  
    specialize-pat {type-param∗ = []} σ (_ , ⊢pattern-struct px₁ m wf₁ wf₂)
      = {!!} -- _ , ⊢pattern-struct px₁ m wf₁ wf₂
    specialize-pat {type-param∗ = x ∷ x₁} σ (_ , ⊢pattern-struct dt m wf₁ wf₂)
      = _ , let foo = ⊢pattern-struct dt (match-arg-subst∗ σ m) {!wf₁!} {!wf₂!} in {!!}
      where
        
        
  
    postulate 
      specialize-expr
        : ∀ ψ∗ (σ : SubstitutionT [ Δ⟨ Γ ⟩ v↦ type-param∗ ] (Δ⟨ Γ ⟩ .variables))
        → ⊢Expr (bindPats (wk type-param∗ Γ) ψ∗) τ
        → ⊢Expr (bindPats Γ (⋊[ σ ]p∗ ψ∗)) (⋊[ σ ] τ) 
  
