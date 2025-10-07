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
-- *** The language definition in this file was automatically generated from the Lexpr Nanopass IR
-- *** 
-- *** TIMESTAMP: 2024-11-12 10:43:21 
-- *** 

open import Data.String  using (String) 
open import Data.List    using (List; [] ; _∷_) 
open import Data.Bool    using (Bool)
open import Data.Nat     using (ℕ)
open import Data.Sum     using (_⊎_)
open import Data.Maybe   using (Maybe)
open import Data.Product using (_×_ ; _,_)
open import Data.Unit    using (⊤)
import Agda.Builtin.Reflection as Reflection

module Syntax.Generated.Lexpr where
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
      `tref : Type-Ref -> Type
      tboolean : Type
      tfield : Type
      tunsigned : Type-Size -> Type
      tunsigned1 : Type-Size -> Maybe Type-Size -> Type
      tbytes : Type-Size -> Type
      topaque : String -> Type
      tvector : Type-Size -> Type -> Type
      tvoid : Type
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
      constructor′ : List Argument -> Expression -> Ledger-Constructor
    
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
      
    
    -- Sort: Public-Ledger-ADT
    data Public-Ledger-ADT : Set where
      unnamed : String -> List Public-Ledger-ADT-Arg -> Public-Ledger-ADT
    
    variable
      public-adt public-adt₁ public-adt₂ public-adt₃ public-adt′ : Public-Ledger-ADT
      public-adt∗ : List Public-Ledger-ADT
      public-adt^ : Maybe Public-Ledger-ADT
      
    
    -- Sort: Witness-Declaration
    data Witness-Declaration : Set where
      witness : Bool -> String -> List Type-Param -> List Argument -> Type -> Witness-Declaration
    
    variable
      wdecl wdecl₁ wdecl₂ wdecl₃ wdecl′ : Witness-Declaration
      wdecl∗ : List Witness-Declaration
      wdecl^ : Maybe Witness-Declaration
      
    
    -- Sort: Type-Size
    data Type-Size : Set where
      quote′ : ℕ -> Type-Size
      type-size-ref : String -> Type-Size
    
    variable
      tsize tsize₁ tsize₂ tsize₃ tsize′ : Type-Size
      tsize∗ : List Type-Size
      tsize^ : Maybe Type-Size
      
    
    -- Sort: Expression
    data Expression : Set where
      =′ : Expression -> Expression -> Expression
      += : Expression -> Expression -> Expression
      -= : Expression -> Expression -> Expression
      assert : Expression -> String -> Expression
      let* : List Local -> List Expression -> Expression -> Expression
      for : String -> Expression -> Expression -> Expression
      block : List String -> Expression -> Expression
      quote′ : ℕ ⊎ Bool -> Expression
      var-ref : String -> Expression
      default : Public-Ledger-ADT-Type -> Expression
      if : Expression -> Expression -> Expression -> Expression
      elt-ref : Expression -> String -> Expression
      elt-call : Expression -> String -> List Expression -> Expression
      vector : List Expression -> Expression
      vector-ref : Expression -> ℕ -> Expression
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
      void : Expression
      cast : Type -> Expression -> Expression
    
    variable
      expr expr₁ expr₂ expr₃ expr′ : Expression
      expr∗ : List Expression
      expr^ : Maybe Expression
      
    
    -- Sort: Local
    data Local : Set where
      unnamed : String -> Public-Ledger-ADT-Type -> Local
    
    variable
      local local₁ local₂ local₃ local′ : Local
      local∗ : List Local
      local^ : Maybe Local
      
    
    -- Sort: Program
    data Program : Set where
      program : List Program-Element -> Program
    
    variable
      p p₁ p₂ p₃ p′ : Program
      p∗ : List Program
      p^ : Maybe Program
      
    
    -- Sort: External-Contract-Circuit
    data External-Contract-Circuit : Set where
      unnamed : Bool -> String -> List Argument -> Type -> External-Contract-Circuit
    
    variable
      ecdecl-circuit ecdecl-circuit₁ ecdecl-circuit₂ ecdecl-circuit₃ ecdecl-circuit′ : External-Contract-Circuit
      ecdecl-circuit∗ : List External-Contract-Circuit
      ecdecl-circuit^ : Maybe External-Contract-Circuit
      
    
    -- Sort: Structure-Definition
    data Structure-Definition : Set where
      struct : Bool -> String -> List Type-Param -> List Argument -> Structure-Definition
    
    variable
      structdef structdef₁ structdef₂ structdef₃ structdef′ : Structure-Definition
      structdef∗ : List Structure-Definition
      structdef^ : Maybe Structure-Definition
      
    
    -- Sort: Program-Element
    data Program-Element : Set where
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
      public-ledger-declaration : Bool -> Bool -> String -> Public-Ledger-ADT -> Ledger-Declaration
    
    variable
      ldecl ldecl₁ ldecl₂ ldecl₃ ldecl′ : Ledger-Declaration
      ldecl∗ : List Ledger-Declaration
      ldecl^ : Maybe Ledger-Declaration
      
    
    -- Sort: Import-Declaration
    data Import-Declaration : Set where
      import′ : String -> List Type-Argument -> String -> Import-Declaration
    
    variable
      idecl idecl₁ idecl₂ idecl₃ idecl′ : Import-Declaration
      idecl∗ : List Import-Declaration
      idecl^ : Maybe Import-Declaration
      
    
    -- Sort: Type-Argument
    data Type-Argument : Set where
      quote′ : ℕ -> Type-Argument
      `type : Type -> Type-Argument
    
    variable
      targ targ₁ targ₂ targ₃ targ′ : Type-Argument
      targ∗ : List Type-Argument
      targ^ : Maybe Type-Argument
      
    
    -- Sort: Function
    data Function : Set where
      circuit : List Argument -> Type -> Expression -> Function
      fref : String -> Function
      fref1 : String -> List Type-Argument -> Function
    
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
      
    
    -- Sort: Type-Param
    data Type-Param : Set where
      nat-valued : String -> Type-Param
      type-valued : String -> Type-Param
    
    variable
      type-param type-param₁ type-param₂ type-param₃ type-param′ : Type-Param
      type-param∗ : List Type-Param
      type-param^ : Maybe Type-Param
      
    
    -- Sort: Public-Ledger-ADT-Type
    data Public-Ledger-ADT-Type : Set where
      `type : Type -> Public-Ledger-ADT-Type
      `public-adt : Public-Ledger-ADT -> Public-Ledger-ADT-Type
    
    variable
      adt-type adt-type₁ adt-type₂ adt-type₃ adt-type′ : Public-Ledger-ADT-Type
      adt-type∗ : List Public-Ledger-ADT-Type
      adt-type^ : Maybe Public-Ledger-ADT-Type
      
    
    -- Sort: Public-Ledger-ADT-Arg
    data Public-Ledger-ADT-Arg : Set where
      nat : ℕ -> Public-Ledger-ADT-Arg
      `adt-type : Public-Ledger-ADT-Type -> Public-Ledger-ADT-Arg
    
    variable
      adt-arg adt-arg₁ adt-arg₂ adt-arg₃ adt-arg′ : Public-Ledger-ADT-Arg
      adt-arg∗ : List Public-Ledger-ADT-Arg
      adt-arg^ : Maybe Public-Ledger-ADT-Arg
      
    
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
      circuit : Bool -> Bool -> String -> List Type-Param -> List Argument -> Type -> Expression -> Circuit-Definition
    
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
      
  Lexpr : List (Set × String)
  Lexpr = 
    (Argument , "arg") ∷
    (Type , "type") ∷
    (New-Field , "new-field") ∷
    (Ledger-Constructor , "lconstructor") ∷
    (External-Declaration , "edecl") ∷
    (Public-Ledger-ADT , "public-adt") ∷
    (Witness-Declaration , "wdecl") ∷
    (Type-Size , "tsize") ∷
    (Expression , "expr") ∷
    (Local , "local") ∷
    (Program , "p") ∷
    (External-Contract-Circuit , "ecdecl-circuit") ∷
    (Structure-Definition , "structdef") ∷
    (Program-Element , "pelt") ∷
    (Ledger-Declaration , "ldecl") ∷
    (Import-Declaration , "idecl") ∷
    (Type-Argument , "targ") ∷
    (Function , "fun") ∷
    (Module-Definition , "mdefn") ∷
    (Type-Param , "type-param") ∷
    (Public-Ledger-ADT-Type , "adt-type") ∷
    (Public-Ledger-ADT-Arg , "adt-arg") ∷
    (Export-Declaration , "xdecl") ∷
    (Type-Ref , "tref") ∷
    (Circuit-Definition , "cdefn") ∷
    (External-Contract-Declaration , "ecdecl") ∷
    (Enum-Definition , "enumdef") ∷
    []
