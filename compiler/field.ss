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

(library (field)
  (export max-field field?
          max-jubjub-scalar jubjub-scalar?
          max-secp256k1-base secp256k1-base?
          max-secp256k1-scalar secp256k1-scalar?)
  (import (chezscheme))

  (define-syntax define-field-predicate
    (syntax-rules ()
      [(field-predicate name max)
       (define (name x)
         (and (integer? x)
              (exact? x)
              (<= 0 x (max))))]))

  ; a field value is a natural number whose range is bounded by a prime number determined in
  ; relation to the proof system.  max-field is the largest representable field value.
  ; WARNING: keep in sync with midnight-base-crypto. Will be caught by tests.
  (define (max-field) 52435875175126190479447740508185965837690552500527637822603658699938581184512)
  (define-field-predicate field? max-field)

  ; This value should match `MAX_JUBJUB_SCALAR` in the Compact runtime.
  (define (max-jubjub-scalar)
    #xe7db4ea6533afa906673b0101343b00a6682093ccc81082d0970e5ed6f72cb6)
  (define-field-predicate jubjub-scalar? max-jubjub-scalar)

  (define (max-secp256k1-base)
    (1- (- (expt 2 256) (expt 2 32) 977)))
  (define-field-predicate secp256k1-base? max-secp256k1-base)

  (define (max-secp256k1-scalar)
    #xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364140)
  (define-field-predicate secp256k1-scalar? max-secp256k1-scalar)
)
