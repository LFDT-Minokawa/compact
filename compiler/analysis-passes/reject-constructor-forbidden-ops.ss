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

(define-pass reject-constructor-forbidden-ops : Lnodca (ir) -> Lnodca ()
  ; this pass reports an error if the constructor calls, either directly or
  ; indirectly, an operation that is forbidden in a constructor.  the forbidden
  ; operations are:
  ;   - ledger ADT functions whose declaration carries the is-forbidden-in-constructor flag
  ;   - natives whose declaration carries the is-forbidden-in-constructor flag
  ;   - emit.
  (definitions
    ; a forbidden-condition records one forbidden operation found within a circuit:
    ;   what: a string describing the forbidden operation, e.g., "call kernel.self"
    ;   end:  what the operation is called at the end of a call path, e.g., kernel.self
    ;   src:  the source location of the forbidden operation
    ;   via:  the circuits through which the operation is reached, e.g.,
    ;         constructor -> foo -> bar -> actual-offender
    (define-condition-type &forbidden-condition &condition
      make-forbidden-condition forbidden-condition?
      (what forbidden-condition-what)
      (end forbidden-condition-end)
      (src forbidden-condition-src)
      (via forbidden-condition-via))
    ; ledger-adt-ht maps ledger field names to a pair of the name of their ADT and its ADT ops
    (define ledger-adt-ht (make-eq-hashtable))
    ; function-ht maps ids (circuit names) to one of:
    ;   an Lnodca Expression:      a circuit that has yet to be processed
    ;   inprocess-circuit:         a circuit that is being processed; used to detect cycles
    ;   forbidden-native:          a native known to be forbidden in a constructor
    ;   #f:                        a processed circuit, determined not to contain a forbidden operation
    ;   a forbidden-condition:     a processed circuit, determined to contain at least one forbidden operation
    (define function-ht (make-eq-hashtable))
    (define (process-circuit! a)
      (let ([function-name (car a)] [maybe-expr (cdr a)])
        (when (Lnodca-Expression? maybe-expr)
          (guard (c [(forbidden-condition? c) (set-cdr! a c)]
                    [else (raise-continuable c)])
            (set-cdr! a 'inprocess-circuit)
            (Expression maybe-expr function-name)
            (set-cdr! a #f)))))
    (define (process-function-name! function-name src)
      (let ([a (eq-hashtable-cell function-ht function-name #f)])
        (when (eq? (cdr a) 'forbidden-native)
          (raise (make-forbidden-condition (format "call ~a" (id-sym function-name)) (id-sym function-name) src '())))
        (process-circuit! a)
        (let ([result (cdr a)])
          (assert (not (eq? result 'inprocess-circuit)))
          (when (forbidden-condition? result)
            (raise (make-forbidden-condition (forbidden-condition-what result)
                                             (forbidden-condition-end result)
                                             (forbidden-condition-src result)
                                             (cons function-name (forbidden-condition-via result))))))))
    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
    (define (record-ledger-adt! public-binding)
      (nanopass-case (Lnodca Public-Ledger-Binding) public-binding
        [(,src ,ledger-field-name ,type)
         (nanopass-case (Lnodca Type) (de-alias type)
           [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
            (eq-hashtable-set! ledger-adt-ht ledger-field-name (cons adt-name adt-op*))]
           [else (assert cannot-happen)])]))
    (define (forbidden-in-constructor? adt-op* ledger-op)
      (ormap
        (lambda (adt-op)
          (nanopass-case (Lnodca ADT-Op) adt-op
            [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code ,forbidden?-in-constructor)
             (and (eq? ledger-op^ ledger-op) forbidden?-in-constructor)]))
        adt-op*))
    (define (record-ledger-adts! pelt)
      (nanopass-case (Lnodca Program-Element) pelt
        [(kernel-declaration ,public-binding)
         (record-ledger-adt! public-binding)]
        [(public-ledger-declaration ,public-binding* ... ,lconstructor)
         (for-each record-ledger-adt! public-binding*)]
        [else (void)]))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-ledger-adts! pelt*)
     (for-each record-function-kind! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-function-kind! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name expr)]
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (when (native-entry-forbidden?-in-constructor native-entry)
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
         (when (forbidden-condition? result)
           (let ([via (map id-sym (forbidden-condition-via result))])
             (if (null? via)
                 (pending-errorf src "constructor cannot ~a but does so at ~a"
                   (forbidden-condition-what result)
                   (format-source-object (forbidden-condition-src result)))
                 ; the call path runs from the constructor to the forbidden operation
                 (pending-errorf src "constructor cannot ~a but does so at ~a (called via ~{~a~^ -> ~})"
                   (forbidden-condition-what result)
                   (format-source-object (forbidden-condition-src result))
                   (append '(constructor) via (list (forbidden-condition-end result)))))))))
     ir])
  (Expression : Expression (ir function-name) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
       (let* ([a (eq-hashtable-ref ledger-adt-ht ledger-field-name #f)]
              [adt-name (car a)]
              [adt-op* (cdr a)])
         (for-each
           (lambda (accessor)
             (nanopass-case (Lnodca Ledger-Accessor) accessor
               [(,src^ ,ledger-op ,expr* ...)
                (when (forbidden-in-constructor? adt-op* ledger-op)
                  ; the kernel's ledger field name is internal
                  (let ([op-name (format "~a.~a" (if (eq? adt-name 'Kernel) 'kernel ledger-field-name) ledger-op)])
                    (raise (make-forbidden-condition (format "call ~a" op-name) (string->symbol op-name) src^ '()))))]))
           accessor*))
       ir]
    [(call ,src ,function-name^ ,[expr*] ...)
     (process-function-name! function-name^ src)
     ir]
    [(emit ,src ,type ,expr)
     (nanopass-case (Lnodca Type) (de-alias type)
       [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
        (let ([what (format "emit event ~a" struct-name)])
          (raise (make-forbidden-condition what what src '())))]
       [else (assert cannot-happen)])])
  (Ledger-Accessor : Ledger-Accessor (ir function-name) -> Ledger-Accessor ())
  (Function : Function (ir function-name) -> Function ()
    [(fref ,src ,function-name)
     (process-function-name! function-name src)
     ir]))
