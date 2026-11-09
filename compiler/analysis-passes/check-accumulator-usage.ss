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

;; check-accumulator-usage checks that every Accumulator value is used exactly
;; once on every path through a circuit.
;;
;; An Accumulator defers the final pairing check of a verified proof, so an
;; Accumulator that is dropped is a proof that is never checked, and ZKIR
;; rejects one that is used twice.  An Accumulator is used by binding it with
;; const, passing it to a circuit, returning it, or yielding it from a branch
;; of an if, whose two branches are then merged with a select.  It cannot be
;; used anywhere else: not in an operator, a tuple, vector, or struct, a
;; disclose, a ledger operation, or as the argument of a native or witness
;; that does not declare an Accumulator parameter.
;;
;; The check is path-sensitive.  The two branches of an if must use the same
;; Accumulators bound outside it, so the one a select drops is always one the
;; untaken branch produced, which its guard reduces to the trivial
;; Accumulator.  A for loop, map, or fold body runs once per element, so it
;; cannot use an Accumulator bound outside it.
;;
;; The environment threaded through the walk is either the symbol dead, for
;; a path that has returned, or an association list mapping each Accumulator
;; variable in scope to one of:
;;   live      bound and not yet used
;;   used      already used on this path
;;   captured  bound outside the loop body being checked
;; Later entries shadow earlier ones; ids are unique, so scope exit needs no
;; removal.

;; It is called by infer-types on every typed program element, including
;; those unreachable from the exports, so that, like type errors, misuse is
;; reported even in circuits that are never called.

(define (check-accumulator-usage! pelt*)
  (let ()
    (define-record-type signature
      (nongenerative)
      (fields kind arg-type* maybe-type-param* return-type))

    ;; maps circuit, native, and witness names to their signatures
    (define signature-ht (make-eq-hashtable))

    (define (accumulator-type? type)
      (nanopass-case (Ltypes Type) type
        [(taccumulator ,src) #t]
        [(talias ,src ,nominal? ,type-name ,type) (accumulator-type? type)]
        [else #f]))

    (define (arg-name arg) (nanopass-case (Ltypes Argument) arg [(,var-name ,type) var-name]))
    (define (arg-type arg) (nanopass-case (Ltypes Argument) arg [(,var-name ,type) type]))

    (define (dead? env) (eq? env 'dead))
    (define (env-state env id) (cond [(assq id env) => cdr] [else #f]))
    (define (env-extend env id state) (cons (cons id state) env))
    (define (env-ids env)
      (let loop ([env env] [seen '()])
        (if (null? env)
            seen
            (loop (cdr env) (if (memq (caar env) seen) seen (cons (caar env) seen))))))
    (define (capture env)
      (if (dead? env) env (map (lambda (a) (cons (car a) 'captured)) env)))
    (define (bind-args env arg*)
      (fold-left
        (lambda (env arg)
          (if (accumulator-type? (arg-type arg))
              (env-extend env (arg-name arg) 'live)
              env))
        env
        arg*))

    (define (use src env id)
      (case (env-state env id)
        [(live) (env-extend env id 'used)]
        [(used) (source-errorf src "Accumulator ~s is used more than once" (id-sym id))]
        [(captured) (source-errorf src "Accumulator ~s cannot be used inside a for loop, map, or fold" (id-sym id))]
        [else (internal-errorf 'check-accumulator-usage "unrecognized Accumulator ~s" id)]))

    (define (verify-used! env id*)
      (unless (dead? env)
        (for-each
          (lambda (id)
            (when (eq? (env-state env id) 'live)
              (source-errorf (id-src id) "Accumulator ~s is never used" (id-sym id))))
          id*)))

    (define (verify-none-live! src env)
      (for-each
        (lambda (id)
          (when (eq? (env-state env id) 'live)
            (source-errorf (id-src id) "Accumulator ~s is never used on the path through the return at ~a"
              (id-sym id) (format-source-object src))))
        (env-ids env)))

    (define (merge-branches src env env1 env2)
      (cond
        [(dead? env1) env2]
        [(dead? env2) env1]
        [else
         (for-each
           (lambda (id)
             (unless (eq? (env-state env1 id) (env-state env2 id))
               (source-errorf src "Accumulator ~s is used on some paths through this if but not on others"
                 (id-sym id))))
           (env-ids env))
         env1]))

    ;; Walks expr with environment env and returns two values: the environment
    ;; after expr, and either #f or, when expr's value is an Accumulator that its
    ;; context must use, the source object of the expression producing it.
    (define (Expr expr env)
      (define (none env) (values env #f))
      (if (dead? env)
          (none env)
          (nanopass-case (Ltypes Expression) expr
            [(quote ,src ,datum) (none env)]
            [(var-ref ,src ,var-name)
             (if (env-state env var-name)
                 (values (use src env var-name) src)
                 (none env))]
            [(ledger-ref ,src ,ledger-field-name) (none env)]
            [(default ,src ,type) (none env)]
            [(enum-ref ,src ,type ,elt-name) (none env)]
            [(if ,src ,expr0 ,expr1 ,expr2)
             (let ([env (No-Accumulator expr0 env "the test of an if")])
               (if (dead? env)
                   (none env)
                   (let-values ([(env1 src1) (Expr expr1 env)] [(env2 src2) (Expr expr2 env)])
                     (values
                       (merge-branches src env env1 env2)
                       (and (or src1 src2) src)))))]
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
                            (let-values ([(env acc-src) (Expr expr env)])
                              (cond
                                [(dead? env) env]
                                [acc-src (env-extend env (arg-name local) 'live)]
                                [else env])))
                          env local* expr*)])
               (let-values ([(env acc-src) (Expr expr env)])
                 (verify-used! env (map arg-name (filter (lambda (local) (accumulator-type? (arg-type local))) local*)))
                 (values env acc-src)))]
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
            ;; infer-types inserts a safe-cast between two types only when they
            ;; differ, and Accumulator is a subtype only of itself, so a
            ;; safe-cast never applies to an Accumulator.
            [(safe-cast ,src ,type ,type^ ,expr) (none (No-Accumulator expr env "the operand of a cast"))]
            [(disclose ,src ,expr) (none (No-Accumulator expr env "the argument of disclose"))]
            [(ledger-call ,src ,ledger-op ,sugar? ,expr ,expr* ...)
             (none (No-Accumulator* (cons expr expr*) env "an argument of a ledger operation"))]
            [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
             (none (No-Accumulator* (cons expr expr*) env "an argument of a contract call"))]
            [(prepare-verification ,src ,vk ,expr1 ,expr2)
             (let ([env (No-Accumulator* (list expr1 expr2) env "an argument of prepareVerification")])
               (values env (and (not (dead? env)) src)))]
            [(return ,src ,expr)
             (let-values ([(env acc-src) (Expr expr env)])
               (unless (dead? env) (verify-none-live! src env))
               (none 'dead))]
            [else (internal-errorf 'check-accumulator-usage "unexpected expression ~s" expr)])))

    (define (tuple-arg-expr tuple-arg)
      (nanopass-case (Ltypes Tuple-Argument) tuple-arg
        [(single ,src ,expr) expr]
        [(spread ,src ,nat ,expr) expr]))

    (define (map-arg-expr map-arg)
      (nanopass-case (Ltypes Map-Argument) map-arg
        [(,expr ,type ,type^) expr]))

    ;; Walks expr in a context that cannot use an Accumulator.
    (define (No-Accumulator expr env what)
      (let-values ([(env acc-src) (Expr expr env)])
        (when acc-src
          (source-errorf acc-src "an Accumulator cannot be used as ~a" what))
        env))

    (define (No-Accumulator* expr* env what)
      (fold-left (lambda (env expr) (No-Accumulator expr env what)) env expr*))

    ;; Walks expr in a context that discards its value.
    (define (Discard env expr)
      (let-values ([(env acc-src) (Expr expr env)])
        (when acc-src
          (source-errorf acc-src "this Accumulator is never used"))
        env))

    (define (Call src fun expr* env)
      (nanopass-case (Ltypes Function) fun
        [(fref ,src^ ,function-name)
         (let ([sig (eq-hashtable-ref signature-ht function-name #f)])
           (unless sig
             (internal-errorf 'check-accumulator-usage "no signature for ~s" function-name))
           (let loop ([expr* expr*] [i 0] [env env])
             (cond
               [(null? expr*)
                (values env (and (not (dead? env)) (accumulator-type? (signature-return-type sig)) src))]
               [else
                (let-values ([(env acc-src) (Expr (car expr*) env)])
                  (when (and acc-src (not (accepts-accumulator? sig i)))
                    (source-errorf acc-src "an Accumulator cannot be passed to ~a ~s"
                      (signature-kind sig) (id-sym function-name)))
                  (loop (cdr expr*) (fx+ i 1) env))])))]
        ;; an anonymous circuit called on the spot runs once, like a let*
        [(circuit ,src^ (,arg* ...) ,type ,expr)
         (let ([env (fold-left
                      (lambda (env arg expr)
                        (let-values ([(env acc-src) (Expr expr env)])
                          (if (and acc-src (not (dead? env)))
                              (env-extend env (arg-name arg) 'live)
                              env)))
                      env arg* expr*)])
           (let-values ([(env acc-src) (Expr expr env)])
             (verify-used! env (map arg-name (filter (lambda (arg) (accumulator-type? (arg-type arg))) arg*)))
             (values env acc-src)))]))

    ;; A circuit uses an Accumulator argument by binding it to its parameter,
    ;; which its own body must then use.  A native uses one only through a
    ;; parameter declared as Accumulator, not through a type parameter, so
    ;; that a generic native like transientHash cannot absorb an Accumulator.
    (define (accepts-accumulator? sig i)
      (and (accumulator-type? (list-ref (signature-arg-type* sig) i))
           (case (signature-kind sig)
             [(circuit) #t]
             [(native) (not (list-ref (signature-maybe-type-param* sig) i))]
             [else #f])))

    ;; A loop body runs once per element, so it can neither produce an
    ;; Accumulator for each element nor use one bound outside it.
    (define (verify-loop-function! src fun env what)
      (nanopass-case (Ltypes Function) fun
        [(fref ,src^ ,function-name)
         (let ([sig (eq-hashtable-ref signature-ht function-name #f)])
           (when (and sig (accumulator-type? (signature-return-type sig)))
             (source-errorf src "~a cannot produce an Accumulator" what)))]
        [(circuit ,src^ (,arg* ...) ,type ,expr)
         (when (accumulator-type? type)
           (source-errorf src "~a cannot produce an Accumulator" what))
         (verify-body! arg* type expr (capture env))]))

    ;; Checks a circuit body whose parameters are arg* and whose return type is
    ;; type (#f for the constructor), starting from env.
    (define (verify-body! arg* type expr env)
      (let-values ([(env acc-src) (Expr expr (bind-args env arg*))])
        (when (and acc-src (not (and type (accumulator-type? type))))
          (source-errorf acc-src "this Accumulator is never used"))
        (verify-used! env (map arg-name (filter (lambda (arg) (accumulator-type? (arg-type arg))) arg*)))))

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
    (for-each verify-element! pelt*)))
