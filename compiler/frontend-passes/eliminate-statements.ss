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
    (define (circuit-body src blck)
      (let ([tail (list (with-output-language (Lexpr Expression) `(return ,src)))])
        (make-seq src (Statement blck tail))))
    (define block-ends '(dummy))
    )
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,[arg*] ...) ,blck)
     `(constructor ,src (,arg* ...) ,(circuit-body src blck))])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,[arg*] ...) ,[type] ,blck)
     `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,(circuit-body src blck))])
  (Statement : Statement (ir tail) -> * (tail)
    [(statement-expression ,src ,expr) (cons (Expression expr) tail)]
    [(return ,src) 
     (with-output-language (Lexpr Expression)
       (list `(return ,src)))]
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
    [(for ,src ,var-name ,[tsize0] ,[tsize1] ,stmt)
     (with-output-language (Lexpr Expression)
       (cons
         `(for ,src ,var-name ,tsize0 ,tsize1
            ,(let ([tail (list `(tuple ,src))])
               (let ([tail (Statement stmt tail)])
                 (make-seq src tail))))
         tail))]
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
    [(circuit ,src (,[arg*] ...) ,[type] ,blck)
     `(circuit ,src (,arg* ...) ,type ,(circuit-body src blck))]))
