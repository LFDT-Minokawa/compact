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



{-# OPTIONS --without-K --safe #-} 

--
-- This file contains some auxiliary definitions that check coverage
-- of a typing relation defined over compiler-generated syntax
-- definitions. 
--
-- 
import Agda.Builtin.Reflection as R
open import Reflection.TCM.Syntax
  using ( _>>_ ; _>>=_ )
open import Function
  using ( _∘_ ; case_of_ ; _$_ )

import Data.List as L
open import Data.Nat
  using ( ℕ ; suc ; zero ) 
open import Data.Product
  using ( _×_ ; _,_ ; ∃ ; ∃₂ ; proj₁ ; Σ )
open import Data.String
  using ( String ; wordsBy ; _==_ )
open import Data.Bool
  using ( Bool ; T? ; if_then_else_ )
open import Agda.Builtin.Char
  using ( primCharEquality )
open import Data.Sum
  using ( _⊎_ ; inj₁ ; inj₂ )
  renaming ( [_,_] to ⊎[_,_] )
open import Data.Unit
  using ( ⊤ ; tt )
open import Data.String
  using (_++_ ) 

open import Data.List.Membership.Propositional
  using ( _∈_ )
open import Data.List.Relation.Unary.All
  using ( All ; _∷_ ; [] )

open import Util.ListSyntax
  using ( [_] )

module Semantics.Static.Coverage where 


-- A "Typing" for a given syntactic object `S`.
--
-- We define typings either as a three-place relation over context, syntax, and, index: 
-- 
-- R <context> <syntax> <index>
--
-- Or, as a two-place relation over context and syntax:  
--
-- R <context> <syntax>
--
Typing : (S : Set) → Set₁
Typing S =
  ( ∃ λ
      (CTX : Set) →
        CTX → S → Set
  ) ⊎ ∃₂ λ
    (CTX : Set) (I : CTX → Set) →
       (ctx : CTX) → S → I ctx → Set


-- Characterizes syntax definitions with a typing relation.
--
-- The compiler generates a mutually recursive family of data types
-- (together with a string for each data type that defines the
-- metavariables ranging over that type). This family has a typing if
-- we have a typing relation for each member of the family. 
-- 
record HasTyping (syn : L.List  (Set × String)) : Set₁ where
  field
    rels : All (Typing ∘ proj₁) syn

open HasTyping ⦃...⦄ public

-- Turns a qualified name into an unqualifed one. 
unqualify
  : Data.String.String
  → Data.String.String
unqualify s with wordsBy (T? ∘ primCharEquality '.') s
... | L.[]       = ""
... | (x L.∷ xs) = lastname xs x
  where
  lastname
    : L.List  Data.String.String
    → Data.String.String
    → Data.String.String
  lastname L.[]       s
    = s
  lastname (x L.∷ xs) s
    = lastname xs x

--
-- Checks for a given syntax definition and typing relation over this
-- defintion whether the typing relation is complete. That is, for
-- every constructor there should be at least one typing rule
-- corresponding to that constructor.
--
-- We can force a type systme to be deterministic (or, syntax
-- directed) by checking the converse as well. That is, there is at
-- most one typing rule per constructor.
--
checkTyping
  : (syn : R.Name)
  → (ty  : R.Name)
  → R.TC (L.List  R.ErrorPart)
checkTyping syn ty = do
  def ← R.getDefinition ty
  case def of λ where
    (R.data-type pars cs) → do
      is   ← getIndices pars cs
      def′ ← R.getDefinition syn
      case def′ of λ where 
        (R.data-type pars cs) → compareNames cs is
        _ → 
          R.typeError
            [ R.strErr "Syntax definition not defined as data type" ]
    _ → 
      R.typeError
        [ R.strErr "Typing relation not defined as a Data Type: "
        , R.nameErr ty
        ]
  where
    -- Finds the return type of a (nested) Pi type 
    returnType
      : R.Type
      → R.Type
    returnType (R.pi a (R.abs _ t))
      = returnType t
    returnType t
      = t 

    -- Retrieves the type expression corresponding to the index
    -- position given the type signature of a constructor.
    --
    -- The index position (1st param) is given by the number of
    -- parameters + 1.
    --
    -- Throws an error if the index is larger than the number of
    -- arguments.
    getIndex :
        ℕ
      → L.List (R.Arg R.Type)
      → R.TC R.Type 
    getIndex _       L.[]
      = R.typeError
          [ R.strErr "Index out of bounds" ]
    getIndex zero    (R.arg _ t L.∷ xs)
      = R.returnTC t
    getIndex (suc n) (x L.∷ xs)
      = getIndex n xs

    -- Retrieves a list of the names of all the constructors that are
    -- covered by the relation. 
    getIndices :
        ℕ
      → L.List R.Name
      → R.TC (L.List  R.Name)
    getIndices pars L.[]
      = R.returnTC L.[]
    getIndices pars (c L.∷ cs) = do
      type ← R.getType c >>= R.normalise
      let rtype = returnType type
      case rtype of λ where 
        (R.def name args) → do
          i ← getIndex pars args 
          case i of λ where
            (R.con n _) → do  
              xs ← getIndices pars cs
              R.returnTC (n L.∷ xs) 
            _ →
              R.typeError
                [ ( R.strErr
                      $  "Found something that's not a constructor in "
                      ++ "the syntax-position of a typing relation: ") 
                , R.nameErr c 
                ] 
        _ →
          R.typeError
            [ R.strErr (
              "This shouldn't happen;"
              ++ "the return type of a constructor was found to be"
              ++ "something else than a defined name. ")
            ]

    -- Looks up a constructur name in the list of constructors covered
    -- by a relation, accumulating an error message if the relation
    -- doesn't cover it.
    findName
      : (c : R.Name)
      → (is : L.List  R.Name)
      → R.TC (L.List  R.ErrorPart)
    findName x L.[]
      = R.returnTC
          [ R.strErr "  ---> No typing rule found for constructor "
          , R.nameErr x
          , R.strErr "\n" 
          ]
    findName c (i L.∷ is)
      = if ( unqualify (R.primShowQName c))
               == (unqualify (R.primShowQName i) )
        then
          R.returnTC L.[] 
        else
          findName c is

    -- Check if all names in the first list occur in the 2nd list  
    compareNames
      : (cs is : L.List  R.Name)
      → R.TC (L.List  R.ErrorPart) 
    compareNames cs is
      = go cs 
      where
        go
          : (cs : L.List  R.Name)
          → R.TC (L.List  R.ErrorPart)
        go L.[] = R.returnTC L.[]
        go (c L.∷ cs) = do
          err  ← findName c is 
          errs ← go cs
          R.returnTC (err L.++ errs) 


-- Checks the given typings for a syntax family are covering relation.
--
-- The meta-program gathers a list of constructors for which typing
-- rules are missing, and emits a single error message for the entire
-- syntax family if one or more typing rules are missing (rather than
-- striking out at the first missing rule). 
checkRels
  : L.List  (Σ Set Typing)
  → L.List  R.ErrorPart
  → R.TC ⊤
checkRels L.[] L.[]
  = R.returnTC tt
checkRels L.[] errs@(_ L.∷ _)
  = R.typeError errs
checkRels ((A , R) L.∷ xs) errs = do
  x     ← getNameOfSet A
  y     ← getNameOfRel R
  errs′ ← checkTyping x y
  case errs′ of λ where
    L.[] →
      checkRels xs (errs L.++ errs′) 
    _ →
      checkRels xs
        ( errs L.++
        [ ( R.strErr
              $  "\nDiscovered missing rule(s) while checking coverage "
              ++ "of relation " )
        , R.nameErr y , R.strErr "\n"
        ] L.++ errs′
        )  
  where
    -- Given an index type A, if it's given by a named definition,
    -- retrieve the name. Throws an error if the given set doesn't
    -- normalize to a defined name.
    getNameOfSet
      : (A : Set)
      → R.TC R.Name
    getNameOfSet A = do
      t ← R.quoteTC A >>= R.normalise 
      case t of λ where
        (R.def n _) →
          R.returnTC n
        _           →
          R.typeError
            [ ( R.strErr
                  $  "Expected name when quoting a syntax definition, but " 
                  ++ "found something else instead: " )
            , R.termErr t
            ]

    -- Retrieves the name of a given typing relation. Throws an error
    -- if the typing object doesn't normalize to a defined name.
    getNameOfRel
      : ∀ {A}
      → (T : Typing A)
      → R.TC R.Name
    getNameOfRel (inj₁ (_ , T))     = do
      t ← R.quoteTC T >>= R.normalise
      case t of λ where
        (R.def n _) →
          R.returnTC n
        _ →
          R.typeError
            [ ( R.strErr
                  $  "Expected name when quoting a syntax definition, but found "
                  ++ "something else instead: " )
            , R.termErr t
            ]
    getNameOfRel (inj₂ (_ , _ , T)) = do
      t ← R.quoteTC T >>= R.normalise
      case t of λ where
        (R.def n _) →
          R.returnTC n
        _ →
          R.typeError
            [ ( R.strErr 
                  $  "Expected name when quoting a syntax definition, but found"
                  ++ "something else instead: " ) 
            , R.termErr t
            ]

-- Resolves typing relations for a given syntax definition
getTyping
 : ∀ syn
 → ⦃ HasTyping syn ⦄
 → L.List  (Σ Set Typing)  
getTyping syn ⦃ x ⦄
  = zipAll syn rels
  where
    zipAll :
      ∀ {a b} {A : Set a} {P : A → Set b}
      → (xs : L.List  (A × String))
      → All (P ∘ proj₁) xs
      → L.List  (Σ A P)
    zipAll L.[] []
      = L.[]
    zipAll ((x , _) L.∷ xs) (px ∷ pxs)
      = (x , px) L.∷ zipAll xs pxs
