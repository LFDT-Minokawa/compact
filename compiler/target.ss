;;; This file is part of Compact.
;;; Copyright (C) 2026 Minokawa project contributors
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

;;; A target is the pair of the on-chain runtime and ZKIR versions that a
;;; compactc build is built for.  This library only defines the
;;; shape of a target; each directory under compiler/targets/ instantiates it in
;;; a library named (current-target).  Which instance a build uses is fixed at
;;; build time by which target directory is on the library path.
;;;
;;; The ledger version is informational as the compiler is not directly configured by it.

(library (target)
  (export make-target target? target-name target-onchain-runtime-version
          target-zkir-version target-ledger-version)
  (import (chezscheme))

  (define-record-type target
    (fields name onchain-runtime-version zkir-version ledger-version)))
