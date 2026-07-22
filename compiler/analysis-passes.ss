;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;; 	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

#!chezscheme

(library (analysis-passes)
  (export analysis-passes fixup-analysis-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (config-params)
          (field)
          (datatype)
          (nanopass)
          (langs)
          (ledger)
          (natives)
          (events)
          (inlines)
          (json)
          (pass-helpers)
          (parser)
          (frontend-passes)
          (standard-library-aliases))

  (include "analysis-passes/expand-modules-and-types.ss")

  (include "analysis-passes/infer-types.ss")

  (include "analysis-passes/remove-tundeclared.ss")

  (include "analysis-passes/combine-ledger-declarations.ss")

  (include "analysis-passes/discard-unused-functions.ss")

  (include "analysis-passes/reject-recursive-circuits.ss")

  (include "analysis-passes/recognize-let.ss")

  (include "analysis-passes/check-types-Lnodca.ss")

  (include "analysis-passes/check-sealed-fields.ss")

  (include "analysis-passes/reject-constructor-emit.ss")

  (include "analysis-passes/reject-constructor-cc-calls.ss")

  (include "analysis-passes/identify-pure-circuits.ss")

  (include "analysis-passes/determine-ledger-paths.ss")

  (include "analysis-passes/propagate-ledger-paths.ss")

  (include "analysis-passes/track-witness-data.ss")

  (include "analysis-passes/remove-disclose.ss")

  (include "analysis-passes/expand-serialize.ss")

  (include "analysis-passes/lower-emit.ss")

  (define-passes analysis-passes
    (expand-modules-and-types        Lexpanded)
    (infer-types                     Ltypes)
    (remove-tundeclared              Lnotundeclared)
    (combine-ledger-declarations     Loneledger)
    (discard-unused-functions        Loneledger)
    (reject-recursive-circuits       Loneledger)
    (recognize-let                   Lnodca)
    (check-sealed-fields             Lnodca)
    (reject-constructor-emit         Lnodca)
    (reject-constructor-cc-calls     Lnodca)
    (identify-pure-circuits          Lnodca)
    (determine-ledger-paths          Lwithpaths0)
    (propagate-ledger-paths          Lwithpaths)
    (track-witness-data              Lwithpaths)
    (remove-disclose                 Lnodisclose)
    (expand-serialize                Lnoserialize)
    (lower-emit                      Lloweredemit))

  (define-passes fixup-analysis-passes
    (expand-modules-and-types        Lexpanded)
    (infer-types                     Ltypes))

  (define-checker check-types/Lnodca Lnodca)
)
