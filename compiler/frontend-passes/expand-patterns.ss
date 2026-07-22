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
    (define (do-circuit src parg* blck)
      (let-values ([(arg* stmt*) (let f ([parg* parg*])
                                   (if (null? parg*)
                                       (values '() '())
                                       (let-values ([(arg* stmt*) (f (cdr parg*))])
                                         (let-values ([(arg stmt*) (Pattern-Argument (car parg*) stmt*)])
                                           (values (cons arg arg*) stmt*)))))])
        (values arg*
                (if (null? stmt*)
                    blck
                    (with-output-language (Lnopattern Block)
                      `(block ,src ,stmt* ... ,blck))))))
    )
  (Pattern-Argument : Pattern-Argument (ir stmt*) -> Argument (stmt*)
    [(,src ,pattern ,[type])
     (let-values ([(var-name stmt*) (do-pattern pattern stmt*)])
       (values `(,src ,var-name ,type) stmt*))])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,parg* ...) ,[blck])
     (let-values ([(arg* blck) (do-circuit src parg* blck)])
       `(constructor ,src (,arg* ...) ,blck))])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,parg* ...) ,[type] ,[blck])
     (let-values ([(arg* blck) (do-circuit src parg* blck)])
       `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,blck))])
  (Statement : Statement (ir) -> Statement ()
    [(const ,src ,pattern ,[type] ,[expr])
     (let-values ([(var-name stmt*) (do-pattern pattern '())])
       (let ([stmt `(const ,src ,var-name ,type ,expr)])
         (if (null? stmt*)
             stmt
            `(seq ,src ,stmt ,stmt* ...))))])
  (Function : Function (ir) -> Function ()
    [(circuit ,src (,parg* ...) ,[type] ,[blck])
     (let-values ([(arg* blck) (do-circuit src parg* blck)])
       `(circuit ,src (,arg* ...) ,type ,blck))])
  )
