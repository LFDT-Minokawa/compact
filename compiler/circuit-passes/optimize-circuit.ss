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

;;; optimize-circuit:
;;;  - propagates copies
;;;  - eliminates unused bindings
;;;  - eliminates pure forms in effect context
;;;  - eliminates common subexpressions
;;;  - paritially folds operators, e.g., (+ x 0) -> x
;;;  - simplifies nested operations, e.g., (not (not x)) -> x, (or x (not x)) => #t
;;;  - drops asserts that can never fail
(define-pass optimize-circuit : Lflattened (ir) -> Lflattened ()
  ; this pass is an optimization pass and is thus optional.
  (definitions
    (module (triv-equal? nontriv-single-equal? triv-vec-equal? assert-equal?)
      (define-syntax T
        (syntax-rules ()
          [(_ NT ir ir^ [pat pat^ e] ...)
           (nanopass-case (Lflattened NT) ir
             [pat (nanopass-case (Lflattened NT) ir^ [pat^ e] [else #f])]
             ...
             [else #f])]))
      (define (field-type-equal? ftype ftype^)
        (nanopass-case (Lflattened Field-Type) ftype
          [(field-native)
           (nanopass-case (Lflattened Field-Type) ftype^
             [(field-native) #t]
             [else #f])]
          [(field-scalar (curve-jubjub))
           (nanopass-case (Lflattened Field-Type) ftype^
             [(field-scalar (curve-jubjub)) #t]
             [else #f])]
          [(field-base (curve-secp256k1))
           (nanopass-case (Lflattened Field-Type) ftype^
             [(field-base (curve-secp256k1)) #t]
             [else #f])]
          [(field-scalar (curve-secp256k1))
           (nanopass-case (Lflattened Field-Type) ftype^
             [(field-scalar (curve-secp256k1)) #t]
             [else #f])]))
      (define (primitive-type-equal? primitive-type primitive-type^)
        (nanopass-case (Lflattened Primitive-Type) primitive-type
          [(tfield ,ftype)
           (nanopass-case (Lflattened Primitive-Type) primitive-type^
             [(tfield ,ftype^) (field-type-equal? ftype ftype^)]
             [else #f])]
          [(tunsigned ,nat)
           (nanopass-case (Lflattened Primitive-Type) primitive-type^
             [(tunsigned ,nat^) (eqv? nat nat^)]
             [else #f])]
          [(topaque ,opaque-type)
           (nanopass-case (Lflattened Primitive-Type) primitive-type^
             [(topaque ,opaque-type^) (string=? opaque-type opaque-type^)]
             [else #f])]
          ;; We just say that tcontract and tadt are never equal.
          [else #f]))
      (define (triv-equal? triv triv^)
        (T Triv triv triv^
           [,var-name ,var-name^ (eq? var-name var-name^)]
           [,nat ,nat^ (equal? nat nat^)]))
      (define trivs-equal?
        (case-lambda
          [(triv1 triv1^ triv2 triv2^)
           (and (triv-equal? triv1 triv1^)
                (triv-equal? triv2 triv2^))]
          [(triv1 triv1^ triv2 triv2^ triv3 triv3^)
           (and (trivs-equal? triv1 triv1^ triv2 triv2^)
                (triv-equal? triv3 triv3^))]))
      (define (commutative-trivs-equal? triv1 triv1^ triv2 triv2^)
        (or (trivs-equal? triv1 triv1^ triv2 triv2^)
            (trivs-equal? triv1 triv2^ triv2 triv1^)))
      (define (nontriv-single-equal? test.single test.single^)
        (and (triv-equal? (car test.single) (car test.single^))
             (let ([single (cdr test.single)] [single^ (cdr test.single^)])
               (T Single single single^
                  [(+ ,mbits ,triv1 ,triv2) (+ ,mbits^ ,triv1^ ,triv2^)
                   (and (eqv? mbits mbits^)
                        (commutative-trivs-equal? triv1 triv1^ triv2 triv2^))]
                  [(- ,mbits ,triv1 ,triv2) (- ,mbits^ ,triv1^ ,triv2^)
                   (and (eqv? mbits mbits^)
                        (trivs-equal? triv1 triv1^ triv2 triv2^))]
                  [(* ,mbits ,triv1 ,triv2) (* ,mbits^ ,triv1^ ,triv2^)
                   (and (eqv? mbits mbits^)
                        (commutative-trivs-equal? triv1 triv1^ triv2 triv2^))]
                  [(< ,bits ,triv1 ,triv2) (< ,bits^ ,triv1^ ,triv2^)
                   (and (eqv? bits bits^)
                        (trivs-equal? triv1 triv1^ triv2 triv2^))]
                  [(== ,triv1 ,triv2) (== ,triv1^ ,triv2^)
                   (commutative-trivs-equal? triv1 triv1^ triv2 triv2^)]
                  [(select ,triv0 ,triv1 ,triv2) (select ,triv0^ ,triv1^ ,triv2^)
                   (trivs-equal? triv0 triv0^ triv1 triv1^ triv2 triv2^)]
                  [(bytes-ref ,triv ,nat) (bytes-ref ,triv^ ,nat^)
                   (and (eqv? nat nat^)
                        (triv-equal? triv triv^))]
                  [(bytes->field ,src ,ftype ,len ,triv1 ,triv2)
                   (bytes->field ,src^ ,ftype^ ,len^ ,triv1^ ,triv2^)
                   (and (field-type-equal? ftype ftype^)
                        (eqv? len len^)
                        (trivs-equal? triv1 triv1^ triv2 triv2^))]
                  [(cast-to-field ,ftype ,primitive-type ,triv) (cast-to-field ,ftype^ ,primitive-type^ ,triv^)
                   (and (field-type-equal? ftype ftype^)
                        (primitive-type-equal? primitive-type primitive-type^)
                        (triv-equal? triv triv^))]
                  [(cast-from-field ,src ,safe ,nat ,ftype ,triv) (cast-from-field ,src^ ,safe^ ,nat^ ,ftype^ ,triv^)
                   (and (eqv? safe safe^)
                        (eqv? nat nat^)
                        (field-type-equal? ftype ftype^)
                        (triv-equal? triv triv^))]
                  [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,triv) (downcast-unsigned ,src^ ,safe^ ,nat2^ ,nat1^ ,triv^)
                   (and (eqv? safe safe^)
                        (eqv? nat1 nat1^)
                        (triv-equal? triv triv^))]))))
      (define (triv-vec-equal? v1 v2)
        (let ([n (vector-length v1)])
          (and (fx= (vector-length v2) n)
               (let f ([i 0])
                 (or (fx= i n)
                     (and (triv-equal? (vector-ref v1 i) (vector-ref v2 i))
                          (f (fx+ i 1))))))))
      (define (assert-equal? p1 p2)
        (and (triv-equal? (car p1) (car p2))
             (string=? (cdr p1) (cdr p2)))))
    ; single-hash is adapted from Chez Scheme equal-hash
    ; Copyright 1984-2017 Cisco Systems Inc. and licensed under Apache Version 2.0
    (module (nontriv-single-hash triv-vec-hash assert-hash)
      (define (update hc k)
        (#3%fx+ (#3%fxsll hc 2) hc k))
      (define (boolean-hash b hc)
        (update hc (if b 0 1)))
      (define (nat-hash nat hc)
        (update hc (if (fixnum? nat) nat (modulo nat (most-positive-fixnum)))))
      (define (bits-hash bits hc)
        (nat-hash bits hc))
      (define (mbits-hash mbits hc)
        (if mbits (bits-hash mbits hc) hc))
      (define (field-type-hash ftype hc)
        (nat-hash (nanopass-case (Lflattened Field-Type) ftype
                    [(field-native) 0]
                    [(field-scalar (curve-jubjub)) 1]
                    [(field-base (curve-secp256k1)) 2]
                    [(field-scalar (curve-secp256k1)) 3])
          hc))
      (define (triv-hash triv hc)
        (nanopass-case (Lflattened Triv) triv
          [,var-name (update hc (id-uniq var-name))]
          [,nat (nat-hash nat hc)]
          [else (assert cannot-happen)]))
      (define (commutative-triv-hash triv1 triv2 hc)
        (update hc (#3%fx+ (triv-hash triv1 0) (triv-hash triv2 0))))
      (define (nontriv-single-hash test.single)
        (triv-hash (car test.single)
          (nanopass-case (Lflattened Single) (cdr test.single)
            [(+ ,mbits ,triv1 ,triv2) (mbits-hash mbits (commutative-triv-hash triv1 triv2 119001092))]
            [(- ,mbits ,triv1 ,triv2) (mbits-hash mbits (triv-hash triv1 (triv-hash triv2 410225874)))]
            [(* ,mbits ,triv1 ,triv2) (mbits-hash mbits (commutative-triv-hash triv1 triv2 513566316))]
            [(< ,bits ,triv1 ,triv2) (bits-hash bits (triv-hash triv1 (triv-hash triv2 730407)))]
            [(== ,triv1 ,triv2) (commutative-triv-hash triv1 triv2 45862114)]
            [(select ,triv0 ,triv1 ,triv2)
             (triv-hash triv0
               (triv-hash triv1
                 (triv-hash triv2
                   33905826)))]
            [(bytes-ref ,triv ,nat)
             (nat-hash nat
               (triv-hash triv 29360158))]
            [(bytes->field ,src ,ftype ,len ,triv1 ,triv2)
             (field-type-hash ftype
               (triv-hash triv1
                 (triv-hash triv2
                   (nat-hash len 536285952))))]
            [(vector->bytes ,triv ,triv* ...)
             (fold-left (lambda (hc triv) (triv-hash triv hc))
               447395717
               (cons triv triv*))]
            [(cast-to-field ,ftype ,primitive-type ,triv)
             (field-type-hash ftype (triv-hash triv 597056600))]
            [(cast-from-field ,src ,safe ,nat ,ftype ,triv)
             (field-type-hash ftype (triv-hash triv (nat-hash nat 680186174)))]
            [(downcast-unsigned ,src ,safe ,nat? ,nat ,triv)
             (boolean-hash safe
               (triv-hash triv
                 (let ([h (triv-hash nat 314267636)])
                   (if nat? (triv-hash nat? h) h))))]
            [else (internal-errorf 'nontriv-single-hash "unhandled form ~s" (cdr test.single))])))
      (define (triv-vec-hash v)
        (let ([n (vector-length v)])
          (do ([i 0 (fx+ i 1)]
               [hc 883823588 (triv-hash (vector-ref v i) hc)])
              ((fx= i n) hc))))
      (define (assert-hash p)
        (triv-hash (car p) (update 398346201 (string-hash (cdr p))))))
    (define var->triv)
    (define var->nontriv-single)
    (define nontriv-single->var)
    (define ref-ht)
    (define fbexpr->vars)
    (define dmpot->vars)
    (define bvexpr->vars)
    (define assert-ht)
    (define-syntax with-hashtables
      (syntax-rules ()
        [(_ b1 b2 ...)
         (fluid-let ([var->triv (make-eq-hashtable)]
                     [var->nontriv-single (make-eq-hashtable)]
                     [nontriv-single->var (make-hashtable nontriv-single-hash nontriv-single-equal?)]
                     [ref-ht (make-eq-hashtable)]
                     [fbexpr->vars (make-hashtable triv-vec-hash triv-vec-equal?)]
                     [dmpot->vars (make-hashtable triv-vec-hash triv-vec-equal?)]
                     [bvexpr->vars (make-hashtable triv-vec-hash triv-vec-equal?)]
                     [assert-ht (make-hashtable assert-hash assert-equal?)])
           (let () b1 b2 ...))]))
    (define (ifconstant triv k)
      (nanopass-case (Lflattened Triv) triv
        [,nat (k nat)]
        [else #f]))
     (define (ifconstants triv* k)
       (if (null? triv*)
           (k '())
           (ifconstant (car triv*)
             (lambda (x)
               (ifconstants (cdr triv*)
                 (lambda (x*) (k (cons x x*))))))))
    (module (undefined! undefined?)
      ; the additional undefined marker on var-names would not be necessary if we
      ; replaced assert in Lcircuit and beyond with assert-not so that a 0 value
      ; for the tests suppresses the message rather than a 1 value.
      (define undefined-ht (make-eq-hashtable))
      (define (undefined! var-name) (hashtable-set! undefined-ht var-name #t))
      (define (undefined? triv)
        (nanopass-case (Lflattened Triv) triv
          [,var-name (hashtable-ref undefined-ht var-name #f)]
          ; this case isn't exercised because reduce-to-circuit always produces
          ; a variable reference for the assert form's test
          [else #f])))
    )
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
     (with-hashtables
       (let* ([rstmt* (fold-left
                        (lambda (rstmt* stmt) (FWD-Statement stmt rstmt*))
                        '()
                        stmt*)]
              [triv* (map FWD-Triv triv*)]
              [triv* (map BWD-Triv triv*)]
              [stmt* (fold-left
                       (lambda (stmt* stmt) (BWD-Statement stmt stmt*))
                       '()
                       rstmt*)])
         `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))))]
    [else (internal-errorf 'Circuit-Definition "unexpected ir ~s" ir)])
  (FWD-Statement : Statement (ir rstmt*) -> * (rstmt*)
    ; NB. FWD-Statement eliminates all statements whose conditional-execution
    ; flag (test) is the constant 0 (assignments) or 1 (asserts).  it also eliminates
    ; asserts if the flag is undefined, which can happen only if the statement is in
    ; a part of the circuit that is never enabled.  the undefined check is necessary
    ; for asserts but not assignments because undefined vars are given the value 0.
    [(= ,[FWD-Triv : test] ,var-name ,single)
     (if (eqv? test 0)
         (begin
           (hashtable-set! var->triv var-name 0)
           (undefined! var-name)
           rstmt*)
         (with-output-language (Lflattened Statement)
           (let* ([single (FWD-Single single)]
                  [single (cond
                            [(Lflattened-Triv? single)
                             (hashtable-set! var->triv var-name single)
                             single]
                            [(hashtable-ref nontriv-single->var (cons test single) #f) =>
                             (lambda (var-name^)
                               (hashtable-set! var->triv var-name var-name^)
                               var-name^)]
                            [else
                             (hashtable-set! nontriv-single->var (cons test single) var-name)
                             (hashtable-set! var->nontriv-single var-name single)
                             single])])
             (cons `(= ,test ,var-name ,single) rstmt*))))]
    [(= ,[FWD-Triv : test] (,var-name* ...) ,multiple)
     (if (eqv? test 0)
         (begin
           (for-each (lambda (var-name) (hashtable-set! var->triv var-name 0) (undefined! var-name)) var-name*)
           rstmt*)
         (FWD-Multiple multiple test var-name* rstmt*))]
    [(assert ,src ,[FWD-Triv : test] ,mesg)
     (if (or (eqv? test 1) (undefined? test))
         rstmt*
         (with-output-language (Lflattened Statement)
           (let ([a (hashtable-cell assert-ht (cons test mesg) #f)])
             (if (cdr a)
                 rstmt*
                 (begin
                   (set-cdr! a #t)
                   (cons `(assert ,src ,test ,mesg) rstmt*))))))]
    [else (internal-errorf 'FWD-Statement "unexpected ir ~s" ir)])
  (FWD-Multiple : Multiple (ir test var-name* rstmt*) -> * (rstmt*)
    [(call ,src ,function-name ,[FWD-Triv : triv*] ...)
     (with-output-language (Lflattened Statement)
       (cons `(= ,test (,var-name* ...) (call ,src ,function-name ,triv* ...)) rstmt*))]
    [(emit ,src ,event-version ,event-tag ,len ,[FWD-Triv : triv*] ... ,vm-code)
     (with-output-language (Lflattened Statement)
       (cons `(= ,test (,var-name* ...) (emit ,src ,event-version ,event-tag ,len ,triv* ... ,vm-code)) rstmt*))]
    [(contract-call ,src ,elt-name ((,[FWD-Triv : recv*] ...) ,primitive-type) ,[FWD-Triv : triv*] ...)
     (with-output-language (Lflattened Statement)
       (cons `(= ,test (,var-name* ...) (contract-call ,src ,elt-name ((,recv* ...) ,primitive-type) ,triv* ...)) rstmt*))]
    [(default ,opaque-type)
     (with-output-language (Lflattened Statement)
       (cons `(= ,test (,var-name* ...) (default ,opaque-type)) rstmt*))]
    [(field->bytes ,src ,len ,ftype ,[FWD-Triv : triv])
     (assert (fx= (length var-name*) 2))
     (assert (not (= len 0)))
     (with-output-language (Lflattened Statement)
       (let ([var-name1 (car var-name*)] [var-name2 (cadr var-name*)])
         (or (ifconstant triv
               (lambda (nat)
                 (and (< nat (expt 2 (* 8 len)))
                      ; case currently unreachable if resolve-indices/simplify is doing its job
                      (let-values ([(q r) (div-and-mod nat (expt 2 (* 8 (field-bytes))))])
                        (hashtable-set! var->triv var-name1 q)
                        (hashtable-set! var->triv var-name2 r)
                        rstmt*))))
             (let ([a (hashtable-cell fbexpr->vars (vector test len triv) #f)])
               (cond
                 [(cdr a) =>
                  (lambda (vars)
                    (hashtable-set! var->triv var-name1 (car vars))
                    (hashtable-set! var->triv var-name2 (cdr vars))
                    rstmt*)]
                 [else
                  (set-cdr! a (cons var-name1 var-name2))
                  (cons `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,triv)) rstmt*)])))))]
    [(div-mod-power-of-two ,[FWD-Triv : triv] ,bits)
     (assert (fx= (length var-name*) 2))
     (with-output-language (Lflattened Statement)
       (let ([var-name1 (car var-name*)] [var-name2 (cadr var-name*)])
         (or (ifconstant triv
               (lambda (nat)
                 (let-values ([(q r) (div-and-mod nat (expt 2 bits))])
                   (hashtable-set! var->triv var-name1 q)
                   (hashtable-set! var->triv var-name2 r)
                   rstmt*)))
             (let ([a (hashtable-cell dmpot->vars (vector test triv bits) #f)])
               (cond
                 [(cdr a) =>
                  (lambda (vars)
                    (hashtable-set! var->triv var-name1 (car vars))
                    (hashtable-set! var->triv var-name2 (cdr vars))
                    rstmt*)]
                 [else
                  (set-cdr! a (cons var-name1 var-name2))
                  (cons `(= ,test (,var-name1 ,var-name2) (div-mod-power-of-two ,triv ,bits)) rstmt*)])))))]
    [(bytes->vector ,[FWD-Triv : triv])
     (with-output-language (Lflattened Statement)
       (or (ifconstant triv
             (lambda (bytes)
               (fold-left
                 (lambda (bytes var-name)
                   (let-values ([(q r) (div-and-mod bytes 256)])
                     (hashtable-set! var->triv var-name r)
                     q))
                 bytes
                 var-name*)
               rstmt*))
           (let ([a (hashtable-cell bvexpr->vars (vector (length var-name*) triv) #f)])
             (cond
               [(cdr a) =>
                (lambda (vars)
                  (for-each
                    (lambda (var-name var)
                      (hashtable-set! var->triv var-name var))
                    var-name*
                    vars)
                  rstmt*)]
               [else
                (set-cdr! a var-name*)
                (cons `(= ,test (,var-name* ...) (bytes->vector ,triv)) rstmt*)]))))]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,[FWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[FWD-Triv : triv*] ...)
     (with-output-language (Lflattened Statement)
       (cons `(= ,test
                 (,var-name* ...)
                 (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
             rstmt*))])
  (FWD-Single : Single (ir) -> Single ()
    ; some of the expressions in FWD-Single are unreachable because they duplicate the folding
    ; already done by resolve-indices/simplify
    (definitions
      (define == (lambda (x y) (if (= x y) 1 0)))
      (define lessthan (lambda (x y) (if (< x y) 1 0)))
      (module (add subtract multiply)
        (define m (+ (max-field) 1))
        (define (add mbits)
          (lambda (x y)
            (let ([a (+ x y)])
              (if mbits
                  a ; guaranteed by infer-types to be less than 2^mbits
                  (modulo a m)))))
        (define (subtract mbits)
          (lambda (x y)
            (let ([a (- x y)])
              (if mbits
                  (and (>= a 0) a)
                  (modulo a m)))))
        (define (multiply mbits)
          (lambda (x y)
            (let ([a (* x y)])
              (if mbits
                  a ; guaranteed by infer-types to be less than 2^mbits
                  (modulo a m))))))
      (define (ifsingle triv k)
        (let ([maybe-single (nanopass-case (Lflattened Triv) triv
                              [,var-name (hashtable-ref var->nontriv-single var-name #f)]
                              [else #f])])
          (and maybe-single (k maybe-single))))
      (define (ifnot triv k)
        (ifsingle triv
          (lambda (single)
            (nanopass-case (Lflattened Single) single
              [(select ,triv0 ,nat1 ,nat2)
               (guard (and (eqv? nat1 0) (eqv? nat2 1)))
               (k triv0)]
              [else #f]))))
      (define ($fold2 op triv1 triv2 commutative? rewrite default)
        (let ([triv1 (FWD-Triv triv1)] [triv2 (FWD-Triv triv2)])
          (or (ifconstant triv1
                (lambda (nat1)
                  (ifconstant triv2
                    (lambda (nat2)
                      (op nat1 nat2)))))
              (or (rewrite triv1 triv2)
                  (and commutative? (rewrite triv2 triv1)))
                  #| not presently needed
                  (and nontrivial?
                       (or (ifsingle triv1
                             (lambda (single1)
                               (or (rewrite single1 triv2)
                                   (and commutative? (rewrite triv2 single1)))))
                           (ifsingle triv2
                             (lambda (single2)
                               (or (rewrite triv1 single2)
                                   (and commutative? (rewrite single2 triv1)))))))
                  ; NB: (rewrite maybe-single1 maybe-single2) is not presently supported
                  |#
                  (default triv1 triv2))))
      (define-syntax fold2
        (lambda (x)
          (syntax-case x ()
            [(_ ?op ?mbits ?triv1 ?triv2 commutative? [(_ pat1 pat2) e1 e2 ...] ...)
             #`($fold2 (lambda (x y) (?op x y)) ?triv1 ?triv2 commutative?
                 (lambda (single1 single2)
                   (or (nanopass-case (Lflattened Single) single1
                         [pat1 (nanopass-case (Lflattened Single) single2
                                 [pat2 e1 e2 ...]
                                 [else #f])]
                         [else #f])
                       ...))
                 (lambda (triv1 triv2)
                   (with-output-language (Lflattened Single)
                     #,(if (datum ?mbits)
                           #'`(?op ,?mbits ,triv1 ,triv2)
                           #'`(?op ,triv1 ,triv2)))))]))))
    [,triv (FWD-Triv ir)]
    [(+ ,mbits ,triv1 ,triv2)
     (let ([+ (add mbits)])
       (fold2 + mbits triv1 triv2 #t
         [(_ ,triv ,nat) (and (eqv? nat 0) triv)]))]
    [(- ,mbits ,triv1 ,triv2)
     (let ([- (subtract mbits)])
       (fold2 - mbits triv1 triv2 #f
         [(_ ,triv ,nat) (and (eqv? nat 0) triv)]
         [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 0)]))]
    [(* ,mbits ,triv1 ,triv2)
     (let ([* (multiply mbits)])
       (fold2 * mbits triv1 triv2 #t
         [(_ ,triv ,nat)
          (or (and (eqv? nat 0) 0)
              (and (eqv? nat 1) triv))]))]
    [(< ,bits ,triv1 ,triv2)
     (let ([< lessthan])
       (fold2 < bits triv1 triv2 #f
         ; TODO: special-case
         ;  (< var-name 0)
         ;  (< var-name (+ var-name n>0))
         ;  (< (- var-name n>0) var-name)
         [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 0)]))]
    [(== ,triv1 ,triv2)
     (fold2 == #f triv1 triv2 #t
       ; TODO: special case (= (+ var-name n>0) 0) and (= (+ n>0 var-name) 0)?
       [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 1)])]
    [(select ,[FWD-Triv : triv0] ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
     (let-values ([(triv0 triv1 triv2)
                   (cond
                     [(ifnot triv0 values) => (lambda (triv0) (values triv0 triv2 triv1))]
                     [else (values triv0 triv1 triv2)])])
       (define (maybe-fold triv0 triv1 triv2)
         (or (ifconstant triv0
               (lambda (b) (if (eqv? b 1) triv1 triv2)))
             (and (triv-equal? triv1 triv2) triv1)
             (and (or (eq? triv1 triv0)
                      (ifconstant triv1 (lambda (b) (eq? b 1))))
                  (or (eq? triv2 triv0)
                      (ifconstant triv2 (lambda (b) (eq? b 0))))
                  triv0)))
       (define (f triv val0)
         (define (subst triv) (if (eq? triv triv0) val0 triv))
         (or (and (eq? triv triv0) val0)
             (ifsingle triv
               (lambda (single)
                 (nanopass-case (Lflattened Single) single
                   [(select ,triv0^ ,triv1^ ,triv2^)
                    (maybe-fold (f (subst triv0^) val0) (f (subst triv1^) val0) (f (subst triv2^) val0))]
                   [else #f])))
             triv))
       (let ([triv1 (f triv1 1)] [triv2 (f triv2 0)])
         (or (maybe-fold triv0 triv1 triv2)
             `(select ,triv0 ,triv1 ,triv2))))]
    [(bytes-ref ,[FWD-Triv : triv] ,nat)
     (or (ifconstant triv
           (lambda (nat^)
             (let* ([start (* nat 8)] [end (+ start 8)])
               (bitwise-bit-field nat^ start end))))
         `(bytes-ref ,triv ,nat))]
    [(bytes->field ,src ,ftype ,len ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
     (or (ifconstant triv1
           (lambda (nat1)
             (ifconstant triv2
               (lambda (nat2)
                 (let ([x (+ (bitwise-arithmetic-shift-left nat1 (* 8 (field-bytes))) nat2)])
                   (and (<= x (max-field)) x))))))
         `(bytes->field ,src ,ftype ,len ,triv1 ,triv2))]
    [(vector->bytes ,[FWD-Triv : triv] ,[FWD-Triv : triv*] ...)
     (or (ifconstant triv
           (lambda (u8)
             (ifconstants triv*
               (lambda (u8*)
                 (fold-right
                   (lambda (u8 bytes) (+ (ash bytes 8) u8))
                   0
                   (cons u8 u8*))))))
         (let ([triv* (fold-right
                        (lambda (triv triv*)
                          (if (and (null? triv*)
                                   (nanopass-case (Lflattened Triv) triv
                                     [,nat (eqv? nat 0)]
                                     [else #f]))
                              triv*
                              (cons triv triv*)))
                        '()
                        triv*)])
           `(vector->bytes ,triv ,triv* ...)))]
    [(cast-to-field ,ftype ,primitive-type ,[FWD-Triv : triv])
     ;; TODO(kmillikin): Is there an opportunity to optimize here?
     `(cast-to-field ,ftype ,primitive-type ,triv)]
    [(cast-from-field ,src ,safe ,nat ,ftype ,[FWD-Triv : triv])
     ;; TODO(kmillikin): Is there an opportunity to optimize here?
     `(cast-from-field ,src ,safe ,nat ,ftype ,triv)]
    [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,[FWD-Triv : triv])
     (or (ifconstant triv
           (lambda (nat^)
             (and (<= nat^ nat1) nat^)))
         `(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,triv))]
    [else (internal-errorf 'FWD-Single "unexpected ir ~s" ir)])
  (FWD-Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,type ,[FWD-Triv : triv*] ...) `(,src ,type ,triv* ...)])
  (FWD-Triv : Triv (ir) -> Triv ()
    [,var-name (hashtable-ref var->triv var-name var-name)]
    [else ir])
  (BWD-Statement : Statement (ir stmt*) -> Statement (stmt*)
    (definitions
      (define (pure? single)
        (nanopass-case (Lflattened Single) single
          [,triv #t]
          [(+ ,mbits ,triv1 ,triv2) #t]
          [(- ,mbits ,triv1 ,triv2) #t]
          [(* ,mbits ,triv1 ,triv2) #t]
          [(< ,bits ,triv1 ,triv2) #t]
          [(== ,triv1 ,triv2) #t]
          [(select ,triv0 ,triv1 ,triv2) #t]
          [(bytes-ref ,triv ,nat) #t]
          [(bytes->field ,src ,ftype ,len ,triv1 ,triv2)
           (nanopass-case (Lflattened Field-Type) ftype
             [(field-base (curve-secp256k1)) #t]
             [(field-scalar (curve-secp256k1)) #t]
             [(field-native) (<= len (field-bytes))]
             [else (assert cannot-happen)])]
          [(vector->bytes ,triv ,triv* ...) #t]
          [(cast-to-field ,ftype ,primitive-type ,triv) #t]
          [(cast-from-field ,src ,safe ,nat ,ftype ,triv) #f]
          [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,triv) #f])))
    [(= ,test ,var-name ,single)
     (guard
       (not (hashtable-contains? ref-ht var-name))
       (pure? single))
     ; discard without processing any of the subexpressions to avoid marking any variables referenced
     stmt*]
    [(= ,[BWD-Triv : test] ,var-name ,[BWD-Single : single])
     (cons `(= ,test ,var-name ,single) stmt*)]
    [(= ,[BWD-Triv : test] (,var-name* ...) (call ,src ,function-name ,[BWD-Triv : triv*] ...))
     (cons `(= ,test (,var-name* ...) (call ,src ,function-name ,triv* ...)) stmt*)]
    [(= ,[BWD-Triv : test] (,var-name* ...) (emit ,src ,event-version ,event-tag ,len ,[BWD-Triv : triv*] ... ,vm-code))
     (cons `(= ,test (,var-name* ...) (emit ,src ,event-version ,event-tag ,len ,triv* ... ,vm-code)) stmt*)]
    [(= ,[BWD-Triv : test] (,var-name* ...) (contract-call ,src ,elt-name ((,[BWD-Triv : recv*] ...) ,primitive-type) ,[BWD-Triv : triv*] ...))
     (cons `(= ,test (,var-name* ...) (contract-call ,src ,elt-name ((,recv* ...) ,primitive-type) ,triv* ...)) stmt*)]
    [(= ,test (,var-name* ...) (default ,opaque-type))
     (guard (andmap (lambda (var-name) (not (hashtable-contains? ref-ht var-name))) var-name*))
     stmt*]
    [(= ,[BWD-Triv : test] (,var-name* ...) (default ,opaque-type))
     (cons `(= ,test (,var-name* ...) (default ,opaque-type)) stmt*)]
    [(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,triv))
     (guard
       (>= len (field-bytes))
       (not (hashtable-contains? ref-ht var-name1))
       (not (hashtable-contains? ref-ht var-name2)))
     stmt*]
    [(= ,[BWD-Triv : test] (,var-name1 ,var-name2)
       (field->bytes ,src ,len ,ftype ,[BWD-Triv : triv]))
     (cons `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,triv)) stmt*)]
    [(= ,test (,var-name1 ,var-name2) (div-mod-power-of-two ,triv ,bits))
     (guard
       (not (hashtable-contains? ref-ht var-name1))
       (not (hashtable-contains? ref-ht var-name2)))
     stmt*]
    [(= ,[BWD-Triv : test] (,var-name1 ,var-name2) (div-mod-power-of-two ,[BWD-Triv : triv] ,bits))
     (cons `(= ,test (,var-name1 ,var-name2) (div-mod-power-of-two ,triv ,bits)) stmt*)]
    [(= ,test (,var-name* ...) (bytes->vector ,triv))
     (guard (not (ormap (lambda (var-name) (hashtable-contains? ref-ht var-name)) var-name*)))
     stmt*]
    [(= ,[BWD-Triv : test] (,var-name* ...) (bytes->vector ,[BWD-Triv : triv]))
     (cons `(= ,test (,var-name* ...) (bytes->vector ,triv)) stmt*)]
    [(= ,[BWD-Triv : test]
        (,var-name* ...)
        (public-ledger ,src ,ledger-field-name ,sugar? (,[BWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[BWD-Triv : triv*] ...))
     (cons `(= ,test
               (,var-name* ...)
               (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
           stmt*)]
    [(assert ,src ,[BWD-Triv : test] ,mesg)
     (cons `(assert ,src ,test ,mesg) stmt*)]
    [else (internal-errorf 'BWD-Statement "unexpected ir ~s" ir)])
  (BWD-Single : Single (ir) -> Single ()
    [,triv (BWD-Triv ir)] ; not exercised since FWD-Single propagates Triv Rhs
    [(+ ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(+ ,mbits ,triv1 ,triv2)]
    [(- ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(- ,mbits ,triv1 ,triv2)]
    [(* ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(* ,mbits ,triv1 ,triv2)]
    [(< ,bits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(< ,bits ,triv1 ,triv2)]
    [(== ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(== ,triv1 ,triv2)]
    [(select ,[BWD-Triv : triv0] ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
     `(select ,triv0 ,triv1 ,triv2)]
    [(bytes-ref ,[BWD-Triv : triv] ,nat) `(bytes-ref ,triv ,nat)]
    [(bytes->field ,src ,ftype ,len ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
     `(bytes->field ,src ,ftype ,len ,triv1 ,triv2)]
    [(vector->bytes ,[BWD-Triv : triv] ,[BWD-Triv : triv*] ...)
     `(vector->bytes ,triv ,triv* ...)]
    [(cast-to-field ,ftype ,primitive-type ,[BWD-Triv : triv])
     `(cast-to-field ,ftype ,primitive-type ,triv)]
    [(cast-from-field ,src ,safe ,nat ,ftype ,[BWD-Triv : triv])
     `(cast-from-field ,src ,safe ,nat ,ftype ,triv)]
    [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,[BWD-Triv : triv])
     `(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,triv)]
    [else (internal-errorf 'BWD-Single "unexpected ir ~s" ir)])
  (BWD-Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,type ,[BWD-Triv : triv*] ...) `(,src ,type ,triv* ...)])
  (BWD-Triv : Triv (ir) -> Triv ()
    [,var-name
     (hashtable-set! ref-ht var-name #f)
     var-name]
    [else ir])
  )
