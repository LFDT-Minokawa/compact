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

(define-pass reject-constructor-cc-calls : Lnodca (ir) -> Lnodca ()
  ; this pass raises an exception if the constructor attempts a cross-contract call
  ; TODO: later we might want to allow constructors to call pure circuits from an external contract.
  (definitions
    (define-condition-type &cc-call-condition &condition
      make-cc-call-condition cc-call-condition?
      (function-name cc-call-condition-function-name)
      (src cc-call-condition-src)
      (reason cc-call-condition-reason))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   #f:                    a processed circuit, determined not to make any cross-contract calls
    ;   a sealed condition:    a processed circuit, determined to make at least one cross-contract call
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(cc-call-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (cc-call-condition? result)
            (raise-continuable result)))))
    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
    (define (name-of-contract type)
      (nanopass-case (Lnodca Type) (de-alias type)
        [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          contract-name]
        [else (assert cannot-happen)]))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-function-kind! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-function-kind! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name expr)]
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
         (when (cc-call-condition? result)
           (let ([offending-function-name (cc-call-condition-function-name result)])
             (if (eq? offending-function-name #f)
                 (source-errorf src "constructor cannot call external contracts but ~a at ~a"
                                (cc-call-condition-reason result)
                                (format-source-object (cc-call-condition-src result)))
                 (source-errorf src "constructor cannot call external contracts but calls (directly or indirectly) ~a, which ~a at ~a"
                                (id-sym offending-function-name)
                                (cc-call-condition-reason result)
                                (format-source-object (cc-call-condition-src result))))))))
     ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name^)
     ir]
    [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
     (raise (make-cc-call-condition function-name src
              (format "calls circuit ~a from external contract ~a"
                elt-name
                (name-of-contract type))))])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name)
     ir]))
