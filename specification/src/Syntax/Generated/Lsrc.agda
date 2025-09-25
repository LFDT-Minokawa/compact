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
-- *** The definitions in this file were automatically generated from the `Lsrc` Nanopass IR.
-- *** 
-- *** TIMESTAMP: 2025-06-26 10:42:22 
-- *** 
-- *** Compiler version: 0.24.103
-- *** Language version: 0.16.103

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

module Syntax.Generated.Lsrc where
  mutual
    
    -- Sort: Pattern-Argument
    data Pattern-Argument : Set where
      unnamed : Pattern -> Type -> Pattern-Argument
    
    variable
      parg parg₁ parg₂ parg₃ parg′ : Pattern-Argument
      parg∗ : List Pattern-Argument
      parg^ : Maybe Pattern-Argument
      
    
    -- Sort: Argument
    data Argument : Set where
      unnamed : String -> Type -> Argument
    
    variable
      arg arg₁ arg₂ arg₃ arg′ : Argument
      arg∗ : List Argument
      arg^ : Maybe Argument
      
    
    -- Sort: Import-Name
    data Import-Name : Set where
      module-name : String -> Import-Name
      file : String -> Import-Name
    
    variable
      import-name import-name₁ import-name₂ import-name₃ import-name′ : Import-Name
      import-name∗ : List Import-Name
      import-name^ : Maybe Import-Name
      
    
    -- Sort: Type
    data Type : Set where
      `tref : Type-Ref -> Type
      tboolean : Type
      tfield : Type
      tunsigned : Type-Size -> Type
      tunsigned1 : Type-Size -> Maybe Type-Size -> Type
      tbytes : Type-Size -> Type
      topaque : String -> Type
      tvector : Type-Size -> Type -> Type
      ttuple : List Type -> Type
      tundeclared : Type
    
    variable
      type type₁ type₂ type₃ type′ : Type
      type∗ : List Type
      type^ : Maybe Type
      
    
    -- Sort: New-Field
    data New-Field : Set where
      spread : Expression -> New-Field
      positional : Expression -> New-Field
      named : String -> Expression -> New-Field
    
    variable
      new-field new-field₁ new-field₂ new-field₃ new-field′ : New-Field
      new-field∗ : List New-Field
      new-field^ : Maybe New-Field
      
    
    -- Sort: Ledger-Constructor
    data Ledger-Constructor : Set where
      constructor′ : List Pattern-Argument -> Statement -> Ledger-Constructor
    
    variable
      lconstructor lconstructor₁ lconstructor₂ lconstructor₃ lconstructor′ : Ledger-Constructor
      lconstructor∗ : List Ledger-Constructor
      lconstructor^ : Maybe Ledger-Constructor
      
    
    -- Sort: External-Declaration
    data External-Declaration : Set where
      external : Bool -> String -> List Type-Param -> List Argument -> Type -> External-Declaration
    
    variable
      edecl edecl₁ edecl₂ edecl₃ edecl′ : External-Declaration
      edecl∗ : List External-Declaration
      edecl^ : Maybe External-Declaration
      
    
    -- Sort: Witness-Declaration
    data Witness-Declaration : Set where
      witness : Bool -> String -> List Type-Param -> List Argument -> Type -> Witness-Declaration
    
    variable
      wdecl wdecl₁ wdecl₂ wdecl₃ wdecl′ : Witness-Declaration
      wdecl∗ : List Witness-Declaration
      wdecl^ : Maybe Witness-Declaration
      
    
    -- Sort: Type-Size
    data Type-Size : Set where
      type-size : ℕ -> Type-Size
      type-size-ref : String -> Type-Size
    
    variable
      tsize tsize₁ tsize₂ tsize₃ tsize′ : Type-Size
      tsize∗ : List Type-Size
      tsize^ : Maybe Type-Size
      
    
    -- Sort: Expression
    data Expression : Set where
      quote′ : ℕ ⊎ Bool -> Expression
      var-ref : String -> Expression
      default : Type -> Expression
      if : Expression -> Expression -> Expression -> Expression
      elt-ref : Expression -> String -> Expression
      elt-call : Expression -> String -> List Expression -> Expression
      =′ : Expression -> Expression -> Expression
      += : Expression -> Expression -> Expression
      -= : Expression -> Expression -> Expression
      tuple : List Expression -> Expression
      tuple-ref : Expression -> ℕ -> Expression
      + : Expression -> Expression -> Expression
      - : Expression -> Expression -> Expression
      * : Expression -> Expression -> Expression
      or : Expression -> Expression -> Expression
      and : Expression -> Expression -> Expression
      not : Expression -> Expression
      < : Expression -> Expression -> Expression
      <= : Expression -> Expression -> Expression
      > : Expression -> Expression -> Expression
      >= : Expression -> Expression -> Expression
      == : Expression -> Expression -> Expression
      != : Expression -> Expression -> Expression
      map : Function -> Expression -> List Expression -> Expression
      fold : Function -> Expression -> Expression -> List Expression -> Expression
      call : Function -> List Expression -> Expression
      new : Type-Ref -> List New-Field -> Expression
      seq : List Expression -> Expression -> Expression
      cast : Type -> Expression -> Expression
      disclose : Expression -> Expression
      assert : Expression -> String -> Expression
    
    variable
      expr expr₁ expr₂ expr₃ expr′ : Expression
      expr∗ : List Expression
      expr^ : Maybe Expression
      
    
    -- Sort: Program
    data Program : Set where
      program : List Program-Element -> Program
    
    variable
      p p₁ p₂ p₃ p′ : Program
      p∗ : List Program
      p^ : Maybe Program
      
    
    -- Sort: Pattern
    data Pattern : Set where
      var-name : String -> Pattern
      tuple : List (Maybe Pattern) -> Pattern
      struct : List (Pattern × String) -> Pattern
    
    variable
      pat pat₁ pat₂ pat₃ pat′ : Pattern
      pat∗ : List Pattern
      pat^ : Maybe Pattern
      
    
    -- Sort: External-Contract-Circuit
    data External-Contract-Circuit : Set where
      unnamed : Bool -> String -> List Argument -> Type -> External-Contract-Circuit
    
    variable
      ecdecl-circuit ecdecl-circuit₁ ecdecl-circuit₂ ecdecl-circuit₃ ecdecl-circuit′ : External-Contract-Circuit
      ecdecl-circuit∗ : List External-Contract-Circuit
      ecdecl-circuit^ : Maybe External-Contract-Circuit
      
    
    -- Sort: Statement
    data Statement : Set where
      statement-expression : Expression -> Statement
      return : Expression -> Statement
      const : Pattern -> Type -> Expression -> Statement
      if : Expression -> Statement -> Statement -> Statement
      for : String -> Expression -> Statement -> Statement
      block : List Statement -> Statement
    
    variable
      stmt stmt₁ stmt₂ stmt₃ stmt′ : Statement
      stmt∗ : List Statement
      stmt^ : Maybe Statement
      
    
    -- Sort: Structure-Definition
    data Structure-Definition : Set where
      struct : Bool -> String -> List Type-Param -> List Argument -> Structure-Definition
    
    variable
      structdef structdef₁ structdef₂ structdef₃ structdef′ : Structure-Definition
      structdef∗ : List Structure-Definition
      structdef^ : Maybe Structure-Definition
      
    
    -- Sort: Program-Element
    data Program-Element : Set where
      `incld : Include -> Program-Element
      `mdefn : Module-Definition -> Program-Element
      `idecl : Import-Declaration -> Program-Element
      `xdecl : Export-Declaration -> Program-Element
      `ldecl : Ledger-Declaration -> Program-Element
      `lconstructor : Ledger-Constructor -> Program-Element
      `cdefn : Circuit-Definition -> Program-Element
      `edecl : External-Declaration -> Program-Element
      `wdecl : Witness-Declaration -> Program-Element
      `ecdecl : External-Contract-Declaration -> Program-Element
      `structdef : Structure-Definition -> Program-Element
      `enumdef : Enum-Definition -> Program-Element
    
    variable
      pelt pelt₁ pelt₂ pelt₃ pelt′ : Program-Element
      pelt∗ : List Program-Element
      pelt^ : Maybe Program-Element
      
    
    -- Sort: Ledger-Declaration
    data Ledger-Declaration : Set where
      public-ledger-declaration : Bool -> Bool -> String -> Type -> Ledger-Declaration
    
    variable
      ldecl ldecl₁ ldecl₂ ldecl₃ ldecl′ : Ledger-Declaration
      ldecl∗ : List Ledger-Declaration
      ldecl^ : Maybe Ledger-Declaration
      
    
    -- Sort: Import-Declaration
    data Import-Declaration : Set where
      import′ : Import-Name -> List Type-Argument -> String -> Import-Declaration
    
    variable
      idecl idecl₁ idecl₂ idecl₃ idecl′ : Import-Declaration
      idecl∗ : List Import-Declaration
      idecl^ : Maybe Import-Declaration
      
    
    -- Sort: Type-Argument
    data Type-Argument : Set where
      targ-size : ℕ -> Type-Argument
      targ-type : Type -> Type-Argument
    
    variable
      targ targ₁ targ₂ targ₃ targ′ : Type-Argument
      targ∗ : List Type-Argument
      targ^ : Maybe Type-Argument
      
    
    -- Sort: Function
    data Function : Set where
      fref : String -> Function
      fref1 : String -> List Type-Argument -> Function
      circuit : List Pattern-Argument -> Type -> Statement -> Function
    
    variable
      fun fun₁ fun₂ fun₃ fun′ : Function
      fun∗ : List Function
      fun^ : Maybe Function
      
    
    -- Sort: Module-Definition
    data Module-Definition : Set where
      module′ : Bool -> String -> List Type-Param -> List Program-Element -> Module-Definition
    
    variable
      mdefn mdefn₁ mdefn₂ mdefn₃ mdefn′ : Module-Definition
      mdefn∗ : List Module-Definition
      mdefn^ : Maybe Module-Definition
      
    
    -- Sort: Include
    data Include : Set where
      include : String -> Include
    
    variable
      incld incld₁ incld₂ incld₃ incld′ : Include
      incld∗ : List Include
      incld^ : Maybe Include
      
    
    -- Sort: Type-Param
    data Type-Param : Set where
      nat-valued : String -> Type-Param
      type-valued : String -> Type-Param
    
    variable
      type-param type-param₁ type-param₂ type-param₃ type-param′ : Type-Param
      type-param∗ : List Type-Param
      type-param^ : Maybe Type-Param
      
    
    -- Sort: Export-Declaration
    data Export-Declaration : Set where
      export : List String -> Export-Declaration
    
    variable
      xdecl xdecl₁ xdecl₂ xdecl₃ xdecl′ : Export-Declaration
      xdecl∗ : List Export-Declaration
      xdecl^ : Maybe Export-Declaration
      
    
    -- Sort: Type-Ref
    data Type-Ref : Set where
      type-ref : String -> List Type-Argument -> Type-Ref
    
    variable
      tref tref₁ tref₂ tref₃ tref′ : Type-Ref
      tref∗ : List Type-Ref
      tref^ : Maybe Type-Ref
      
    
    -- Sort: Circuit-Definition
    data Circuit-Definition : Set where
      circuit : Bool -> Bool -> String -> List Type-Param -> List Pattern-Argument -> Type -> Statement -> Circuit-Definition
    
    variable
      cdefn cdefn₁ cdefn₂ cdefn₃ cdefn′ : Circuit-Definition
      cdefn∗ : List Circuit-Definition
      cdefn^ : Maybe Circuit-Definition
      
    
    -- Sort: External-Contract-Declaration
    data External-Contract-Declaration : Set where
      external-contract : Bool -> String -> List External-Contract-Circuit -> External-Contract-Declaration
    
    variable
      ecdecl ecdecl₁ ecdecl₂ ecdecl₃ ecdecl′ : External-Contract-Declaration
      ecdecl∗ : List External-Contract-Declaration
      ecdecl^ : Maybe External-Contract-Declaration
      
    
    -- Sort: Enum-Definition
    data Enum-Definition : Set where
      enum : Bool -> String -> String -> List String -> Enum-Definition
    
    variable
      enumdef enumdef₁ enumdef₂ enumdef₃ enumdef′ : Enum-Definition
      enumdef∗ : List Enum-Definition
      enumdef^ : Maybe Enum-Definition
      
  Lsrc : List (Set × String)
  Lsrc = 
    (Pattern-Argument , "parg") ∷
    (Argument , "arg") ∷
    (Import-Name , "import-name") ∷
    (Type , "type") ∷
    (New-Field , "new-field") ∷
    (Ledger-Constructor , "lconstructor") ∷
    (External-Declaration , "edecl") ∷
    (Witness-Declaration , "wdecl") ∷
    (Type-Size , "tsize") ∷
    (Expression , "expr") ∷
    (Program , "p") ∷
    (Pattern , "pattern") ∷
    (External-Contract-Circuit , "ecdecl-circuit") ∷
    (Statement , "stmt") ∷
    (Structure-Definition , "structdef") ∷
    (Program-Element , "pelt") ∷
    (Ledger-Declaration , "ldecl") ∷
    (Import-Declaration , "idecl") ∷
    (Type-Argument , "targ") ∷
    (Function , "fun") ∷
    (Module-Definition , "mdefn") ∷
    (Include , "incld") ∷
    (Type-Param , "type-param") ∷
    (Export-Declaration , "xdecl") ∷
    (Type-Ref , "tref") ∷
    (Circuit-Definition , "cdefn") ∷
    (External-Contract-Declaration , "ecdecl") ∷
    (Enum-Definition , "enumdef") ∷
    []
