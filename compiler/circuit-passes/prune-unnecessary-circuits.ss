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

(define-pass prune-unnecessary-circuits : Lnovectorref (ir) -> Lnovectorref ()
  (definitions
    (define keepers (make-eq-hashtable)))
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
     (let ([pelt* (fold-right Program-Element '() pelt*)])
       (let-values ([(export-name* name*)
                     (let f ([export-name* export-name*] [name* name*])
                       (if (null? export-name*)
                           (values '() '())
                           (let-values ([(export-name name) (values (car export-name*) (car name*))]
                                        [(export-name* name*) (f (cdr export-name*) (cdr name*))])
                             (if (eq-hashtable-contains? keepers name)
                                 (values (cons export-name export-name*) (cons name name*))
                                 (values export-name* name*)))))])
         `(program ,src ((,export-name* ,name*) ...)
            ,pelt*
            ...)))])
  (Program-Element : Program-Element (ir pelt*) -> * (pelt*)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (if (and (id-exported? function-name)
              (guard (c [(or (eq? c 'ledger) (eq? c 'emit)) #t])
                (Expression expr)
                #f))
         (begin
           (hashtable-set! keepers function-name #t)
           (cons ir pelt*))
         pelt*)]
    [else (cons ir pelt*)])
  (Expression : Expression (ir) -> Expression ()
    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[expr*] ...)
     (raise 'ledger)]
    [(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code)
     (raise 'emit)]))
