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

(library (frontend-passes)
  (export frontend-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (parser)
          (ledger)
          (pass-helpers))

  (define-pass resolve-includes : Lsrc (ir) -> Lnoinclude ()
    (definitions
      (define already-seen '()))
    (expand-pelt : Program-Element (ir pelt*) -> * (pelt*)
      [(include ,src ,file)
       (let ([pathname (find-source-pathname src file
                         (lambda (pathname)
                           (if (string=? file "std")
                               (source-errorf src "failed to locate file ~s: possibly replace include with import CompactStandardLibrary" pathname)
                               (source-errorf src "failed to locate file ~s" pathname))))])
         (when (member pathname already-seen)
           (source-errorf src "include cycle involving ~s" pathname))
         (fluid-let ([already-seen (cons pathname already-seen)])
           (nanopass-case (Lsrc Program) (parse-file pathname)
             [(program ,src ,pelt^* ...)
              (parameterize ([relative-path (path-parent pathname)])
                (fold-right expand-pelt pelt* pelt^*))])))]
      [else (cons (Program-Element ir) pelt*)])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Program : Program (ir) -> Program ()
      [(program ,src ,pelt* ...)
       `(program ,src ,(fold-right expand-pelt '() pelt*) ...)])
    (Module-Definition : Module-Definition (ir) -> Module-Definition ()
      [(module ,src ,exported? ,module-name (,[type-param*] ...) ,pelt* ...)
       `(module ,src ,exported? ,module-name (,type-param* ...) ,(fold-right expand-pelt '() pelt*) ...)]))

  ; expands a multi-variable const into multiple single-variable const
  (define-pass expand-const : Lnoinclude (ir) -> Lsingleconst ()
    (Const-Binding : Const-Binding (ir) -> Statement ()
      [(,src ,[pattern] ,[type] ,[expr])
       `(const ,src ,pattern ,type ,expr)])
    (Statement : Statement (ir) -> Statement ()
      [(const ,src ,[Const-Binding : cbinding -> stmt]) stmt]
      [(const ,src ,[Const-Binding : cbinding -> stmt] ,[Const-Binding : cbinding* -> stmt*] ...)
       `(seq ,src ,stmt ,stmt* ...)]))

  (define-pass expand-patterns : Lsingleconst (ir) -> Lnopattern ()
    (definitions
      (define next-tmp
        (let ([n 0])
          (lambda ()
            (set! n (fx+ n 1))
            (string->symbol (format "__compact_pattern_tmp~a" n)))))
      (define (do-pattern pattern stmt*)
        (with-output-language (Lnopattern Statement)
          (nanopass-case (Lsingleconst Pattern) pattern
            [,var-name (values var-name stmt*)]
            [(tuple ,src ,pattern?* ...)
             (let ([tmp (next-tmp)])
               (values
                 tmp
                 (fold-right
                   (lambda (pattern? i stmt*)
                     (if pattern?
                         (let-values ([(var-name stmt*) (do-pattern pattern? stmt*)])
                           (cons
                             `(const ,src ,var-name (tundeclared) (tuple-ref ,src (var-ref ,src ,tmp) (quote ,src ,i)))
                             stmt*))
                         stmt*))
                   stmt*
                   pattern?*
                   (enumerate pattern?*))))]
            [(struct ,src (,pattern* ,elt-name*) ...)
             (let ([tmp (next-tmp)])
               (values
                 tmp
                 (fold-right
                   (lambda (pattern elt-name stmt*)
                     (let-values ([(var-name stmt*) (do-pattern pattern stmt*)])
                       (cons
                         `(const ,src ,var-name (tundeclared) (elt-ref ,src (var-ref ,src ,tmp) ,elt-name))
                         stmt*)))
                   stmt*
                   pattern*
                   elt-name*)))])))
      (define (do-circuit src parg* stmt)
        (let-values ([(arg* stmt*) (let f ([parg* parg*])
                                     (if (null? parg*)
                                         (values '() '())
                                         (let-values ([(arg* stmt*) (f (cdr parg*))])
                                           (let-values ([(arg stmt*) (Pattern-Argument (car parg*) stmt*)])
                                             (values (cons arg arg*) stmt*)))))])
          (values arg*
                  (if (null? stmt*)
                      stmt
                      (with-output-language (Lnopattern Statement)
                        `(block ,src ,stmt* ... ,stmt))))))
      )
    (Pattern-Argument : Pattern-Argument (ir stmt*) -> Argument (stmt*)
      [(,src ,pattern ,[type])
       (let-values ([(var-name stmt*) (do-pattern pattern stmt*)])
         (values `(,src ,var-name ,type) stmt*))])
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src (,parg* ...) ,[stmt])
       (let-values ([(arg* stmt) (do-circuit src parg* stmt)])
         `(constructor ,src (,arg* ...) ,stmt))])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,parg* ...) ,[type] ,[stmt])
       (let-values ([(arg* stmt) (do-circuit src parg* stmt)])
         `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,stmt))])
    (Statement : Statement (ir) -> Statement ()
      [(const ,src ,pattern ,[type] ,[expr])
       (let-values ([(var-name stmt*) (do-pattern pattern '())])
         (let ([stmt `(const ,src ,var-name ,type ,expr)])
           (if (null? stmt*)
               stmt
              `(seq ,src ,stmt ,stmt* ...))))])
    (Function : Function (ir) -> Function ()
      [(circuit ,src (,parg* ...) ,[type] ,[stmt])
       (let-values ([(arg* stmt) (do-circuit src parg* stmt)])
         `(circuit ,src (,arg* ...) ,type ,stmt))])
    )

  (define-pass report-unreachable : Lnopattern (ir) -> Lnopattern ()
    (definitions
      (define (unreachable src)
        (source-errorf src "unreachable statement"))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ,pelt* ...)
       (for-each Program-Element pelt*)
       ir])
    (Program-Element : Program-Element (ir) -> * ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,stmt)
       (Statement stmt #t)]
      [(constructor ,src (,arg* ...) ,stmt)
       (Statement stmt #t)]
      [else (void)])
    (Statement : Statement (ir [reachable? #t]) -> * (reachable?)
      [(statement-expression ,src ,[expr])
       (unless reachable? (unreachable src))
       #t]
      [(const ,src ,var-name ,type ,[expr])
       (unless reachable? (unreachable src))
       #t]
      [(for ,src ,var-name ,[expr] ,stmt)
       (unless reachable? (unreachable src))
       (Statement stmt #t)]
      [(return ,src ,[expr])
       (unless reachable? (unreachable src))
       #f]
      [(if ,src ,[expr] ,stmt1 ,stmt2)
       (unless reachable? (unreachable src))
       (or (Statement stmt1 #t) (Statement stmt2 #t))]
      [(seq ,src ,stmt* ...)
       (fold-left (lambda (reachable? stmt) (Statement stmt reachable?)) #t stmt*)]
      [(block ,src ,stmt* ...)
       (unless reachable? (unreachable src))
       (fold-left (lambda (reachable? stmt) (Statement stmt reachable?)) #t stmt*)])
    (Function : Function (ir) -> Function ()
      [(circuit ,src (,arg* ...) ,type ,stmt)
       (Statement stmt #t)
       ir]
      [else ir]))

  ;; hoist-local-variables lifts the declarations for const-bound
  ;; variables to the top of the enclosing block.  A (single) assignment
  ;; remains where the const form originally appeared.  An exception
  ;; is raised if two or more bindings for the same variable are
  ;; found in the same block or if a binding appears in a "single-statement"
  ;; context, i.e., one of the arms of an if statement.
  (define-pass hoist-local-variables : Lnopattern (ir) -> Lhoisted ()
    (definitions
      (define vars))
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src (,[arg*] ...) ,[SingleStatement : stmt])
       `(constructor ,src (,arg* ...) ,stmt)])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,[arg*] ...) ,[type] ,[SingleStatement : stmt])
       `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,stmt)])
    (SingleStatement : Statement (ir) -> Statement ()
      [(const ,src ,var-name ,[type] ,[expr])
       (source-errorf src "binding for ~s found in a single-statement context" var-name)]
      [else (Statement ir)])
    (BlockStatement : Statement (ir) -> Statement ()
      [(const ,src ,var-name ,[type] ,[expr])
       (let ([a (hashtable-cell vars var-name #f)])
         (when (cdr a)
           (source-errorf src "found multiple bindings for ~s in the same block" var-name))
         (set-cdr! a #t))
       `(= ,src ,var-name ,type ,expr)]
      [else (Statement ir)])
    (Statement : Statement (ir) -> Statement ()
      [(if ,src ,[expr] ,[SingleStatement : stmt1] ,[SingleStatement : stmt2]) `(if ,src ,expr ,stmt1 ,stmt2)]
      [(for ,src ,var-name ,[expr] ,[SingleStatement : stmt]) `(for ,src ,var-name ,expr ,stmt)]
      [(seq ,src ,stmt* ...) `(seq ,src ,(map BlockStatement stmt*) ...)]
      [(block ,src ,stmt* ...)
       (fluid-let ([vars (make-hashtable symbol-hash eq?)])
         (let ([stmt* (map BlockStatement stmt*)])
           (define (symbol<? x y) (string<? (symbol->string x) (symbol->string y)))
           (let ([var-name* (sort symbol<? (vector->list (hashtable-keys vars)))])
             `(block ,src (,var-name* ...) ,stmt* ...))))])
    (Function : Function (ir) -> Function ()
      [(circuit ,src (,[arg*] ...) ,[type] ,[SingleStatement : stmt])
       `(circuit ,src (,arg* ...) ,type ,stmt)]))

  (define-pass reject-duplicate-bindings : Lhoisted (ir) -> Lhoisted ()
    (definitions
      (define reject-duplicate!
        (let ([ht (make-hashtable symbol-hash eq?)])
          (lambda (src what sym*)
            (hashtable-clear! ht)
            (for-each
              (lambda (sym)
                (let ([a (hashtable-cell ht sym #f)])
                  (when (cdr a) (source-errorf src "duplicate ~a ~s" what sym))
                  (set-cdr! a #t)))
              sym*))))
      (define (arg->sym arg)
        (nanopass-case (Lhoisted Argument) arg
          [(,src ,var-name ,type) var-name]))
      (define (type-param->tvar-name type-param)
        (nanopass-case (Lhoisted Type-Param) type-param
          [(nat-valued ,src ,tvar-name) tvar-name]
          [(type-valued ,src ,tvar-name) tvar-name]))
      )
    (External-Declaration : External-Declaration (ir) -> External-Declaration ()
      [(external ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
       (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
       (reject-duplicate! src "parameter name" (map arg->sym arg*))
       ir])
    (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
      [(witness ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
       (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
       (reject-duplicate! src "parameter name" (map arg->sym arg*))
       ir])
    (Module-Definition : Module-Definition (ir) -> Module-Definition ()
      [(module ,src ,exported? ,module-name (,type-param* ...) ,[pelt*] ...)
       (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
       ir])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,[stmt])
       (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
       (reject-duplicate! src "parameter name" (map arg->sym arg*))
       ir])
    (Structure-Definition : Structure-Definition (ir) -> Structure-Definition ()
      [(struct ,src ,exported? ,struct-name (,type-param* ...) ,arg* ...)
       (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
       (reject-duplicate! src "field name" (map arg->sym arg*))
       ir])
    (Enum-Definition : Enum-Definition (ir) -> Enum-Definition ()
      [(enum ,src ,exported? ,enum-name ,elt-name ,elt-name* ...)
       (reject-duplicate! src "element name" (cons elt-name elt-name*))
       ir])
    (Function : Function (ir) -> Function ()
      [(circuit ,src (,arg* ...) ,type ,[stmt])
       (reject-duplicate! src "parameter name" (map arg->sym arg*))
       ir]))

  ;; eliminate-statements converts statements to expressions and eliminates
  ;; return forms in favor of placing the returned expression in tail position
  ;; with respect to the enclosing body.  it sometimes duplicates code but
  ;; minimizes the duplication where possible.
  (define-pass eliminate-statements : Lhoisted (ir) -> Lexpr ()
    (definitions
      (define (unit? x)
        (nanopass-case (Lexpr Expression) x
          [(tuple ,src) #t]
          [else #f]))
      (define make-seq
        (case-lambda
          [(src expr*)
           (if (null? expr*)
               (with-output-language (Lexpr Expression) `(tuple ,src))
               (let loop ([expr+ expr*] [rexpr* '()])
                 (let ([expr (car expr+)] [expr* (cdr expr+)])
                   (if (null? expr*)
                       (make-seq src (reverse rexpr*) expr)
                       (loop expr* (cons expr rexpr*))))))]
          [(src expr* expr)
           (let ([expr* (remp unit? expr*)])
             (if (null? expr*)
                 expr
                 (with-output-language (Lexpr Expression)
                   `(seq ,src ,expr* ... ,expr))))]))
      (define block-ends '(dummy)))
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src (,[arg*] ...) ,stmt)
       (let ([tail (list (with-output-language (Lexpr Expression) `(tuple ,src)))])
         (let ([tail (Statement stmt tail)])
           `(constructor ,src (,arg* ...) ,(make-seq src tail))))])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,[arg*] ...) ,[type] ,stmt)
       (let ([tail (list (with-output-language (Lexpr Expression) `(tuple ,src)))])
         (let ([tail (Statement stmt tail)])
           `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,(make-seq src tail))))])
    (Statement : Statement (ir tail) -> * (tail)
      [(statement-expression ,src ,expr) (cons (Expression expr) tail)]
      [(return ,src ,[expr])
       (with-output-language (Lexpr Expression)
         (list `(return ,src ,expr)))]
      [(= ,src ,var-name ,[type] ,[expr])
       (with-output-language (Lexpr Expression)
         (let-values ([(head tail)
                       (let f ([tail tail])
                         (if (or (null? tail) (eq? tail (car block-ends)))
                             (values '() tail)
                             (let-values ([(x) (car tail)] [(head tail) (f (cdr tail))])
                               (values (cons x head) tail))))])
           (cons
             `(let* ,src ([(,src ,var-name ,type) ,expr])
                ,(if (null? head)
                     (with-output-language (Lexpr Expression) `(tuple ,src))
                     (make-seq src head)))
             tail)))]
      [(if ,src ,[expr0] ,stmt1 ,stmt2)
       (with-output-language (Lexpr Expression)
         (let ([tail1 (Statement stmt1 tail)]
               [tail2 (Statement stmt2 tail)])
           (let ([n (length tail)])
             (let ([n1 (fx- (length tail1) n)] [n2 (fx- (length tail2) n)])
               (if (and (and (fx>= n1 0) (fx>= n2 0))
                        (eq? (list-tail tail1 n1) (list-tail tail2 n2)))
                   (cons
                     `(if ,src ,expr0
                          ,(make-seq src (list-head tail1 n1))
                          ,(make-seq src (list-head tail2 n2)))
                     tail)
                   (list
                     `(if ,src ,expr0
                          ,(make-seq src tail1)
                          ,(make-seq src tail2))))))))]
      [(for ,src ,var-name ,expr ,stmt)
       (with-output-language (Lexpr Expression)
         (cons
           `(for ,src ,var-name ,(Expression expr)
              ,(let ([tail (list `(tuple ,src))])
                 (let ([tail (Statement stmt tail)])
                   (make-seq src tail))))
           tail))]
      [(seq ,src ,stmt* ...) (fold-right Statement tail stmt*)]
      [(block ,src (,var-name* ...) ,stmt* ...)
       (with-output-language (Lexpr Expression)
         (let ([tail^ (fluid-let ([block-ends (cons tail block-ends)])
                        (fold-right Statement tail stmt*))])
           (if (null? var-name*)
               tail^
               (let-values ([(tail^ tail)
                             (let ([n (length tail)])
                               (let ([n^ (fx- (length tail^) n)])
                                 (if (and (fx>= n^ 0) (eq? (list-tail tail^ n^) tail))
                                     (values (list-head tail^ n^) tail)
                                     (values tail^ '()))))])
                 (cons `(block ,src (,var-name* ...) ,(make-seq src tail^)) tail)))))])
    (Expression : Expression (ir) -> Expression ()
      [(seq ,src ,[expr*] ... ,[expr]) (make-seq src expr* expr)])
    (Function : Function (ir) -> Function ()
      [(circuit ,src (,[arg*] ...) ,[type] ,stmt)
       (let ([tail (list (with-output-language (Lexpr Expression) `(tuple ,src)))])
         (let ([tail (Statement stmt tail)])
           `(circuit ,src (,arg* ...) ,type ,(make-seq src tail))))]))

  (define-pass eliminate-boolean-connectives : Lexpr (ir) -> Lnoandornot ()
    (Expression : Expression (ir) -> Expression ()
      [(not ,src ,[expr]) `(if ,src ,expr (quote ,src #f) (quote ,src #t))]
      [(and ,src ,[expr1] ,[expr2]) `(if ,src ,expr1 ,expr2 (quote ,src #f))]
      [(or ,src ,[expr1] ,[expr2]) `(if ,src ,expr1 (quote ,src #t) ,expr2)]))

  (define-pass prepare-for-expand : Lnoandornot (ir) -> Lpreexpand())

  (define-passes frontend-passes
    (resolve-includes                Lnoinclude)
    (expand-const                    Lsingleconst)
    (expand-patterns                 Lnopattern)
    (report-unreachable              Lnopattern)
    (hoist-local-variables           Lhoisted)
    (reject-duplicate-bindings       Lhoisted)
    (eliminate-statements            Lexpr)
    (eliminate-boolean-connectives   Lnoandornot)
    (prepare-for-expand              Lpreexpand))
)
