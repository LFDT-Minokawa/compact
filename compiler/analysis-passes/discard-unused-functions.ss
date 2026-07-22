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

(define-pass discard-unused-functions : Loneledger (ir) -> Loneledger ()
  (definitions
    (define worklist)
    (define deferred-ht (make-eq-hashtable))
    (define-record-type ipelt (nongenerative) (fields index pelt))
    (define (ipelt<? ipelt1 ipelt2) (fx<? (ipelt-index ipelt1) (ipelt-index ipelt2)))
    (define (ipelt->function-name ipelt)
      (nanopass-case (Loneledger Program-Element) (ipelt-pelt ipelt)
        [(circuit ,src ,function-name (,arg* ...) ,type ,expr) function-name]
        [(native ,src ,function-name ,native-entry (,arg* ...) ,type) function-name]
        [(witness ,src ,function-name (,arg* ...) ,type) function-name]
        [else #f]))
    (define (exported? ipelt)
      (let ([id (ipelt->function-name ipelt)])
        (or (not id) (id-exported? id)))))
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (let-values ([(exported* nonexported*) (partition exported? (map make-ipelt (enumerate pelt*) pelt*))])
       (for-each
         (lambda (ipelt) (hashtable-set! deferred-ht (ipelt->function-name ipelt) ipelt))
         nonexported*)
       (fluid-let ([worklist exported*])
         (let loop ([keep* '()])
           (if (null? worklist)
               `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,(map ipelt-pelt (sort ipelt<? keep*)) ...)
               (let ([ipelt (car worklist)])
                 (set! worklist (cdr worklist))
                 (loop (cons (make-ipelt (ipelt-index ipelt) (Program-Element (ipelt-pelt ipelt))) keep*)))))))])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Function : Function (ir) -> Function ()
    [(fref ,src ,function-name)
     (cond
       [(hashtable-ref deferred-ht function-name #f) =>
        (lambda (ipelt)
          (hashtable-delete! deferred-ht function-name)
          (set! worklist (cons ipelt worklist)))])
     ir]))
