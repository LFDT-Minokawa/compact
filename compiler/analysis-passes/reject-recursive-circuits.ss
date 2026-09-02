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

(define-pass reject-recursive-circuits : Loneledger (ir) -> Loneledger ()
  (definitions
    (define call-stack '())
    ; circuit-ht maps ids (specifically circuit names) to one of:
    ;   an Loneledger Expression (id names a circuit that has yet to be processed)
    ;   the symbol in-process (id names a circuit that is being processed)
    ;   the symbol processed (id names a circuit that has already been processed)
    (define circuit-ht (make-eq-hashtable))
    (define (process-circuit function-name)
      (let ([a (eq-hashtable-cell circuit-ht function-name 'not-a-circuit)])
        (case (cdr a)
          [(processed not-a-circuit) (void)]
          [(in-process)
           (let ([id+ (sort (lambda (id1 id2) (source-object<? (id-src id1) (id-src id2)))
                              (let f ([call-stack call-stack] [function-name^ function-name])
                                 (cons function-name^
                                      (let ([function-name^ (car call-stack)])
                                        (if (eq? function-name^ function-name)
                                            '()
                                            (f (cdr call-stack) function-name^))))))])
             (let ([id (car id+)] [id* (cdr id+)])
               (source-errorf (id-src id)
                 "recursion involving~?"
                 "~#[~; ~a~; ~a and ~a~:;~@{~#[~; and~] ~a~^,~}~]"
                 (cons (id-sym id)
                       (map (lambda (id) (format "~s at ~a" (id-sym id) (format-source-object (id-src id))))
                            id*)))))]
          [else
           (let ([expr (cdr a)])
             (set-cdr! a 'in-process)
             (fluid-let ([call-stack (cons function-name call-stack)])
               (Expression expr)
               (set-cdr! a 'processed)))])))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each record-circuit! pelt*)
     `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,(map Program-Element pelt*) ...)])
  (record-circuit! : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (eq-hashtable-set! circuit-ht function-name expr)]
    [else (void)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (process-circuit function-name)
     ir]
    [else ir])
  (Expression : Expression (ir) -> Expression ())
  (Function : Function (ir) -> Function ()
    [(fref ,src ,function-name)
     (process-circuit function-name)
     ir]))
