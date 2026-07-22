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

(define-pass inline-circuits : Lunrolled (ir) -> Linlined ()
  (definitions
    (define circuit-ht (make-eq-hashtable))
    (define (arg->name arg)
      (nanopass-case (Linlined Argument) arg
        [(,var-name ,type) var-name]))
    (define (arg->type arg)
      (nanopass-case (Linlined Argument) arg
        [(,var-name ,type) type]))
    (define empty-env '())
    (define (extend-env p var-name*)
      (let ([ht (make-eq-hashtable)])
        (let ([new-var-name* (map (lambda (var-name)
                                    (let ([new-var-name (make-temp-id (id-src var-name) (id-sym var-name))])
                                      (hashtable-set! ht var-name new-var-name)
                                      new-var-name))
                                  var-name*)])
        (values (cons ht p) new-var-name*))))
    (define (maybe-rename p var-name)
      (or (ormap (lambda (ht) (hashtable-ref ht var-name #f)) p)
          var-name))
    (define-pass rename-expr : (Linlined Expression) (ir p) -> (Linlined Expression) ()
      (Expression : Expression (ir p) -> Expression ()
        [(var-ref ,src ,var-name) `(var-ref ,src ,(maybe-rename p var-name))]
        [(let* ,src ([,local* ,[expr*]] ...) ,expr)
         (let-values ([(p var-name*) (extend-env p (map arg->name local*))]
                      [(type*) (map arg->type local*)])
           `(let* ,src ([(,var-name* ,type*) ,expr*] ...) ,(Expression expr p)))])
      (Tuple-Argument : Tuple-Argument (ir p) -> Tuple-Argument ())
      (Path-Element : Path-Element (ir p) -> Path-Element ()))
    (define-record-type circuit
      (nongenerative)
      (fields
        src
        name
        arg*                  ; Linlined
        type                  ; Linlined
        (mutable expr)        ; initially Lunrolled; once processed Linlined
        (mutable status)      ; one of {unprocessed, in-process, processed, consumed}
        )
      (protocol
        (lambda (new)
          (lambda (src name arg* type expr)
            (new src name arg* type expr 'unprocessed)))))
    (define (process-circuit! circuit)
      (case (circuit-status circuit)
        [(unprocessed)
         (circuit-status-set! circuit 'in-process)
         (circuit-expr-set! circuit (Expression (circuit-expr circuit)))
         (circuit-status-set! circuit 'processed)]
        ; recursive circuits should be caught by reject-recursive-circuits
        [(in-process) (assert cannot-happen)]
        [(processed consumed) (void)]))
  )
  (Program : Program (ir) -> Program ()
    [(program ,src  ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-circuit! pelt*)
     (let ([circuit* (hashtable-values circuit-ht)])
       (vector-for-each process-circuit! circuit*))
     `(program ,src ((,export-name* ,name*) ...)
        ,(fold-right
           (lambda (pelt pelt*)
             (nanopass-case (Lunrolled Program-Element) pelt
               [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
                (let ([circuit (hashtable-ref circuit-ht function-name #f)])
                  (assert circuit)
                  (if (and (eq? (circuit-status circuit) 'consumed)
                           (not (id-exported? function-name)))
                      pelt*
                      (cons
                        `(circuit ,src ,function-name
                           (,(circuit-arg* circuit) ...)
                           ,(circuit-type circuit)
                           ,(circuit-expr circuit))
                        pelt*)))]
               [,ndecl (cons (Native-Declaration ndecl) pelt*)]
               [,wdecl (cons (Witness-Declaration wdecl) pelt*)]
               [,kdecl (cons (Kernel-Declaration kdecl) pelt*)]
               [,ldecl (cons (Ledger-Declaration ldecl) pelt*)]))
           '()
           pelt*)
        ...)])
  (record-circuit! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
     (hashtable-set! circuit-ht function-name
       (make-circuit src function-name arg* type expr))]
    [else (void)])
  (Native-Declaration : Native-Declaration (ir) -> Native-Declaration ())
  (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ())
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ())
  (Kernel-Declaration : Kernel-Declaration (ir) -> Kernel-Declaration ())
  (Expression : Expression (ir) -> Expression ()
    [(flet ,src ,function-name
       (,src^ (,[arg*] ...) ,[type] ,expr^)
       ,expr)
     (hashtable-set! circuit-ht function-name
       (make-circuit src^ function-name arg* type expr^))
     (Expression expr)]
    [(call ,src ,function-name ,[expr*] ...)
     (cond
       [(hashtable-ref circuit-ht function-name #f) =>
        (lambda (circuit)
          (process-circuit! circuit)
          (circuit-status-set! circuit 'consumed)
          (let ([arg* (circuit-arg* circuit)] [expr (circuit-expr circuit)])
            (let-values ([(p var-name*) (extend-env empty-env (map arg->name arg*))]
                         [(type*) (map arg->type arg*)])
              `(let* ,src ([(,var-name* ,type*) ,expr*] ...)
                 ,(rename-expr expr p)))))]
       [else `(call ,src ,function-name ,expr* ...)])]))
