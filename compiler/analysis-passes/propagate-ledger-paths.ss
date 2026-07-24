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

; FIXME: building in knowledge of the ledger here
(define-pass propagate-ledger-paths : Lwithpaths0 (ir) -> Lwithpaths ()
  (definitions
    (module (memoize)
      (define $memoize
        (let ([ht (make-eq-hashtable)])
          (lambda (ir th)
            (let ([a (eq-hashtable-cell ht ir #f)])
              (or (cdr a)
                  (let ([v (th)])
                    (set-cdr! a v)
                    v))))))
      (define-syntax memoize
        (syntax-rules ()
          [(_ ir e) ($memoize ir (lambda () e))])))
    (module (record-ledger-binding! lookup-ledger-binding)
      (define ledger-ht (make-eq-hashtable))
      (define (check-adt-nesting! type)
        (nanopass-case (Lwithpaths Type) (de-alias type)
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (for-each
             (lambda (adt-arg)
               (nanopass-case (Lwithpaths Public-Ledger-ADT-Arg) adt-arg
                 [,type
                  (nanopass-case (Lwithpaths Type) (de-alias type)
                    [(tadt ,src ,adt-name^ ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                     (unless (eq? adt-name 'Map)
                       ; this should already be ruled out by the ledger meta-type checks
                       (source-errorf src "ADT nesting is permitted only within Map ADTs"))
                     (when (eq? adt-name^ 'Kernel)
                       (source-errorf src "cannot nest ~s ADTs within another ADT" adt-name^))
                     (check-adt-nesting! type)]
                    [else (void)])]
                 [else (void)]))
             adt-arg*)]))
      (define (record-one! public-binding)
        (nanopass-case (Lwithpaths0 Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,[Type : type])
           (check-adt-nesting! type)
           (hashtable-set! ledger-ht ledger-field-name (list (de-alias type) path-index*))]))
      (define (record-ledger-binding! pelt)
        (nanopass-case (Lwithpaths0 Program-Element) pelt
          [(kernel-declaration ,public-binding)
           (record-one! public-binding)]
          [(public-ledger-declaration ,pl-array ,lconstructor)
           (let f ([pl-array pl-array])
             (nanopass-case (Lwithpaths0 Public-Ledger-Array) pl-array
               [(public-ledger-array ,pl-array-elt* ...)
                (for-each
                  (lambda (pl-array-elt)
                    (nanopass-case (Lwithpaths0 Public-Ledger-Array-Element) pl-array-elt
                      [,pl-array (f pl-array)]
                      [,public-binding (record-one! public-binding)]))
                  pl-array-elt*)]))]
          [else (void)]))
      (define (lookup-ledger-binding ledger-field-name)
        (assert (hashtable-ref ledger-ht ledger-field-name #f))))
    (define (de-alias type)
      (nanopass-case (Lwithpaths Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
    (define (public-adt? type)
      (nanopass-case (Lwithpaths Type) (de-alias type)
        [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
        [else #f]))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-ledger-binding! pelt*)
     `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,(map Program-Element pelt*) ...)])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Type : Type (ir) -> Type ()
    [(tadt ,src ,adt-name ((,adt-formal* ,[adt-arg*]) ...) ,vm-expr (,adt-op* ...) (,[adt-rt-op*] ...))
     (memoize ir
       (let ([adt-op* (map (lambda (adt-op) (ADT-Op adt-op adt-name adt-formal* adt-arg*)) adt-op*)])
         `(tadt ,src ,adt-name ((,adt-formal* ,adt-arg*) ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))))])
  (ADT-Op : ADT-Op (ir adt-name adt-formal* adt-arg*) -> ADT-Op ()
    [(,ledger-op ,[op-class] ((,var-name* ,[type*] ,discloses?*) ...) ,[type] ,vm-code)
     `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)])
  (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
  (Expr : Expression (ir) -> Expression ()
    (definitions
      (define (bind-if-complex src expr* type* k)
        (define (complex? expr)
          (nanopass-case (Lwithpaths Expression) expr
            [(quote ,src ,datum) #f]
            [(var-ref ,src ,var-name) #f]
            [(enum-ref ,src ,type ,elt-name^) #f]
            [(default ,src ,type)
             (nanopass-case (Lwithpaths Type) (de-alias type)
               [(tboolean ,src) #f]
               [(tfield ,src ,ftype) #f]
               [(tunsigned ,src ,nat) #f]
               [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #f]
               [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #f]
               [else #t])]
            [(disclose ,src ,expr) (complex? expr)]
            [else #t]))
        (let f ([expr* expr*] [type* type*] [rexpr* '()])
          (if (null? expr*)
              (k (reverse rexpr*))
              (let ([expr (car expr*)] [expr* (cdr expr*)])
                (if (complex? expr)
                    (let ([var-name (make-temp-id src 'tmp)])
                      (with-output-language (Lwithpaths Expression)
                        `(let* ,src ([(,var-name ,(car type*)) ,expr])
                           ,(f expr* (cdr type*) (cons `(var-ref ,src ,var-name) rexpr*)))))
                    (f expr* (cdr type*) (cons expr rexpr*))))))))
    [(public-ledger ,src ,ledger-field-name ,sugar? ,accessor ,accessor* ...)
     (let-values ([(public-adt path-index*) (apply values (lookup-ledger-binding ledger-field-name))])
       (let loop ([accessor accessor]
                  [accessor* accessor*]
                  [public-adt public-adt]
                  [rpath-src* '()]
                  [rpath-expr* '()]
                  [rpath-type* '()])
         (nanopass-case (Lwithpaths0 Ledger-Accessor) accessor
           [(,src^ ,ledger-op ,expr* ...)
            (let ([expr* (map Expr expr*)])
              (nanopass-case (Lwithpaths Type) (de-alias public-adt)
                [(tadt ,src^^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                 (let find-adt-op ([adt-op* adt-op*])
                   (assert (not (null? adt-op*)))
                   (let ([adt-op (car adt-op*)] [adt-op* (cdr adt-op*)])
                     (nanopass-case (Lwithpaths ADT-Op) adt-op
                       [(,ledger-op^ ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type* ,discloses?*) ...) ,type ,vm-code)
                        (if (eq? ledger-op^ ledger-op)
                            (begin
                              (assert (fx= (length type*) (length expr*)))
                              (if (null? accessor*)
                                  (let ([path-src* (reverse rpath-src*)]
                                        [path-expr* (reverse rpath-expr*)]
                                        [path-type* (reverse rpath-type*)])
                                    (bind-if-complex src expr* type*
                                      (lambda (expr*)
                                        (bind-if-complex src path-expr* path-type*
                                          (lambda (path-expr*)
                                            `(public-ledger ,src ,ledger-field-name ,sugar? (,path-index* ... (,path-src* ,path-type* ,path-expr*) ...) ,src^ ,adt-op ,expr* ...))))))
                                  (begin
                                    ; nothing but Map should have gotten past check-adt-nesting!
                                    (assert (eq? adt-name 'Map))
                                    ; nothing but lookup with one argument (the key) should have gotten past the type checker
                                    (assert (and (eq? ledger-op 'lookup) (fx= (length expr*) 1)))
                                    ; and the only element of type* should be a base type
                                    (assert (not (public-adt? (car type*))))
                                    ; and since we're nested, nothing but a public-adt return type should have gotten past the type checker
                                    (assert (public-adt? type))
                                    (loop (car accessor*)
                                          (cdr accessor*)
                                          type
                                          (cons src^ rpath-src*)
                                          (cons (car expr*) rpath-expr*)
                                          (cons (car type*) rpath-type*)))))
                            (find-adt-op adt-op*))])))]))])))]))
