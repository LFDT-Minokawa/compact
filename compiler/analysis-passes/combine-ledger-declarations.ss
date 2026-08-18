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

(define-pass combine-ledger-declarations : Lnotundeclared (ir) -> Loneledger ()
  (definitions
    (define kernel-id*)
    (define (de-alias type)
      (nanopass-case (Lnotundeclared Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
    (define (kernel? ldecl)
      (nanopass-case (Lnotundeclared Ledger-Declaration) ldecl
        [(public-ledger-declaration ,src ,ledger-field-name ,type)
         (nanopass-case (Lnotundeclared Type) (de-alias type)
           [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
            (eq? adt-name 'Kernel)]
           [else (assert cannot-happen)])])))
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (let*-values ([(ldecl* pelt*) (partition Lnotundeclared-Ledger-Declaration? pelt*)]
                   [(lconstructor* pelt*) (partition Lnotundeclared-Ledger-Constructor? pelt*)]
                   [(kernel-ldecl* ldecl*) (partition kernel? ldecl*)])
       (fluid-let ([kernel-id* (map (lambda (kernel-ldecl)
                                      (nanopass-case (Lnotundeclared Ledger-Declaration) kernel-ldecl
                                        [(public-ledger-declaration ,src ,ledger-field-name ,type)
                                         ledger-field-name]))
                                    kernel-ldecl*)])
         `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...)
            ,(if (null? kernel-ldecl*)
                 '()
                 (list
                   (nanopass-case (Lnotundeclared Ledger-Declaration) (car kernel-ldecl*)
                     [(public-ledger-declaration ,src ,ledger-field-name ,type)
                      `(kernel-declaration (,src ,ledger-field-name ,(Type type)))])))
            ...
            (public-ledger-declaration
              ,(map (lambda (ldecl)
                      (nanopass-case (Lnotundeclared Ledger-Declaration) ldecl
                        [(public-ledger-declaration ,src ,ledger-field-name ,type)
                         `(,src ,ledger-field-name ,(Type type))]))
                    ldecl*)
              ...
              ,(cond
                [(null? lconstructor*) `(constructor ,src () (tuple ,src))]
                [(null? (cdr lconstructor*))
                 (nanopass-case (Lnotundeclared Ledger-Constructor) (car lconstructor*)
                   [(constructor ,src (,arg* ...) ,expr)
                    `(constructor ,src (,(map Argument arg*) ...) ,(Expression expr))])]
                [else
                 (let ([src* (map (lambda (lconstructor)
                                    (nanopass-case (Lnotundeclared Ledger-Constructor) lconstructor
                                      [(constructor ,src (,arg* ...) ,expr) src]))
                                  lconstructor*)])
                   (source-errorf (car src*)
                                  "found other ledger constructors in program: \
                                   ~{\n    ~a~^,~}"
                                  (map format-source-object (cdr src*))))]))
            ,(map Program-Element pelt*)
            ...)))])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [,ldecl (assert cannot-happen)]
    [,lconstructor (assert cannot-happen)])
  (Argument : Argument (ir) -> Argument ())
  (Type : Type (ir) -> Type ())
  (Expression : Expression (ir) -> Expression ()
    [(ledger-ref ,src ,ledger-field-name) (assert cannot-happen)]
    [(ledger-call ,src ,ledger-op ,sugar? ,expr ,expr* ...)
     (let loop ([src src] [ledger-op ledger-op] [expr expr] [expr* expr*] [accessor* '()])
       (let ([accessor* (cons (with-output-language (Loneledger Ledger-Accessor)
                                `(,src ,ledger-op ,(map Expression expr*) ...))
                              accessor*)])
         (nanopass-case (Lnotundeclared Expression) expr
           [(ledger-call ,src ,ledger-op ,sugar^? ,expr ,expr* ...)
            (assert (not sugar^?))
            (loop src ledger-op expr expr* accessor*)]
           [(ledger-ref ,src ,ledger-field-name)
            (let ([ledger-field-name (if (memq ledger-field-name kernel-id*)
                                         (car kernel-id*)
                                         ledger-field-name)])
              `(public-ledger ,src ,ledger-field-name ,sugar? ,accessor* ...))]
           [else (assert cannot-happen)])))])
)
