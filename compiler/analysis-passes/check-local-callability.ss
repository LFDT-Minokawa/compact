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
  ; circuits, host functions, and local ADT operations, but nothing that reaches the public
  ; transcript or the proof, therefore no witnesses, no impure circuits, no cross-contract
  ; calls, no events, and no ledger writes; ledger reads (read and local-read classes, and
  ; for-of iteration) are snapshot quotes, so a local function may perform them.  The local
  ; constructor is a local function with no arguments, run as the prologue of the account's
  ; first landed circuit call against that call's basis, therefore the same rules apply to
  ; it, but host calls stay out of it in this iteration (plan §5).  An exported local
  ; function is the DApp's read-only view of the capsule, therefore it must not update
  ; local state, and the DApp's accessor has no host access, therefore it must not call
  ; host functions either, in both cases directly or through the local functions it calls
  ; (the host rule is an implementation decision to revisit); the walk records each local
  ; function's local writes, ledger reads, host calls, and local calls, and the closures
  ; are checked afterward.  The ledger-read closure also settles `id-reads-ledger?`, which
  ; tells the TypeScript backend which exported local functions need a ledger state.
  (definitions
    ; function names to 'witness, 'native-witness, 'circuit, 'callable (pure natives),
    ; 'local-circuit, or 'host
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
        [(,src ,ledger-op ,expr* ...) ledger-op]))
    ;; closure bookkeeping: ctx is 'circuit, 'local-constructor, or a local function's id,
    ;; so only an id context collects touches and edges
    (define write-ht (make-eq-hashtable))       ; local function -> (src . description)
    (define host-ht (make-eq-hashtable))        ; local function -> (src . host function)
    (define read-ht (make-eq-hashtable))        ; local function -> #t
    (define edge-ht (make-eq-hashtable))        ; local function -> (callee ...)
    (define exported-local* '())
    (define (record-local-write! ctx src description)
      (unless (symbol? ctx)
        (unless (eq-hashtable-ref write-ht ctx #f)
          (eq-hashtable-set! write-ht ctx (cons src description)))))
    (define (record-host-call! ctx src function-name)
      (if (eq? ctx 'local-constructor)
          (source-errorf src "the local constructor cannot call host function ~a" (id-sym function-name))
          (unless (eq-hashtable-ref host-ht ctx #f)
            (eq-hashtable-set! host-ht ctx (cons src function-name)))))
    (define (record-ledger-read! ctx)
      (unless (symbol? ctx)
        (eq-hashtable-set! read-ht ctx #t)))
    (define (record-local-call! ctx function-name)
      (unless (symbol? ctx)
        (eq-hashtable-set! edge-ht ctx (cons function-name (eq-hashtable-ref edge-ht ctx '())))))
    ;; the local functions reachable from f through local calls, f included
    (define (closure f)
      (let loop ([pending (list f)] [seen '()])
        (cond
          [(null? pending) seen]
          [(memq (car pending) seen) (loop (cdr pending) seen)]
          [else
           (loop (append (eq-hashtable-ref edge-ht (car pending) '()) (cdr pending))
                 (cons (car pending) seen))]))))
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-declaration! pelt*)
     (for-each Program-Element pelt*)
     (let ([local* (vector->list (hashtable-keys function-ht))])
       (for-each
         (lambda (f)
           (when (and (eq? (eq-hashtable-ref function-ht f #f) 'local-circuit)
                      (ormap (lambda (g) (eq-hashtable-ref read-ht g #f)) (closure f)))
             (id-reads-ledger?-set! f #t)))
         local*))
     (for-each
       (lambda (f)
         (cond
           [(eq-hashtable-ref write-ht f #f) =>
            (lambda (touch)
              (source-errorf (id-src f)
                "exported local function ~a cannot update local state but ~a at ~a"
                (id-sym f) (cdr touch) (format-source-object (car touch))))]
           [(find (lambda (g) (eq-hashtable-ref write-ht g #f)) (remq f (closure f))) =>
            (lambda (g)
              (let ([touch (eq-hashtable-ref write-ht g #f)])
                (source-errorf (id-src f)
                  "exported local function ~a cannot update local state but calls (directly or indirectly) local function ~a, which ~a at ~a"
                  (id-sym f) (id-sym g) (cdr touch) (format-source-object (car touch)))))]
           [(eq-hashtable-ref host-ht f #f) =>
            (lambda (touch)
              (source-errorf (id-src f)
                "exported local function ~a cannot call host functions but calls host function ~a at ~a"
                (id-sym f) (id-sym (cdr touch)) (format-source-object (car touch))))]
           [(find (lambda (g) (eq-hashtable-ref host-ht g #f)) (remq f (closure f))) =>
            (lambda (g)
              (let ([touch (eq-hashtable-ref host-ht g #f)])
                (source-errorf (id-src f)
                  "exported local function ~a cannot call host functions but calls (directly or indirectly) local function ~a, which calls host function ~a at ~a"
                  (id-sym f) (id-sym g) (id-sym (cdr touch)) (format-source-object (car touch)))))]
           [else (void)]))
       (reverse exported-local*))
     ir])
  (record-declaration! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name 'circuit)]
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! function-ht function-name 'local-circuit)
     (when (id-exported? function-name)
       (set! exported-local* (cons function-name exported-local*)))]
    [(witness ,src ,function-name (,arg* ...) ,type)
     (eq-hashtable-set! function-ht function-name 'witness)]
    [(host ,src ,function-name ,interface-id ,host-name (,arg* ...) ,type)
     (eq-hashtable-set! function-ht function-name 'host)]
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
         [(id-local? ledger-field-name)
          (unless (class-memq? op-class '(read local-read))
            (record-local-write! ctx src (format "updates local field ~a" (id-sym ledger-field-name))))]
         [(class-memq? op-class '(read local-read)) (record-ledger-read! ctx)]
         [else
          (source-errorf src "~a cannot update ledger field ~a"
            (context-name ctx) (id-sym ledger-field-name))]))
     ir]
    [(foreach ,src ,var-name ,ledger-field-name ,type ,expr)
     (cond
       [(eq? ctx 'circuit)
        (source-errorf src "for-of iteration over a container is only available in local functions")]
       [(id-local? ledger-field-name) (void)]
       [else (record-ledger-read! ctx)])
     (Expression expr ctx)
     ir]
    [(call ,src ,function-name ,[expr*] ...)
     (unless (eq? ctx 'circuit)
       (case (eq-hashtable-ref function-ht function-name #f)
         [(witness native-witness)
          (source-errorf src "~a cannot call witness ~a" (context-name ctx) (id-sym function-name))]
         [(circuit)
          (unless (id-pure? function-name)
            (source-errorf src "~a cannot call impure circuit ~a" (context-name ctx) (id-sym function-name)))]
         [(local-circuit) (record-local-call! ctx function-name)]
         [(host) (record-host-call! ctx src function-name)]
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
         [(local-circuit) (record-local-call! ctx function-name^)]
         [(host) (record-host-call! ctx src function-name^)]
         [else (void)]))
     ir]))
