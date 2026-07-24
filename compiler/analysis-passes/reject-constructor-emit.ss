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

(define-pass reject-constructor-emit : Lnodca (ir) -> Lnodca ()
  ; this pass raises an exception if the constructor attempts an emit
  (definitions
    (define-condition-type &emit-condition &condition
      make-emit-condition emit-condition?
      (function-name emit-condition-function-name)
      (src emit-condition-src)
      (reason emit-condition-reason))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   #f:                    a processed circuit, determined not to emit
    ;   a sealed condition:    a processed circuit, determined to at least emit once
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(emit-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (emit-condition? result)
            (raise-continuable result)))))
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
         (when (emit-condition? result)
           (let ([offending-function-name (emit-condition-function-name result)])
             (if (eq? offending-function-name #f)
                 (source-errorf src "constructor cannot emit an event but ~a at ~a"
                                (emit-condition-reason result)
                                (format-source-object (emit-condition-src result)))
                 (source-errorf src "constructor cannot emit an event but calls (directly or indirectly) ~a, which ~a at ~a"
                                (id-sym offending-function-name)
                                ;; offending-function-name
                                (emit-condition-reason result)
                                (format-source-object (emit-condition-src result))))))))
     ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name^)
     ir]
    [(emit ,src ,type ,expr)
     (nanopass-case (Lnodca Type) (de-alias type)
       [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
        (raise (make-emit-condition function-name src
                 (format "emits event ~a" struct-name)))]
       [else (assert cannot-happen)])])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name)
     ir]))
