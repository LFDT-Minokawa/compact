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

(define-pass check-sealed-fields : Lnodca (ir) -> Lnodca ()
  ; this pass complains if a sealed field can be modified by an exported circuit or any
  ; circuit that is reachable from an exported circuit.  we presently assume that no
  ; witnesses or natives can modify any sealed fields.
  (definitions
    (define-condition-type &sealed-condition &condition
      make-sealed-condition sealed-condition?
      (function-name sealed-condition-function-name)
      (src sealed-condition-src)
      (reason sealed-condition-reason))
    ; function-ht maps function names to one of:
    ;   an Lnodca Expression:  a circuit that has yet to be processed
    ;   inprocess-circuit:     a circuit that is being processed; used to detect cycles
    ;   #f:                    a processed circuit, determined not to modify any sealed fields
    ;   a sealed condition:    a processed circuit, determined to modify at least one sealed field
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(sealed-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (sealed-condition? result)
            (raise-continuable result)))))
    (define (read-op? ledger-field-name accessor+)
      (let loop ([accessor+ accessor+]
                 [adt-op* (lookup-adt-ops ledger-field-name)])
        (let ([accessor (car accessor+)] [accessor* (cdr accessor+)])
          (nanopass-case (Lnodca Ledger-Accessor) accessor
            [(,src ,ledger-op ,expr* ...)
             (let find-adt-op ([adt-op* adt-op*])
               (assert (not (null? adt-op*)))
               (nanopass-case (Lnodca ADT-Op) (car adt-op*)
                 [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                  (guard (eq? ledger-op^ ledger-op))
                  (if (null? accessor*)
                      (eq? op-class 'read)
                      (loop accessor*
                            (nanopass-case (Lnodca Type) (de-alias type)
                              [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                               adt-op*]
                              [else (assert cannot-happen)])))]
                 [else (find-adt-op (cdr adt-op*))]))]))))
    (module (record-adt-ops! lookup-adt-ops)
      (define ledger-ht (make-eq-hashtable))
      (define (record-one! public-binding)
        (nanopass-case (Lnodca Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name ,type)
           (nanopass-case (Lnodca Type) (de-alias type)
             [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
              (hashtable-set! ledger-ht ledger-field-name adt-op*)]
             [else (assert cannot-happen)])]))
      (define (record-adt-ops! pelt)
        (nanopass-case (Lnodca Program-Element) pelt
          [(kernel-declaration ,public-binding)
           (record-one! public-binding)]
          [(public-ledger-declaration ,public-binding* ... ,lconstructor)
           (for-each record-one! public-binding*)]
          [else (void)]))
      (define (lookup-adt-ops ledger-field-name)
        (assert (hashtable-ref ledger-ht ledger-field-name #f))))
    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-adt-ops! pelt*)
     (for-each record-function! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-function! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name expr)]
    [else (void)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (when (id-exported? function-name)
       (let ([a (eq-hashtable-cell function-ht function-name #f)])
         (process-circuit! a)
         (let ([result (cdr a)])
           (when (sealed-condition? result)
             (let ([offending-function-name (sealed-condition-function-name result)])
               (if (eq? offending-function-name #f)
                   (source-errorf src "exported circuits cannot modify sealed ledger fields but ~a at ~a"
                                  (sealed-condition-reason result)
                                  (format-source-object (sealed-condition-src result)))
                   (source-errorf src "exported circuits cannot modify sealed ledger fields but ~a calls (directly or indirectly) ~a, which ~a at ~a"
                                  (id-sym function-name)
                                  (id-sym offending-function-name)
                                  (sealed-condition-reason result)
                                  (format-source-object (sealed-condition-src result)))))))))
     ir]
    [else ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
     (when (id-sealed? ledger-field-name)
       (unless (read-op? ledger-field-name accessor*)
         (raise (make-sealed-condition function-name src
                  (format "modifies sealed field ~a" (id-sym ledger-field-name))))))
     ir]
    [(call ,src ,function-name ,[expr*] ...)
     (process-function-name! function-name)
     ir])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name)
     ir]))
