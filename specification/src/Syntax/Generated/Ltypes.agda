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



-- ***
-- *** The language definition in this file was automatically generated from the Ltypes Nanopass IR
-- *** 
-- *** TIMESTAMP: 2025-06-26 08:26:47 
-- *** 

{-# OPTIONS --safe --without-K #-}
open import Data.String  using (String) 
open import Data.List    using (List; [] ; _∷_) 
open import Data.Bool    using (Bool)
open import Data.Nat     using (ℕ)
open import Data.Sum     using (_⊎_)
open import Data.Maybe   using (Maybe)
open import Data.Product using (_×_ ; _,_)
open import Data.Unit    using (⊤)
import Agda.Builtin.Reflection as Reflection

module Syntax.Generated.Ltypes where
  mutual
    
    -- Sort: Argument
    data Argument : Set where
      unnamed : String -> Type -> Argument
    
    variable
      arg arg₁ arg₂ arg₃ arg′ : Argument
      arg∗ : List Argument
      arg^ : Maybe Argument
      
    
    -- Sort: Type
    data Type : Set where
      tvar-name : Type
      tboolean : Type
      tfield : Type
      tunsigned : ℕ -> Type
      tbytes : ℕ -> Type
      topaque : String -> Type
      tvector : ℕ -> Type -> Type
      ttuple : List Type -> Type
      tcontract : String -> List String -> List Bool -> List (List Type) -> List Type -> Type
      tstruct : String -> List String -> List Type -> Type
      tenum : String -> String -> List String -> Type
      tundeclared : Type
      tunknown : Type
    
    variable
      type type₁ type₂ type₃ type′ : Type
      type∗ : List Type
      type^ : Maybe Type
      
    
    -- Sort: Public-Ledger-ADT
    data Public-Ledger-ADT : Set where
      unnamed : String -> List ⊤ -> List Public-Ledger-ADT-Arg -> {- vm-expr -> -} List ADT-Op -> List ADT-Runtime-Op -> Public-Ledger-ADT
    
    variable
      public-adt public-adt₁ public-adt₂ public-adt₃ public-adt′ : Public-Ledger-ADT
      public-adt∗ : List Public-Ledger-ADT
      public-adt^ : Maybe Public-Ledger-ADT
      
    
    -- Sort: Ledger-Constructor
    data Ledger-Constructor : Set where
      constructor′ : List Argument -> Expression -> Ledger-Constructor
    
    variable
      lconstructor lconstructor₁ lconstructor₂ lconstructor₃ lconstructor′ : Ledger-Constructor
      lconstructor∗ : List Ledger-Constructor
      lconstructor^ : Maybe Ledger-Constructor
      
    
    -- Sort: External-Declaration
    data External-Declaration : Set where
      external : String -> ⊤ -> List Argument -> Type -> External-Declaration
    
    variable
      edecl edecl₁ edecl₂ edecl₃ edecl′ : External-Declaration
      edecl∗ : List External-Declaration
      edecl^ : Maybe External-Declaration
      
    
    -- Sort: Witness-Declaration
    data Witness-Declaration : Set where
      witness : String -> List Argument -> Type -> Witness-Declaration
    
    variable
      wdecl wdecl₁ wdecl₂ wdecl₃ wdecl′ : Witness-Declaration
      wdecl∗ : List Witness-Declaration
      wdecl^ : Maybe Witness-Declaration
      
    
    -- Sort: Expression
    data Expression : Set where
      quote′ : ℕ ⊎ Bool -> Expression
      var-ref : String -> Expression
      ledger-ref : String -> Expression
      default : Public-Ledger-ADT-Type -> Expression
      if : Expression -> Expression -> Expression -> Expression
      elt-ref : Expression -> String -> ℕ -> Expression
      enum-ref : Type -> String -> Expression
      tuple : List Expression -> Expression
      tuple-ref : Expression -> ℕ -> Expression
      + : ⊤ -> Expression -> Expression -> Expression
      - : ⊤ -> Expression -> Expression -> Expression
      * : ⊤ -> Expression -> Expression -> Expression
      < : ⊤ -> Expression -> Expression -> Expression
      <= : ⊤ -> Expression -> Expression -> Expression
      > : ⊤ -> Expression -> Expression -> Expression
      >= : ⊤ -> Expression -> Expression -> Expression
      == : Type -> Expression -> Expression -> Expression
      != : Type -> Expression -> Expression -> Expression
      map : Maybe Type -> Function -> Expression -> Type -> List Expression -> List Type -> Expression
      fold : Maybe Type -> Function -> Expression -> Type -> Expression -> Type -> List Expression -> List Type -> Expression
      call : Function -> List Expression -> Expression
      new : Type -> List Expression -> Expression
      seq : List Expression -> Expression -> Expression
      let* : List Local -> List Expression -> Expression -> Expression
      assert : Expression -> String -> Expression
      field->bytes : ℕ -> Expression -> Expression
      bytes->field : ℕ -> Expression -> Expression
      enum->field : Expression -> Expression
      field->unsigned : ℕ -> Expression -> Expression
      upcast : Type -> Maybe Type -> Expression -> Expression
      downcast-unsigned : ℕ -> Expression -> Bool -> Expression
      disclose : Expression -> Expression
      ledger-call : {- ledger-op ->  maybe -> sugar ->-} Expression -> List Expression -> Expression
      contract-call : String -> Type -> List Expression -> Expression
      return : Expression -> Expression
    
    variable
      expr expr₁ expr₂ expr₃ expr′ : Expression
      expr∗ : List Expression
      expr^ : Maybe Expression
      
    
    -- Sort: Program
    data Program : Set where
      program : List String -> List String -> List Program-Element -> Program
    
    variable
      p p₁ p₂ p₃ p′ : Program
      p∗ : List Program
      p^ : Maybe Program
      
    
    -- Sort: Local
    data Local : Set where
      unnamed : String -> Public-Ledger-ADT-Type -> Local
    
    variable
      local local₁ local₂ local₃ local′ : Local
      local∗ : List Local
      local^ : Maybe Local
      
    
    -- Sort: ADT-Runtime-Op
    data ADT-Runtime-Op : Set where
      unnamed : {- ledger-op -> -} List Argument -> Type -> {- runtime-code -> -} ADT-Runtime-Op
    
    variable
      adt-rt-op adt-rt-op₁ adt-rt-op₂ adt-rt-op₃ adt-rt-op′ : ADT-Runtime-Op
      adt-rt-op∗ : List ADT-Runtime-Op
      adt-rt-op^ : Maybe ADT-Runtime-Op
      
    
    -- Sort: Program-Element
    data Program-Element : Set where
      `cdefn : Circuit-Definition -> Program-Element
      `edecl : External-Declaration -> Program-Element
      `wdecl : Witness-Declaration -> Program-Element
      `ldecl : Ledger-Declaration -> Program-Element
      `lconstructor : Ledger-Constructor -> Program-Element
      `typedef : Type-Definition -> Program-Element
    
    variable
      pelt pelt₁ pelt₂ pelt₃ pelt′ : Program-Element
      pelt∗ : List Program-Element
      pelt^ : Maybe Program-Element
      
    
    -- Sort: Ledger-Declaration
    data Ledger-Declaration : Set where
      public-ledger-declaration : String -> Public-Ledger-ADT -> Ledger-Declaration
    
    variable
      ldecl ldecl₁ ldecl₂ ldecl₃ ldecl′ : Ledger-Declaration
      ldecl∗ : List Ledger-Declaration
      ldecl^ : Maybe Ledger-Declaration
      
    
    -- Sort: Type-Definition
    data Type-Definition : Set where
      type-definition : String -> List String -> Type -> Type-Definition
    
    variable
      typedef typedef₁ typedef₂ typedef₃ typedef′ : Type-Definition
      typedef∗ : List Type-Definition
      typedef^ : Maybe Type-Definition
      
    
    -- Sort: Function
    data Function : Set where
      fref : String -> Function
      circuit : List Argument -> Type -> Expression -> Function
    
    variable
      fun fun₁ fun₂ fun₃ fun′ : Function
      fun∗ : List Function
      fun^ : Maybe Function
      
    
    -- Sort: Public-Ledger-ADT-Arg
    data Public-Ledger-ADT-Arg : Set where
      nat : ℕ -> Public-Ledger-ADT-Arg
      `adt-type : Public-Ledger-ADT-Type -> Public-Ledger-ADT-Arg
    
    variable
      adt-arg adt-arg₁ adt-arg₂ adt-arg₃ adt-arg′ : Public-Ledger-ADT-Arg
      adt-arg∗ : List Public-Ledger-ADT-Arg
      adt-arg^ : Maybe Public-Ledger-ADT-Arg
      
    
    -- Sort: Public-Ledger-ADT-Type
    data Public-Ledger-ADT-Type : Set where
      `type : Type -> Public-Ledger-ADT-Type
      `public-adt : Public-Ledger-ADT -> Public-Ledger-ADT-Type
    
    variable
      adt-type adt-type₁ adt-type₂ adt-type₃ adt-type′ : Public-Ledger-ADT-Type
      adt-type∗ : List Public-Ledger-ADT-Type
      adt-type^ : Maybe Public-Ledger-ADT-Type
      
    
    -- Sort: ADT-Op
    data ADT-Op : Set where
      unnamed : {- ledger-op -> ledger-op-class -> -} List String -> List Public-Ledger-ADT-Type -> Maybe Bool -> Public-Ledger-ADT-Type -> {- vm-code -> -} ADT-Op
    
    variable
      adt-op adt-op₁ adt-op₂ adt-op₃ adt-op′ : ADT-Op
      adt-op∗ : List ADT-Op
      adt-op^ : Maybe ADT-Op
      
    
    -- Sort: Circuit-Definition
    data Circuit-Definition : Set where
      circuit : String -> List Argument -> Type -> Expression -> Circuit-Definition
    
    variable
      cdefn cdefn₁ cdefn₂ cdefn₃ cdefn′ : Circuit-Definition
      cdefn∗ : List Circuit-Definition
      cdefn^ : Maybe Circuit-Definition
      
  Ltypes : List (Set × String)
  Ltypes = 
    (Argument , "arg") ∷
    (Type , "type") ∷
    (Public-Ledger-ADT , "public-adt") ∷
    (Ledger-Constructor , "lconstructor") ∷
    (External-Declaration , "edecl") ∷
    (Witness-Declaration , "wdecl") ∷
    (Expression , "expr") ∷
    (Program , "p") ∷
    (Local , "local") ∷
    (ADT-Runtime-Op , "adt-rt-op") ∷
    (Program-Element , "pelt") ∷
    (Ledger-Declaration , "ldecl") ∷
    (Type-Definition , "typedef") ∷
    (Function , "fun") ∷
    (Public-Ledger-ADT-Arg , "adt-arg") ∷
    (Public-Ledger-ADT-Type , "adt-type") ∷
    (ADT-Op , "adt-op") ∷
    (Circuit-Definition , "cdefn") ∷
    []
