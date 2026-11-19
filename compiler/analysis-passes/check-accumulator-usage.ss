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

;; check-accumulator-usage checks that each Accumulator is used exactly once,
;; as ZKIR's lifecycle check requires.  infer-types calls it on every program
;; element, so misuse is reported even in circuits that are never called.
;;
;; An Accumulator is used by binding it, passing it to a circuit or to an
;; Accumulator parameter of a native, returning it, or yielding it from a
;; branch; disclose passes it through.  One returned by a witness can only be
;; used among prepareVerification's public inputs.
;;
;; ZKIR computes both branches of an if, so a branch cannot use an Accumulator
;; bound outside the if (conservatively, even where a single use would be
;; sound).  Code after an early return is the if's other branch.  A loop body
;; cannot use one bound outside it either.  A return leaves its circuit or
;; anonymous circuit called on the spot, which must have used what it bound.
;;
;; env maps each Accumulator variable to live, used, (branch . if-src), or loop.

(define (check-accumulator-usage! pelt*)
  (define-record-type signature
    (nongenerative)
    (fields kind arg-type* maybe-type-param* return-type))

  ;; maps circuit, native, and witness names to their signatures
  (define signature-ht (make-eq-hashtable))

  ;; an Accumulator-valued expression: its src and whether a witness returned it
  (define-record-type produced
    (nongenerative)
    (fields src witness?))

  (define (produced-witness*? p*)
    (and (exists (lambda (p) (and p (produced-witness? p))) p*) #t))

  ;; the ids of the variables bound to an Accumulator returned by a witness
  (define witness-var-ht (make-eq-hashtable))

  (define (verify-not-witness! p what)
    (when (and p (produced-witness? p))
      (source-errorf (produced-src p)
        "an Accumulator returned by a witness can only be used among the public inputs of prepareVerification, not ~a"
        what)))

  ;; what a return leaves: a circuit body or an anonymous circuit called on the
  ;; spot (kind lambda); returned* collects what its returns produce
  (define-record-type target
    (nongenerative)
    (fields kind base-ids (mutable returned*)))

  (define current-target (make-parameter #f))

  ;; the walk after a return, holding the environment at the return
  (define-record-type returned
    (nongenerative)
    (fields env))

  (define (dead? env) (returned? env))

  (define (accumulator-type? type)
    (nanopass-case (Ltypes Type) type
      [(taccumulator ,src) #t]
      [(talias ,src ,nominal? ,type-name ,type) (accumulator-type? type)]
      [else #f]))

  (define (arg-name arg) (nanopass-case (Ltypes Argument) arg [(,var-name ,type) var-name]))
  (define (arg-type arg) (nanopass-case (Ltypes Argument) arg [(,var-name ,type) type]))

  (define (accumulator-arg-names arg*)
    (map arg-name (filter (lambda (arg) (accumulator-type? (arg-type arg))) arg*)))

  (define (env-state env id) (cond [(assq id env) => cdr] [else #f]))
  ;; ids are unique, so entries are replaced rather than shadowed
  (define (env-extend env id state)
    (if (assq id env)
        (map (lambda (a) (if (eq? (car a) id) (cons id state) a)) env)
        (cons (cons id state) env)))
  (define (env-ids env) (map car env))
  (define (capture env state)
    (map (lambda (a) (if (eq? (cdr a) 'live) (cons (car a) state) a)) env))

  (define (bind-args env arg*)
    (fold-left (lambda (env id) (env-extend env id 'live)) env (accumulator-arg-names arg*)))

  ;; binds arg by its declared type
  (define (bind env arg p)
    (cond
      [(dead? env) env]
      [(accumulator-type? (arg-type arg))
       (unless p
         (internal-errorf 'check-accumulator-usage "no Accumulator produced for ~s" (arg-name arg)))
       (when (produced-witness? p) (eq-hashtable-set! witness-var-ht (arg-name arg) #t))
       (env-extend env (arg-name arg) 'live)]
      [else
       (when p
         (internal-errorf 'check-accumulator-usage "Accumulator produced for ~s, which is not one" (arg-name arg)))
       env]))

  (define (use src env id)
    (let ([state (env-state env id)])
      (cond
        [(eq? state 'live) (env-extend env id 'used)]
        [(eq? state 'used) (source-errorf src "Accumulator ~s is used more than once" (id-sym id))]
        [(and (pair? state) (eq? (car state) 'branch))
         (let ([if-src (cdr state)])
           ;; a use past the end of the if follows an early return
           (if (> (source-object-bfp src) (source-object-efp if-src))
               (source-errorf src "Accumulator ~s is bound before the if at ~a, which can return early, so the code after that if cannot use it"
                 (id-sym id) (format-source-object if-src))
               (source-errorf src "Accumulator ~s is bound outside the if at ~a, so neither of its branches can use it"
                 (id-sym id) (format-source-object if-src))))]
        [(eq? state 'loop) (source-errorf src "Accumulator ~s cannot be used inside a for loop, map, or fold" (id-sym id))]
        [else (internal-errorf 'check-accumulator-usage "unrecognized Accumulator ~s" id)])))

  (define (verify-used! env id*)
    (unless (dead? env)
      (for-each
        (lambda (id)
          (when (eq? (env-state env id) 'live)
            (source-errorf (id-src id) "Accumulator ~s is never used" (id-sym id))))
        id*)))

  ;; checks the Accumulators bound within the current target are used by src
  (define (verify-none-live! src env mesg)
    (let ([base-ids (target-base-ids (current-target))])
      (for-each
        (lambda (id)
          (when (and (eq? (env-state env id) 'live) (not (memq id base-ids)))
            (source-errorf (id-src id) mesg (id-sym id) (format-source-object src))))
        (env-ids env))))

  ;; walks a target's body, returning the env after it, its fall-through value,
  ;; and the values of every path out of it
  (define (Target kind base-ids expr env)
    (let ([t (make-target kind base-ids '())])
      (let-values ([(env p) (parameterize ([current-target t]) (Expr expr env))])
        (let ([p* (if (dead? env) (target-returned* t) (cons p (target-returned* t)))])
          (values
            (if (dead? env) (returned-env env) env)
            p
            p*)))))

  ;; all paths out of an expression produce an Accumulator, or none does
  (define (combine src p*)
    (cond
      [(for-all not p*) #f]
      [(exists not p*)
       (internal-errorf 'check-accumulator-usage "only some paths at ~a produce an Accumulator"
         (format-source-object src))]
      [else (make-produced src (produced-witness*? p*))]))

  ;; returns the env after expr and, if expr yields an Accumulator, its produced
  (define (Expr expr env)
    (define (none env) (values env #f))
    (if (dead? env)
        (none env)
        (nanopass-case (Ltypes Expression) expr
          [(quote ,src ,datum) (none env)]
          [(var-ref ,src ,var-name)
           (if (env-state env var-name)
               (values (use src env var-name)
                       (make-produced src (eq-hashtable-ref witness-var-ht var-name #f)))
               (none env))]
          [(ledger-ref ,src ,ledger-field-name) (none env)]
          [(default ,src ,type) (none env)]
          [(enum-ref ,src ,type ,elt-name) (none env)]
          ;; a branch changes nothing bound outside the if
          [(if ,src ,expr0 ,expr1 ,expr2)
           (let ([env (No-Accumulator expr0 env "the test of an if")])
             (if (dead? env)
                 (none env)
                 (let ([benv (capture env (cons 'branch src))])
                   (let-values ([(env1 p1) (Expr expr1 benv)] [(env2 p2) (Expr expr2 benv)])
                     (if (and (dead? env1) (dead? env2))
                         ;; nothing after the if runs
                         (begin
                           (verify-none-live! src env "Accumulator ~s is never used before the if at ~a, both of whose branches return")
                           (none (make-returned env)))
                         (values env
                           (combine src
                             (append (if (dead? env1) '() (list p1))
                                     (if (dead? env2) '() (list p2))))))))))]
          [(elt-ref ,src ,expr ,elt-name ,nat)
           (none (No-Accumulator expr env "the operand of a field reference"))]
          [(emit ,src ,type ,expr) (none (No-Accumulator expr env "an event"))]
          [(serialize ,src ,len ,type ,expr) (none (No-Accumulator expr env "the argument of serialize"))]
          ;; an Accumulator built from arbitrary bytes would be unchecked
          [(deserialize ,src ,len ,type ,expr)
           (let ([env (No-Accumulator expr env "the argument of deserialize")])
             (when (accumulator-type? type)
               (source-errorf src "an Accumulator cannot be deserialized"))
             (none env))]
          [(tuple ,src ,tuple-arg* ...) (none (No-Accumulator* (map tuple-arg-expr tuple-arg*) env "a tuple element"))]
          [(vector ,src ,tuple-arg* ...) (none (No-Accumulator* (map tuple-arg-expr tuple-arg*) env "a vector element"))]
          [(tuple-ref ,src ,expr ,kindex) (none (No-Accumulator expr env "the operand of a tuple reference"))]
          [(tuple-slice ,src ,type ,expr ,kindex ,len) (none (No-Accumulator expr env "the operand of a slice"))]
          [(vector-ref ,src ,type ,expr ,index) (none (No-Accumulator* (list expr index) env "an operand of a vector reference"))]
          [(vector-slice ,src ,type ,expr ,index ,len) (none (No-Accumulator* (list expr index) env "an operand of a slice"))]
          [(bytes-ref ,src ,type ,expr ,index) (none (No-Accumulator* (list expr index) env "an operand of a bytes reference"))]
          [(bytes-slice ,src ,type ,expr ,index ,len) (none (No-Accumulator* (list expr index) env "an operand of a slice"))]
          [(+ ,src ,type ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of +"))]
          [(- ,src ,type ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of -"))]
          [(* ,src ,type ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of *"))]
          [(< ,src ,bits ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of <"))]
          [(<= ,src ,bits ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of <="))]
          [(> ,src ,bits ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of >"))]
          [(>= ,src ,bits ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of >="))]
          [(== ,src ,type ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of =="))]
          [(!= ,src ,type ,expr1 ,expr2) (none (No-Accumulator* (list expr1 expr2) env "an operand of !="))]
          [(map ,src ,len ,fun ,map-arg ,map-arg* ...)
           (verify-loop-function! src fun env "map")
           (none (No-Accumulator* (map map-arg-expr (cons map-arg map-arg*)) env "a map argument"))]
          [(fold ,src ,len ,fun (,expr0 ,type0) ,map-arg ,map-arg* ...)
           (when (accumulator-type? type0)
             (source-errorf src "a for loop or fold cannot carry an Accumulator"))
           (verify-loop-function! src fun env "a for loop or fold")
           (none (No-Accumulator* (cons expr0 (map map-arg-expr (cons map-arg map-arg*))) env "a fold argument"))]
          [(call ,src ,fun ,expr* ...) (Call src fun expr* env)]
          [(new ,src ,type ,expr* ...) (none (No-Accumulator* expr* env "a struct field"))]
          [(seq ,src ,expr* ... ,expr)
           (let ([env (fold-left Discard env expr*)])
             (Expr expr env))]
          [(let* ,src ([,local* ,expr*] ...) ,expr)
           (let ([env (fold-left
                        (lambda (env local expr)
                          (let-values ([(env p) (Expr expr env)])
                            (bind env local p)))
                        env local* expr*)])
             (let-values ([(env p) (Expr expr env)])
               (verify-used! env (accumulator-arg-names local*))
               (values env p)))]
          [(assert ,src ,expr ,mesg) (none (No-Accumulator expr env "the test of an assert"))]
          [(field->bytes ,src ,len ,ftype ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(cast-from-bytes ,src ,type ,len ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(vector->bytes ,src ,len ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(bytes->vector ,src ,len ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(cast-from-enum ,src ,type ,type^ ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(cast-to-enum ,src ,type ,type^ ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(cast-to-field ,src ,ftype ,type ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(cast-from-field ,src ,nat ,ftype ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(downcast-unsigned ,src ,nat2 ,nat1 ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          ;; never an Accumulator, which is a subtype only of itself
          [(safe-cast ,src ,type ,type^ ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
          [(disclose ,src ,expr) (Expr expr env)]
          [(ledger-call ,src ,ledger-op ,sugar? ,expr ,expr* ...)
           (none (No-Accumulator* (cons expr expr*) env "an argument of a ledger operation"))]
          [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
           (none (No-Accumulator* (cons expr expr*) env "an argument of a contract call"))]
          ;; an Accumulator among the public inputs is bound to the inner proof
          [(prepare-verification ,src ,vk (,pubin* ...) ,expr)
           (let* ([env (fold-left
                         (lambda (env pubin)
                           (nanopass-case (Ltypes Public-Input) pubin
                             [(pi-fields ,expr ,type) (No-Accumulator expr env "a public input of prepareVerification")]
                             [(pi-accumulator ,expr) (let-values ([(env p) (Expr expr env)]) env)]))
                         env
                         pubin*)]
                  [env (No-Accumulator expr env "the proof of prepareVerification")])
             (values env (and (not (dead? env)) (make-produced src #f))))]
          [(return ,src ,expr)
           (let-values ([(env p) (Expr expr env)])
             (if (dead? env)
                 (none env)
                 (let ([t (current-target)])
                   (when (eq? (target-kind t) 'circuit) (verify-not-witness! p "returned"))
                   (verify-none-live! src env "Accumulator ~s is never used on the path through the return at ~a")
                   (target-returned*-set! t (cons p (target-returned* t)))
                   (none (make-returned env)))))]
          [else (internal-errorf 'check-accumulator-usage "unexpected expression ~s" expr)])))

  (define (tuple-arg-expr tuple-arg)
    (nanopass-case (Ltypes Tuple-Argument) tuple-arg
      [(single ,src ,expr) expr]
      [(spread ,src ,nat ,expr) expr]))

  (define (map-arg-expr map-arg)
    (nanopass-case (Ltypes Map-Argument) map-arg
      [(,expr ,type ,type^) expr]))

  ;; walks expr in a context that cannot use an Accumulator
  (define (No-Accumulator expr env what)
    (let-values ([(env p) (Expr expr env)])
      (when p
        (source-errorf (produced-src p) "an Accumulator cannot be used as ~a" what))
      env))

  (define (No-Accumulator* expr* env what)
    (fold-left (lambda (env expr) (No-Accumulator expr env what)) env expr*))

  ;; walks expr in a context that discards its value
  (define (Discard env expr)
    (let-values ([(env p) (Expr expr env)])
      (when p
        (source-errorf (produced-src p) "this Accumulator is never used"))
      env))

  (define (lookup-signature function-name)
    (or (eq-hashtable-ref signature-ht function-name #f)
        (internal-errorf 'check-accumulator-usage "no signature for ~s" function-name)))

  (define (callee-description kind function-name)
    (case kind
      ;; the n-ary accumulate is a nest of the private binary one
      [(native) (if (eq? (id-sym function-name) '__compact_accumulate)
                    "accumulate"
                    (symbol->string (id-sym function-name)))]
      [else (format "~a ~s" kind (id-sym function-name))]))

  (define (Call src fun expr* env)
    (nanopass-case (Ltypes Function) fun
      [(fref ,src^ ,function-name)
       (let ([sig (lookup-signature function-name)])
         (let loop ([expr* expr*] [i 0] [env env])
           (cond
             [(null? expr*)
              (values env
                      (and (not (dead? env))
                           (accumulator-type? (signature-return-type sig))
                           (make-produced src (eq? (signature-kind sig) 'witness))))]
             [else
              (let-values ([(env p) (Expr (car expr*) env)])
                (when (and p (not (accepts-accumulator? sig i)))
                  (source-errorf (produced-src p) "an Accumulator cannot be passed to ~a ~s"
                    (signature-kind sig) (id-sym function-name)))
                (verify-not-witness! p
                  (format "passed to ~a" (callee-description (signature-kind sig) function-name)))
                (loop (cdr expr*) (fx+ i 1) env))])))]
      ;; runs once, like a let*, and is its own return target
      [(circuit ,src^ (,arg* ...) ,type ,expr)
       (let* ([base-ids (env-ids env)]
              [env (fold-left
                     (lambda (env arg expr)
                       (let-values ([(env p) (Expr expr env)])
                         (bind env arg p)))
                     env arg* expr*)])
         (if (dead? env)
             (values env #f)
             (let-values ([(env p p*) (Target 'lambda base-ids expr env)])
               (verify-used! env (accumulator-arg-names arg*))
               (values env (combine src p*)))))]))

  ;; a native takes one only through a parameter declared Accumulator, so a
  ;; generic native like transientHash cannot absorb it
  (define (accepts-accumulator? sig i)
    (and (accumulator-type? (list-ref (signature-arg-type* sig) i))
         (case (signature-kind sig)
           [(circuit) #t]
           [(native) (not (list-ref (signature-maybe-type-param* sig) i))]
           [else #f])))

  (define (verify-loop-function! src fun env what)
    (nanopass-case (Ltypes Function) fun
      [(fref ,src^ ,function-name)
       (when (accumulator-type? (signature-return-type (lookup-signature function-name)))
         (source-errorf src "~a cannot produce an Accumulator" what))]
      [(circuit ,src^ (,arg* ...) ,type ,expr)
       (when (accumulator-type? type)
         (source-errorf src "~a cannot produce an Accumulator" what))
       (verify-body! arg* type expr (capture env 'loop))]))

  ;; type is #f for the constructor
  (define (verify-body! arg* type expr env)
    (let-values ([(env p p*) (Target 'circuit (env-ids env) expr (bind-args env arg*))])
      (when (and p (not (and type (accumulator-type? type))))
        (source-errorf (produced-src p) "this Accumulator is never used"))
      (verify-not-witness! p "returned")
      (verify-used! env (accumulator-arg-names arg*))))

  (define (record-signature! pelt)
    (nanopass-case (Ltypes Program-Element) pelt
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (eq-hashtable-set! signature-ht function-name
         (make-signature 'circuit (map arg-type arg*) #f type))]
      [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
       (eq-hashtable-set! signature-ht function-name
         (make-signature 'native (map arg-type arg*) (native-entry-maybe-type-param* native-entry) type))]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (eq-hashtable-set! signature-ht function-name
         (make-signature 'witness (map arg-type arg*) #f type))]
      [else (void)]))

  (define (verify-element! pelt)
    (nanopass-case (Ltypes Program-Element) pelt
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr) (verify-body! arg* type expr '())]
      [(constructor ,src (,arg* ...) ,expr) (verify-body! arg* #f expr '())]
      [else (void)]))

  (for-each record-signature! pelt*)
  (for-each verify-element! pelt*))
