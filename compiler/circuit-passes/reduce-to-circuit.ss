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
    (define default-src)
    (define (arg->name arg)
      (nanopass-case (Lnovectorref Argument) arg
        [(,var-name ,type) var-name]))
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
    [(+ ,src ,mbits ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
               `(+ ,mbits ,triv1 ,triv2)))))))]
    [(- ,src ,mbits ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(- ,mbits ,triv1 ,triv2)))))))]
    [(* ,src ,mbits ,expr1 ,expr2)
     (Triv expr1 test
       (lambda (triv1)
         (Triv expr2 test
           (lambda (triv2)
             (k (with-output-language (Lcircuit Rhs)
                `(* ,mbits ,triv1 ,triv2)))))))]
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
     (Triv expr test
       (lambda (triv)
         (k (with-output-language (Lcircuit Rhs)
            `(vector->bytes ,len ,triv)))))]
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
