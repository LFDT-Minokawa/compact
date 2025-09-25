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

open import Data.String using (String)
open import Data.List using (List ; _++_ ; [] ; _∷_) renaming (map to mapᴸ)
open import Data.Nat using (ℕ)

open import Data.Product hiding (map)

module Semantics.Operational.Untyped.Context (𝓟 : Set) where 

open import Semantics.Operational.Untyped.State 𝓟
open import Semantics.Operational.Untyped.Value 𝓟
open import Semantics.Operational.Untyped.Substitution
open import Syntax.Generated.Lsrc

module _ where

  -- Evaluation contexts for different syntactic sorts, in the style
  -- of Wright & Felleisen (1994).
  --
  -- These are chosen to enforce a leftmost-outermost reduction
  -- strategy. (Is this wat Compact uses?) 
  mutual
    data CTX-NF : Set where
      SPREAD : CTX-EXPR → CTX-NF
      POSITIONAL : CTX-EXPR → CTX-NF
      NAMED : String → CTX-EXPR → CTX-NF 

    data CTX-EXPR : Set where 
      IF : CTX-EXPR → Expression → Expression → CTX-EXPR
      TUPLE : List Value → CTX-EXPR → List Expression → CTX-EXPR
      TUPLE-REF : CTX-EXPR → ℕ → CTX-EXPR
      _+₁_ _-₁_ _*₁_ OR AND _<₁_ _<=₁_ _>₁_ _>=₁_ _==₁_ _!=₁_ : CTX-EXPR → Expression → CTX-EXPR
      _+₂_ _-₂_ _*₂_ _<₂_ _<=₂_ _>₂_ _>=₂_ _==₂_ _!=₂_ : Value → CTX-EXPR → CTX-EXPR
      _=′₁_ _+=₁_ _-=₁_ : CTX-EXPR → Expression → CTX-EXPR
      _=′₂_ _+=₂_ _-=₂_ : Value → CTX-EXPR → CTX-EXPR
      MAP₁ : Function → CTX-EXPR → List Expression → CTX-EXPR
      MAP₂ : Function → Value → List Value → CTX-EXPR → List Expression → CTX-EXPR
      FOLD₁ : Function → CTX-EXPR → Expression → List Expression → CTX-EXPR
      FOLD₂ : Function → Value → CTX-EXPR → List Expression → CTX-EXPR
      FOLD₃ : Function → Value → Value → List Value → CTX-EXPR → List Expression → CTX-EXPR
      CALL  : Function → List Value → CTX-EXPR → List Expression → CTX-EXPR
      NEW   : Type-Ref → List NFValue → CTX-NF → List New-Field → CTX-EXPR
      SEQ   : List Value → CTX-EXPR → List Expression → Expression → CTX-EXPR
      CAST  : Type → CTX-EXPR → CTX-EXPR
      ASSERT : CTX-EXPR → (msg : String) → CTX-EXPR
      ■     : CTX-EXPR

    data CTX-STMT : Set where
      EXPR : CTX-EXPR → CTX-STMT
      RETURN : CTX-EXPR → CTX-STMT
      CONST : Pattern → Type → CTX-EXPR → CTX-STMT
      IFS : CTX-EXPR → Statement → Statement → CTX-STMT
      FOR : String → CTX-EXPR → Statement → CTX-STMT
      BLOCK : CTX-STMT → List Statement → CTX-STMT

    _·[_]NF : CTX-NF → Expression → New-Field
    SPREAD E ·[ expr ]NF = spread (E ·[ expr ])
    POSITIONAL E ·[ expr ]NF = positional (E ·[ expr ])
    NAMED name E ·[ expr ]NF = named name (E ·[ expr ])
  
    _·[_]
      : CTX-EXPR → Expression → Expression
    IF E expr₁ expr₂ ·[ expr ]
      = if (E ·[ expr ]) expr₁ expr₂
    (E =′₁ expr′) ·[ expr ]
      = =′ (E ·[ expr ]) expr′
    (E +=₁ expr′) ·[ expr ]
      = += (E ·[ expr ]) expr′
    (E -=₁ expr′) ·[ expr ]
      = -= (E ·[ expr ]) expr′
    (value =′₂ E) ·[ expr ]
      = =′ (value .proj₁) (E ·[ expr ])
    (value +=₂ E) ·[ expr ]
      = += (value .proj₁) (E ·[ expr ])
    (value -=₂ E) ·[ expr ]
      = -= (value .proj₁) (E ·[ expr ])
    TUPLE value∗ E expr∗ ·[ expr ]
      = tuple (mapᴸ proj₁ value∗ ++ (E ·[ expr ] ∷ []) ++ expr∗)
    TUPLE-REF E n ·[ expr ]
      = tuple-ref (E ·[ expr ]) n
    (E +₁ expr′) ·[ expr ]
      = + (E ·[ expr ]) expr′
    (E -₁ expr′) ·[ expr ]
      = - (E ·[ expr ]) expr′
    (E *₁ expr′) ·[ expr ]
      = * (E ·[ expr ]) expr′
    OR E expr′ ·[ expr ]
      = or (E ·[ expr ]) expr′
    AND E expr′ ·[ expr ]
      = and (E ·[ expr ]) expr′
    (E <₁ expr′) ·[ expr ]
      = < ((E ·[ expr ])) expr′
    (E <=₁ expr′) ·[ expr ]
      = <= ((E ·[ expr ])) expr′
    (E >₁ expr′) ·[ expr ]
      = > ((E ·[ expr ])) expr′
    (E >=₁ expr′) ·[ expr ]
      = >= ((E ·[ expr ])) expr′
    (E ==₁ expr′) ·[ expr ]
      = == ((E ·[ expr ])) expr′
    (E !=₁ expr′) ·[ expr ]
      = != ((E ·[ expr ])) expr′
    (value +₂ E) ·[ expr ]
      = + (value .proj₁) ((E ·[ expr ]))
    (value -₂ E) ·[ expr ]
      = - (value .proj₁) ((E ·[ expr ]))
    (value *₂ E) ·[ expr ]
      = * (value .proj₁) ((E ·[ expr ]))
    (value <₂ E) ·[ expr ]
      = < (value .proj₁) ((E ·[ expr ]))
    (value <=₂ E) ·[ expr ]
      = <= (value .proj₁) ((E ·[ expr ]))
    (value >₂ E) ·[ expr ]
      = > (value .proj₁) ((E ·[ expr ]))
    (value >=₂ E) ·[ expr ]
      = >= (value .proj₁) ((E ·[ expr ]))
    (value ==₂ E) ·[ expr ]
      = == (value .proj₁) ((E ·[ expr ]))
    (value !=₂ E) ·[ expr ]
      = != (value .proj₁) ((E ·[ expr ]))
    MAP₁ fun E expr∗ ·[ expr ]
      = map fun ((E ·[ expr ])) expr∗
    MAP₂ fun value value∗ E expr∗ ·[ expr ]
      = map fun (value .proj₁) (mapᴸ proj₁ value∗ ++ (((E ·[ expr ])) ∷ []) ++ expr∗ )
    FOLD₁ fun E expr′ expr∗ ·[ expr ]
      = fold fun ((E ·[ expr ])) expr′ expr∗
    FOLD₂ fun value E expr∗ ·[ expr ]
      = fold fun (value .proj₁) ((E ·[ expr ])) expr∗
    FOLD₃ fun value₁ value₂ value∗ E expr∗ ·[ expr ]
      = fold fun (value₁ .proj₁) (value₂ .proj₁) (mapᴸ proj₁ value∗ ++ (((E ·[ expr ])) ∷ []) ++ expr∗)
    CALL fun value∗ E expr∗ ·[ expr ]
      = call fun (mapᴸ proj₁ value∗ ++ (((E ·[ expr ])) ∷ []) ++ expr∗)
    NEW tref nfv∗ F new-field∗ ·[ expr ]
      = new tref (mapᴸ proj₁ nfv∗ ++ ((F ·[ expr ]NF) ∷ []) ++ new-field∗) 
    SEQ value∗ E expr∗ expr′ ·[ expr ]
      = Expression.seq ((mapᴸ proj₁ value∗ ++ (((E ·[ expr ])) ∷ []) ++ expr∗)) expr′
    CAST type E ·[ expr ]
      = cast type (E ·[ expr ])
    ASSERT E msg ·[ expr ]
      = assert (E ·[ expr ]) msg
    ■ ·[ expr ]
      = expr
  
    _·[_]S : CTX-STMT → Expression → Statement
    EXPR E ·[ expr ]S
      = statement-expression (E ·[ expr ])
    RETURN E ·[ expr ]S
      = return (E ·[ expr ])
    CONST pat type E ·[ expr ]S
      = Statement.const pat type (E ·[ expr ])
    IFS E stmt₁ stmt₂ ·[ expr ]S
      = if (E ·[ expr ]) stmt₁ stmt₂
    FOR name E stmt ·[ expr ]S
      = for name (E ·[ expr ]) stmt
    BLOCK S stmt∗ ·[ expr ]S
      = block ((S ·[ expr ]S) ∷ stmt∗)

  variable E E₁ E₂ E′ : CTX-EXPR
  variable S S₁ S₂ S′ : CTX-STMT
