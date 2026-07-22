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

(define-pass resolve-indices/simplify : Lnosafecast (ir) -> Lnovectorref ()
  (definitions
    (module (no-var-name set-binding! remove-binding! with-binding has-binding? get-binding)
      ; no-var-name is used for CTVs created as the result of evaluating
      ; some expression.  a CTV without a var-name in-scope is recreated with a
      ; var-name x when x is bound to the corresponding expression's value.
      (define no-var-name (cons 'no 'var-name))

      ; var-ht maps var-names (identifiers) to compile-time values (CTVs)
      (define var-ht (make-eq-hashtable))

      (define (set-binding! var-name ctv) (eq-hashtable-set! var-ht var-name ctv))
      (define (remove-binding! var-name) (eq-hashtable-delete! var-ht var-name))
      (define (with-binding var-name ctv k)
        (let ([a (eq-hashtable-cell var-ht var-name #f)])
          (let ([ctv? (cdr a)])
            (set-cdr! a ctv)
            (let-values ([v* (k)])
              (if ctv?
                  (set-cdr! a ctv?)
                  (eq-hashtable-delete! var-ht var-name))
              (apply values v*)))))

      ; has-binding? and get-binding must return #f for no-var-name as well as for
      ; var-names that have no recorded bindings.
      (define (has-binding? var-name) (eq-hashtable-contains? var-ht var-name))
      (define (get-binding var-name) (eq-hashtable-ref var-ht var-name #f))
      )
    (define-datatype (CTV var-name)
      (CTV-const datum)
      (CTV-tuple ctv*)
      (CTV-struct elt-name* ctv*)
      (CTV-unknown)
      )
    (define (same-var-name? ctv1 ctv2)
      ; same-var-name? is used by some operator handlers to recognize one case
      ; where two expressions will evaluate to the same value, namely when both
      ; will evaluate to the value of the same variable.
      (let ([var-name (CTV-var-name ctv1)])
        (and (eq? var-name (CTV-var-name ctv2))
             (has-binding? var-name))))
    (define (handle-let src var-name type expr expr-ctv do-body)
      (set-binding! var-name
        (if (has-binding? (CTV-var-name expr-ctv))
            expr-ctv
            (CTV-case expr-ctv
              [(CTV-const datum) (CTV-const var-name datum)]
              [(CTV-tuple ctv*) (CTV-tuple var-name ctv*)]
              [(CTV-struct elt-name* ctv*) (CTV-struct var-name elt-name* ctv*)]
              [(CTV-unknown) (CTV-unknown var-name)])))
      (let-values ([(body body-ctv) (do-body)])
        (remove-binding! var-name)
        (values
          (with-output-language (Lnovectorref Expression)
            `(let* ,src (((,var-name ,type) ,expr)) ,body))
          body-ctv)))
    (define (new-let src type expr expr-ctv do-body)
      (let ([var-name (make-temp-id src 't)])
        (handle-let src var-name type expr expr-ctv
          (lambda () (do-body var-name)))))
    (define (if-has-in-scope-var-name ctv k)
      (let ([var-name (CTV-var-name ctv)])
        (and (has-binding? var-name)
             (k var-name))))
    (define (ifconstant ctv k)
      (CTV-case ctv
        [(CTV-const datum) (k datum)]
        [else #f]))
    (define (iszero? x) (eqv? x 0)) ; like zero? but more efficient for exact values
    (define (isone? x) (eqv? x 1))
    (define (tvector->length type)
      (nanopass-case (Lnovectorref Type) type
        [(tvector ,src ,len ,type) len]
        [else (assert cannot-happen)]))
    (define (tbytes->length type)
      (nanopass-case (Lnovectorref Type) type
        [(tbytes ,src ,len) len]
        [else (assert cannot-happen)]))
    (define-syntax mvor 
      (syntax-rules ()
        [(_ e) e]
        [(_ e1 e2 e3 ...)
         (call-with-values
           (lambda () e1)
           (lambda (x . r) (if x (apply values x r) (mvor e2 e3 ...))))]))
    (define (handle-var-ref src var-name)
      (with-output-language (Lnovectorref Expression)
        (let ([ctv (assertf (get-binding var-name) "~s is not bound" var-name)])
            (mvor (ifconstant ctv
                    (lambda (datum)
                      (and
                        (or (not (bytevector? datum))
                            (<= (bytevector-length datum) (field-bytes))) ; avoid duplicating bytes objects that don't fit in a field
                        (values 
                          `(quote ,src ,datum)
                          ctv))))
                  (if-has-in-scope-var-name ctv
                    (lambda (var-name^)
                      ; second chance: original variable might have been rebound to true or false
                      ; in the consequent or alternative of an if expression; look it up to see
                      (let ([ctv (assert (get-binding var-name^))])
                        (values
                          (or (ifconstant ctv
                                (lambda (datum)
                                  (and
                                    (or (not (bytevector? datum))
                                        (<= (bytevector-length datum) (field-bytes))) ; avoid duplicating bytes objects that don't fit in a field
                                    `(quote ,src ,datum))))
                              `(var-ref ,src ,var-name^))
                          ctv))))
                  ; should not be reached: the ctv of any var being referenced should at least be associated
                  ; with itself and be in scope
                  (values `(var-ref ,src ,var-name) ctv)))))
    (define (handle-tuple-ref src expr ctv kindex)
      (with-output-language (Lnovectorref Expression)
        (CTV-case ctv
          [(CTV-tuple ctv*)
           (let ([ctv (list-ref ctv* kindex)])
             (values
               (or (ifconstant ctv
                     (lambda (datum)
                       `(seq ,src ,expr (quote ,src ,datum))))
                   (if-has-in-scope-var-name ctv
                     (lambda (var-name)
                       `(seq ,src ,expr (var-ref ,src ,var-name))))
                   `(tuple-ref ,src ,expr ,kindex))
               ctv))]
          [else (values
                  `(tuple-ref ,src ,expr ,kindex)
                  (CTV-unknown no-var-name))])))
    (define (handle-bytes-ref src expr ctv kindex)
      (with-output-language (Lnovectorref Expression)
        (CTV-case ctv
          [(CTV-const datum)
           (assert (and (bytevector? datum) (< kindex (bytevector-length datum))))
           (let* ([b (bytevector-u8-ref datum kindex)]
                  [ctv (CTV-const no-var-name b)])
             (values
               `(quote ,src ,b)
               ctv))]
          [else (values
                  `(bytes-ref ,src ,expr ,kindex)
                  (CTV-unknown no-var-name))])))
    (define (handle-elt-ref src expr ctv elt-name)
      (with-output-language (Lnovectorref Expression)
        (CTV-case ctv
          [(CTV-struct elt-name* ctv*)
           (let ([ctv (let f ([elt-name* elt-name*] [ctv* ctv*])
                        (assert (not (null? elt-name*)))
                        (if (eq? (car elt-name*) elt-name)
                            (car ctv*)
                            (f (cdr elt-name*) (cdr ctv*))))])
             (values
               (or (ifconstant ctv
                     (lambda (datum)
                       `(seq ,src ,expr (quote ,src ,datum))))
                   (if-has-in-scope-var-name ctv
                     (lambda (var-name)
                       `(seq ,src ,expr (var-ref ,src ,var-name))))
                   `(elt-ref ,src ,expr ,elt-name))
               ctv))]
          [else (values
                  `(elt-ref ,src ,expr ,elt-name)
                  (CTV-unknown no-var-name))])))
    (define (handle-binop src proc expr1 expr2 special-cases build-expr)
      ; handle-binop processes expr1 and expr2 to get residual expr1 and expr2 and CTVs ctv1 and ctv2.
      ; If the ctvs are both CTV-const, it applies proc to the constants to effect constant folding.
      ; It assumes proc produced a valid value unless proc raises an exception with condition 'fail.
      ; If the ctvs are not both CTV-const or if proc raises an exception with condition 'fail,
      ; handle-binop invokes special-cases on ctv1 and ctv2.  special-cases should return either #f
      ; or a ctv representing the ctv of the output expression.  If special-cases returns a ctv that
      ; is a CTV-const or a CTV with an in-scope variable, handle-binop returns a quote or
      ; var-ref expression and the ctv.  Otherwise handle-binop punts to build-expr to create a
      ; residual form of the original operation and returns it along with a CTV-unknown.
      (with-output-language (Lnovectorref Expression)
        (let-values ([(expr1 ctv1) (Expression expr1)]
                     [(expr2 ctv2) (Expression expr2)])
          (mvor (ifconstant ctv1
                  (lambda (datum1)
                    (ifconstant ctv2
                      (lambda (datum2)
                        (call/cc
                          (lambda (k)
                            (let ([datum (with-exception-handler
                                           ; (raise-continuable) is unreachable if the compiler is working correctly
                                           (lambda (c) (if (eq? c 'fail) (k #f) (raise-continuable c)))
                                           (lambda () (proc datum1 datum2)))])
                              (values
                                `(seq ,src ,expr1 ,expr2 (quote ,src ,datum))
                                (CTV-const no-var-name datum)))))))))
                (let ([ctv (special-cases ctv1 ctv2)])
                  (and ctv
                       (mvor (ifconstant ctv
                               (lambda (datum)
                                 (values
                                   `(seq ,src ,expr1 ,expr2 (quote ,src ,datum))
                                   ctv)))
                             (if-has-in-scope-var-name ctv
                               (lambda (var-name)
                                 (values
                                   `(seq ,src ,expr1 ,expr2 (var-ref ,src ,var-name))
                                   ctv))))))
                (values
                  (build-expr expr1 expr2)
                  (CTV-unknown no-var-name))))))
    (define (do-circuit-body var-name* expr)
      (for-each
        (lambda (var-name) (set-binding! var-name (CTV-unknown var-name)))
        var-name*)
      (let-values ([(expr ctv) (Expression expr)])
        (for-each remove-binding! var-name*)
        expr))
    )
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
    [(public-ledger-declaration ,[pl-array] ,lconstructor)
     (nanopass-case (Lnosafecast Ledger-Constructor) lconstructor
       [(constructor ,src ((,var-name* ,type*) ...) ,expr)
        (do-circuit-body var-name* expr)])
     `(public-ledger-declaration ,pl-array)])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
     (define (arg->var-name arg)
       (nanopass-case (Lnovectorref Argument) arg
         [(,var-name ,type) var-name]))
     (let ([expr (do-circuit-body (map arg->var-name arg*) expr)])
       `(circuit ,src ,function-name (,arg* ...) ,type ,expr))])
  (Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,[type] ,[expr ctv]) `(,src ,type ,expr)])
  (Expression : Expression (ir) -> Expression (ctv)
    [(quote ,src ,datum)
     (values
       `(quote ,src ,datum)
       (CTV-const no-var-name datum))]
    [(var-ref ,src ,var-name) (handle-var-ref src var-name)]
    [(let* ,src ((,[local*] ,expr*) ...) ,expr)
     (let loop ([local* local*] [expr* expr*])
       (if (null? local*)
           (Expression expr)
           (nanopass-case (Lnovectorref Argument) (car local*)
             [(,var-name ,type)
              (let-values ([(expr expr-ctv) (Expression (car expr*))])
                (handle-let src var-name type expr expr-ctv
                  (lambda () (loop (cdr local*) (cdr expr*)))))])))]
    [(default ,src ,[type])
     (define (ifdefault-value type k)
       (nanopass-case (Lnovectorref Type) type
         [(tboolean ,src) (k #f)]
         [(tfield ,src ,ftype) (k 0)]
         [(tunsigned ,src ,nat) (k 0)]
         [(tbytes ,src ,len) (and (<= len (field-bytes)) (k (make-bytevector len 0)))]
         [else #f]))
     (define (default-ctv type)
       (call/cc
         (lambda (k)
           (let f ([type type])
             (or (ifdefault-value type
                   (lambda (datum)
                     (CTV-const no-var-name datum)))
                 (nanopass-case (Lnovectorref Type) type
                   [(ttuple ,src ,type* ...) (CTV-tuple no-var-name (map f type*))]
                   [(tvector ,src ,len ,type) (guard (<= len 10)) (CTV-tuple no-var-name (make-list len (f type)))]
                   [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) (CTV-struct no-var-name elt-name* (map f type*))]
                   [else (k (CTV-unknown no-var-name))]))))))
     (mvor (ifdefault-value type
             (lambda (datum)
               (values
                 `(quote ,src ,datum)
                 (CTV-const no-var-name datum))))
           (values
             `(default ,src ,type)
             (default-ctv type)))]
    [(if ,src ,[expr0 ctv0] ,expr1 ,expr2)
     (define (intersect ctv1 ctv2)
       (if (eq? ctv1 ctv2)
           ctv1
           (let ([var-name (let ([var-name (CTV-var-name ctv1)])
                             (if (eq? var-name (CTV-var-name ctv2))
                                 var-name
                                 no-var-name))])
             (or (CTV-case ctv1
                   [(CTV-const datum1)
                    (CTV-case ctv2
                      [(CTV-const datum2)
                       (and (equal? datum1 datum2)
                            (CTV-const var-name datum1))]
                      [else #f])]
                   [(CTV-tuple ctv1*)
                    (CTV-case ctv2
                      [(CTV-tuple ctv2*)
                       (CTV-tuple var-name (map intersect ctv1* ctv2*))]
                      [else #f])]
                   [(CTV-struct elt-name1* ctv1*)
                    (CTV-case ctv2
                     [(CTV-struct elt-name2* ctv2*)
                      (assert (andmap eq? elt-name1* elt-name2*))
                      (CTV-struct var-name elt-name1* (map intersect ctv1* ctv2*))]
                     [else #f])]
                  [(CTV-unknown) #f])
                 (CTV-unknown var-name)))))
     ; if could process just one of expr1 or expr2 when ctv0 is a CTV-const, but instead
     ; always process both to catch vector-ref/vector-slice index errors
     (let-values ([(expr1 ctv1 expr2 ctv2)
                   (let ([var-name (CTV-var-name ctv0)])
                     (if (eq? var-name no-var-name)
                         (let-values ([(expr1 ctv1) (Expression expr1)]
                                      [(expr2 ctv2) (Expression expr2)])
                           (values expr1 ctv1 expr2 ctv2))
                         (let-values ([(expr1 ctv1) (with-binding var-name (CTV-const no-var-name #t) (lambda () (Expression expr1)))]
                                      [(expr2 ctv2) (with-binding var-name (CTV-const no-var-name #f) (lambda () (Expression expr2)))])
                           (values expr1 ctv1 expr2 ctv2))))])
       (mvor (ifconstant ctv0
               (lambda (datum)
                 (if datum
                     (values `(seq ,src ,expr0 ,expr1) ctv1)
                     (values `(seq ,src ,expr0 ,expr2) ctv2))))
             (values
               `(if ,src ,expr0 ,expr1 ,expr2)
               (intersect ctv1 ctv2))))]
    [(tuple ,src ,[tuple-arg* maybe-ctv**] ...)
     (values
       `(tuple ,src ,tuple-arg* ...)
       (if (andmap values maybe-ctv**)
           (CTV-tuple no-var-name (apply append maybe-ctv**))
           ; this case shouldn't be reachable for tuples
           (CTV-unknown no-var-name)))]
    [(vector ,src ,[tuple-arg* maybe-ctv**] ...)
     (values
       `(vector ,src ,tuple-arg* ...)
       (if (andmap values maybe-ctv**)
           (CTV-tuple no-var-name (apply append maybe-ctv**))
           (CTV-unknown no-var-name)))]
    [(tuple-ref ,src ,[expr ctv] ,kindex)
     (handle-tuple-ref src expr ctv kindex)]
    [(bytes-ref ,src ,[type] ,[expr expr-ctv] ,[index index-ctv])
     (mvor (ifconstant index-ctv
             (lambda (kindex)
               (let ([len (tbytes->length type)])
                 (unless (< kindex len)
                   (source-errorf src "invalid Bytes index ~d for a Bytes value of length ~d" kindex len)))
               (new-let src type expr expr-ctv
                 (lambda (var-name)
                   (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                     (let-values ([(expr ctv) (handle-bytes-ref src var-ref var-ctv kindex)])
                       (values
                         `(seq ,src ,index ,expr)
                         ctv)))))))
           (source-errorf src "Bytes index did not reduce to a constant nonnegative value at compile time"))]
    [(vector-ref ,src ,[type] ,[expr expr-ctv] ,[index index-ctv])
     (mvor (ifconstant index-ctv
             (lambda (kindex)
               (let ([len (tvector->length type)])
                 (unless (< kindex len)
                   (source-errorf src "invalid vector index ~d for vector of length ~d" kindex len)))
               (new-let src type expr expr-ctv
                 (lambda (var-name)
                   (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                     (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)])
                       (values
                         `(seq ,src ,index ,expr)
                         ctv)))))))
           (source-errorf src "vector index did not reduce to a constant nonnegative value at compile time"))]
    [(tuple-slice ,src ,[type] ,[expr expr-ctv] ,kindex ,len)
     (new-let src type expr expr-ctv
       (lambda (var-name)
         (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
           (let-values ([(expr* ctv*)
                         (let f ([len len] [kindex kindex])
                           (if (fx= len 0)
                               (values '() '())
                               (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)]
                                            [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                 (values (cons expr expr*) (cons ctv ctv*)))))])
             (values
               `(tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...)
               (CTV-tuple no-var-name ctv*))))))]
    [(bytes-slice ,src ,[type] ,[expr expr-ctv] ,[index index-ctv] ,len)
     (mvor (ifconstant index-ctv
             (lambda (kindex)
               (let ([input-len (tbytes->length type)] [end (+ kindex len)])
                 (unless (<= end input-len)
                   (source-errorf src "invalid slice index ~d and length ~d for a Bytes value of length ~d" kindex len input-len)))
               (mvor (ifconstant expr-ctv
                       (lambda (bv)
                         (assert (and (bytevector? bv) (<= (+ kindex len) (bytevector-length bv))))
                         (let ([new-bv (make-bytevector len)])
                           (bytevector-copy! bv kindex new-bv 0 len)
                           (values
                             `(seq ,src ,expr ,index (quote ,src ,new-bv))
                             (CTV-const no-var-name new-bv)))))
                     (new-let src type expr expr-ctv
                       (lambda (var-name)
                         (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                           (let-values ([(expr* ctv*)
                                         (let f ([len len] [kindex kindex])
                                           (if (fx= len 0)
                                               (values '() '())
                                               (let-values ([(expr ctv) (handle-bytes-ref src var-ref var-ctv kindex)]
                                                            [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                                 (values (cons expr expr*) (cons ctv ctv*)))))])
                             (values
                               `(seq ,src ,index (vector->bytes ,src ,len (tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...)))
                               (CTV-unknown no-var-name)))))))))
           (source-errorf src "slice index did not reduce to a constant nonnegative value at compile time"))]
    [(vector-slice ,src ,[type] ,[expr expr-ctv] ,[index index-ctv] ,len)
     (mvor (ifconstant index-ctv
             (lambda (kindex)
               (let ([input-len (tvector->length type)] [end (+ kindex len)])
                 (unless (<= end input-len)
                   (source-errorf src "invalid slice index ~d and length ~d for vector of length ~d" kindex len input-len)))
               (new-let src type expr expr-ctv
                 (lambda (var-name)
                   (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                     (let-values ([(expr* ctv*)
                                   (let f ([len len] [kindex kindex])
                                     (if (fx= len 0)
                                         (values '() '())
                                         (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)]
                                                      [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                           (values (cons expr expr*) (cons ctv ctv*)))))])
                       (values
                         `(seq ,src ,index (tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...))
                         (CTV-tuple no-var-name ctv*))))))))
           (source-errorf src "slice index did not reduce to a constant nonnegative value at compile time"))]
    [(new ,src ,[type] ,[expr* ctv*] ...)
     (values
       `(new ,src ,type ,expr* ...)
       (nanopass-case (Lnovectorref Type) type
         [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
          (CTV-struct no-var-name elt-name* ctv*)]
         [else (assert cannot-happen)]))]
    [(elt-ref ,src ,[expr ctv] ,elt-name)
     (handle-elt-ref src expr ctv elt-name)]
    [(emit ,src ,event-version ,event-tag ,len ,[expr ctv] ,vm-code)
     (values
       `(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code)
       (CTV-unknown no-var-name))]
    [(+ ,src ,mbits ,expr1 ,expr2)
     (define (add x y)
       (let ([a (+ x y)])
         (if mbits
             a ; guaranteed by infer-types not to overflow
             (modulo a (+ (max-field) 1)))))
     (handle-binop src add expr1 expr2
       (lambda (ctv1 ctv2)
         (cond
           [(ifconstant ctv1 iszero?) ctv2]
           [(ifconstant ctv2 iszero?) ctv1]
           [else #f]))
       (lambda (expr1 expr2)
         `(+ ,src ,mbits ,expr1 ,expr2)))]
    [(- ,src ,mbits ,expr1 ,expr2)
     (define (subtract x y)
       (let ([a (- x y)])
         (if mbits
             (if (< a 0) (raise 'fail) a)
             (mod a (+ (max-field) 1)))))
     (handle-binop src subtract expr1 expr2
       (lambda (ctv1 ctv2)
         (cond
           [(ifconstant ctv2 iszero?) ctv1]
           [(same-var-name? ctv1 ctv2) (CTV-const no-var-name 0)]
           [else #f]))
       (lambda (expr1 expr2)
         `(- ,src ,mbits ,expr1 ,expr2)))]
    [(* ,src ,mbits ,expr1 ,expr2)
     (define (multiply x y)
       (let ([a (* x y)])
         (if mbits
             a ; guaranteed by infer-types not to overflow
             (modulo a (+ (max-field) 1)))))
     (handle-binop src multiply expr1 expr2
       (lambda (ctv1 ctv2)
         (cond
           [(ifconstant ctv1 iszero?) (CTV-const no-var-name 0)]
           [(ifconstant ctv2 iszero?) (CTV-const no-var-name 0)]
           [(ifconstant ctv1 isone?) ctv2]
           [(ifconstant ctv2 isone?) ctv1]
           [else #f]))
       (lambda (expr1 expr2) `(* ,src ,mbits ,expr1 ,expr2)))]
    [(< ,src ,bits ,expr1 ,expr2)
     (handle-binop src < expr1 expr2
       (lambda (ctv1 ctv2)
         (cond
           [(same-var-name? ctv1 ctv2) (CTV-const no-var-name #f)]
           [else #f]))
         (lambda (expr1 expr2) `(< ,src ,bits ,expr1 ,expr2)))]
    [(== ,src ,[type] ,expr1 ,expr2)
     (handle-binop src equal? expr1 expr2
       (lambda (ctv1 ctv2)
         (cond
           [(same-var-name? ctv1 ctv2) (CTV-const no-var-name #t)]
           [else #f]))
       (lambda (expr1 expr2) `(== ,src ,type ,expr1 ,expr2)))]
    [(seq ,src ,[expr* ctv*] ... ,[expr ctv])
     (values
       `(seq ,src ,expr* ... ,expr)
       ctv)]
    [(assert ,src ,[expr ctv] ,mesg)
     (values
       `(assert ,src ,expr ,mesg)
       (CTV-tuple no-var-name '()))]
    [(field->bytes ,src ,len ,[ftype] ,[expr ctv])
     (assert (not (= len 0)))
     (cond
       [(ifconstant ctv
          (lambda (datum)
            (and (or (> len (field-bytes)) ; quick check when nat is large
                     (> (expt 2 len) datum))
                 (let ([bv (make-bytevector len)])
                   (bytevector-uint-set! bv 0 datum (endianness little) len)
                   bv)))) =>
        (lambda (bv) (values `(quote ,src ,bv) (CTV-const no-var-name bv)))]
       [else (values
               `(field->bytes ,src ,len ,ftype ,expr)
               (CTV-unknown no-var-name))])]
    [(bytes->field ,src ,[ftype] ,len ,[expr ctv])
     (cond
       [(ifconstant ctv
          (lambda (datum)
            (let ([n (bytevector-length datum)])
              (if (fx= n 0)
                  0
                  (let ([x (bytevector-uint-ref datum 0 (endianness little) n)])
                    (and (nanopass-case (Lnovectorref Field-Type) ftype
                           [(field-native) (<= x (max-field))]
                           [else #f])
                         x)))))) =>
        (lambda (nat) (values `(quote ,src ,nat) (CTV-const no-var-name nat)))]
       [else (values
               `(bytes->field ,src ,ftype ,len ,expr)
               (CTV-unknown no-var-name))])]
    [(vector->bytes ,src ,len ,[expr ctv])
     (cond
       [(CTV-case ctv
          [(CTV-tuple ctv*)
           (let ([maybe-nat* (map (lambda (ctv) (ifconstant ctv values)) ctv*)])
             (and (andmap values maybe-nat*) (apply bytevector maybe-nat*)))]
          [else #f]) =>
        (lambda (bv)
          (values
            ; NB: if we add a (bytes expr ...) like (tuple expr ...) use it here and allow refs to visible vars as well as consts
            `(quote ,src ,bv)
            (CTV-const no-var-name bv)))]
       [else (values
               `(vector->bytes ,src ,len ,expr)
               (CTV-unknown no-var-name))])]
    [(bytes->vector ,src ,len ,[expr ctv])
     (cond
       [(ifconstant ctv bytevector->u8-list) =>
        (lambda (u8*)
          (values
            `(tuple ,src ,(map (lambda (u8) `(single ,src (quote ,src ,u8))) u8*) ...)
            (CTV-tuple no-var-name (map (lambda (u8) (CTV-const no-var-name u8)) u8*))))]
       [else (values
               `(bytes->vector ,src ,len ,expr)
               (CTV-unknown no-var-name))])]
    [(cast-to-field ,src ,[ftype] ,[type] ,[expr ctv])
     ;; TODO(kmillikin): optimize this.
     (values
       `(cast-to-field ,src ,ftype ,type ,expr)
       (CTV-unknown no-var-name))]
    [(cast-from-field ,src ,nat (field-native) ,[expr ctv])
     (CTV-case ctv
       [(CTV-const datum)
        (values `(seq ,src ,expr (quote ,src ,datum))
          ctv)]
       [else (values `(cast-from-field ,src ,nat (field-native) ,expr)
               (CTV-unknown no-var-name))])]
    [(cast-from-field ,src ,nat (field-scalar (curve-jubjub)) ,[expr ctv])
     (cond
       [(ifconstant ctv (lambda (datum) (and (<= datum (max-jubjub-scalar)) datum))) =>
        (lambda (datum)
          (values `(seq ,src ,expr (quote ,src ,datum))
            ctv))]
       [else (values `(cast-from-field ,src ,nat (field-scalar (curve-jubjub)) ,expr)
               (CTV-unknown no-var-name))])]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,[expr ctv])
     (cond
       [(ifconstant ctv (lambda (datum) (and (<= datum nat1) datum))) =>
        (lambda (datum)
          (values
            `(seq ,src ,expr (quote ,src ,datum))
            ctv))]
       [else (values
               `(downcast-unsigned ,src ,nat2 ,nat1 ,expr)
               (CTV-unknown no-var-name))])]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt] ...) ,src^ ,[adt-op] ,[expr* ctv*] ...)
     (values
       `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt ...) ,src^ ,adt-op ,expr* ...)
       (CTV-unknown no-var-name))]
    [(call ,src ,function-name ,[expr* ctv*] ...)
     (values
       `(call ,src ,function-name ,expr* ...)
       (CTV-unknown no-var-name))]
    [(contract-call ,src ,elt-name (,[expr ctv] ,[type]) ,[expr* ctv*] ...)
     (values
       `(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (CTV-unknown no-var-name))]
    [else (internal-errorf 'Expression "unexpected expr ~s" (unparse-Lnosafecast ir))])
  (Tuple-Argument : Tuple-Argument (ir) -> Tuple-Argument (maybe-ctv*)
    [(single ,src ,[expr ctv]) (values `(single ,src ,expr) (list ctv))]
    [(spread ,src ,nat ,[expr ctv])
     (values
       `(spread ,src ,nat ,expr)
       (CTV-case ctv
         [(CTV-tuple ctv*) ctv*]
         [else #f]))]))
