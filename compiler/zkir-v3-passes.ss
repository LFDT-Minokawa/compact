;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;  	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

#!chezscheme

(library (zkir-v3-passes)
  (export zkir-v3-passes)
  (import (except (chezscheme) errorf)
          (config-params)
          (utils)
          (field)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers)
          (natives)
          (ledger)
          (vm)
          (json))

  (include "zkir-v3-passes/reduce-to-zkir.ss")

  (include "zkir-v3-passes/print-zkir-v3.ss")

  (define-passes zkir-v3-passes
    (reduce-to-zkir Lzkir)
    (print-zkir-v3  Lzkir))
  )
