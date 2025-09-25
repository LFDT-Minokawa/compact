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

open import Data.List hiding ([_])
open import Level
open import Data.Product 

module Util.ListSyntax where 

record ListSyntax {a b} (A : Set a) (B : Set b) : Set (a ⊔ b) where
  field [_] : B → List A

open ListSyntax ⦃ ... ⦄ public

instance
  cons : ∀ {a b} {A : Set a} {B : Set b} ⦃ _ : ListSyntax A B ⦄
       →  ListSyntax A (A × B)
  [_] ⦃ cons ⦄ (x , xs) = x ∷ [ xs ]

instance
  sing : ∀ {a} {A : Set a} → ListSyntax A A
  [_] ⦃ sing ⦄ = _∷ []
