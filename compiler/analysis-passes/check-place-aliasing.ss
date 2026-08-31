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

(define-pass check-place-aliasing : Lnodca (ir) -> Lnodca ()
  ; Phase E of place-references-impl-plan.md: reject a circuit whose behaviour changes
  ; if two of its place parameters turn out to name the same location.
  ;
  ;   circuit move(a: &Counter, b: &Counter) { ... }
  ;   move(&accounts.lookup(k), &accounts.lookup(j));   // k and j may be equal
  ;
  ; MONOMORPHIZATION MAKES THIS INTRA-BODY.  A specialization exists precisely because
  ; some call site created it, and by this language its places are baked into the body
  ; as `public-ledger` nodes carrying the field, the accessor chain and the keys.  So
  ; there is no call graph to walk and no per-circuit summary to compute: a hazardous
  ; specialization *is* a hazardous call.  (This is the correction to E1 of the plan,
  ; which proposed deciding aliasing with targ-info-equal? -- that lives in
  ; expand-modules-and-types and is long gone by here.  E3's placement is right; E1's
  ; mechanism is not available at it.)
  ;
  ; WHEN TWO ACCESSES MAY ALIAS.  Same ledger field, same sequence of navigation ops,
  ; and different place provenance.  Provenance comes from id-place-name, stamped on a
  ; keys parameter by expand-modules-and-types; two accesses through the *same* place
  ; parameter are the same location by construction and are not an aliasing question.
  ; An access with no place provenance is a direct ledger access, also not in scope.
  ;
  ; WHAT COUNTS AS A HAZARD.  Two things:
  ;   - a read sequenced after a write (E2), and
  ;   - two writes whose operations do not commute.
  ; The second is not in the plan; it was added because E2 alone misses
  ;     const v = a.read(); b.increment(v); a.resetToDefault();
  ; which ends at zero when a and b alias.  Commutation is what separates that from
  ; `a.decrement(n); b.increment(n)`, which is correct when aliased and is the false
  ; positive E4 warns about -- increment and decrement compose commutatively, whereas
  ; increment and resetToDefault do not.
  ;
  ; ORDER comes from source position, NOT traversal order.  An earlier version of this
  ; pass assumed the two coincided; they do not.  Nanopass binds the catamorphisms of
  ; `(seq src expr* ... expr)` in a `let`, and Chez evaluates `let` bindings right to
  ; left, so the body's trailing expression is visited FIRST.  A circuit that ends by
  ; returning a ledger read therefore recorded that read before the writes preceding it,
  ; and the read-after-write test silently never fired.  Every multi-child production has
  ; the same exposure, so events are sorted by source position instead of being trusted
  ; in the order they arrive.  Within one body source order is execution order for
  ; straight-line code; the two arms of an `if` are treated as though both ran, which
  ; over-reports rather than under-reports.
  (definitions
    (define-record-type access
      (nongenerative)
      (fields src field-name nav-op* place-name adt-name op op-class))

    ; A hazard found in a circuit body: two places that may be one location, and why.
    (define-record-type hazard
      (nongenerative)
      (fields kind later-place later-op later-src earlier-place earlier-op earlier-src))

    ; One traversal collects three kinds of event per circuit body, in order:
    ;   (access . <access>)          a ledger access through a place
    ;   (assert-ne <expr> . <expr>)  an asserted disequality between two expressions
    ;   (call <src> <callee> . <arg expr list>)
    ; Hazards are then computed from the accesses, and call sites checked against the
    ; callees' hazards -- which is why collection has to finish for every circuit before
    ; any call site is judged.
    (define revent* '())                       ; current body, reversed
    (define circuit-event* '())                ; (function-name . events) for each circuit
    (define hazard-ht (make-eq-hashtable))     ; function-name -> hazard list
    (define arg-index-ht (make-eq-hashtable))  ; function-name -> (place-name . index) alist

    (define (de-alias type)
      (nanopass-case (Lnodca Type) type
        [(talias ,src ,nominal? ,type-name ,type) (de-alias type)]
        [else type]))

    (module (record-adt-ops! lookup-adt)
      (define ledger-ht (make-eq-hashtable))
      (define (record-one! public-binding)
        (nanopass-case (Lnodca Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name ,type)
           (nanopass-case (Lnodca Type) (de-alias type)
             [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
              (hashtable-set! ledger-ht ledger-field-name (cons adt-name adt-op*))]
             [else (void)])]))
      (define (record-adt-ops! pelt)
        (nanopass-case (Lnodca Program-Element) pelt
          [(kernel-declaration ,public-binding) (record-one! public-binding)]
          [(public-ledger-declaration ,public-binding* ... ,lconstructor)
           (for-each record-one! public-binding*)]
          [else (void)]))
      (define (lookup-adt ledger-field-name)
        (hashtable-ref ledger-ht ledger-field-name #f)))

    ; Walk the accessor chain against the ADT op table, as check-sealed-fields'
    ; read-op? does, but return what the *last* accessor is: the ADT it is called on,
    ; its name, and its op class.  #f if the chain cannot be resolved, in which case
    ; this access is simply not analysed.
    (define (final-op-info field-name accessor+)
      (let ([a (lookup-adt field-name)])
        (and a
             (let loop ([accessor+ accessor+] [adt-name (car a)] [adt-op* (cdr a)])
               (and (pair? accessor+)
                    (let ([accessor (car accessor+)] [accessor* (cdr accessor+)])
                      (nanopass-case (Lnodca Ledger-Accessor) accessor
                        [(,src ,ledger-op ,expr* ...)
                         (let find ([adt-op^* adt-op*])
                           (and (pair? adt-op^*)
                                (nanopass-case (Lnodca ADT-Op) (car adt-op^*)
                                  [(,ledger-op^ ,op-class ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                                   (guard (eq? ledger-op^ ledger-op))
                                   (if (null? accessor*)
                                       (list adt-name ledger-op op-class)
                                       (nanopass-case (Lnodca Type) (de-alias type)
                                         [(tadt ,src^ ,adt-name^ ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op^* ...) (,adt-rt-op^* ...))
                                          (loop accessor* adt-name^ adt-op^*)]
                                         [else #f]))]
                                  [else (find (cdr adt-op^*))])))])))))))

    ; The place a key expression came from, or #f.  The shape generated by
    ; expand-modules-and-types is (tuple-ref (var-ref <keys parameter>) i); a local
    ; bound to one of those carries the provenance too, see Expression's let* clause.
    (define (place-of-expr expr)
      (nanopass-case (Lnodca Expression) expr
        [(var-ref ,src ,var-name) (id-place-name var-name)]
        [(tuple-ref ,src ,expr^ ,kindex) (place-of-expr expr^)]
        [else #f]))

    (define (place-of-accessor accessor)
      (nanopass-case (Lnodca Ledger-Accessor) accessor
        [(,src ,ledger-op ,expr* ...)
         (ormap place-of-expr expr*)]))

    ; the navigation prefix is every accessor but the last: those are what select the
    ; location, and the last is what is done to it
    (define (split-accessors accessor*)
      (let loop ([accessor* accessor*] [rnav '()])
        (if (or (null? accessor*) (null? (cdr accessor*)))
            (values (reverse rnav) accessor*)
            (loop (cdr accessor*) (cons (car accessor*) rnav)))))

    (define (nav-op-names nav*)
      (map (lambda (accessor)
             (nanopass-case (Lnodca Ledger-Accessor) accessor
               [(,src ,ledger-op ,expr* ...) ledger-op]))
           nav*))

    (define (record-access! src field-name accessor*)
      (let-values ([(nav* last*) (split-accessors accessor*)])
        (unless (null? last*)
          (let ([info (final-op-info field-name accessor*)]
                [place-name (ormap place-of-accessor nav*)])
            (when (and info place-name)
              (set! revent*
                (cons (cons 'access
                            (make-access src field-name (nav-op-names nav*) place-name
                                         (car info) (cadr info) (caddr info)))
                      revent*)))))))

    ; `assert(j != k, ...)` is the opt-in that says two places are distinct.  It is
    ; recorded as an event rather than acted on here: the assertion lives in the CALLER,
    ; naming the caller's key variables, while the accesses live in the callee.  That
    ; separation is E6 of place-references-impl-plan.md, and is why the in-body form the
    ; plan originally specified could never fire -- a callee cannot name its own keys.
    (define (note-assertion! expr)
      (nanopass-case (Lnodca Expression) expr
        [(!= ,src ,type ,expr1 ,expr2)
         (set! revent* (cons (list 'assert-ne src expr1 expr2) revent*))]
        [else (void)]))

    ; Two key expressions are the same only when we can see that they are.  Anything
    ; computed inline fails to match, which leaves the call reported rather than excused.
    (define (expr-equal? e1 e2)
      (nanopass-case (Lnodca Expression) e1
        [(var-ref ,src1 ,var-name1)
         (nanopass-case (Lnodca Expression) e2
           [(var-ref ,src2 ,var-name2) (eq? var-name1 var-name2)]
           [else #f])]
        [else #f]))

    ; Every event carries a source position: an access through its ledger reference, an
    ; assertion and a call through their own src.
    (define (event-src event)
      (case (car event)
        [(access) (access-src (cdr event))]
        [else (cadr event)]))

    (define (in-source-order event*)
      (sort (lambda (e1 e2)
              (< (source-object-bfp (event-src e1)) (source-object-bfp (event-src e2))))
            event*))

    ; the place parameters of a circuit, as (place-name . argument index)
    (define (place-arg-indices arg*)
      (let loop ([arg* arg*] [i 0] [acc '()])
        (if (null? arg*)
            (reverse acc)
            (loop (cdr arg*) (fx+ i 1)
                  (nanopass-case (Lnodca Argument) (car arg*)
                    [(,var-name ,type)
                     (let ([place-name (id-place-name var-name)])
                       (if place-name (cons (cons place-name i) acc) acc))])))))

    ; the key expressions inside a keys-tuple actual argument
    (define (keys-of-argument expr)
      (nanopass-case (Lnodca Expression) expr
        [(tuple ,src ,tuple-arg* ...)
         (map (lambda (tuple-arg)
                (nanopass-case (Lnodca Tuple-Argument) tuple-arg
                  [(single ,src^ ,expr^) expr^]
                  [else #f]))
              tuple-arg*)]
        [else '()]))

    ; Two places are separated when some key position is asserted different.  One
    ; position suffices: distinct keys anywhere along the path mean distinct locations.
    (define (separated? key1* key2* ne*)
      (let loop ([a key1*] [b key2*])
        (and (pair? a) (pair? b)
             (or (and (car a) (car b)
                      (ormap (lambda (ne)
                               (or (and (expr-equal? (car ne) (car a))
                                        (expr-equal? (cdr ne) (car b)))
                                   (and (expr-equal? (car ne) (car b))
                                        (expr-equal? (cdr ne) (car a)))))
                             ne*))
                 (loop (cdr a) (cdr b))))))

    (define (write? a) (not (eq? (access-op-class a) 'read)))

    ; NOT a commutativity table -- a whitelist of write pairs we have decided not to
    ; complain about.  The distinction matters, because the two are not the same and a
    ; future reader would otherwise "correct" this into being wrong:
    ;
    ;   Counter.increment and Counter.decrement do NOT commute.  decrement errors below
    ;   zero, and that partiality is observable: on a counter holding 1,
    ;   `inc(1); dec(2)` succeeds and `dec(2); inc(1)` aborts.  The pair is listed here
    ;   because E4 requires `a.decrement(n); b.increment(n)` not be rejected -- it is
    ;   correct when aliased -- not because the operations commute.
    ;
    ; Commutation proper is also not a property of an op pair at all: Cell.write(v1) and
    ; Cell.write(v2) agree iff v1 = v2, which is a run-time condition.  So any table
    ; keyed on op names alone has to be conservative wherever the arguments matter.
    ;
    ; The set of pairs is finite and enumerable -- 96 unordered write pairs across the
    ; seven ADTs reachable at the end of a place path (Kernel is not one of them).  This
    ; covers a handful of them and treats everything else as hazardous.  See E5 of
    ; place-references-impl-plan.md for deriving the full table from each op's VM code
    ; instead of maintaining it by hand.
    (define (writes-commute? a b)
      (let ([adt (access-adt-name a)] [op1 (access-op a)] [op2 (access-op b)])
        (and (eq? adt (access-adt-name b))
             (case adt
               ; addition and subtraction on a counter compose in either order; this is
               ; the `a.decrement(n); b.increment(n)` case E4 flags as correct-when-aliased
               [(Counter)
                (and (memq op1 '(increment decrement)) (memq op2 '(increment decrement)))]
               ; adding the same element twice is idempotent, in either order
               [(Set) (and (eq? op1 'insert) (eq? op2 'insert))]
               ; two identical resets or removals agree whichever runs second
               [else (and (eq? op1 op2) (memq (access-op-class a) '(remove)))]))))

    (define (may-alias? a b)
      (and (eq? (access-field-name a) (access-field-name b))
           (not (eq? (access-place-name a) (access-place-name b)))
           (equal? (access-nav-op* a) (access-nav-op* b))))

    ; Phase 1: what would go wrong in this body if two of its places coincided.  No
    ; error is raised here -- the call site is what supplies the keys, and so is where
    ; the author can do something about it.
    (define (compute-hazards event*)
      (let ([access* (fold-right (lambda (event acc)
                                   (if (eq? (car event) 'access) (cons (cdr event) acc) acc))
                                 '() event*)])
        (let loop ([access* access*] [rhazard* '()])
          (if (null? access*)
              (reverse rhazard*)
              (let ([earlier (car access*)])
                (loop (cdr access*)
                      (fold-left
                        (lambda (rhazard* later)
                          (if (and (may-alias? earlier later) (write? earlier))
                              (cond
                                [(not (write? later))
                                 (cons (make-hazard 'read-after-write
                                                    (access-place-name later) (access-op later)
                                                    (access-src later)
                                                    (access-place-name earlier) (access-op earlier)
                                                    (access-src earlier))
                                       rhazard*)]
                                [(not (writes-commute? earlier later))
                                 (cons (make-hazard 'non-commuting
                                                    (access-place-name later) (access-op later)
                                                    (access-src later)
                                                    (access-place-name earlier) (access-op earlier)
                                                    (access-src earlier))
                                       rhazard*)]
                                [else rhazard*])
                              rhazard*))
                        rhazard* (cdr access*))))))))

    ; Phase 2: judge each call of a circuit that has hazards.  Only disequalities
    ; asserted *before* the call count, matching how phase 1 approximates order.
    (define (check-calls! a)
      (let loop ([event* (cdr a)] [ne* '()])
        (unless (null? event*)
          (let ([event (car event*)])
            (case (car event)
              [(assert-ne)
               (loop (cdr event*) (cons (cons (caddr event) (cadddr event)) ne*))]
              [(call)
               (let* ([src (cadr event)]
                      [callee (caddr event)]
                      [arg* (cdddr event)]
                      [hazard* (hashtable-ref hazard-ht callee '())]
                      [index* (hashtable-ref arg-index-ht callee '())])
                 (for-each
                   (lambda (hazard)
                     (let ([i (assq (hazard-later-place hazard) index*)]
                           [j (assq (hazard-earlier-place hazard) index*)])
                       (when (and i j
                                  (fx< (cdr i) (length arg*))
                                  (fx< (cdr j) (length arg*))
                                  (not (separated? (keys-of-argument (list-ref arg* (cdr i)))
                                                   (keys-of-argument (list-ref arg* (cdr j)))
                                                   ne*)))
                         (report! src callee hazard))))
                   hazard*))
               (loop (cdr event*) ne*)]
              [else (loop (cdr event*) ne*)])))))

    (define (report! src callee hazard)
      (if (eq? (hazard-kind hazard) 'read-after-write)
          (source-errorf src
            "this call may pass one location as both places ~s and ~s of ~a, which reads \
             it at ~a after writing it at ~a; assert that the two keys differ before the call"
            (hazard-later-place hazard) (hazard-earlier-place hazard) (id-sym callee)
            (format-source-object (hazard-later-src hazard))
            (format-source-object (hazard-earlier-src hazard)))
          (source-errorf src
            "this call may pass one location as both places ~s and ~s of ~a, where ~s at ~a \
             does not commute with ~s at ~a; assert that the two keys differ before the call"
            (hazard-later-place hazard) (hazard-earlier-place hazard) (id-sym callee)
            (hazard-later-op hazard) (format-source-object (hazard-later-src hazard))
            (hazard-earlier-op hazard) (format-source-object (hazard-earlier-src hazard)))))
    )

  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-adt-ops! pelt*)
     ; collect every body first: a call cannot be judged until its callee's hazards are
     ; known, and the callee may be defined after the caller
     (for-each Program-Element pelt*)
     (let ([body* (reverse circuit-event*)])
       (for-each
         (lambda (a)
           (let ([hazard* (compute-hazards (cdr a))])
             (unless (null? hazard*)
               (hashtable-set! hazard-ht (car a) hazard*))))
         body*)
       (for-each check-calls! body*))
     ir])

  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (fluid-let ([revent* '()])
       (Expression expr)
       (set! circuit-event*
         (cons (cons function-name (in-source-order revent*)) circuit-event*)))
     (hashtable-set! arg-index-ht function-name (place-arg-indices arg*))
     ir]
    ; no clause for the ledger constructor: Loneledger folds it into the ledger
    ; declaration rather than leaving it a Program-Element, and it cannot take place
    ; parameters in any case -- expand-place-params rejects & at that boundary.
    [else ir])

  (Ledger-Accessor : Ledger-Accessor (ir) -> Ledger-Accessor ())

  (Expression : Expression (ir) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? ,[accessor*] ...)
     (record-access! src ledger-field-name accessor*)
     ir]
    [(assert ,src ,[expr] ,mesg)
     ; a disequality between two places is the opt-in that says they are distinct
     (note-assertion! expr)
     ir]
    [(call ,src ,function-name ,[expr*] ...)
     (set! revent* (cons (list* 'call src function-name expr*) revent*))
     ir]
    [(let* ,src ([,local* ,[expr*]] ...) ,[expr])
     ; carry provenance across a binding, so that a hoisted key expression still
     ; attributes its access to the right place
     (for-each
       (lambda (local rhs)
         (let ([place-name (place-of-expr rhs)])
           (when place-name
             ; local is an Argument, (var-name type) -- the id is inside it
             (nanopass-case (Lnodca Argument) local
               [(,var-name ,type) (id-place-name-set! var-name place-name)]))))
       local* expr*)
     ir]))
