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

(define-pass reject-constructor-effects : Lnodca (ir) -> Lnodca ()
  ; this pass raises an exception if the constructor attempts an effect producing
  ; operation either directly or indirectly
  (definitions
    (define-condition-type &effect-condition &condition
      make-effect-condition effect-condition?
      (function-name effect-condition-function-name)
      (src effect-condition-src)
      (reason effect-condition-reason))
    ; Kernel update operations that emit a transaction-level effect
    (define forbidden-kernel-ops
      '(self
        mintShielded
        mintUnshielded
        claimZswapCoinReceive
        claimZswapCoinSpend
        claimZswapNullifier
        claimUnshieldedCoinSpend
        incUnshieldedInputs
        incUnshieldedOutputs
        claimContractCall
        checkpoint))
    ; native entries that create Zswap coin inputs/outputs
    (define forbidden-native-functions
      '("__compactRuntime.createZswapInput"
        "__compactRuntime.createZswapOutput"))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   forbidden-native:      a native circuit known to produce an effect
    ;   #f:                    a processed circuit, determined not to prodcue an effect
    ;   an effect condition:   a processed circuit, determined to at least produce an effect once
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(effect-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name src)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (when (eq? (cdr a) 'forbidden-native)
            (raise (make-effect-condition function-name src (format "calls ~a" (id-sym function-name)))))
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (effect-condition? result)
            (raise-continuable (make-effect-condition function-name
                                                      (effect-condition-src result)
                                                      (effect-condition-reason result)))))))
    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-function-kind! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-function-kind! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name expr)]
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (when (member (native-entry-function native-entry) forbidden-native-functions)
       (eq-hashtable-set! function-ht function-name 'forbidden-native))]
    [else (void)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (process-circuit! (eq-hashtable-cell function-ht function-name #f))
     ir])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,arg* ... ) ,expr)
     (let ([a (cons #f expr)])
       (process-circuit! a)
       (let ([result (cdr a)])
         (when (effect-condition? result)
           (let ([offending-function-name (effect-condition-function-name result)])
             (if (eq? offending-function-name #f)
                 (source-errorf src "constructor cannot call an effect-producing operation but ~a at ~a"
                                (effect-condition-reason result)
                                (format-source-object (effect-condition-src result)))
                 (source-errorf src "constructor cannot call an effect-producing operation but calls (directly or indirectly) ~a, which ~a at ~a"
                                (id-sym offending-function-name)
                                (effect-condition-reason result)
                                (format-source-object (effect-condition-src result))))))))
     ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
       (for-each
         (lambda (accessor)
           (nanopass-case (Lnodca Ledger-Accessor) accessor
             [(,src^ ,ledger-op ,expr* ...)
              (when (memq ledger-op forbidden-kernel-ops)
                (raise (make-effect-condition function-name src^ (format "calls kernel.~a" ledger-op))))]))
         accessor*)
       ir]
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name^ src)
     ir]
    [(emit ,src ,type ,expr)
     (nanopass-case (Lnodca Type) (de-alias type)
       [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
        (raise (make-effect-condition function-name src
                 (format "emits event ~a" struct-name)))]
       [else (assert cannot-happen)])])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name src)
     ir]))
