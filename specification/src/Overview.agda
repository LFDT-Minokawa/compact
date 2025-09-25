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



{- This file imports all files relevant for Compact's static semantic
specification -}

module Overview where


-- Generated syntax for the Lsrc IR, as definid in
-- `compiler/langs.ss`. This defines the abstract syntax of Compact.
open import Syntax.Generated.Lsrc

-- Defines the "coverage check" that we can use to ensure that the
-- defined typing relation actually covers all parts of Compact's
-- abstract syntax 
open import Semantics.Static.Coverage

-- Defines the static semantics of type-level objects in Compact. 
open import Semantics.Static.Lsrc.Lsrc-Typing

-- Defines the static semantics of term-level objects in Compact. 
open import Semantics.Static.Lsrc.Lsrc 
