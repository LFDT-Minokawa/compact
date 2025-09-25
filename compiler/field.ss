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

(library (field)
  (export max-field field?)
  (import (chezscheme))

  ; a field value is a natural number whose range is bounded by a prime number determined in
  ; relation to the proof system.  max-field is the largest representable field value.
  ; WARNING: keep in sync with midnight-base-crypto. Will be caught by tests.
  (define (max-field) 52435875175126190479447740508185965837690552500527637822603658699938581184512)

  (define (field? x)
    (and (integer? x)
         (exact? x)
         (<= 0 x (max-field))))
)
