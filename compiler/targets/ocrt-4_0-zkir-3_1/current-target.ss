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

;;; The target of this directory.  Its name and its on-chain runtime and ZKIR
;;; versions are the ones of the name of the directory; the ledger version is the
;;; one that cannot be derived from it (see target-directory.ss).

(library (current-target)
  (export current-target)
  (import (chezscheme) (target) (target-directory))

  (define current-target (make-target-here "9.1.0")))
