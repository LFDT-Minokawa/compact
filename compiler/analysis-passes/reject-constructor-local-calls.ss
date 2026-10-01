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

(define-pass reject-constructor-local-calls : Lnodca (ir) -> Lnodca ()
  ; The deploy runs no capsule, therefore the constructor can run no local code: it may
  ; neither call a local function nor operate on a local field, directly or through the
  ; circuits it calls.
  (definitions
    (define-condition-type &local-code-condition &condition
      make-local-code-condition local-code-condition?
      (function-name local-code-condition-function-name)
      (src local-code-condition-src)
      (reason local-code-condition-reason))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   #f:                    a processed circuit, determined not to run local code
    ;   a sealed condition:    a processed circuit, determined to run local code
    (define function-ht (make-eq-hashtable))
    (define local-function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(local-code-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! src function-name^ function-name)
      (if (eq-hashtable-ref local-function-ht function-name^ #f)
          (raise (make-local-code-condition function-name src
                   (format "calls local function ~a" (id-sym function-name^))))
          (let ([a (eq-hashtable-cell function-ht function-name^ #f)])
            (process-circuit! a)
            (let ([result (cdr a)])
              (assert (not (eq? result 'inprocess-circuit)))
              (when (local-code-condition? result)
                (raise-continuable result))))))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-function-kind! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-function-kind! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name expr)]
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! local-function-ht function-name #t)]
    [else (void)])
  ;; only the constructor is checked; circuits are processed as the constructor reaches them
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr) ir]
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr) ir])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,arg* ... ) ,expr)
     (let ([a (cons #f expr)])
       (process-circuit! a)
       (let ([result (cdr a)])
         (when (local-code-condition? result)
           (let ([offending-function-name (local-code-condition-function-name result)])
             (if (eq? offending-function-name #f)
                 (source-errorf src "constructor cannot run local code but ~a at ~a"
                                (local-code-condition-reason result)
                                (format-source-object (local-code-condition-src result)))
                 (source-errorf src "constructor cannot run local code but calls (directly or indirectly) ~a, which ~a at ~a"
                                (id-sym offending-function-name)
                                (local-code-condition-reason result)
                                (format-source-object (local-code-condition-src result))))))))
     ir]
    [(local-constructor ,src ,expr) ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! src function-name^ function-name)
     ir]
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
     (when (id-local? ledger-field-name)
       (raise (make-local-code-condition function-name src
                (format "operates on local field ~a" (id-sym ledger-field-name)))))
     ir]
    [(foreach ,src ,var-name ,ledger-field-name ,type ,[expr])
     (when (id-local? ledger-field-name)
       (raise (make-local-code-condition function-name src
                (format "iterates local field ~a" (id-sym ledger-field-name)))))
     ir])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name^)
     (process-function-name! src function-name^ function-name)
     ir]))
