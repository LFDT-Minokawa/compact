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



module Semantics.Static.Lsrc.Substitution where 

open import Semantics.Static.Lsrc.Renaming

open import Semantics.Static.Lsrc.Lsrc-Typing
open import Semantics.Static.Lsrc.Lsrc
open import Syntax.Generated.Lsrc

open import Data.List.Membership.Propositional
open import Data.List.Membership.Propositional.Properties
open import Data.Product 
open import Relation.Unary hiding (_∈_)
open import Data.Sum 
open import Data.Maybe

open import Data.List.Relation.Unary.All renaming (map to amap ; lookup to resolve)
open import Data.List hiding (or)
open import Data.List.Relation.Binary.Pointwise hiding (refl)

open import Function

open import Relation.Binary.PropositionalEquality

open import Class.MonotonePredicate

Substitution : IsContext Δ → (v∗ : Variables Δ) → Set
Substitution 𝓒 v∗
  = ∀ {name τ} → (name , τ) ∈ 𝓒 .vars → ⊢Expr (-, < 𝓒 v↦ v∗ >) τ 

open Rename ⦃...⦄

ext-subst
  : Substitution 𝓒 v∗
  → Substitution (bindVars v∗′ 𝓒) (v∗′ ++ v∗)
ext-subst {v∗ = v∗} {v∗′} σ px with ∈-++⁻ v∗′ px 
... | inj₁ x = mkEx _ (⊢expr-var-ref (∈-++⁺ˡ x))
... | inj₂ y = rename (∈-++⁺ʳ _) (σ y)

mutual

  substitute-expr∗◇
    : Substitution 𝓒 v∗
    → ∀[ All (◇ (⊢Expr (Δ , 𝓒))) ⇒ All (◇ (⊢Expr (Δ , < 𝓒 v↦ v∗ >))) ] 
  substitute-expr∗◇ σ []
    = []
  substitute-expr∗◇ σ (◇⟨ ι , ε ⟩ ∷ xs)
    = ◇⟨ ι , (substitute σ ε) ⟩ ∷ substitute-expr∗◇ σ xs

  substitute-expr∗vec
    : Substitution 𝓒 v∗
    → ∀[ All (◇ (⊢Expr (Δ , 𝓒) ∘ ⊢vector ζ)) ⇒ All (◇ (⊢Expr (Δ , < 𝓒 v↦ v∗ >) ∘ ⊢vector ζ)) ]
  substitute-expr∗vec
    σ [] = []
  substitute-expr∗vec
    σ (◇⟨ ι , ε ⟩ ∷ xs)
    = ◇⟨ ι , (substitute σ ε) ⟩ ∷ substitute-expr∗vec σ xs


  substitute
    : Substitution 𝓒 v∗
    → ∀[ ⊢Expr (Δ , 𝓒) ⇒ ⊢Expr (Δ , < 𝓒 v↦ v∗ >) ]
  
  substitute σ (mkEx _ ⊢expr-quote′)
    = mkEx _ ⊢expr-quote′
    
  substitute σ (mkEx _ (⊢expr-var-ref x))
    = σ x
  
  substitute σ (mkEx _ (⊢expr-default τ))
    = ⊢default τ
    
  substitute σ (mkEx _ (⊢expr-if wf wf₁ wf₂ x))
    = ⊢if (substitute σ (mkEx _ wf))
        (substitute σ (mkEx _ wf₁))
        (substitute σ (mkEx _ wf₂))
        (record { ⊢max = x })
    
  substitute σ (mkEx e ⊢elt-ref)
    = mkEx e ⊢elt-ref
  
  substitute σ (mkEx e ⊢expr-elt-call)
    = mkEx e ⊢expr-elt-call
  
  substitute σ (mkEx _ (⊢expr-tuple ε∗))
    = mkEx _ (⊢expr-tuple (substitute-expr∗◇ σ ε∗))
    
  substitute σ (mkEx _ (⊢expr-vector ε∗))
    = mkEx _ (⊢expr-vector (substitute-expr∗◇ σ ε∗))
    
  substitute σ (mkEx _ (⊢expr-tuple-ref ε px))
    = mkEx _ (⊢expr-tuple-ref (substitute σ ε) px)
    
  substitute σ (mkEx _ (⊢expr-vector-ref ε i))
    = mkEx _ (⊢expr-vector-ref (substitute σ ε) i)

  substitute σ (mkEx _ (⊢expr-+ wf wf₁))
    = mkEx _
        (⊢expr-+
          (substitute σ (mkEx _ wf) .well-formed-expression)
          (substitute σ (mkEx _ wf₁) .well-formed-expression))
    
  substitute σ (mkEx _ (⊢expr-- wf wf₁))
    = mkEx _
        (⊢expr--
          (substitute σ (mkEx _ wf) .well-formed-expression)
          (substitute σ (mkEx _ wf₁) .well-formed-expression))
  
  substitute σ (mkEx _ (⊢expr-* wf wf₁))
    = mkEx _
        (⊢expr-*
          (substitute σ (mkEx _ wf) .well-formed-expression)
          (substitute σ (mkEx _ wf₁) .well-formed-expression))
  
  substitute σ (mkEx _ (⊢expr-or wf wf₁ x))
    = ⊢or (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x
  
  substitute σ (mkEx _ (⊢expr-and wf wf₁ x))
    = ⊢and (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x
  
  substitute σ (mkEx _ (⊢expr-not wf))
    = ⊢not (substitute σ (mkEx _ wf))
  
  substitute σ (mkEx _ (⊢expr-< x y wf wf₁ z))
    = ⊢< (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x y z
  
  substitute σ (mkEx _ (⊢expr-<= x y wf wf₁ z))
    = ⊢<= (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x y z
  
  substitute σ (mkEx _ (⊢expr-> x y wf wf₁ z))
    = ⊢> (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x y z
  
  substitute σ (mkEx _ (⊢expr->= x y wf wf₁ z))
    = ⊢>= (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x y z
  
  substitute σ (mkEx _ (⊢expr-== wf wf₁ x))
    = ⊢== (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x
    
  substitute σ (mkEx _ (⊢expr-!= wf wf₁ x))
    = ⊢!= (substitute σ (mkEx _ wf)) (substitute σ (mkEx _ wf₁)) x
  
  substitute σ (mkEx _ (⊢expr-map fn ◇⟨ ι , ε ⟩ ε∗ eq))
    = subst (⊢Expr _) (cong (⊢vector _) substitute-return)
      $ ⊢map (substitute-fun σ fn) ◇⟨ ι , (substitute σ ε) ⟩
          (substitute-expr∗vec σ ε∗)
          (trans substitute-args eq) 
    
  substitute σ (mkEx _ (⊢expr-fold fn (◇⟨_,_⟩ {x} ι₁ ε₁) ◇⟨ ι₂ , ε₂ ⟩ ε∗ eq))
    = subst (⊢Expr _) substitute-return
      $ ⊢fold (substitute-fun σ fn)
         ◇⟨ (subst (x ⊑-⊢_) (sym substitute-return) ι₁) , (substitute σ ε₁) ⟩
         ◇⟨ ι₂ , substitute σ ε₂ ⟩
         (substitute-expr∗vec σ ε∗)
         (trans substitute-args (trans eq (cong (_∷ _) (sym substitute-return))))

  substitute σ (mkEx _ (⊢expr-call fn ε∗))
    = subst (⊢Expr _) substitute-return
      $ ⊢call
          (substitute-fun σ fn)
          (subst (All (◇ (⊢Expr _)))
            (sym substitute-args) $ substitute-expr∗◇ σ ε∗) 

  substitute σ (mkEx _ (⊢expr-new τ?∗ px m wf args))
    = ⊢new τ?∗ px m wf (substitute-new-field∗ σ args)
  
  substitute σ (mkEx _ (⊢expr-seq ε∗ wf))
    = ⊢seq (substitute-expr∗◇ σ ε∗) (substitute σ (mkEx _ wf))
    
  substitute σ (mkEx _ (⊢expr-cast wf cx))
    = ⊢cast cx (substitute σ (mkEx _ wf))
    
  substitute σ (mkEx _ (⊢expr-disclose wf))
    = ⊢disclose (substitute σ (mkEx _ wf))

  substitute-new-field
    : ∀ {struct τ?} 
    → Substitution 𝓒 v∗
    → ⊢New-Field ((Δ , 𝓒) , struct) τ?
    → ⊢New-Field ((Δ , < 𝓒 v↦ v∗ >) , struct) τ? 
  substitute-new-field
    σ (mkNF nf (⊢new-field-spread m wf ε))
    = mkNF _ (⊢new-field-spread m wf (substitute σ ε))
  substitute-new-field
    σ (mkNF nf (⊢new-field-positional ε))
    = mkNF _ (⊢new-field-positional (substitute σ ε))
  substitute-new-field
    σ (mkNF nf (⊢new-field-named {name = name} ε))
    = mkNF _ (⊢new-field-named {name = name} (substitute σ ε))

  substitute-new-field∗
    : ∀ {struct τ?∗} 
    → Substitution 𝓒 v∗
    → All (⊢New-Field ((Δ , 𝓒) , struct)) τ?∗
    → All (⊢New-Field ((Δ , < 𝓒 v↦ v∗ >) , struct)) τ?∗
  substitute-new-field∗ σ []
    = []
  substitute-new-field∗ σ (nf ∷ xs)
    = substitute-new-field σ nf ∷ substitute-new-field∗ σ xs

  substitute-fun
    : Substitution 𝓒 v∗
    → ⊢Fun (Δ , 𝓒) → ⊢Fun (Δ , < 𝓒 v↦ v∗ >)
  substitute-fun σ (mkFun f (⊢fun-mono fn))
    = mkFun f (⊢fun-mono fn)
  substitute-fun σ (mkFun f (⊢fun-gen fn m args))
    = mkFun f (⊢fun-gen fn m args)
  substitute-fun σ (mkFun f (⊢fun-circuit ψ∗ τ 𝓢))
    = mkFun _ (⊢fun-circuit ψ∗ τ (substitute-stmt (ext-subst σ) 𝓢)) 

  substitute-stmt
    : Substitution 𝓒 v∗
    → ∀[ ⊢Stmt ((Δ , 𝓒) , τ) ⇒ ⊢Stmt ((Δ , < 𝓒 v↦ v∗ >) , τ) ]
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-expr ε x))
    = mkStmt _ (⊢stmt-expr (substitute σ ε) x)
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-=′ {expr₁ = expr₁} {expr₂ = expr₂}))
    = mkStmt _ (⊢stmt-=′ {expr₁ = expr₁} {expr₂ = expr₂})
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-+= {expr₁ = expr₁} {expr₂ = expr₂}))
    = mkStmt _ (⊢stmt-+= {expr₁ = expr₁} {expr₂ = expr₂})
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt--= {expr₁ = expr₁} {expr₂ = expr₂}))
    = mkStmt _ (⊢stmt--= {expr₁ = expr₁} {expr₂ = expr₂})
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-return ◇⟨ ι , ε ⟩))
    = mkStmt _ (⊢stmt-return ◇⟨ ι , (substitute σ ε) ⟩)
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-assert msg ε))
    = mkStmt _ (⊢stmt-assert msg (substitute σ ε))
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-const _ x ε))
    = mkStmt _ (⊢stmt-const _ x (substitute σ ε))
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-if ε 𝓢₁ 𝓢₂))
    = mkStmt _ (⊢stmt-if (substitute σ ε) (substitute-stmt σ 𝓢₁) (substitute-stmt σ 𝓢₂))
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-for name ε 𝓢))
    = mkStmt _ (⊢stmt-for name (substitute σ ε) (substitute-stmt (ext-subst σ) 𝓢))
    
  substitute-stmt
    σ (mkStmt _ (⊢stmt-block b))
    = mkStmt _ (⊢stmt-block (substitute-block σ b))

  substitute-block
    : Substitution 𝓒 v∗
    → ∀[ Block ((Δ , 𝓒) , τ) ⇒ Block ((Δ , < 𝓒 v↦ v∗ >) , τ) ]
  substitute-block
    σ empty = empty
  substitute-block
    σ (cons 𝓢 b)
    = cons (substitute-stmt σ 𝓢) (substitute-block (ext-subst σ) b)

  substitute-return
    : ∀ {fn : ⊢Fun Γ} {v∗} {σ : Substitution 𝓒⟨ Γ ⟩ v∗}
    → returnT (substitute-fun σ fn) ≡ returnT fn
  substitute-return {Γ} {mkFun f (⊢fun-mono x)} {v∗} {σ}
    = refl
  substitute-return {Γ} {mkFun f (⊢fun-gen x x₁ x₂)} {v∗} {σ}
    = refl
  substitute-return {Γ} {mkFun f (⊢fun-circuit ψ∗ τ 𝓢)} {v∗} {σ}
    = refl

  substitute-args
    : ∀ {fn : ⊢Fun Γ} {v∗} {σ : Substitution 𝓒⟨ Γ ⟩ v∗}
    → argsT (substitute-fun σ fn) ≡ argsT fn
  substitute-args {Γ} {mkFun f (⊢fun-mono x)} {v∗} {σ}
    = refl
  substitute-args {Γ} {mkFun f (⊢fun-gen x x₁ x₂)} {v∗} {σ}
    = refl
  substitute-args {Γ} {mkFun f (⊢fun-circuit ψ∗ τ 𝓢)} {v∗} {σ}
    = refl
