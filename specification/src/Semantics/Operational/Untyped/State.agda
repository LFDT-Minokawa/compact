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

module Semantics.Operational.Untyped.State (𝓟 : Set) where

open import Syntax.Generated.Lsrc

open import Data.Unit 
open import Data.List 
open import Data.Nat
open import Data.Product
open import Data.Vec
open import Data.String using (String)

open import Data.List.Membership.Propositional

Name = String

variable name name₁ name₂ name′ : Name 

data Bounded (n : ℕ) : Set where
  bounded : (k : ℕ) → k ≤ n → Bounded n

getNum : ∀ n → Bounded n → ℕ
getNum n (bounded k _) = k

-- field-aligned binary format 
-- TODO change to actual FAB
AlignedValue : ∀ (n : ℕ) → Set 
AlignedValue n = Bounded n

Cell = AlignedValue

data StateType : Set where
  tnull : StateType 
  tcell : (n : ℕ) → StateType 
  tmap  : (n : ℕ) (t : StateType) → StateType
  tarray : (n : Bounded 15) (t : StateType) → StateType
  tmtree : (n : Bounded 32) (t : StateType) → StateType 

variable
  s t : StateType
  t∗ : List StateType 

-- TODO: import this from ledger spec 
data StateValue : Set where

  svNull
    : StateValue -- An empty value.
      
  cell
    : ∀ (n : ℕ) → Cell n → StateValue -- memory cell containing a single FAB AlignedValue

  svMap
    : ∀ (n : ℕ)
    → ∀ (lm : List (((AlignedValue n) × StateValue)))
    -- → left-unique-l n StateValue lm
    → StateValue 

  array
    : ∀ (a : Bounded 15)
    → Vec StateValue (getNum 15 a)
    → StateValue  

  boundedMerkleTree
    : ∀ (a : Bounded 32)
    -- → ∀ (bmt : MerkleTreeΣ vu832 StateValue emptyHashVu832)
    -- → maxDepth _ _ _ bmt (getNum 32 a)
    → StateValue  -- depth-n Merkle tree of leaf hash values, for 0 < n <= 32 


record State : Set where
  constructor <<_∙_>> 
  field
    publ : List (Name × StateValue)
    priv : 𝓟 

open State public 

record EvaluationContext : Set where
  field
    witnesses : List (Name × (List Expression → 𝓟 → 𝓟 × Expression))
    circuits  : List (Name × Circuit-Definition)
    
open EvaluationContext public 

data FunctionRef (name : Name) (𝓔 : EvaluationContext) : Set where
  rwitness : (f : List Expression → 𝓟 → 𝓟 × Expression) → (name , f) ∈ 𝓔 .witnesses → FunctionRef name 𝓔
  rcircuit : (name , cdefn) ∈ 𝓔 .circuits → FunctionRef name 𝓔
