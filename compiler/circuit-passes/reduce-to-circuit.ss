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

(define-pass reduce-to-circuit : Lnovectorref (ir) -> Lcircuit ()
  (definitions
    (define fun-ht (make-eq-hashtable))
    ;; Unconditional A-normalization can separate compiler-generated
    ;; vector->bytes(vector(...)) shapes into several let-bound definitions.
    ;; Retain just enough exact provenance to recover those shapes without
    ;; changing evaluation: recovered leaves must already be trivial values.
    (define aggregate-provenance-ht (make-eq-hashtable))
    (define bytes-vector-provenance-ht (make-eq-hashtable))
    (define default-src)
    (define (unconditional-test? test)
      (nanopass-case (Lcircuit Triv) test
        [(quote ,datum) (eqv? datum #t)]
        [else #f]))
    (define (arg->name arg)
      (nanopass-case (Lnovectorref Argument) arg
        [(,var-name ,type) var-name]))
    (define (trivial-expression? expr)
      (nanopass-case (Lnovectorref Expression) expr
        [(var-ref ,src ,var-name) #t]
        [(quote ,src ,datum) #t]
        [else #f]))
    (define (expression->var-name expr)
      (nanopass-case (Lnovectorref Expression) expr
        [(var-ref ,src ,var-name) var-name]
        [else #f]))
    (define (record-serialize-provenance! local* expr* test)
      (when (unconditional-test? test)
        (for-each
          (lambda (local expr)
            (let ([var-name (arg->name local)])
              (nanopass-case (Lnovectorref Expression) expr
                [(vector ,src ,tuple-arg* ...)
                 (hashtable-set! aggregate-provenance-ht var-name tuple-arg*)]
                [(tuple ,src ,tuple-arg* ...)
                 (hashtable-set! aggregate-provenance-ht var-name tuple-arg*)]
                [(bytes->vector ,src ,len ,expr^)
                 (when (trivial-expression? expr^)
                   (hashtable-set! bytes-vector-provenance-ht var-name
                                   (cons len expr^)))]
                [else (void)])))
          local*
          expr*)))
    (define (Triv expr test k)
      (Rhs expr test
        (lambda (rhs)
          (if (Lcircuit-Triv? rhs)
              (k rhs)
              (let ([t (make-temp-id default-src 't)])
                (with-output-language (Lcircuit Statement)
                  (cons
                    `(= ,test ,t ,rhs)
                    (k t))))))))
    (define (Triv* expr* test k)
      (let f ([expr* expr*] [rtriv* '()])
        (if (null? expr*)
            (k (reverse rtriv*))
            (Triv (car expr*) test
              (lambda (triv)
                (f (cdr expr*) (cons triv rtriv*)))))))
    (define (Tuple-Argument tuple-arg test k)
      (with-output-language (Lcircuit Tuple-Argument)
        (nanopass-case (Lnovectorref Tuple-Argument) tuple-arg
          [(single ,src ,expr)
           (Triv expr test
             (lambda (triv)
               (k `(single ,src ,triv))))]
          [(spread ,src ,nat ,expr)
           (Triv expr test
             (lambda (triv)
               (k `(spread ,src ,nat ,triv))))])))
    (define (Tuple-Argument* tuple-arg* test k)
      (let f ([tuple-arg* tuple-arg*] [rtuple-arg* '()])
        (if (null? tuple-arg*)
            (k (reverse rtuple-arg*))
            (Tuple-Argument (car tuple-arg*) test
              (lambda (tuple-arg)
                (f (cdr tuple-arg*) (cons tuple-arg rtuple-arg*)))))))
    ;; expand-serialize emits vector->bytes of a vector whose elements are
    ;; either individual bytes or exact spreads of bytes->vector.  Recognize
    ;; only that shape: it lets the circuit backend retain bounded byte-string
    ;; segments while every other vector->bytes keeps the established lowering.
    (define (serialize-tuple-argument? tuple-arg)
      (nanopass-case (Lnovectorref Tuple-Argument) tuple-arg
        [(single ,src ,expr) #t]
        [(spread ,src ,nat ,expr)
         (and (fx> nat 0)
              (nanopass-case (Lnovectorref Expression) expr
                [(bytes->vector ,src^ ,len ,expr^) (fx= nat len)]
                [else #f]))]))
    (define (serialize-tuple-argument*? tuple-arg* len)
      ;; The vector->bytes type check has already proved every single element is
      ;; Uint8.  Spreads are accepted only when their declared width exactly
      ;; matches the underlying Bytes conversion, and check-types/Lflattened
      ;; independently re-proves every retained segment bound.
      (and (not (null? tuple-arg*))
           (andmap serialize-tuple-argument? tuple-arg*)
           (fx= len
             (fold-left
               (lambda (len tuple-arg)
                 (fx+ len
                   (nanopass-case (Lnovectorref Tuple-Argument) tuple-arg
                     [(single ,src ,expr) 1]
                     [(spread ,src ,nat ,expr) nat])))
               0
               tuple-arg*))))
    ;; Leave exact native byte-operation idioms on the established lowering
    ;; path so flatten-datatypes can validate their provenance before selecting
    ;; a native ZKIR operation. Other scalar-only serializer shapes remain
    ;; eligible for serialize-pack.
    (define (reverse-vector32? tuple-arg*)
      (and (fx= (length tuple-arg*) 32)
           (let loop ([tuple-arg* tuple-arg*] [kindex 31] [base-var-name #f])
             (if (null? tuple-arg*)
                 #t
                 (nanopass-case (Lnovectorref Tuple-Argument) (car tuple-arg*)
                   [(single ,src ,expr)
                    (nanopass-case (Lnovectorref Expression) expr
                      [(tuple-ref ,src^ ,expr^ ,kindex^)
                       (let ([var-name (expression->var-name expr^)])
                         (and var-name
                              (fx= kindex kindex^)
                              (or (not base-var-name)
                                  (eq? base-var-name var-name))
                              (loop (cdr tuple-arg*) (fx1- kindex)
                                    (or base-var-name var-name))))]
                      [(bytes-ref ,src^ ,expr^ ,kindex^)
                       (let ([var-name (expression->var-name expr^)])
                         (and var-name
                              (fx= kindex kindex^)
                              (or (not base-var-name)
                                  (eq? base-var-name var-name))
                              (loop (cdr tuple-arg*) (fx1- kindex)
                                    (or base-var-name var-name))))]
                      [else #f])]
                   [else #f])))))
    (define (zero16-aggregate? expr)
      (define (zero-single? tuple-arg)
        (nanopass-case (Lnovectorref Tuple-Argument) tuple-arg
          [(single ,src ,expr)
           (nanopass-case (Lnovectorref Expression) expr
             [(quote ,src^ ,datum) (eqv? datum 0)]
             [else #f])]
          [else #f]))
      (define (zero16? tuple-arg*)
        (and (fx= (length tuple-arg*) 16)
             (andmap zero-single? tuple-arg*)))
      (or
        (nanopass-case (Lnovectorref Expression) expr
          [(tuple ,src ,tuple-arg* ...) (zero16? tuple-arg*)]
          [(vector ,src ,tuple-arg* ...) (zero16? tuple-arg*)]
          [else #f])
        (let ([var-name (expression->var-name expr)])
          (and var-name
               (let ([tuple-arg*
                      (hashtable-ref aggregate-provenance-ht var-name #f)])
                 (and tuple-arg* (zero16? tuple-arg*)))))))
    (define (indexed-reference expr)
      (nanopass-case (Lnovectorref Expression) expr
        [(tuple-ref ,src ,expr^ ,kindex)
         (let ([var-name (expression->var-name expr^)])
           (and var-name (cons var-name kindex)))]
        [(bytes-ref ,src ,expr^ ,kindex)
         (let ([var-name (expression->var-name expr^)])
           (and var-name (cons var-name kindex)))]
        [else #f]))
    (define (numeric-abi-vector32? tuple-arg*)
      (and (fx= (length tuple-arg*) 17)
           (nanopass-case (Lnovectorref Tuple-Argument) (car tuple-arg*)
             [(spread ,src ,nat ,expr)
              (and (fx= nat 16) (zero16-aggregate? expr))]
             [else #f])
           (let loop ([tuple-arg* (cdr tuple-arg*)]
                      [index 15]
                      [base-var-name #f])
             (if (null? tuple-arg*)
                 (fx= index -1)
                 (nanopass-case (Lnovectorref Tuple-Argument) (car tuple-arg*)
                   [(single ,src ,expr)
                    (let ([reference (indexed-reference expr)])
                      (and reference
                           (fx= (cdr reference) index)
                           (or (not base-var-name)
                               (eq? (car reference) base-var-name))
                           (loop (cdr tuple-arg*)
                                 (fx1- index)
                                 (or base-var-name (car reference)))))]
                   [else #f])))))
    (define (special-byte-vector32? tuple-arg*)
      (or (reverse-vector32? tuple-arg*)
          (numeric-abi-vector32? tuple-arg*)))
    ;; Resolve an A-normalized aggregate back to bounded segments.  Every leaf
    ;; is a variable or literal that was already evaluated by its original
    ;; statement, so replacing the pure aggregate/conversion chain cannot
    ;; duplicate effects.  The optimizer later removes the now-dead chain.
    (define (provenance-serialize-segments expr len)
      (define (segments-width segment*)
        (fold-left (lambda (n segment) (fx+ n (car segment))) 0 segment*))
      (define (resolve-spread expr len recovered?)
        (or
          (nanopass-case (Lnovectorref Expression) expr
            [(bytes->vector ,src ,len^ ,expr^)
             ;; An operand recovered from a recorded aggregate was already
             ;; evaluated by its let binding, so only reuse it when it is
             ;; trivial. A spread inside the aggregate currently being lowered
             ;; may evaluate an arbitrary producer exactly once.
             (and (fx= len len^)
                  (or (not recovered?) (trivial-expression? expr^))
                  (list (cons len expr^)))]
            [else #f])
          (nanopass-case (Lnovectorref Expression) expr
            [(tuple ,src ,tuple-arg* ...)
             (let ([segment* (resolve-arguments tuple-arg* recovered?)])
               (and segment*
                    (fx= len (segments-width segment*))
                    segment*))]
            [(vector ,src ,tuple-arg* ...)
             (let ([segment* (resolve-arguments tuple-arg* recovered?)])
               (and segment*
                    (fx= len (segments-width segment*))
                    segment*))]
            [else #f])
          (let ([var-name (expression->var-name expr)])
            (and var-name
                 (or
                   (let ([entry
                          (hashtable-ref bytes-vector-provenance-ht var-name #f)])
                     (and entry
                          (fx= len (car entry))
                          (list (cons len (cdr entry)))))
                   (let ([tuple-arg*
                          (hashtable-ref aggregate-provenance-ht var-name #f)])
                     (and tuple-arg*
                          (not (special-byte-vector32? tuple-arg*))
                          (let ([segment* (resolve-arguments tuple-arg* #t)])
                            (and segment*
                                 (fx= len (segments-width segment*))
                                 segment*)))))))))
      (define (resolve-arguments tuple-arg* recovered?)
        (let loop ([tuple-arg* tuple-arg*] [rsegment* '()])
          (if (null? tuple-arg*)
              (reverse rsegment*)
              (nanopass-case (Lnovectorref Tuple-Argument) (car tuple-arg*)
                [(single ,src ,expr)
                 (and (trivial-expression? expr)
                      (loop (cdr tuple-arg*) (cons (cons 1 expr) rsegment*)))]
                [(spread ,src ,nat ,expr)
                 (let ([segment* (resolve-spread expr nat recovered?)])
                   (and segment*
                        (loop (cdr tuple-arg*)
                              (append (reverse segment*) rsegment*))))]))))
      (let* ([direct-tuple-arg*
              (nanopass-case (Lnovectorref Expression) expr
                [(tuple ,src ,tuple-arg* ...) tuple-arg*]
                [(vector ,src ,tuple-arg* ...) tuple-arg*]
                [else #f])]
             [tuple-arg*
              (or direct-tuple-arg*
                  (let ([var-name (expression->var-name expr)])
                    (and var-name
                         (hashtable-ref aggregate-provenance-ht var-name #f))))])
        (and tuple-arg*
             (not (special-byte-vector32? tuple-arg*))
             (let ([segment*
                    (resolve-arguments tuple-arg*
                      (not direct-tuple-arg*))])
               (and segment*
                    (fx= len (segments-width segment*))
                    segment*)))))
    (define (Serialize-Provenance-Segment* segment* test k)
      (let loop ([segment* segment*] [rwidth.triv* '()])
        (if (null? segment*)
            (k (reverse rwidth.triv*))
            (Triv (cdar segment*) test
              (lambda (triv)
                (loop (cdr segment*)
                      (cons (cons (caar segment*) triv) rwidth.triv*)))))))
    ;; Lower recognized segments left-to-right, matching Tuple-Argument*'s
    ;; evaluation order.  Spread operands bypass bytes->vector but retain its
    ;; statically checked byte width alongside the underlying Bytes value.
    (define (Serialize-Segment* tuple-arg* test k)
      (let f ([tuple-arg* tuple-arg*] [rwidth.triv* '()])
        (if (null? tuple-arg*)
            (k (reverse rwidth.triv*))
            (nanopass-case (Lnovectorref Tuple-Argument) (car tuple-arg*)
              [(single ,src ,expr)
               (Triv expr test
                 (lambda (triv)
                   (f (cdr tuple-arg*) (cons (cons 1 triv) rwidth.triv*))))]
              [(spread ,src ,nat ,expr)
               (nanopass-case (Lnovectorref Expression) expr
                 [(bytes->vector ,src^ ,len ,expr^)
                  (Triv expr^ test
                    (lambda (triv)
                      (f (cdr tuple-arg*) (cons (cons nat triv) rwidth.triv*))))]
                 [else (assert cannot-happen)])]))))
    (define (Path-Element* path-elt* test k)
      (let f ([path-elt* path-elt*] [rpath-elt* '()])
        (if (null? path-elt*)
            (k (reverse rpath-elt*))
            (let ([path-elt (car path-elt*)] [path-elt* (cdr path-elt*)])
              (nanopass-case (Lnovectorref Path-Element) path-elt
                [,path-index (f path-elt* (cons path-index rpath-elt*))]
                [(,src ,type ,expr)
                 (Triv expr test
                   (lambda (triv)
                     (f path-elt*
                        (cons
                          (with-output-language (Lcircuit Path-Element)
                            `(,src ,(Type type) ,triv))
                          rpath-elt*))))])))))
    (define (add-test src test triv k)
      (let ([t1 (make-temp-id src 't)] [t2 (make-temp-id src 't)])
        (with-output-language (Lcircuit Statement)
          (cons*
            ; t1 = triv && test
            `(= (quote #t) ,t1 (select ,triv ,test (quote #f)))
            ; t2 = !triv && test
            `(= (quote #t) ,t2 (select ,triv (quote #f) ,test))
            (k t1 t2)))))
    )
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
     (fluid-let ([default-src src])
       (let ([triv #f])
         (let ([stmt* (Triv expr
                        (with-output-language (Lcircuit Triv) `(quote #t))
                        (lambda (triv^) (set! triv triv^) '()))])
           `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... ,triv))))])
  (Statement : Expression (ir test stmt*) -> * (stmt*)
    [(seq ,src ,expr* ... ,expr)
     (fold-right
       (lambda (expr stmt*) (Statement expr test stmt*))
       (Statement expr test stmt*)
       expr*)]
    [(let* ,src ([,local* ,expr*] ...) ,expr)
     (record-serialize-provenance! local* expr* test)
     (fold-right
       (lambda (local expr stmt*)
         (nanopass-case (Lnovectorref Argument) local
           [(,var-name ,type)
            (Rhs expr test
              (lambda (rhs)
                (cons
                  (with-output-language (Lcircuit Statement)
                    `(= ,test ,var-name ,rhs))
                  stmt*)))]))
       (Statement expr test stmt*)
       local*
       expr*)]
    [(if ,src ,expr0 ,expr1 ,expr2)
     ; we could let the Triv call below handle "if" via Rhs, but we handle
     ; Statement "if" directly here to avoid the generation of a select with
     ; possibly mismatched branch types, which could cause trouble downstream.
     (Triv expr0 test
       (lambda (triv0)
         (add-test src test triv0
           (lambda (test1 test2)
             (Statement expr1 test1
               (Statement expr2 test2 stmt*))))))]
    [else
     (Triv ir test
       (lambda (triv)
         ; dropping triv here, since it has no effect
         stmt*))])
  (Rhs : Expression (ir test k) -> * (stmt*)
    [(seq ,src ,expr* ... ,expr)
     (fold-right
       (lambda (expr stmt*) (Statement expr test stmt*))
       (Rhs expr test k)
       expr*)]
    [(if ,src ,expr0 ,expr1 ,expr2)
     (Triv expr0 test
       (lambda (triv0)
         (add-test src test triv0
           (lambda (test1 test2)
             (Triv expr1 test1
               (lambda (triv1)
                 (Triv expr2 test2
                   (lambda (triv2)
                     (k (with-output-language (Lcircuit Rhs)
                          `(select ,triv0 ,triv1 ,triv2)))))))))))]
    [(let* ,src ([,local* ,expr*] ...) ,expr)
     (let f ([local* local*] [expr* expr*])
       (if (null? local*)
           (Rhs expr test k)
           (nanopass-case (Lnovectorref Argument) (car local*)
             [(,var-name ,type)
              (Rhs (car expr*) test
                (lambda (rhs)
                  (cons
                    (with-output-language (Lcircuit Statement)
                      `(= ,test ,var-name ,rhs))
                    (f (cdr local*) (cdr expr*)))))])))]
    [(call ,src ,function-name ,expr* ...)
     (Triv* expr* test
       (lambda (triv*)
         (k (with-output-language (Lcircuit Rhs)
              `(call ,src ,function-name ,triv* ...)))))]
    [(assert ,src ,expr ,mesg)
     (Triv expr test
       (lambda (triv)
         (let ([t1 (make-temp-id src 't)] [t2 (make-temp-id src 't)])
           (with-output-language (Lcircuit Statement)
             (cons*
               `(= (quote #t) ,t2 (select ,test ,triv (quote #t)))
               `(assert ,src ,t2 ,mesg)
               (k (with-output-language (Lcircuit Rhs)
                  `(tuple))))))))]
    [(quote ,src ,datum)
     (k (with-output-language (Lcircuit Rhs)
          `(quote ,datum)))]
    [(var-ref ,src ,var-name)
     (k var-name)]
    [(default ,src ,[type])
     (k (with-output-language (Lcircuit Rhs)
          `(default ,type)))]
    [(+ ,src ,[type] ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
               `(+ ,type ,triv1 ,triv2)))))))]
    [(- ,src ,[type] ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(- ,type ,triv1 ,triv2)))))))]
    [(* ,src ,[type] ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(* ,type ,triv1 ,triv2)))))))]
    [(< ,src ,bits ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(< ,bits ,triv1 ,triv2)))))))]
    [(== ,src ,type ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(== ,triv1 ,triv2)))))))]
    [(new ,src ,[type] ,expr* ...)
     (Triv* expr* test
       (lambda (triv*)
         (k (with-output-language (Lcircuit Rhs)
            `(new ,type ,triv* ...)))))]
    [(elt-ref ,src ,expr ,elt-name)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
            `(elt-ref ,triv ,elt-name)))))]
    [(tuple ,src ,tuple-arg* ...)
     (Tuple-Argument* tuple-arg* test
       (lambda (tuple-arg*)
         (k (with-output-language (Lcircuit Rhs)
            `(tuple ,tuple-arg* ...)))))]
    [(vector ,src ,tuple-arg* ...)
     (Tuple-Argument* tuple-arg* test
       (lambda (tuple-arg*)
         (k (with-output-language (Lcircuit Rhs)
            `(vector ,tuple-arg* ...)))))]
    [(tuple-ref ,src ,expr ,nat)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
            `(tuple-ref ,triv ,nat)))))]
    [(bytes-ref ,src ,expr ,nat)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
            `(bytes-ref ,triv ,nat)))))]
    [(bytes->field ,src ,[ftype] ,len ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(bytes->field ,src ,ftype ,len ,triv)))))]
    [(field->bytes ,src ,len ,[ftype] ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(field->bytes ,src ,len ,ftype ,triv)))))]
    [(bytes->vector ,src ,len ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
           `(bytes->vector ,len ,triv)))))]
    [(vector->bytes ,src ,len ,expr)
     (let ([tuple-arg*
            (and (feature-zkir-v3)
                 (unconditional-test? test)
                 (nanopass-case (Lnovectorref Expression) expr
                   [(vector ,src^ ,tuple-arg* ...) tuple-arg*]
                   [else #f]))])
       (define (finish width.triv*)
         (let ([nat* (map car width.triv*)]
               [triv* (map cdr width.triv*)])
           (k (with-output-language (Lcircuit Rhs)
                `(serialize-pack ,src ,len (,nat* ,triv*) ...)))))
       (cond
         [(and tuple-arg*
               (not (special-byte-vector32? tuple-arg*))
               (serialize-tuple-argument*? tuple-arg* len))
          (Serialize-Segment* tuple-arg* test finish)]
         [(and (feature-zkir-v3) (unconditional-test? test)
               (provenance-serialize-segments expr len)) =>
          (lambda (segment*)
            (Serialize-Provenance-Segment* segment* test finish))]
         [else
          (Triv expr test
            (lambda (triv)
              (k (with-output-language (Lcircuit Rhs)
                   `(vector->bytes ,len ,triv)))))]))]
    [(cast-to-field ,src ,[ftype] ,[type] ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(cast-to-field ,src ,ftype ,type ,triv)))))]
    [(cast-from-field ,src ,nat ,[ftype] ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(cast-from-field ,src ,nat ,ftype ,triv)))))]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,expr)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(downcast-unsigned ,src ,nat2 ,nat1 ,triv)))))]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,[adt-op] ,expr* ...)
     (Path-Element* path-elt* test
       (lambda (path-elt*)
         (Triv* expr* test
           (lambda (triv*)
             (k (with-output-language (Lcircuit Rhs)
                  `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...)))))))]
    [(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code)
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
              `(emit ,src ,event-version ,event-tag ,len ,triv ,vm-code)))))]
    [(contract-call ,src ,elt-name (,expr ,[type]) ,expr* ...)
     (Triv expr test
       (lambda (triv)
         (Triv* expr* test
           (lambda (triv*)
             (k (with-output-language (Lcircuit Rhs)
                 `(contract-call ,src ,elt-name (,triv ,type) ,triv* ...)))))))]
    [else (internal-errorf 'Rhs "unexpected ir ~s" ir)])
  (Type : Type (ir) -> Type ())
  )
