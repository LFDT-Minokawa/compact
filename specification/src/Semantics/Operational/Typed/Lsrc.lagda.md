# Lsrc 

```agda 
module Semantics.Operational.Typed.Lsrc where 

open import Syntax.Generated.Lsrc 

--open import Semantics.Operational.Type 
open import Semantics.Operational.Typed.State
open import Semantics.Static.Lsrc.Lsrc
open import Semantics.Static.Lsrc.Lsrc-Typing

open import Class.MonotonePredicate
open import Prelude.InferenceRules

open import Data.Fin
open import Data.List
  using (length) 
open import Data.List.Relation.Unary.All 
open import Data.Product
open import Data.List.Membership.Propositional
```


```agda

module _ where  

  open Operations renaming (return to ↑ )

  data ⟪_∙_⟫_──→_⟪_⟫ (δ : ⟦ Δ⟨ Γ ⟩ ⟧Δ) (Φ : ContractState Γ δ)
    : ∀ {τ} → ⊢Expr Γ τ
    → ◇ (⊢Expr Γ) τ
    → (ψ : ContractState Γ δ)
    → Set where 

    ──→-if₁
      : (px : τ ≡-⊢max⟨ τ₁ , τ₂ ⟩ )
      → ───────────────────────────────────────────────────────────────────
        ⟪ δ ∙ Φ ⟫ ⊢if ⊢false ε₁ ε₂ px ──→ ◇⟨ ⊑-maxʳ (px .⊢max) , ε₂ ⟩ ⟪ Φ ⟫

    ──→-if₂
      : (px : τ ≡-⊢max⟨ τ₁ , τ₂ ⟩ )
      → ──────────────────────────────────────────────────────────────────
        ⟪ δ ∙ Φ ⟫ ⊢if ⊢true ε₁ ε₂ px ──→ ◇⟨ ⊑-maxˡ (px .⊢max) , ε₁ ⟩ ⟪ Φ ⟫ 

    ──→-or₁
      : ───────────────────────────────────── 
        ⟪ δ ∙ Φ ⟫ ⊢or ⊢false ε ──→ ↑ ε₂ ⟪ Φ ⟫

    ──→-or₂
      : ─────────────────────────────────────── 
        ⟪ δ ∙ Φ ⟫ ⊢or ⊢true ε ──→ ↑ ⊢true ⟪ Φ ⟫ 

    ──→-and₁
      : ──────────────────────────────────────────
        ⟪ δ ∙ Φ ⟫ ⊢and ⊢false ε ──→ ↑ ⊢false ⟪ Φ ⟫  

    ──→-and₂
      : ──────────────────────────────────── 
        ⟪ δ ∙ Φ ⟫ ⊢and ⊢true ε ──→ ↑ ε ⟪ Φ ⟫

    ──→-tuple
      : ( ε∗ : All (◇ (⊢Expr Γ)) τ∗ )
      → ( i  : τ ∈ τ∗ )
      → ─────────────────────────────────────────────────────
        ⟪ δ ∙ Φ ⟫ ⊢proj (⊢mktuple ε∗) i ──→ lookup ε∗ i ⟪ Φ ⟫ 
```
