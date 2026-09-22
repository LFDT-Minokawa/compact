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

;; The `local` forms have layout but no code generation, therefore this pass
;; rejects them with a clear error rather than letting a later pass choke.  A
;; local-store `public-ledger` operation implies a local declaration, therefore
;; rejecting the package covers the operations too.
(define-pass reject-local-declarations : Lwithpaths (ir) -> Lnolocal ()
  (definitions
    (define (first-binding-src pl-array)
      (nanopass-case (Lwithpaths Public-Ledger-Array) pl-array
        [(public-ledger-array ,pl-array-elt* ...)
         (let loop ([pl-array-elt* pl-array-elt*])
           (if (null? pl-array-elt*)
               #f
               (nanopass-case (Lwithpaths Public-Ledger-Array-Element) (car pl-array-elt*)
                 [,pl-array (or (first-binding-src pl-array) (loop (cdr pl-array-elt*)))]
                 [,public-binding
                  (nanopass-case (Lwithpaths Public-Ledger-Binding) public-binding
                    [(,src ,ledger-field-name (,path-index* ...) ,type) src])])))])))
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
    [(local-ledger-declaration ,pl-array ,lconstructor)
     (cond
       [(first-binding-src pl-array) =>
        (lambda (src) (source-errorf src "local declarations are not yet implemented"))]
       [else (Ledger-Constructor lconstructor)])])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(local-constructor ,src ,expr)
     (source-errorf src "the local constructor is not yet implemented")])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(local-circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (source-errorf src "local functions are not yet implemented")]))
