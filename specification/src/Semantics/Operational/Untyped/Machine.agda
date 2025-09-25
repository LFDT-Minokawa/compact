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



module Semantics.Operational.Untyped.Machine (𝓟 : Set) where 

open import Semantics.Operational.Untyped.State 𝓟 
open import Semantics.Operational.Untyped.Value 𝓟

open import Syntax.Generated.Lsrc

open import Data.Sum
open import Data.List hiding (or ; and) renaming (map to mapᴸ)
open import Data.Product
open import Data.Nat 
open import Data.String hiding (_++_)
open import Data.Maybe hiding (_>>=_)
open import Data.Bool 
open import Function

Val = Expression 

Env = List (Name × Val)

-- TODO: should we have frames for assignment operators, or should
-- they lazily reduce?

data EFrame : Set where
  halt : EFrame
  fif : (x y : Expression) → Env → EFrame 
  ftuple : List Val → List Expression → Env → EFrame
  ftuple-ref : ℕ → EFrame
  f+₁ f-₁ f*₁ for₁ fand₁ f<₁ f<=₁ f>₁ f>=₁ f==₁ f!=₁ f=′₁ f+=₁ f-=₁ : (e : Expression) → (η′ : Env) → EFrame
  f+₂ f-₂ f*₂ f<₂ f<=₂ f>₂ f>=₂ f==₂ f!=₂ f=′₂ f+=₂ f-=₂ : (v′ : Val) → EFrame 
  fnot : EFrame

  fmap₁ : Function → List Expression → Env → EFrame
  fmap₂ : Function → Val → List Val → List Expression → Env → EFrame

  ffold₁ : Function → Expression → List Expression → Env → EFrame
  ffold₂ : Function → Val → List Expression → Env → EFrame
  ffold₃ : Function → Val → Val → List Val → List Expression → Env → EFrame 

  fcall₁ : Function → List Val → List Expression → Env → EFrame
  fcall₂ : List Val → EFrame 
  fnew  : Type-Ref → List New-Field → List New-Field → Env → EFrame  

  fseq      : List Val → List Expression → Expression → Env → EFrame
  fcast     : Type → EFrame
  fdisclose : EFrame
  fassert   : String → EFrame

  fnamed : String → EFrame
  fspread fpositional : EFrame

  fstexp freturn : EFrame

  fconst : Pattern → Type → Env → EFrame 
  fifs : Statement → Statement → Env → EFrame
  ffor : String → Statement → Env → EFrame
  fblock : List Statement → Env → EFrame 


Frame = EFrame

data Control : Set where
  ex : Expression → Control
  st : Statement → Control
  nf : New-Field → Control
  fn : Function → List Expression → Control 
  va : Expression → Control 

record ST : Set where
  constructor ⟪_·_·_·_⟫ 
  field
    ctrl   : Control
    η      : List (Name × Val)
    σ      : State
    κ      : List Frame  

data Result (A : Set) : Set where
  ↑ : A → Result A
  stop : Result A 
  configurationError : Result A
  variableNotFound : Result A
  indexNotFound : Result A
  matchError : Result A
  assertError : String → Result A

fetch : Name → List (Name × Val) → Result Val
fetch = {!!}

deref : ℕ → List Val → Result Val
deref = {!!} 

_>>=_ : {A B : Set} → Result A → (A → Result B) → Result B
_>>=_ = {!!} 

step : ST → Result ST

step ⟪ ex (quote′ v) · η · σ · κ ⟫
  = ↑ ⟪ va (quote′ v) · η · σ · κ ⟫

step ⟪ ex (var-ref x) · η · σ · κ ⟫
  = do v ← fetch x η
       ↑ ⟪ va v · η · σ · κ ⟫

step ⟪ ex (default t) · η · σ · κ ⟫
  = ↑ ⟪ va {!!} · η · σ · κ ⟫

step ⟪ ex (if e₁ e₂ e₃) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · fif e₂ e₃ η ∷ κ ⟫

step ⟪ ex (elt-ref x x₁) · η · σ · κ ⟫
  = {!!}
  
step ⟪ ex (elt-call x x₁ x₂) · η · σ · κ ⟫
  = {!!}

step ⟪ ex (=′ x x₁) · η · σ · κ ⟫ = {!!}
step ⟪ ex (+= x x₁) · η · σ · κ ⟫ = {!!}
step ⟪ ex (-= x x₁) · η · σ · κ ⟫ = {!!}

step ⟪ ex (tuple []) · η · σ · κ ⟫
  = ↑ ⟪ va (tuple []) · η · σ · κ ⟫
  
step ⟪ ex (tuple (e ∷ e∗)) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · ftuple [] e∗ η ∷ κ ⟫

step ⟪ ex (tuple-ref e n) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · ftuple-ref n ∷ κ ⟫

step ⟪ ex (+ e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f+₁ e₂ η ∷ κ ⟫

step ⟪ ex (- e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f-₁ e₂ η ∷ κ ⟫

step ⟪ ex (* e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f*₁ e₂ η ∷ κ ⟫

step ⟪ ex (or e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · for₁ e₂ η ∷ κ ⟫

step ⟪ ex (and e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · fand₁ e₂ η ∷ κ ⟫

step ⟪ ex (not e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fnot ∷ κ ⟫

step ⟪ ex (< e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f<₁ e₂ η ∷ κ ⟫

step ⟪ ex (<= e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f<=₁ e₂ η  ∷ κ ⟫

step ⟪ ex (> e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f>₁ e₂ η  ∷ κ ⟫

step ⟪ ex (>= e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f>=₁ e₂ η  ∷ κ ⟫

step ⟪ ex (== e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f==₁ e₂ η  ∷ κ ⟫

step ⟪ ex (!= e₁ e₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · f!=₁ e₂ η  ∷ κ ⟫

step ⟪ ex (Expression.map f e e∗) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fmap₁ f e∗ η ∷ κ ⟫
  
step ⟪ ex (fold f e₁ e₂ e∗) · η · σ · κ ⟫
  = ↑ ⟪ ex e₁ · η · σ · ffold₁ f e₂ e∗ η ∷ κ ⟫

step ⟪ ex (call f []) · η · σ · κ ⟫
  = ↑ ⟪ fn f [] · η · σ · fcall₂ [] ∷ κ ⟫

step ⟪ ex (call f (e ∷ e∗)) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fcall₁ f [] e∗ η ∷ κ ⟫

step ⟪ ex (new t []) · η · σ · κ ⟫
  = ↑ ⟪ (va (new t [])) · η · σ · κ ⟫

step ⟪ ex (new t (fl ∷ nf∗)) · η · σ · κ ⟫
  = ↑ ⟪ nf fl · η · σ · fnew t [] nf∗ η ∷ κ ⟫

step ⟪ ex (seq [] e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · κ ⟫

step ⟪ ex (seq (e ∷ e∗) e′) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fseq [] e∗ e′ η ∷ κ ⟫

step ⟪ ex (cast t e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fcast t ∷ κ ⟫

step ⟪ ex (disclose e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fdisclose ∷ κ ⟫ 

step ⟪ ex (assert e msg) · η · σ · κ ⟫
  = ↑ ⟪ (ex e) · η · σ · fassert msg ∷ κ ⟫

step ⟪ fn (fref x) a∗ · η · σ · κ ⟫ = {!!}
step ⟪ fn (fref1 x x₁) a∗ · η · σ · κ ⟫ = {!!}

step ⟪ fn (circuit pats t s) a∗ · η · σ · κ ⟫
  = do v∗ ← maybe′ ↑ matchError $ match∗ pats a∗
       ↑ ⟪ st s · v∗ ++ η · σ · κ ⟫
       
step ⟪ nf (spread e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fspread ∷ κ ⟫ 

step ⟪ nf (positional e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fpositional ∷ κ ⟫

step ⟪ nf (named name e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fnamed name ∷ κ ⟫

step ⟪ st (statement-expression e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fstexp ∷ κ ⟫
  
step ⟪ st (return e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · freturn ∷ κ ⟫
  
step ⟪ st (const pat t e) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fconst pat t η ∷ κ ⟫
  
step ⟪ st (if e s₁ s₂) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · fifs s₁ s₂ η ∷ κ ⟫

step ⟪ st (for name e s) · η · σ · κ ⟫
  = ↑ ⟪ ex e · η · σ · ffor name s η ∷ κ ⟫
  
step ⟪ st (block []) · η · σ · κ ⟫
  = ↑ ⟪ va (tuple []) · η · σ · κ ⟫
  
step ⟪ st (block (s ∷ s∗)) · η · σ · κ ⟫
  = ↑ ⟪ st s · η · σ · fblock s∗ η ∷ κ ⟫

step ⟪ va v · η · σ · [] ⟫
  = stop

step ⟪ va v · η · σ · halt ∷ κ ⟫
  = stop
  
step ⟪ va (quote′ (inj₂ true)) · η · σ · fif e₁ e₂ η′ ∷ κ ⟫
  = ↑ ⟪ ex e₁ · η′ · σ · κ ⟫
  
step ⟪ va (quote′ (inj₂ false)) · η · σ · fif e₁ e₂ η′ ∷ κ ⟫
  = ↑ ⟪ ex e₂ · η′ · σ · κ ⟫
  
step ⟪ va _ · η · σ · fif e₁ e₂ η′ ∷ κ ⟫
  = configurationError

step ⟪ va v · η · σ · ftuple v∗ [] _ ∷ κ ⟫
  = ↑ ⟪ va (tuple (v∗ ++ [ v ])) · η · σ · κ ⟫
  
step ⟪ va v · η · σ · ftuple v∗ (e ∷ e∗) η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · ftuple (v∗ ++ [ v ]) e∗ η′ ∷ κ ⟫

step ⟪ va (tuple v∗) · η · σ · ftuple-ref n ∷ κ ⟫
  = do v ← deref n v∗
       ↑ ⟪ va v · η · σ · κ ⟫

step ⟪ va _ · η · σ · ftuple-ref n ∷ κ ⟫
  = configurationError

step ⟪ va v · η · σ · f+₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f+₂ v ∷ κ ⟫
  
step ⟪ va v · η · σ · f-₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f-₂ v ∷ κ ⟫

step ⟪ va v · η · σ · f*₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f*₂ v ∷ κ ⟫
  
step ⟪ va (quote′ (inj₂ true)) · η · σ · for₁ e η′ ∷ κ ⟫
  = ↑ ⟪ va (quote′ (inj₂ true)) · η · σ · κ ⟫

step ⟪ va (quote′ (inj₂ false)) · η · σ · for₁ e η′ ∷ κ ⟫ 
  = ↑ ⟪ ex e · η′ · σ · κ ⟫

step ⟪ va _ · η · σ · for₁ e η′ ∷ κ ⟫ 
  = configurationError

step ⟪ va (quote′ (inj₂ false)) · η · σ · fand₁ e η′ ∷ κ ⟫
  = ↑ ⟪ va (quote′ (inj₂ false)) · η · σ · κ ⟫
  
step ⟪ va (quote′ (inj₂ true)) · η · σ · fand₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · κ ⟫

step ⟪ va _ · η · σ · fand₁ e η′ ∷ κ ⟫
  = configurationError 
  
step ⟪ va v · η · σ · f<₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f<₂ v ∷ κ ⟫
  
step ⟪ va v · η · σ · f<=₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f<=₂ v ∷ κ ⟫
  
step ⟪ va v · η · σ · f>₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f>₂ v ∷ κ ⟫
  
step ⟪ va v · η · σ · f>=₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f>=₂ v ∷ κ ⟫

step ⟪ va v · η · σ · f==₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f==₂ v ∷ κ ⟫
  
step ⟪ va v · η · σ · f!=₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f!=₂ v ∷ κ ⟫

-- TODO: assignments desugar to ledger ops. Do we need these rules?
step ⟪ va v · η · σ · f=′₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f=′₂ v ∷ κ ⟫ 
step ⟪ va v · η · σ · f+=₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f+=₂ v ∷ κ ⟫
step ⟪ va v · η · σ · f-=₁ e η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · f-=₂ v ∷ κ ⟫

step ⟪ va v · η · σ · f+₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f-₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f*₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f<₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f<=₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f>₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f>=₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f==₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f!=₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f=′₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f+=₂ v′ ∷ κ ⟫ = {!!}
step ⟪ va v · η · σ · f-=₂ v′ ∷ κ ⟫ = {!!}

step ⟪ va (quote′ (inj₂ false)) · η · σ · fnot ∷ κ ⟫
  = ↑ ⟪ va (quote′ (inj₂ true)) · η · σ · κ ⟫
  
step ⟪ va (quote′ (inj₂ true)) · η · σ · fnot ∷ κ ⟫
  = ↑ ⟪ va (quote′ (inj₂ false)) · η · σ · κ ⟫
  
step ⟪ va _ · η · σ · fnot ∷ κ ⟫
  = configurationError

step ⟪ va (tuple v∗) · η · σ · fmap₁ fun [] η′ ∷ κ ⟫
  = ↑ ⟪ ex (tuple (mapᴸ (call fun ∘ [_]) v∗)) · η · σ · κ ⟫
  
step ⟪ va _ · η · σ · fmap₁ fun [] η′ ∷ κ ⟫
  = configurationError
  
step ⟪ va v · η · σ · fmap₁ fun (e ∷ e∗) η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · fmap₂ fun v [] e∗ η′ ∷ κ ⟫

step ⟪ va v · η · σ · fmap₂ fun v′ v∗ [] η′ ∷ κ ⟫
  = {!!}
  
step ⟪ va v · η · σ · fmap₂ fun v′ v∗ (e ∷ e∗) η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η · σ · fmap₂ fun v′ (v∗ ++ [ v ]) e∗ η′ ∷ κ ⟫

step ⟪ va v · η · σ · ffold₁ fun e e∗ η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · ffold₂ fun v e∗ η′ ∷ κ ⟫

step ⟪ va (tuple []) · η · σ · ffold₂ fun v′ [] η′ ∷ κ ⟫
  = ↑ ⟪ {!!} · {!!} · {!!} · {!!} ⟫
step ⟪ va _ · η · σ · ffold₂ fun v′ [] η′ ∷ κ ⟫
  = configurationError 
step ⟪ va v · η · σ · ffold₂ fun v′ (e ∷ e∗) η′ ∷ κ ⟫
  = ↑ ⟪ ex e · η′ · σ · ffold₃ fun v′ v [] e∗ η′ ∷ κ ⟫

step ⟪ va v · η · σ · ffold₃ x x₁ x₂ x₃ x₄ x₅ ∷ κ ⟫ = {!!}

step ⟪ va v · η · σ · fcall₁ x x₁ x₂ x₃ ∷ κ ⟫
  = {!!}
step ⟪ va v · η · σ · fcall₂ x ∷ κ ⟫
  = {!!}

step _ = {!!} 

-- step ⟪ va v · η · σ · fnew x x₁ x₂ x₃ ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fseq x x₁ x₂ x₃ ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fcast x ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fdisclose ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fassert x ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fnamed x ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fspread ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fpositional ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fstexp ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · freturn ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fconst x x₁ x₂ ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fifs x x₁ x₂ ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · ffor x x₁ x₂ ∷ κ ⟫ = {!!}
-- step ⟪ va v · η · σ · fblock x x₁ ∷ κ ⟫ = {!!}
