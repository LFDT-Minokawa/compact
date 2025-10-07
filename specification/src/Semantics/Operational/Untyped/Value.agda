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

open import Data.Sum using (_⊎_; inj₁ ; inj₂)
open import Data.List using (List ; _∷_ ; [] ; _++_)
open import Data.Nat using (ℕ ; suc ; zero)
open import Data.Bool using (Bool ; true ; false ; _∧_)
open import Data.Maybe using (_>>=_ ; Maybe ; just ; nothing)
open import Data.Product using (_×_ ; _,_ ; Σ) 
open import Data.List.Relation.Unary.All using (All ; [] ; _∷_)
open import Function

module Semantics.Operational.Untyped.Value (𝓟 : Set) where

open import Syntax.Generated.Lsrc
open import Semantics.Operational.Untyped.Substitution
open import Semantics.Operational.Untyped.State 𝓟

b· = quote′ ∘ inj₂
n· = quote′ ∘ inj₁
u· : Expression 
u· = tuple [] 

mutual 
  data IsValue : (expr : Expression) → Set where 
    vquote : (x : ℕ ⊎ Bool) → IsValue (quote′ x) 
    vtuple : All IsValue expr∗ → IsValue (tuple expr∗)
    vnew   : All IsNFValue new-field∗ → IsValue (new tref new-field∗)

  data IsNFValue : (new-field : New-Field) → Set where 
    nfvpositional : IsValue expr → IsNFValue (positional expr)
    nfvnamed      : IsValue expr → IsNFValue (named name expr)

mutual
  compare-nat : (x y : ℕ) → Bool
  compare-nat zero zero = true
  compare-nat zero (suc y) = false
  compare-nat (suc x) zero = false
  compare-nat (suc x) (suc y) = compare-nat x y

  compare-lit : (x y : ℕ ⊎ Bool) → Bool 
  compare-lit (inj₁ x) (inj₁ y) = compare-nat x y
  compare-lit (inj₁ x) (inj₂ y) = false
  compare-lit (inj₂ y₁) (inj₁ x) = false
  compare-lit (inj₂ false) (inj₂ false) = true
  compare-lit (inj₂ false) (inj₂ true) = false
  compare-lit (inj₂ true) (inj₂ false) = false
  compare-lit (inj₂ true) (inj₂ true) = true

  compare-value : (v₁ : IsValue expr₁) (v₂ : IsValue expr₂) → Bool
  compare-value (vquote x) (vquote y) = compare-lit x y
  compare-value (vquote _) _ = false 
  compare-value (vtuple x) (vtuple y) = compare-value∗ x y 
  compare-value (vtuple _) _ = false 
  compare-value (vnew xs) (vnew ys) = compare-nfvalue∗ xs ys
  compare-value (vnew _) _ = false

  compare-nfvalue : IsNFValue new-field₁ → IsNFValue new-field₂ → Bool
  compare-nfvalue (nfvpositional v₁) (nfvpositional v₂) = compare-value v₁ v₂
  compare-nfvalue (nfvpositional x) (nfvnamed x₁) = false -- Does it have to be? 
  compare-nfvalue (nfvnamed x) (nfvpositional x₁) = false
  compare-nfvalue (nfvnamed v₁) (nfvnamed v₂) = compare-value v₁ v₂

  compare-nfvalue∗ : ∀ {xs ys} → All IsNFValue xs → All IsNFValue ys → Bool
  compare-nfvalue∗ [] [] = true
  compare-nfvalue∗ [] (px ∷ ys) = false
  compare-nfvalue∗ (px ∷ xs) [] = false
  compare-nfvalue∗ (x ∷ xs) (y ∷ ys) = compare-nfvalue x y ∧ compare-nfvalue∗ xs ys

  compare-value∗ : ∀ {expr∗′} → (v∗₁ : All IsValue expr∗) (v∗₂ : All IsValue expr∗′) → Bool
  compare-value∗ [] [] = true
  compare-value∗ [] (px ∷ v₂) = false
  compare-value∗ (px ∷ v∗₁) [] = false
  compare-value∗ (v₁ ∷ v∗₁) (v₂ ∷ v∗₂) = compare-value v₁ v₂ ∧ compare-value∗ v∗₁ v∗₂

module _ where 

  match : Pattern → Expression → Maybe (List (Name × Expression))
  match (var-name name) expr
    = just ((name , expr) ∷ [])
  match (tuple xs) (tuple ys) = combine xs ys
    where
      combine
        : List (Maybe Pattern)
        → List Expression
        → Maybe (List (Name × Expression))
      combine [] []
        = just []
      combine [] (_ ∷ _)
        = nothing
      combine (_ ∷ _) []
        = nothing
      combine (just pat ∷ xs) (expr ∷ ys)
        = do
          xs′ ← match pat expr
          ys′ ← combine xs ys 
          just (xs′ ++ ys′)
      combine (nothing ∷ xs) (_ ∷ ys)
        = combine xs ys
  match (tuple _) _
    = nothing
  match (struct pats) (new struct-type fields)
    = match-fields pats fields
    where
      match-fields
        : List (Pattern × Name)
        → List New-Field
        → Maybe (List (Name × Expression))
      match-fields [] []
        = just []
      match-fields [] (x ∷ fields)
        = nothing
      match-fields (x ∷ pats) []
        = nothing

      -- TODO: how should matching on struct values proceed if named
      -- arguments don't occur in order?
      match-fields
        ((pat , name) ∷ pats) (positional expr ∷ fields)
        = do
          xs ← match pat expr
          ys ← match-fields pats fields
          just (xs ++ ys) 
      match-fields
        ((pat , name) ∷ pats) (named name′ expr ∷ fields)
        = do
          xs ← match pat expr
          ys ← match-fields pats fields
          just (xs ++ ys) 

      -- Unclear how to evaluate a pattern match on a struct value
      -- constructed using a spread.
      --
      -- Idea: don't consider struct values with spreads as
      -- values. Rather, all struct values can (and should) be
      -- normalized to a collection of named/positional arguments
      -- before executing the match.
      match-fields ((pat , name) ∷ pats) (spread x ∷ fields)
        = nothing
  match (struct _) _
    = nothing

  match∗
    : List Pattern-Argument
    → List Expression
    → Maybe (List (Name × Expression))
  match∗ [] []
    = just []
  match∗ [] (_ ∷ _)
    = nothing
  match∗ (_ ∷ _) []
    = nothing
  match∗ (unnamed pat _ ∷ parg∗) (expr ∷ expr∗) = do
    xs ← match pat expr
    ys ← match∗ parg∗ expr∗
    just (xs ++ ys)

  σ-parg
    : List Pattern-Argument
    → List Expression
    → Maybe Substitution
  σ-parg [] []
    = nothing
  σ-parg [] (_ ∷ _)
    = nothing
  σ-parg (_ ∷ _) []
    = nothing
  σ-parg (unnamed pat _ ∷ parg∗) (expr ∷ expr∗) = do
    xs ← match pat expr
    σ  ← σ-parg parg∗ expr∗
    just ⟪ xs , σ ⟫∗ 
  
  Value = Σ Expression IsValue
  NFValue = Σ New-Field IsNFValue

  variable value value₁ value₂ value₃ value′ : Value
  variable value∗ : List Value

  -- TODO: this should implement casts! Right now it does nothing
  --
  -- Before we can implement this we ought to define how 
  castv : Type → Value → Value 
  castv _ = id
