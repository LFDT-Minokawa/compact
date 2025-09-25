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

(library (vm)
  (export vminstr? vminstr-op vminstr-arg*
          VMop? VMop-case
          VMstack VMvoid VMsuppress VM+ VMalign VMaligned-concat VMnull
          VMmax-sizeof VMvalue->int VMcoin-commit VMleaf-hash VMstate-value-null VMstate-value-cell VMstate-value-ADT
          VMstate-value-map VMstate-value-merkle-tree VMstate-value-array
          check-vm-expr check-vm-code
          expand-vm-expr expand-vm-code)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype))

  (define-record-type vminstr
    (nongenerative)
    (fields op arg*))

  (define-datatype VMop
    (VMstack)
    (VMvoid)
    (VMsuppress)
    (VM+ x y)
    (VMalign value bytes)
    (VMaligned-concat x*)
    (VMnull x)
    (VMmax-sizeof x)
    (VMvalue->int x)
    (VMcoin-commit coin recipient)
    (VMleaf-hash x)
    (VMstate-value-null)
    (VMstate-value-cell val)
    (VMstate-value-ADT val type)
    (VMstate-value-map key* val*)
    (VMstate-value-merkle-tree nat key* val*)
    (VMstate-value-array val*)
    )

  (define prim-ht (make-eq-hashtable))

  (define-record-type prim
    (nongenerative)
    (fields checker expander)
    (protocol
      (lambda (new)
        (lambda (name checker expander)
          (let ([x (new checker expander)])
            (hashtable-set! prim-ht name x)
            x)))))

  (define-syntax define-function
    (syntax-rules ()
      [(_ (name x ... y dots) e1 e2 ...)
       (free-identifier=? #'dots #'(... ...))
       (make-prim 'name
         (lambda (q recur)
           (syntax-case q ()
             [(_ x ... y dots)
              (for-each recur (cons* #'x ... #'(y dots)))]
             [else (syntax-error q)]))
         (lambda (q recur)
           (syntax-case q ()
             [(_ x ... y dots)
              (let ([x (recur #'x)] ... [y (map recur #'(y dots))])
                e1 e2 ...)]
             [else (syntax-error q)])))]
      [(_ (name x ...) e1 e2 ...)
       (make-prim 'name
         (lambda (q recur)
           (syntax-case q ()
             [(_ x ...)
              (for-each recur (list #'x ...))]
             [else (syntax-error q)]))
         (lambda (q recur)
           (syntax-case q ()
             [(_ x ...)
              (let ([x (recur #'x)] ...)
                e1 e2 ...)]
             [else (syntax-error q)])))]))

  (define-syntax define-macro
    (syntax-rules ()
      [(_ name recur [pattern guard checker template] ...)
       (make-prim 'name
         (lambda (x recur)
           (syntax-case x ()
             [pattern guard checker]
             ...))
         (lambda (x recur)
           (syntax-case x ()
             [pattern guard template]
             ...)))]))

  (define (check okay? x complaint)
    (unless (okay? x)
      (syntax-error x complaint)))

  (define (make-check-vm-expr arg-name*)
    (let ([free-name* (cons* 'f 'f-cached arg-name*)])
      (define (free-name? x) (memq x free-name*))
      (rec check-vm-expr
        (lambda (e)
          (syntax-case e ()
            [k (constant? #'k) (void)]
            [id (identifier? #'id) (check free-name? (datum id) "unbound variable in VM expression")]
            [(id . stuff)
             (identifier? #'id)
             (cond
               [(hashtable-ref prim-ht (datum id) #f) =>
                (lambda (x) ((prim-checker x) e check-vm-expr))]
               [else (syntax-error e "unrecognized vm expression")])])))))

  (define (check-vm-expr arg-name* e)
    ((make-check-vm-expr arg-name*) e))

  (define (check-vm-code arg-name* code)
    (define check-vm-expr (make-check-vm-expr arg-name*))
    (define (check-vm-instruction i)
      (syntax-case i ()
        [(op [x e] ...)
         (begin
           (check identifier? #'op "invalid operator name")
           (for-each (lambda (x) (check identifier? x "invalid field name")) #'(x ...))
           (for-each check-vm-expr #'(e ...)))]))
    (syntax-case code ()
      [(i ...) (for-each check-vm-instruction #'(i ...))]))

  (define query-src)

  (module (expand-vm-expr expand-vm-code)
    (define (make-expand-vm-expr alist)
      (rec expand-vm-expr
        (lambda (e)
          (syntax-case e ()
            [k (constant? #'k) (datum k)]
            [id (identifier? #'id) (cdr (assert (assq (datum id) alist)))]
            [(id . stuff)
             (identifier? #'id)
             (cond
               [(hashtable-ref prim-ht (datum id) #f) =>
                (lambda (x) ((prim-expander x) e expand-vm-expr))]
               [else (syntax-error e "unrecognized vm expression")])]))))
    (define (expand-vm-expr src arg-alist e)
      (define expand-vm-expr (make-expand-vm-expr arg-alist))
      (fluid-let ([query-src src])
        (expand-vm-expr e)))
    (define (expand-vm-code src f f-cached arg-alist code)
      (define expand-vm-expr (make-expand-vm-expr (cons* (cons 'f f) (cons 'f-cached f-cached) arg-alist)))
      (define (expand-vm-instruction i)
        (syntax-case i ()
          [(op [x e] ...)
           (make-vminstr
             (symbol->string (datum op))
             (map cons
                  (map symbol->string (datum (x ...)))
                  (map expand-vm-expr #'(e ...))))]))
      (fluid-let ([query-src src])
        (syntax-case code ()
          [(i ...) (map expand-vm-instruction #'(i ...))]))))

  ; FIXME: consider putting everything below into a midnight-specific include file
  (define (nat? x)
    (let ([x (syntax->datum x)])
      (and (integer? x)
           (exact? x)
           (nonnegative? x))))

  (define (constant? x)
    (let ([x (syntax->datum x)])
      (or (boolean? x)
          (and (integer? x) (exact? x)))))

  (define (insist pred? x what)
    (unless (pred? x)
      (source-errorf query-src
        "unexpected ~a value ~s while evaluating VM-instruction argument value"
        what x)))

  (define-function (suppress-null x) (insist list? x "suppress argument 1") (if (null? x) (VMsuppress) x))

  (define-function (suppress-zero x) (insist number? x "suppress argument 1") (if (zero? x) (VMsuppress) x))

  (define-function (list x ...) x)

  (define-function (reverse x)
    (insist list? x "reverse argument 1")
    (reverse x))

  (define-function (length x)
    (insist list? x "length argument 1")
    (length x))

  (define-function (car x)
    (insist pair? x "car argument 1")
    (car x))

  (define-function (cdr x)
    (insist pair? x "cdr argument 1")
    (cdr x))

  (define-function (+ x y)
    (if (and (nat? x) (nat? y))
        (+ x y)
        (VM+ x y)))

  (define-function (* x y)
    (insist nat? x "* argument 1")
    (insist nat? y "* argument 2")
    (* x y))

  (define-function (expt x y)
    (insist nat? x "expt argument 1")
    (insist nat? y "expt argument 2")
    (expt x y))

  (define-function (add1 x)
    (insist nat? x "add1 argument 1")
    (add1 x))

  (define-function (sub1 x)
    (insist nat? x "sub1 argument 1")
    (sub1 x))

  (define-function (void)
    (VMvoid))

  (define-function (rt-aligned-concat x* ...)
    (VMaligned-concat x*))

  (define-function (rt-null x)
    (VMnull x))

  (define-function (rt-max-sizeof x)
    (VMmax-sizeof x))

  (define-function (rt-value->int x)
    (VMvalue->int x))

  (define-function (rt-coin-commit coin recipient)
    (VMcoin-commit coin recipient))

  (define-function (rt-leaf-hash x)
    (VMleaf-hash x))

  (define-function (align value bytes)
    (insist nat? value "align argument 1")
    (insist nat? bytes "align argument 2")
    (VMalign value bytes))

  (define-macro quote recur
    [(_ ?stack)
     (eq? (datum ?stack) 'stack)
     (void)
     (VMstack)])

  (define-macro state-value recur
    [(_ (?quote ?null))
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?null) 'null))
     (void)
     (VMstate-value-null)]
    [(state-value (?quote ?cell) e)
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?cell) 'cell))
     (recur #'e)
     (VMstate-value-cell (recur #'e))]
    [(state-value (?quote ?ADT) e type)
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?ADT) 'ADT))
     (recur #'e)
     (VMstate-value-ADT (recur #'e) (recur #'type))]
    [(_ (?quote ?map) ([key val] ...))
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?map) 'map))
     (begin
       (for-each recur #'(key ...))
       (for-each recur #'(val ...)))
     (VMstate-value-map
       (map recur #'(key ...))
       (map recur #'(val ...)))]
    [(_ (?quote ?merkle-tree) nat ([key val] ...))
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?merkle-tree) 'merkle-tree))
     (begin
       (recur #'nat)
       (for-each recur #'(key ...))
       (for-each recur #'(val ...)))
     (VMstate-value-merkle-tree
       (recur #'nat)
       (map recur #'(key ...))
       (map recur #'(val ...)))]
    [(_ (?quote ?array) (val ...))
     (and (eq? (datum ?quote) 'quote) (eq? (datum ?array) 'array))
     (for-each recur #'(val ...))
     (VMstate-value-array (map recur #'(val ...)))])
)
