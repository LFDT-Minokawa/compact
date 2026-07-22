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
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,blck)
     (Block blck #t)]
    [(constructor ,src (,arg* ...) ,blck)
     (Block blck #t)]
    [else (void)])
  (Block : Block (ir [reachable? #t]) -> * (reachable?)
    [(block ,src ,stmt* ...)
     (unless reachable? (unreachable src))
     (fold-left (lambda (reachable? stmt) (Statement stmt reachable?)) #t stmt*)])
  (Statement : Statement (ir [reachable? #t]) -> * (reachable?)
    [(statement-expression ,src ,[expr])
     (unless reachable? (unreachable src))
     #t]
    [(const ,src ,var-name ,type ,[expr])
     (unless reachable? (unreachable src))
     #t]
    [(for ,src ,var-name ,tsize0 ,tsize1 ,stmt)
     (unless reachable? (unreachable src))
     (Statement stmt #t)]
    [(for ,src ,var-name ,[expr] ,stmt)
     (unless reachable? (unreachable src))
     (Statement stmt #t)]
    [(return ,src ,[expr])
     (unless reachable? (unreachable src))
     #f]
    [(return ,src)
     (unless reachable? (unreachable src))
     #f]
    [(if ,src ,[expr] ,stmt1 ,stmt2)
     (unless reachable? (unreachable src))
     (or (Statement stmt1 #t) (Statement stmt2 #t))]
    [(seq ,src ,stmt* ...)
     (unless reachable? (unreachable src))
     (fold-left (lambda (reachable? stmt) (Statement stmt reachable?)) #t stmt*)]
    [,blck (Block blck reachable?)])
  (Function : Function (ir) -> Function ()
    [(circuit ,src (,arg* ...) ,type ,blck)
     (Block blck #t)
     ir]
    [else ir]))
