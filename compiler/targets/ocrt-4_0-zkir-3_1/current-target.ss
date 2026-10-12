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

;;; The target name is also the name of this directory.
;;; todo @pataei add a check that the name of the target matches
;;; the directory and the onchain-runtime and zkir

(library (current-target)
  (export current-target)
  (import (chezscheme) (target))

  (define current-target
    (make-target "ocrt-4_0-zkir-3_1" "4.0" "3.1" "9.1.0")))
