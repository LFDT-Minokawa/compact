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

(library (circuit-passes)
  (export circuit-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (field)
          (datatype)
          (config-params)
          (nanopass)
          (langs)
          (pass-helpers))

  (include "circuit-passes/drop-ledger-runtime.ss")

  (include "circuit-passes/replace-enums.ss")

  (include "circuit-passes/unroll-loops.ss")

  (include "circuit-passes/inline-circuits.ss")

  (include "circuit-passes/check-types-Linlined.ss")

  (include "circuit-passes/drop-safe-casts.ss")

  (include "circuit-passes/resolve-indices-simplify.ss")

  (include "circuit-passes/discard-useless-code.ss")

  (include "circuit-passes/prune-unnecessary-circuits.ss")

  (include "circuit-passes/reduce-to-circuit.ss")

  (include "circuit-passes/flatten-datatypes.ss")

  (include "circuit-passes/optimize-circuit.ss")

  (include "circuit-passes/missing-guard-workarounds.ss")

  (include "circuit-passes/check-types-Lflattened.ss")

  (define optimize-circuit2 (lambda (x) (optimize-circuit x)))

  (include "circuit-passes/desugar-contract-calls.ss")

  (define-passes circuit-passes
    (drop-ledger-runtime             Lposttypescript)
    (replace-enums                   Lnoenums)
    (unroll-loops                    Lunrolled)
    (inline-circuits                 Linlined)
    (drop-safe-casts                 Lnosafecast)
    (resolve-indices/simplify        Lnovectorref)
    (discard-useless-code            Lnovectorref)
    (prune-unnecessary-circuits      Lnovectorref)
    (reduce-to-circuit               Lcircuit)
    (flatten-datatypes               Lflattened)
    (optimize-circuit                Lflattened)
    (missing-guard-workarounds       Lflattened)
    ; rerun optimize-circuit to optimize code added by missing-guard-workarounds
    (optimize-circuit2               Lflattened)
    (desugar-contract-calls          Lflattened))

  (define-checker check-types/Linlined Linlined)
  (define-checker check-types/Lflattened Lflattened)
)
