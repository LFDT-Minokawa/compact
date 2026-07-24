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

(define-pass discard-useless-code : Lnovectorref (ir) -> Lnovectorref ()
  (definitions
    (module (idset-empty make-idset idset-insert idset-remove idset-union idset-union-all idset-member?)
      ; rkd 2025/07/15: This implementation of set operations is inefficient and, since union is quadratic,
      ; especially inefficient when the sets get large.  To determine if this is likely to be a problem,
      ; I tooled the code to compute average and max set sizes while running the unit tests, which includes
      ; the programs in midnight-applications.  The largest sets contain only 6 elements, and the average
      ; set size is 1.25.  So this might not be a problem, though programs in the wild might be significantly
      ; different from the tests and example applications.  If it does turn out to be a problem, we can
      ; (1) avoid putting anything but let*-bound variables into the sets and (2) adopt some more
      ; efficient set implementation, e.g., the bit-tree operations used for live analysis in
      ; ChezScheme/s/cpnanopass.ss.
      (define (idset-empty) '())
      (define (make-idset id) (list id))
      (define (idset-insert id idset) (if (memq id idset) idset (cons id idset)))
      (define (idset-remove id idset) (remq id idset))
      (define (idset-union idset1 idset2) (fold-right idset-insert idset1 idset2))
      (define (idset-union-all idset*) (fold-left idset-union (idset-empty) idset*))
      (define (idset-member? id idset) (and (memq id idset) #t)))
    (define (empty-tuple? expr)
      (nanopass-case (Lnovectorref Expression) expr
        [(tuple ,src) #t]
        [else #f]))
    (define (make-seq effect? src expr* expr)
      (let-values ([(final-expr* final-expr?)
                    (let f ([expr* expr*])
                      (if (null? expr*)
                          (nanopass-case (Lnovectorref Expression) expr
                            [(seq ,src ,expr* ... ,expr) (values expr* expr)]
                            [(tuple ,src) (guard effect?) (values '() #f)]
                            [else (values '() expr)])
                          (let-values ([(expr) (car expr*)] [(final-expr* final-expr?) (f (cdr expr*))])
                            (nanopass-case (Lnovectorref Expression) expr
                              [(seq ,src ,expr* ... ,expr)
                               (if final-expr?
                                   (values (append expr* (cons expr final-expr*)) final-expr?)
                                   (values expr* expr))]
                              [(tuple ,src) (values final-expr* final-expr?)]
                              [else (if final-expr?
                                        (values (cons expr final-expr*) final-expr?)
                                        (values '() expr))]))))])
        (with-output-language (Lnovectorref Expression)
          (if final-expr?
              (if (null? final-expr*)
                  final-expr?
                  `(seq ,src ,final-expr* ... ,final-expr?))
              `(tuple ,src)))))
    (define (handle-let effect? src local* expr* expr idset)
      (define (arg->var-name arg)
        (nanopass-case (Lnovectorref Argument) arg
          [(,var-name ,type) var-name]))
      (let f ([local* local*] [expr* expr*])
        (if (null? local*)
            (values expr idset)
            (let-values ([(body body-idset) (f (cdr local*) (cdr expr*))])
              (let* ([local (car local*)] [var-name (arg->var-name local)])
                (if (idset-member? var-name body-idset)
                    (let-values ([(rhs rhs-idset) (Value (car expr*))])
                      (values
                        (with-output-language (Lnovectorref Expression)
                          (nanopass-case (Lnovectorref Expression) body
                            [(let* ,src^ ([,local^* ,expr^*] ...) ,expr^)
                             `(let* ,src ([,local ,rhs] [,local^* ,expr^*] ...) ,expr^)]
                            [else `(let* ,src ((,local ,rhs)) ,body)]))
                        (idset-union rhs-idset (idset-remove var-name body-idset))))
                    (let-values ([(rhs rhs-idset) (Effect (car expr*))])
                      (values
                        (make-seq effect? src (list rhs) body)
                        (idset-union rhs-idset body-idset)))))))))
    )
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,[Value : expr idset])
     `(circuit ,src ,function-name (,arg* ...) ,type ,expr)])
  (Path-Element : Path-Element (ir) -> Path-Element (idset)
    [,path-index (values path-index (idset-empty))]
    [(,src ,type ,[Value : expr idset]) (values `(,src ,type ,expr) idset)])
  (Value : Expression (ir) -> Expression (idset)
    [(quote ,src ,datum) (values ir (idset-empty))]
    [(default ,src ,type) (values ir (idset-empty))]
    [(var-ref ,src ,var-name) (values ir (make-idset var-name))]
    [(let* ,src ([,local* ,expr*] ...) ,[Value : expr idset])
     (handle-let #f src local* expr* expr idset)]
    [(if ,src ,[Value : expr0 idset0] ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(if ,src ,expr0 ,expr1 ,expr2)
       (idset-union idset0 (idset-union idset1 idset2)))]
    [(tuple ,src ,[Tuple-Argument-Value : tuple-arg* idset*] ...)
     (values
       `(tuple ,src ,tuple-arg* ...)
       (idset-union-all idset*))]
    [(vector ,src ,[Tuple-Argument-Value : tuple-arg* idset*] ...)
     (values
       `(vector ,src ,tuple-arg* ...)
       (idset-union-all idset*))]
    [(tuple-ref ,src ,[Value : expr idset] ,nat)
     (values
       `(tuple-ref ,src ,expr ,nat)
       idset)]
    [(bytes-ref ,src ,[Value : expr idset] ,nat)
     (values
       `(bytes-ref ,src ,expr ,nat)
       idset)]
    [(new ,src ,type ,[Value : expr* idset*] ...)
     (values
       `(new ,src ,type ,expr* ...)
       (idset-union-all idset*))]
    [(elt-ref ,src ,[Value : expr idset] ,elt-name)
     (values
       `(elt-ref ,src ,expr ,elt-name)
       idset)]
    [(emit ,src ,event-version ,event-tag ,len ,[Value : expr idset] ,vm-code)
     (values
       `(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code)
       idset)]
    [(+ ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(+ ,src ,mbits ,expr1 ,expr2)
       (idset-union idset1 idset2))]
    [(- ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(- ,src ,mbits ,expr1 ,expr2)
       (idset-union idset1 idset2))]
    [(* ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(* ,src ,mbits ,expr1 ,expr2)
       (idset-union idset1 idset2))]
    [(< ,src ,bits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(< ,src ,bits ,expr1 ,expr2)
       (idset-union idset1 idset2))]
    [(== ,src ,type ,[Value : expr1 idset1] ,[Value : expr2 idset2])
     (values
       `(== ,src ,type ,expr1 ,expr2)
       (idset-union idset1 idset2))]
    [(seq ,src ,[Effect : expr* idset*] ... ,[Value : expr idset])
     (values
       (make-seq #f src expr* expr)
       (idset-union-all (cons idset idset*)))]
    [(assert ,src ,[Value : expr idset] ,mesg)
     (values
       (if (nanopass-case (Lnovectorref Expression) expr
             [(quote ,src ,datum) (eq? datum #t)]
             [else #f])
           `(tuple ,src)
           `(assert ,src ,expr ,mesg))
       idset)]
    [(field->bytes ,src ,len ,ftype ,[Value : expr idset])
     (values
       `(field->bytes ,src ,len ,ftype ,expr)
       idset)]
    [(bytes->field ,src ,ftype ,len ,[Value : expr idset])
     (values
       `(bytes->field ,src ,ftype ,len ,expr)
       idset)]
    [(vector->bytes ,src ,len ,[Value : expr idset])
     (values
       `(vector->bytes ,src ,len ,expr)
       idset)]
    [(bytes->vector ,src ,len ,[Value : expr idset])
     (values
       `(bytes->vector ,src ,len ,expr)
       idset)]
    [(cast-to-field ,src ,ftype ,type ,[Value : expr idset])
     (values
       `(cast-to-field ,src ,ftype ,type ,expr)
       idset)]
    [(cast-from-field ,src ,nat ,ftype ,[Value : expr idset])
     (values
       `(cast-from-field ,src ,nat ,ftype ,expr)
       idset)]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,[Value : expr idset])
     (values
       `(downcast-unsigned ,src ,nat2 ,nat1 ,expr)
       idset)]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt idset^*] ...) ,src^ ,adt-op ,[Value : expr* idset*] ...)
     (values
       `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt ...) ,src^ ,adt-op ,expr* ...)
       (idset-union
         (idset-union-all idset^*)
         (idset-union-all idset*)))]
    [(call ,src ,function-name ,[Value : expr* idset*] ...)
     (values
       `(call ,src ,function-name ,expr* ...)
       (idset-union-all idset*))]
    [(contract-call ,src ,elt-name (,[Value : expr idset] ,type) ,[Value : expr* idset*] ...)
     (values
       `(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (idset-union-all (cons idset idset*)))]
    [else (internal-errorf 'discard-useless-code "unhandled Value form ~s" ir)])
  (Tuple-Argument-Value : Tuple-Argument (ir) -> Tuple-Argument (idset)
    [(single ,src ,[Value : expr idset])
     (values `(single ,src ,expr) idset)]
    [(spread ,src ,nat ,[Value : expr idset])
     (values `(spread ,src ,nat ,expr) idset)])
  (Effect : Expression (ir) -> Expression (idset)
    [(quote ,src ,datum) (values `(tuple ,src) (idset-empty))]
    [(default ,src ,type) (values `(tuple ,src) (idset-empty))]
    [(var-ref ,src ,var-name) (values `(tuple ,src) (idset-empty))]
    [(let* ,src ([,local* ,expr*] ...) ,[Effect : expr idset])
     (handle-let #t src local* expr* expr idset)]
    [(if ,src ,expr0 ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (if (and (empty-tuple? expr1) (empty-tuple? expr2))
         (Effect expr0)
         (let-values ([(expr0 idset0) (Value expr0)])
           (values
             `(if ,src ,expr0 ,expr1 ,expr2)
             (idset-union idset0 (idset-union idset1 idset2)))))]
    [(tuple ,src ,[Tuple-Argument-Effect : expr* idset*] ...)
     (values
       (make-seq #t src expr* `(tuple ,src))
       (idset-union-all idset*))]
    [(vector ,src ,[Tuple-Argument-Effect : expr* idset*] ...)
     (values
       (make-seq #t src expr* `(tuple ,src))
       (idset-union-all idset*))]
    [(tuple-ref ,src ,expr ,nat)
     (Effect expr)]
    [(bytes-ref ,src ,expr ,nat)
     (Effect expr)]
    [(new ,src ,type ,[Effect : expr* idset*] ...)
     (values
       (make-seq #t src expr* `(tuple ,src))
       (idset-union-all idset*))]
    [(elt-ref ,src ,expr ,elt-name)
     (Effect expr)]
    [(+ ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (values
       (make-seq #t src (list expr1) expr2)
       (idset-union idset1 idset2))]
    [(- ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (values
       (make-seq #t src (list expr1) expr2)
       (idset-union idset1 idset2))]
    [(* ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (values
       (make-seq #t src (list expr1) expr2)
       (idset-union idset1 idset2))]
    [(< ,src ,bits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (values
       (make-seq #t src (list expr1) expr2)
       (idset-union idset1 idset2))]
    [(== ,src ,type ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
     (values
       (make-seq #t src (list expr1) expr2)
       (idset-union idset1 idset2))]
    [(seq ,src ,[Effect : expr* idset*] ... ,[Effect : expr idset])
     (values
       (make-seq #t src expr* expr)
       (idset-union-all (cons idset idset*)))]
    [(field->bytes ,src ,len ,ftype ,expr)
     (if (nanopass-case (Lnovectorref Field-Type) ftype
           [(field-native) (> len (field-bytes))]
           [else #f])
         (Effect expr)
         (let-values ([(expr idset) (Value expr)])
           (values
             `(field->bytes ,src ,len ,ftype ,expr)
             idset)))]
    [(bytes->field ,src ,ftype ,len ,expr)
     (nanopass-case (Lnovectorref Field-Type) ftype
       [(field-native) (guard (<= len (field-bytes)))
        (Effect expr)]
       [else (let-values ([(expr idset) (Value expr)])
               (values
                 `(bytes->field ,src ,ftype ,len ,expr)
                 idset))])]
    [(vector->bytes ,src ,len ,expr)
     (Effect expr)]
    [(bytes->vector ,src ,len ,expr)
     (Effect expr)]
    [else (Value ir)])
  (Tuple-Argument-Effect : Tuple-Argument (ir) -> Expression (idset)
    [(single ,src ,[Effect : expr idset]) (values expr idset)]
    [(spread ,src ,nat ,[Effect : expr idset]) (values expr idset)]))
