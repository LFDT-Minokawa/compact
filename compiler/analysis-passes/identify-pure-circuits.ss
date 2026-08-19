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

(define-pass identify-pure-circuits : Lnodca (ir) -> Lnodca ()
  ; impure circuits are those that might touch public state, emit an event,
  ; call any witnesses, or call any other impure circuits (including via
  ; cross-contract calls).  pure circuits are those that are not impure.  we
  ; presently assume that all native circuits are pure.
  (definitions
    (define-condition-type &impure-condition &condition
      make-impure-condition impure-condition?
      (function-name impure-condition-function-name)
      (src impure-condition-src)
      (reason impure-condition-reason))
    ; function-ht maps function names to one of:
    ;   witness:               a witness
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   pure-circuit:          a processed circuit, determined pure
    ;   an impure condition:   a processed circuit, determined impure
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(impure-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a 'pure-circuit)))))
    (define (process-function-name! calling-function-name src function-name)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (process-circuit! a)
        (let ([result (cdr a)])
          (cond
            [(eq? result 'pure-circuit) (void)]
            [(eq? result 'witness)
             (raise (make-impure-condition calling-function-name src
                      (format "calls witness ~s" (id-sym function-name))))]
            [(eq? result 'native-witness)
             (raise (make-impure-condition calling-function-name src
                      (format "calls native witness ~s" (id-sym function-name))))]
            [(impure-condition? result) (raise-continuable result)]
            [(eq? result 'inprocess-circuit) (assert cannot-happen)] ; should have been caught by reject-recursive-circuits
            [else (assert cannot-happen)]))))
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
     (eq-hashtable-set! function-ht function-name
       (if (eq? (native-entry-class native-entry) 'witness)
           'native-witness
           (begin
             (id-pure?-set! function-name #t)
             'pure-circuit)))]
    [(witness ,src ,function-name (,arg* ...) ,type)
     (eq-hashtable-set! function-ht function-name 'witness)]
    [,kdecl (void)]
    [,ldecl (void)]
    [,export-tdefn (void)]
    [else (assert cannot-happen)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (let ([a (eq-hashtable-cell function-ht function-name #f)])
       (process-circuit! a)
       (let ([result (cdr a)])
         (cond
           [(eq? result 'pure-circuit)
            (id-pure?-set! function-name #t)]
           [(impure-condition? result)
            (when (id-pure? function-name)
              (let ([offending-function-name (impure-condition-function-name result)])
                (if (eq? offending-function-name function-name)
                    (source-errorf src "circuit ~a is marked pure but is actually impure because it ~a at ~a"
                                   (id-sym function-name)
                                   (impure-condition-reason result)
                                   (format-source-object (impure-condition-src result)))
                    (source-errorf src "circuit ~a is marked pure but is actually impure because it calls (directly or indirectly) impure circuit ~a;\
                                       \n    ~:*~a is impure because it ~a at ~a"
                                       (id-sym function-name)
                                       (id-sym offending-function-name)
                                       (impure-condition-reason result)
                                       (format-source-object (impure-condition-src result))))))]
           [else (assert cannot-happen)])))
     ir]
    [else ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor* ...)
     (raise (make-impure-condition function-name src
              (format "accesses ledger field ~s" (id-sym ledger-field-name))))]
    [(emit ,src ,type ,[expr])
     (nanopass-case (Lnodca Type) (de-alias type)
       [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
        (raise (make-impure-condition function-name src
                 (format "emits an event of type ~s" struct-name)))]
       [else (assert cannot-happen)])]
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name src function-name^)
     ir]
    [(contract-call ,src ,elt-name (,expr ,type) ,[expr*] ...)
     (nanopass-case (Lnodca Type) (de-alias type)
       [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
        (let loop ([elt-name* elt-name*] [pure-dcl* pure-dcl*])
          (when (null? elt-name*) (assert cannot-happen))
          (if (eq? (car elt-name*) elt-name)
              (if (car pure-dcl*)
                  ir
                  (raise (make-impure-condition function-name src
                           (format "calls impure circuit ~a of external contract ~a"
                             elt-name
                             contract-name))))
              (loop (cdr elt-name*) (cdr pure-dcl*))))]
       [else (assert cannot-happen)])])
  (Tuple-Argument : Tuple-Argument (ir function-name) -> Tuple-Argument ())
  (Map-Argument : Map-Argument (ir function-name) -> Map-Argument ())
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name^)
     (process-function-name! function-name src function-name^)
     ir]))
