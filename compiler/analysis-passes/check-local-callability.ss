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

; NB: must come after identify-pure-circuits, which settles `id-pure?`.
(define-pass check-local-callability : Lnodca (ir) -> Lnodca ()
  ; The callability matrix for local code: a local function calls local functions, pure
  ; circuits, and local ADT operations, but nothing that reaches the public transcript or
  ; the proof, therefore no witnesses, no impure circuits, no cross-contract calls, no
  ; events, and no ledger writes; ledger reads are permitted by the design but not yet
  ; implemented.  The local constructor is stricter (join-safety): its result must be
  ; derivable from the contract alone, therefore ledger access of any class is out.  Every
  ; construct legal in a local function is currently also join-safe, so the constructor's
  ; transitive check collapses to these direct checks; a fixed point with call-chain
  ; diagnostics (the shape of identify-pure-circuits) becomes necessary when ledger reads
  ; from local functions arrive.
  (definitions
    ; function names to 'witness, 'native-witness, 'circuit, 'callable (pure natives), or
    ; 'local-circuit
    (define function-ht (make-eq-hashtable))
    ; ledger and local field names to their declared types, for resolving operation classes
    (define field-type-ht (make-eq-hashtable))
    (define (record-binding! pb)
      (nanopass-case (Lnodca Public-Ledger-Binding) pb
        [(,src ,ledger-field-name ,type)
         (eq-hashtable-set! field-type-ht ledger-field-name type)]))
    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type) (de-alias type)]
        [else type]))
    (define (context-name ctx)
      (if (eq? ctx 'local-constructor)
          "the local constructor"
          (format "local function ~a" (id-sym ctx))))
    ; the class of an accessor chain's final operation, walking intermediate result types;
    ; #f when a step cannot be resolved, which callers treat as not-a-read
    (define (final-op-class ledger-field-name accessor*)
      (let loop ([type (eq-hashtable-ref field-type-ht ledger-field-name #f)]
                 [accessor* accessor*])
        (and type
             (not (null? accessor*))
             (nanopass-case (Lnodca Type) (de-alias type)
               [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                (nanopass-case (Lnodca Ledger-Accessor) (car accessor*)
                  [(,src^ ,ledger-op ,expr* ...)
                   (let ([adt-op (find (lambda (adt-op)
                                         (nanopass-case (Lnodca ADT-Op) adt-op
                                           [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                                            (eq? ledger-op^ ledger-op)]))
                                       adt-op*)])
                     (and adt-op
                          (nanopass-case (Lnodca ADT-Op) adt-op
                            [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                             (if (null? (cdr accessor*))
                                 op-class
                                 (loop type (cdr accessor*)))])))])]
               [else #f]))))
    (define (class-memq? op-class class*)
      (and op-class
           (nanopass-case (Lnodca ADT-Op-Class) op-class
             [,ledger-op-class (memq ledger-op-class class*)]
             [else #f])))
    (define (final-op-name accessor*)
      (nanopass-case (Lnodca Ledger-Accessor) (car (last-pair accessor*))
        [(,src ,ledger-op ,expr* ...) ledger-op])))
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-declaration! pelt*)
     (for-each Program-Element pelt*)
     ir])
  (record-declaration! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name 'circuit)]
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name 'local-circuit)]
    [(witness ,src ,function-name (,arg* ...) ,type)
     (eq-hashtable-set! function-ht function-name 'witness)]
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (eq-hashtable-set! function-ht function-name
       (if (eq? (native-entry-class native-entry) 'witness) 'native-witness 'callable))]
    [(kernel-declaration ,public-binding)
     (record-binding! public-binding)]
    [(public-ledger-declaration ,public-binding* ... ,lconstructor)
     (for-each record-binding! public-binding*)]
    [(local-ledger-declaration ,public-binding* ... ,lconstructor)
     (for-each record-binding! public-binding*)]
    [,export-tdefn (void)]
    [else (assert cannot-happen)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (Expression expr function-name)
     ir]
    [(local-ledger-declaration ,public-binding* ... (local-constructor ,src ,expr))
     (Expression expr 'local-constructor)
     ir]
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (Expression expr 'circuit)
     ir]
    [(public-ledger-declaration ,public-binding* ... (constructor ,src ((,var-name* ,type*) ...) ,expr))
     (Expression expr 'circuit)
     ir]
    [else ir])
  (Expression : Expression (ir ctx) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
     (let ([op-class (final-op-class ledger-field-name accessor*)])
       (cond
         [(eq? ctx 'circuit)
          ;; a local-read pins observations for the fold, which only local code needs;
          ;; from a circuit the ordinary read path is the right tool
          (when (class-memq? op-class '(local-read))
            (source-errorf src "~a is only callable from local functions"
              (final-op-name accessor*)))]
         [(id-local? ledger-field-name) (void)]
         [(eq? ctx 'local-constructor)
          (source-errorf src "the local constructor cannot access ledger field ~a"
            (id-sym ledger-field-name))]
         [(class-memq? op-class '(read local-read))
          (source-errorf src "ledger reads from local functions are not yet implemented")]
         [else
          (source-errorf src "~a cannot update ledger field ~a"
            (context-name ctx) (id-sym ledger-field-name))]))
     ir]
    [(call ,src ,function-name ,[expr*] ...)
     (unless (eq? ctx 'circuit)
       (case (eq-hashtable-ref function-ht function-name #f)
         [(witness native-witness)
          (source-errorf src "~a cannot call witness ~a" (context-name ctx) (id-sym function-name))]
         [(circuit)
          (unless (id-pure? function-name)
            (source-errorf src "~a cannot call impure circuit ~a" (context-name ctx) (id-sym function-name)))]
         [else (void)]))
     ir]
    [(contract-call ,src ,elt-name (,[expr] ,type) ,[expr*] ...)
     (unless (eq? ctx 'circuit)
       (source-errorf src "~a cannot make a cross-contract call" (context-name ctx)))
     ir]
    [(emit ,src ,type ,[expr])
     (unless (eq? ctx 'circuit)
       (source-errorf src "~a cannot emit an event" (context-name ctx)))
     ir])
  (Tuple-Argument : Tuple-Argument (ir ctx) -> Tuple-Argument ())
  (Map-Argument : Map-Argument (ir ctx) -> Map-Argument ())
  (Ledger-Accessor : Ledger-Accessor (ir ctx) -> Ledger-Accessor ())
  (Function : Function (ir ctx) -> Function ()
    [(fref ,src ,function-name^)
     (unless (eq? ctx 'circuit)
       (case (eq-hashtable-ref function-ht function-name^ #f)
         [(witness native-witness)
          (source-errorf src "~a cannot call witness ~a" (context-name ctx) (id-sym function-name^))]
         [(circuit)
          (unless (id-pure? function-name^)
            (source-errorf src "~a cannot call impure circuit ~a" (context-name ctx) (id-sym function-name^)))]
         [else (void)]))
     ir]))
