#!chezscheme

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

(library (ledger)
  (export ledger-adt-definitions)
  (import (except (chezscheme) errorf)
          (utils)
          (nanopass)
          (langs)
          (vm)
          (language-version)
          (compiler-version))

  (define (ledger-adt-definitions)
    (define ledger-adt* '())
    (define ledger-type-src (make-source-object (assert (stdlib-sfd)) 0 0 1 1))

    (meta define ledger-type-marker (cons 'ledger 'type))

    (define-syntax declare-ledger-type
      (syntax-rules ()
        [(_ type-name (type-formal ...) abstract-type rust-type)
         (define-syntax type-name
           (make-compile-time-value
             (list ledger-type-marker
                   #'(type-formal ...)
                   #'abstract-type)))]))

    (define-syntax declare-ledger-adt
      (lambda (q)
        (define (check-identifier x) (unless (identifier? x) (syntax-error x "not an identifier")))
        (define (non-negative-fixnum? x) (and (fixnum? x) (fx>= x 0)))
        (define (check-string x) (unless (string? (syntax->datum x)) (syntax-error x "not a string")))
        (define (check-class x)
          (syntax-case x ()
            [class-name
             (identifier? #'class-name)
             (unless (memq (syntax->datum #'class-name) '(read update write remove))
               (syntax-error x "unrecognized class"))]
            [(class-name coin-idx recipient-idx)
             (identifier? #'class-name)
             (begin
               (unless (memq (syntax->datum #'class-name) '(update-with-coin-check))
                 (syntax-error x "unrecognized class"))
               (unless (non-negative-fixnum? (syntax->datum #'coin-idx))
                 (syntax-error #'coin-idx "coin index must be a non-negative integer"))
               (unless (non-negative-fixnum? (syntax->datum #'recipient-idx))
                 (syntax-error #'recipient-idx "recipient index must be a non-negative integer")))]))
        (module (expand-formatting expand-formatting-multiple)
          (define (expand-one formal-param* qs)
            (let ([s (syntax->datum qs)])
              (let ([n (string-length s)])
                (define (s0 i rc* rarg*)
                  (if (fx= i n)
                      (if (null? rarg*)
                          qs
                          #`(format #,(list->string (reverse rc*)) #,@(reverse rarg*)))
                      (let ([c (string-ref s i)] [i (fx+ i 1)])
                        (case c
                          [(#\$) (s1 i rc* rarg*)]
                          [(#\~) (s0 i (cons* #\~ #\~ rc*) rarg*)]
                          [else (s0 i (cons c rc*) rarg*)]))))
                (define (s1 i rc* rarg*)
                  (if (fx= i n)
                      (syntax-error qs "string ended with $")
                      (let ([c (string-ref s i)] [i (fx+ i 1)])
                        (case c
                          [(#\$) (s0 i (cons c rc*) rarg*)]
                          [(#\{) (s2 i rc* rarg* '())]
                          [else (syntax-error qs "string has $ not followed by $ or {")]))))
                (define (s2 i rc* rarg* rc2*)
                  (if (fx= i n)
                      (syntax-error qs "string ended before } found after ${")
                      (let ([c (string-ref s i)] [i (fx+ i 1)])
                        (case c
                          [(#\}) (let ([name (list->string (reverse rc2*))])
                                   (let lookup ([formal-param* formal-param*])
                                     (if (null? formal-param*)
                                         (syntax-error qs (format "unbound substitution ${~a}" name))
                                         (let ([formal-param (car formal-param*)])
                                           (if (string=? (symbol->string (syntax->datum formal-param)) name)
                                               (s0 i (cons* #\a #\~ rc*) (cons formal-param rarg*))
                                               (lookup (cdr formal-param*)))))))]
                          [else (s2 i rc* rarg* (cons c rc2*))]))))
                (s0 0 '() '()))))
          (define (expand-formatting formal-param* qs)
            #`(lambda (#,@formal-param*) #,(expand-one formal-param* qs)))
          (define (expand-formatting-multiple formal-param* qs*)
            #`(lambda (#,@formal-param*) (list #,@(map (lambda (qs) (expand-one formal-param* qs)) qs*)))))
        (lambda (ct-env)
          (define (do-clauses adt-formal* clause*)
            (define (expand-type x)
              (define (handle-ledger-type id args)
                (let ([ledger-type (ct-env id)])
                  (unless (and (pair? ledger-type) (eq? (car ledger-type) ledger-type-marker))
                    (syntax-error id "unrecognized ledger type"))
                  (let-values ([(type-formal* type) (apply values (cdr ledger-type))])
                    (let ([n-expected (length type-formal*)] [n-received (length args)])
                      (unless (= n-received n-expected)
                        (syntax-error id (format "expected ~s parameter~:*~p, received ~s for" n-expected n-received))))
                    (let ([alist (map cons type-formal* (map expand-type args))])
                      (let replace-type ([type type])
                        (syntax-case type (primitive-type type-ref)
                          [name
                            (identifier? #'name)
                            (cond
                              [(assp (lambda (x) (free-identifier=? x #'name)) alist) => cdr]
                              [else (syntax-error #'name)])]
                          [(primitive-type ?Boolean) (eq? (datum ?Boolean) 'Boolean) #'(tboolean ,ledger-type-src)]
                          [(primitive-type ?Field) (eq? (datum ?Field) 'Field) #'(tfield ,ledger-type-src)]
                          [(primitive-type ?Void) (eq? (datum ?Void) 'Void) #'(ttuple ,ledger-type-src)]
                          [(primitive-type ?Bytes n) (eq? (datum ?Bytes) 'Bytes) #'(tbytes ,ledger-type-src (type-size ,ledger-type-src n))]
                          [(primitive-type ?Uint n) (eq? (datum ?Uint) 'Uint) #'(tunsigned ,ledger-type-src (type-size ,ledger-type-src n))]
                          [(type-ref type-name type ...)
                           #`(type-ref ,ledger-type-src type-name
                               #,@(map (lambda (type)
                                         #`(targ-type ,ledger-type-src #,(replace-type type)))
                                       #'(type ...)))]
                          [else (syntax-error type)]))))))
              (if (and (identifier? x)
                       (memp (lambda (y) (free-identifier=? x y)) adt-formal*))
                  #`(type-ref ,ledger-type-src #,x)
                  (syntax-case x ()
                    [id
                     (identifier? #'id)
                     (handle-ledger-type #'id '())]
                    [(id x ...)
                     (identifier? #'id)
                     (handle-ledger-type #'id #'(x ...))]
                    [_ (syntax-error x "expand-type: malformed type")])))
            (define (parse-disclosure disclosure)
              (syntax-case disclosure (discloses nothing)
                [() ""]
                [((discloses nothing)) #f]
                [((discloses what)) (string? (datum what)) #'what]
                [other (syntax-error #'other "invalid discloses syntax")]))
            (let loop ([clause* clause*] [radt-op* '()] [radt-rt-op* '()])
              (if (null? clause*)
                  (list (reverse radt-op*) (reverse radt-rt-op*))
                  (let ([clause (car clause*)] [clause* (cdr clause*)])
                    (let add-cond ([clause clause] [adt-op-cond* '()])
                      (syntax-case clause (when function js-only =)
                        [(function js-only op-name ([input-name input-type] ...) result-type-string doc-string (runtime-string ...))
                         (begin
                           (check-identifier #'op-name)
                           (for-each check-identifier #'(input-name ...))
                           (check-string #'result-type-string)
                           (for-each check-string #'(runtime-string ...))
                           (loop clause*
                                 radt-op*
                                 (cons
                                   (with-syntax ([(input-type ...) (map expand-type #'(input-type ...))]
                                                 [result-type (expand-formatting #`(rtlib #,@adt-formal*) #'result-type-string)]
                                                 [runtime-code (expand-formatting-multiple #`(rtlib this input-name ... #,@adt-formal*) #'(runtime-string ...))])
                                     #'(op-name ((input-name input-type) ...)
                                         ,result-type
                                         ,runtime-code))
                                   radt-rt-op*)))]
                        [(function class op-name ([input-name input-type . disclosure] ...) result-type doc-string (vm-op ...))
                         (begin
                           (check-class #'class)
                           (check-identifier #'op-name)
                           (check-vm-code (syntax->datum #`(input-name ... #,@adt-formal*)) #'(vm-op ...))
                           (for-each check-identifier #'(input-name ...))
                           (loop clause*
                                 (cons
                                   (with-syntax ([(input-type ...) (map expand-type #'(input-type ...))]
                                                 [result-type (expand-type #'result-type)]
                                                 [(adt-op-cond ...) adt-op-cond*]
                                                 [(discloses? ...) (map parse-disclosure #'(disclosure ...))])
                                     #'(op-name class ((input-name input-type discloses?) ...)
                                         result-type
                                         ,(make-vm-code #'(vm-op ...))
                                         adt-op-cond ...))
                                   radt-op*)
                                 radt-rt-op*))]
                        [(when (= tvar-name tvar-name^) clause)
                         (begin
                           (check-identifier #'tvar-name)
                           (check-identifier #'tvar-name^)
                           (unless (memp (lambda (adt-formal) (free-identifier=? adt-formal #'tvar-name)) adt-formal*)
                             (syntax-error #'tvar-name "unrecognized adt formal"))
                           (add-cond #'clause (cons #'(= tvar-name (type-ref ,ledger-type-src tvar-name^)) adt-op-cond*)))]
                        [else (syntax-error clause)]))))))
          (syntax-case q (initial-value)
            [(_ adt-name ([meta-type adt-formal] ...) doc-string (initial-value vm-expr) clause ...)
             (let ()
               (check-identifier #'adt-name)
               (for-each check-identifier #'(adt-formal ...))
               (check-string #'doc-string)
               (with-syntax ([(kind ...) (map (lambda (meta-type)
                                                (case (syntax->datum meta-type)
                                                  [(ADT/Type) #`type-valued]
                                                  [(Type) #`non-adt-type-valued]
                                                  [(Nat) #'nat-valued]
                                                  [else (syntax-error meta-type "invalid meta type")]))
                                              #'(meta-type ...))]
                             [((adt-op ...) (adt-rt-op ...)) (do-clauses #'(adt-formal ...) #'(clause ...))])
                   #'(set! ledger-adt*
                       (cons
                         (with-output-language (Lpreexpand ADT-Definition)
                           `(define-adt ,ledger-type-src #t adt-name
                              ((kind ,ledger-type-src adt-formal) ...)
                              ,(make-vm-expr #'vm-expr)
                              (adt-op ...)
                              (adt-rt-op ...)))
                         ledger-adt*))))]))))
    
    (define-syntax emit-documentation
      (lambda (q)
        (define (expand-formatting qs)
          (let ([s (syntax->datum qs)])
            (let ([n (string-length s)])
              (define (s0 i rc*)
                (if (fx= i n)
                    (list->string (reverse rc*))
                    (let ([c (string-ref s i)] [i (fx+ i 1)])
                      (case c
                        [(#\$) (s1 i rc*)]
                        [(#\~) (s0 i (cons* #\~ #\~ rc*))]
                        [else (s0 i (cons c rc*))]))))
              (define (s1 i rc*)
                (if (fx= i n)
                    (syntax-error qs "string ended with $")
                    (let ([c (string-ref s i)] [i (fx+ i 1)])
                      (case c
                        [(#\$) (s0 i (cons c rc*))]
                        [(#\{) (s2 i rc* '())]
                        [else (syntax-error qs "string has $ not followed by $ or {")]))))
              (define (s2 i rc* rc2*)
                (if (fx= i n)
                    (syntax-error qs "string ended before } found after ${")
                    (let ([c (string-ref s i)] [i (fx+ i 1)])
                      (case c
                        [(#\}) (s0 i
                                   (if (string=? (list->string (reverse rc2*)) "rtlib")
                                       rc*
                                       (append rc2* rc*)))]
                        [else (s2 i rc* (cons c rc2*))]))))
              (s0 0 '()))))
        (syntax-case q ()
          [(k)
           (lambda (ct-env)
             (define (emit-adt-clauses kernel? adt-formal* clause*)
               (define (expand-when clause*)
                 (let f ([clause* clause*] [rexpr* '()] [new-clause* '()])
                   (fold-right
                     (lambda (clause new-clause*)
                       (syntax-case clause (when)
                         [(when expr clause)
                          (f #'(clause) (cons #'expr rexpr*) new-clause*)]
                         [else (cons #`(when #,(reverse rexpr*) #,clause) new-clause*)]))
                     new-clause*
                     clause*)))
               (define (clause<? c1 c2)
                 (define (id<? x y)
                   (define (id->string x) (symbol->string (syntax->datum x)))
                   (string<? (id->string x) (id->string y)))
                 (syntax-case c1 (when function js-only)
                   [(when (expr ...) (function js-only op-name1 . stuff))
                    (syntax-case c2 (when function js-only)
                      [(when (expr ...) (function js-only op-name2 . stuff))
                       (id<? #'op-name1 #'op-name2)]
                      [(when (expr ...) (function class op-name2 . stuff))
                       #f]
                      [else (syntax-error c2 "unhandled case")])]
                   [(when (expr ...) (function class op-name1 . stuff))
                    (syntax-case c2 (when function js-only)
                      [(when (expr ...) (function js-only op-name2 . stuff))
                       #t]
                      [(when (expr ...) (function class op-name2 . stuff))
                       (id<? #'op-name1 #'op-name2)]
                      [else (syntax-error c2 "unhandled case")])]
                   [else (syntax-error c1 "unhandled case")]))
               (let* ([clause* (sort clause<? (expand-when clause*))]
                      [read-op* (if kernel? '() (read-ops clause*))])
                 (for-each
                   (lambda (clause) (emit-adt-clause adt-formal* clause read-op*))
                   clause*)))
             (define (read-ops clause*)
               (let ([op* (fold-left
                            (lambda (op* clause)
                              (syntax-case clause (function js-only)
                                [(when (expr ...) (function js-only op-name ([input-name input-type] ...) result-type-string doc-string (runtime-string ...)))
                                 op*]
                                [(when (expr ...) (function class op-name ([input-name input-type . disclosure] ...) result-type doc-string (vm-instruction ...)))
                                 (if (eq? (datum class) 'read)
                                     (cons (datum op-name) op*)
                                     op*)]
                                [else (syntax-error clause)]))
                            '()
                            clause*)])
                 (if (memq 'read op*)
                     (list 'read)
                     op*)))
             ;; Ensure a blank line between formatted markdown text lines.
             (define (paragraph str . args)
               (printf "~?\n\n" str args))
             ;; Wrap the body expressions in a markdown code block for `language`.
             (define-syntax code-block
               (syntax-rules ()
                 [(_ language body1 body2 ...)
                  (begin
                    (printf "```~a\n" language)
                    (let () body1 body2 ...)
                    (printf "\n```\n\n"))]))
             (define (emit-adt-clause adt-formal* clause read-op*)
               (define (expand-type x)
                 (define (handle-ledger-type id args)
                   (let ([ledger-type (ct-env id)])
                     (unless (and (pair? ledger-type) (eq? (car ledger-type) ledger-type-marker))
                       (syntax-error id "unrecognized ledger type"))
                     (let-values ([(type-formal* type) (apply values (cdr ledger-type))])
                       (let ([n-expected (length type-formal*)] [n-received (length args)])
                         (unless (= n-received n-expected)
                           (syntax-error id (format "expected ~s parameter~:*~p, received ~s for" n-expected n-received))))
                       (let ([alist (map cons (map syntax->datum type-formal*) (map expand-type args))])
                         (let replace-type ([type type])
                           (syntax-case type (primitive-type type-ref)
                             [name (identifier? #'name) (cond [(assq (datum name) alist) => cdr] [else (syntax-error #'name)])]
                             [(primitive-type ?Boolean) (eq? (datum ?Boolean) 'Boolean) `(tboolean)]
                             [(primitive-type ?Field) (eq? (datum ?Field) 'Field) `(tfield)]
                             [(primitive-type ?Void) (eq? (datum ?Void) 'Void) `(ttuple)]
                             [(primitive-type ?Bytes n) (eq? (datum ?Bytes) 'Bytes) `(tbytes ,#'n)]
                             [(primitive-type ?Uint n) (eq? (datum ?Uint) 'Uint) `(tunsigned ,#'n)]
                             [(type-ref type-name type ...) `(type-ref ,#'type-name ,@(map replace-type #'(type ...)))]
                             [else (syntax-error type)]))))))
                 (if (and (identifier? x)
                          (memp (lambda (y) (free-identifier=? x y)) adt-formal*))
                     x
                     (syntax-case x ()
                       [id
                        (identifier? #'id)
                        (handle-ledger-type #'id '())]
                       [(id x ...)
                        (identifier? #'id)
                        (handle-ledger-type #'id #'(x ...))]
                       [_ (syntax-error x "expand-type: malformed type")])))
               (define (format-compact-type type)
                 (let ([type (expand-type type)])
                   (let f ([type type])
                     (syntax-case type (tboolean tfield tunsigned type-ref tbytes ttuple)
                       [name (symbol? (datum name)) (format "~a" (datum name))]
                       [nat (field? (datum nat)) (format "~d" (datum nat))]
                       [(tboolean) "Boolean"]
                       [(tfield) "Field"]
                       [(tunsigned n) (format "Uint<~d>" (datum n))]
                       [(type-ref name) (format "~a" (datum name))]
                       [(type-ref name tvar ...) (format "~a<~{~a~^, ~}>" (datum name) (map f (datum (tvar ...))))]
                       [(tbytes n) (format "Bytes<~d>" (datum n))]
                       [(ttuple) "[]"]
                       [else (syntax-error type "format-compact-type is missing a case for type")]))))
               (define (format-typescript-type type)
                 (let ([type (expand-type type)])
                   (let f ([type type])
                     (syntax-case type (tfield tboolean tunsigned type-ref tbytes)
                       [name (symbol? (datum name)) (format "~a" (datum name))]
                       [nat (field? (datum nat)) (format "~d" (datum nat))]
                       [(tboolean) "boolean"]
                       [(tfield) "bigint"]
                       [(tunsigned n) "bigint"]
                       [(type-ref name) (format "~a" (datum name))]
                       [(type-ref name tvar ...) (format "~a<~{~a~^, ~}>" (datum name) (map f (datum (tvar ...))))]
                       [(tbytes n) "Uint8Array"]
                       ; add cases tboolean, etc., as needed
                       [else (syntax-error type "format-typescript-type is missing a case for type")]))))
               (define (emit-js-function op-name input-name* input-type* result-type-string doc-string cond-str)
                 (let ([js-name (if (eq? op-name 'iter)
                                    "[Symbol.iterator]"
                                    (to-camel-case (symbol->string op-name) #f))])
                   (paragraph "### ~a" js-name)
                   (paragraph "*callable only from TypeScript*")
                   (code-block "typescript"
                     (printf "~a(~{~a~^, ~}): ~a" js-name
                       (map (lambda (input-name input-type)
                              (format "~a: ~a"
                                (syntax->datum input-name)
                                (format-typescript-type input-type)))
                         input-name*
                         input-type*)
                       (expand-formatting (syntax->datum result-type-string))))
                   (paragraph (expand-formatting (syntax->datum doc-string)))))
               (define (emit-function op-name input-name* input-type* result-type doc-string cond-str)
                 (paragraph "### ~a" op-name)
                 (code-block "compact"
                   (printf "~a(~{~a~^, ~}): ~a" op-name
                     (map (lambda (input-name input-type)
                            (format "~a: ~a"
                              (syntax->datum input-name)
                              (format-compact-type input-type)))
                       input-name*
                       input-type*)
                     (format-compact-type result-type)))
                 (paragraph (expand-formatting (syntax->datum doc-string)))
                 (when cond-str
                   (paragraph "**~a**" cond-str))
                 (when (memq op-name read-op*)
                   (if (eq? op-name 'read)
                       (paragraph "*available from Typescript as a getter on the ledger field*")
                       (paragraph "*available from Typescript as `~a(~{~a~^, ~}): ~a`*"
                         (to-camel-case op-name #f)
                         (map (lambda (input-name input-type)
                                (format "~a: ~a"
                                  (syntax->datum input-name)
                                  (format-typescript-type input-type)))
                           input-name*
                           input-type*)
                         (format-typescript-type result-type)))))
               (define (predicate-id? x)
                 (and (identifier? x)
                      (let ([str (symbol->string (syntax->datum x))])
                        (and (fx>= (string-length str) 0)
                             (char=? (string-ref str (fx1- (string-length str))) #\?)))))
               (define (function-clause clause cond-str)
                 (syntax-case clause (function js-only)
                   [(function js-only op-name ([input-name input-type] ...) result-type-string doc-string (runtime-string ...))
                    (emit-js-function (datum op-name) (datum (input-name ...)) #'(input-type ...) (datum result-type-string) (datum doc-string) cond-str)]
                   [(function class op-name ([input-name input-type . disclosure] ...) result-type doc-string (vm-instruction ...))
                    (emit-function (datum op-name) (datum (input-name ...)) #'(input-type ...) #'result-type (datum doc-string) cond-str)]
                   [else (syntax-error clause)]))
               (syntax-case clause (when)
                 [(when () clause) (function-clause #'clause #f)]
                 [(when ((= tvar-name tvar-name^)) clause)
                  (function-clause #'clause
                    (let ([str (symbol->string (datum pred))])
                      (format "available only for ~a ~a"
                              (datum tvar-name^)
                              (datum tvar-name))))]
                 [else (syntax-error clause "unhandled case")]))
             (define (process-form q)
               (syntax-case q (declare-ledger-type declare-ledger-adt initial-value)
                 [(declare-ledger-type type-name (type-formal ...) type rust-type)
                  (void)]
                 [(declare-ledger-adt adt-name ([meta-type adt-formal] ...) doc-string (initial-value vm-expr) clause ...)
                  (string? (datum doc-string))
                  (let ([adt-name (datum adt-name)] [adt-formal* (datum (adt-formal ...))])
                    (if (null? adt-formal*)
                        (paragraph "## ~a" adt-name)
                        (paragraph "## ~a\\<~{~a~^, ~}>" adt-name adt-formal*))
                    (paragraph "This ADT is ~a." (datum doc-string))
                    (emit-adt-clauses (eq? adt-name 'Kernel) #'(adt-formal ...) #'(clause ...)))]
                 [else (syntax-error q "unexpected form found by emit-documentation")]))
             (unless (file-exists? "doc") (mkdir "doc"))
             (with-output-to-file "doc/ledger-adt.mdx"
               (lambda ()
                 (paragraph "# Ledger data types")
                 (paragraph "Compact language version ~a, compiler version ~a."
                   language-version-string
                   compiler-version-string)
                 (load "midnight-ledger.ss"
                   (lambda (x) (process-form (datum->syntax #'k x))))
                 (newline))
               'replace)
             #'(void))])))

      (include "midnight-ledger.ss")
      (emit-documentation)
      ledger-adt*)
)
