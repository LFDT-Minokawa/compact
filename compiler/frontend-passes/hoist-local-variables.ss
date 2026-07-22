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

;; hoist-local-variables lifts the declarations for const-bound
;; variables to the top of the enclosing block.  A (single) assignment
;; remains where the const form originally appeared.  An exception
;; is raised if two or more bindings for the same variable are
;; found in the same block or if a binding appears in a "single-statement"
;; context, i.e., one of the arms of an if statement.
(define-pass hoist-local-variables : Lnopattern (ir) -> Lhoisted ()
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,[arg*] ...) ,[blck])
     `(constructor ,src (,arg* ...) ,blck)])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,[type-param*] ...) (,[arg*] ...) ,[type] ,[blck])
     `(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,blck)])
  (Block : Block (ir) -> Block ()
    [(block ,src ,stmt* ...)
     (let ([vars (make-hashtable symbol-hash eq?)])
       (let ([stmt* (maplr (lambda (stmt) (BlockStatement stmt vars)) stmt*)])
         (define (symbol<? x y) (string<? (symbol->string x) (symbol->string y)))
         (let ([var-name* (sort symbol<? (vector->list (hashtable-keys vars)))])
           `(block ,src (,var-name* ...) ,stmt* ...))))])
  (SingleStatement : Statement (ir vars) -> Statement ()
    [(const ,src ,var-name ,[type] ,[expr])
     (source-errorf src "const binding found in a single-statement context")]
    [(seq ,src ,stmt* ...) `(seq ,src ,(maplr (lambda (stmt) (SingleStatement stmt vars)) stmt*) ...)]
    [else (Statement ir vars)])
  (BlockStatement : Statement (ir vars) -> Statement ()
    [(const ,src ,var-name ,[type] ,[expr])
     (let ([a (hashtable-cell vars var-name #f)])
       (when (cdr a)
         (source-errorf src "found multiple bindings for ~s in the same block" var-name))
       (set-cdr! a #t))
     `(= ,src ,var-name ,type ,expr)]
    [(seq ,src ,stmt* ...) `(seq ,src ,(maplr (lambda (stmt) (BlockStatement stmt vars)) stmt*) ...)]
    [else (Statement ir vars)])
  (Statement : Statement (ir vars) -> Statement ()
    [(if ,src ,[expr] ,[SingleStatement : stmt1 vars -> stmt1] ,[SingleStatement : stmt2 vars -> stmt2]) `(if ,src ,expr ,stmt1 ,stmt2)]
    [(for ,src ,var-name ,[tsize0] ,[tsize1] ,[SingleStatement : stmt vars -> stmt])
     `(for ,src ,var-name ,tsize0 ,tsize1 ,stmt)]
    [(for ,src ,var-name ,[expr] ,[SingleStatement : stmt vars -> stmt])
     `(for ,src ,var-name ,expr ,stmt)]
    [(statement-expression ,src ,[expr]) `(statement-expression ,src ,expr)]
    [(return ,src) `(return ,src)]
    [(return ,src ,[expr]) `(return ,src ,expr)]
    [,blck (Block blck)]
    [else (assert cannot-happen)])
  (Function : Function (ir) -> Function ()
    [(circuit ,src (,[arg*] ...) ,[type] ,[blck])
     `(circuit ,src (,arg* ...) ,type ,blck)]))
