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



{-# OPTIONS --safe --without-K #-} 

-- This really ought to be generated together with the syntax definition ... 
module Semantics.Operational.Untyped.Substitution where

open import Syntax.Generated.Lsrc

open import Data.List hiding (and; or)
open import Data.String
open import Data.String.Properties using (_==_)
open import Data.Bool hiding (not)
open import Data.Product 

Substitution : Set
Substitution = String → Expression


mutual 
  substitute-expr
    : Substitution → Expression → Expression
  substitute-expr σ (quote′ x)
    = quote′ x
  substitute-expr σ (var-ref x)
    = σ x
  substitute-expr σ (default x)
    = default x
  substitute-expr σ (if x y z)
    = if (substitute-expr σ x) (substitute-expr σ y) (substitute-expr σ z)
  substitute-expr σ (elt-ref x y)
    = elt-ref (substitute-expr σ x) y
  substitute-expr σ (elt-call x y z)
    = elt-call (substitute-expr σ x) y (substitute-expr∗ σ z)
  substitute-expr σ (=′ x y)
    = =′ (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (+= x y)
    = += (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (-= x y)
    = -= (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (tuple x)
    = tuple (substitute-expr∗ σ x)
  substitute-expr σ (tuple-ref x y)
    = tuple-ref (substitute-expr σ x) y
  substitute-expr σ (+ x y)
    = + (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (- x y)
    = - (substitute-expr σ x) (substitute-expr σ y) 
  substitute-expr σ (* x y)
    = * (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (or x y)
    = or (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (and x y)
    = and (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (not x)
    = not (substitute-expr σ x)
  substitute-expr σ (< x y)
    = < (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (<= x y)
    = <= (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (> x y)
    = > (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (>= x y)
    = >= (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (== x y)
    = == (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (!= x y)
    = != (substitute-expr σ x) (substitute-expr σ y)
  substitute-expr σ (Expression.map x y z)
    = Expression.map (substitute-fun σ x) (substitute-expr σ y) (substitute-expr∗ σ z)
  substitute-expr σ (fold x y z w)
    = fold (substitute-fun σ x) (substitute-expr σ y) (substitute-expr σ z) (substitute-expr∗ σ w)
  substitute-expr σ (call x y)
    = call (substitute-fun σ x) (substitute-expr∗ σ y)
  substitute-expr σ (new x y)
    = new x (substitute-nf∗ σ y)
  substitute-expr σ (seq x y)
    = seq (substitute-expr∗ σ x) (substitute-expr σ y)
  substitute-expr σ (cast x y)
    = cast x (substitute-expr σ y)
  substitute-expr σ (disclose x)
    = disclose (substitute-expr σ x)
  substitute-expr σ (assert x msg)
    = assert (substitute-expr σ x) msg

  substitute-expr∗
    : Substitution → List Expression → List Expression
  substitute-expr∗ σ []
    = []
  substitute-expr∗ σ (x ∷ xs)
    = substitute-expr σ x ∷ substitute-expr∗ σ xs 

  substitute-fun
    : Substitution → Function → Function
  substitute-fun σ (fref x)
    = fref x
  substitute-fun σ (fref1 x y)
    = fref1 x y
  substitute-fun σ (circuit x y z)
    = circuit x y (substitute-stmt σ z)

  substitute-nf
    : Substitution → New-Field → New-Field
  substitute-nf σ (spread x)
    = spread (substitute-expr σ x)
  substitute-nf σ (positional x)
    = positional (substitute-expr σ x)
  substitute-nf σ (named x y)
    = named x (substitute-expr σ y)

  substitute-nf∗
    : Substitution → List New-Field → List New-Field 
  substitute-nf∗ σ []
    = []
  substitute-nf∗ σ (x ∷ xs)
    = substitute-nf σ x ∷ substitute-nf∗ σ xs

  substitute-stmt
    : Substitution → Statement → Statement  
  substitute-stmt σ (statement-expression x)
      = statement-expression (substitute-expr σ x)
  substitute-stmt σ (return x)
    = return (substitute-expr σ x)
  substitute-stmt σ (const pat y z)
    = const pat y (substitute-expr σ z)
  substitute-stmt σ (if x y z)
    = if (substitute-expr σ x) (substitute-stmt σ y) (substitute-stmt σ z)
  substitute-stmt σ (for x y z)
    = for x (substitute-expr σ y) (substitute-stmt σ z)
  substitute-stmt σ (block x)
    = block (substitute-stmt∗ σ x)

  substitute-stmt∗
    : Substitution → List Statement → List Statement
  substitute-stmt∗ σ []
    = []
  substitute-stmt∗ σ (x ∷ xs)
    = substitute-stmt σ x ∷ substitute-stmt∗ σ xs

idsubst : Substitution
idsubst = var-ref

-- Extends a substitution
⟪_↦_,_⟫ : String → Expression → Substitution → Substitution
⟪ name ↦ expr , σ ⟫ = λ name′ → if _==_ name name′ then expr else σ name′ 

⟪_,_⟫∗ : List (String × Expression) → Substitution → Substitution
⟪ [] , σ ⟫∗ = σ
⟪ (name , expr) ∷ xs , σ ⟫∗ = ⟪ name ↦ expr , ⟪ xs , σ ⟫∗ ⟫

infix 5 _[_∷=_]
_[_∷=_] : Statement → String → Expression → Statement
stmt [ name ∷= expr ] = substitute-stmt ⟪ name ↦ expr , idsubst ⟫ stmt 
