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

(library (frontend-passes)
  (export frontend-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (parser)
          (ledger)
          (pass-helpers))

  (include "frontend-passes/resolve-includes.ss")

  (include "frontend-passes/expand-const.ss")

  (include "frontend-passes/expand-patterns.ss")

  (include "frontend-passes/reject-for-return.ss")

  (include "frontend-passes/report-unreachable.ss")

  (include "frontend-passes/hoist-local-variables.ss")

  (include "frontend-passes/reject-duplicate-bindings.ss")

  (include "frontend-passes/eliminate-statements.ss")

  (include "frontend-passes/eliminate-boolean-connectives.ss")

  (include "frontend-passes/prepare-for-expand.ss")

  (define-passes frontend-passes
    (resolve-includes                Lnoinclude)
    (expand-const                    Lsingleconst)
    (expand-patterns                 Lnopattern)
    (reject-for-return               Lnopattern)
    (report-unreachable              Lnopattern)
    (hoist-local-variables           Lhoisted)
    (reject-duplicate-bindings       Lhoisted)
    (eliminate-statements            Lexpr)
    (eliminate-boolean-connectives   Lnoandornot)
    (prepare-for-expand              Lpreexpand))
)
