;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
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

(define-pass reject-constructor-verify : Lnodca (ir) -> Lnodca ()
  ; this pass raises an exception if the constructor verifies a proof, which would
  ; never take effect, since the constructor is not proved on chain
  (definitions
    (define-condition-type &verify-condition &condition
      make-verify-condition verify-condition?
      (function-name verify-condition-function-name)
      (src verify-condition-src)
      (reason verify-condition-reason))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   #f:                    a processed circuit, determined not to verify a proof
    ;   a verify condition:    a processed circuit, determined to verify at least one proof
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(verify-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (verify-condition? result)
            (raise-continuable result)))))
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
         (when (verify-condition? result)
           (let ([offending-function-name (verify-condition-function-name result)])
             (if (eq? offending-function-name #f)
                 (source-errorf src "constructor cannot verify a proof but ~a at ~a"
                                (verify-condition-reason result)
                                (format-source-object (verify-condition-src result)))
                 (source-errorf src "constructor cannot verify a proof but calls (directly or indirectly) ~a, which ~a at ~a"
                                (id-sym offending-function-name)
                                (verify-condition-reason result)
                                (format-source-object (verify-condition-src result))))))))
     ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name^)
     ir]
    [(prepare-verification ,src ,vk (,pubin* ...) ,expr)
     (raise (make-verify-condition function-name src
              (format "verifies a proof against ~s" (verifying-key-pathname vk))))])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Tuple-Argument : Tuple-Argument (ir function-name) -> Tuple-Argument ())
  (Map-Argument : Map-Argument (ir function-name) -> Map-Argument ())
  (Public-Input : Public-Input (ir function-name) -> Public-Input ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name)
     ir]))
