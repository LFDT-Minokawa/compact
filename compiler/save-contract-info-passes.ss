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

(library (save-contract-info-passes)
  (export save-contract-info-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (json)
          (langs)
          (pass-helpers))

  ; NB: must come after identify-pure-circuits
  (define-pass save-contract-info : Lnodisclose (ir) -> Lnodisclose ()
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (let ([op (get-target-port 'contract-info.json)])
         (print-json op
           (list
             (cons
               "circuits"
               (list->vector
                 (let ([export-alist (map cons export-name* name*)])
                   (fold-right
                     (lambda (pelt circuit*) (exported-circuit pelt circuit* export-alist))
                     '()
                     pelt*))))
             (cons
               "witnesses"
               (list->vector (fold-right Witness '() pelt*)))
             (cons
               "contracts"
               (list->vector (map symbol->string contract-name*))))))
       ir])
    (Witness : Program-Element (ir witness*) -> * (json)
      [(witness ,src ,function-name (,arg* ...) ,type)
       (cons
         (list
           (cons
             "name"
             (symbol->string (id-sym function-name)))
           (cons
             "arguments"
             (list->vector (map Argument arg*)))
           (cons
             "result type"
             (Type type)))
         witness*)]
      [else witness*])
    (exported-circuit : Program-Element (ir circuit* export-alist) -> * (json)
      (definitions
        (define (external-names id)
          (fold-right
            (lambda (a external-name*)
              (if (eq? (cdr a) id)
                  (cons (symbol->string (car a)) external-name*)
                  external-name*))
            '()
            export-alist)))
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (guard (id-exported? function-name))
       (fold-right
         (lambda (external-name circuit*)
           (cons
             (list
               (cons
                 "name"
                 external-name)
               (cons
                 "pure"
                 (id-pure? function-name))
               (cons
                 "arguments"
                 (list->vector (map Argument arg*)))
               (cons
                 "result-type"
                 (Type type)))
             circuit*))
         circuit*
         (external-names function-name))]
      [else circuit*])
    (Argument : Argument (ir) -> * (json)
      [(,var-name ,type)
       (list
         (cons
           "name"
           (symbol->string (id-sym var-name)))
         (cons
           "type"
           (Type type)))])
    (Type : Type (ir) -> * (datum)
      [(tboolean ,src)
       (list
         (cons "type-name" "Boolean"))]
      [(tfield ,src)
       (list
         (cons "type-name" "Field"))]
      [(tunsigned ,src ,nat)
       (list
         (cons "type-name" "Uint")
         (cons "maxval" nat))]
      [(tbytes ,src ,len)
       (list
         (cons "type-name" "Bytes")
         (cons "length" len))]
      [(topaque ,src ,opaque-type)
       (list
         (cons "type-name" "Opaque")
         (cons "tsType" opaque-type))]
      [(tvector ,src ,len ,type)
       (list
         (cons "type-name" "Vector")
         (cons "length" len)
         (cons "type" (Type type)))]
      [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
       (list
         (cons "type-name" "Contract")
         (cons "name" (symbol->string contract-name))
         (cons
           "circuits"
           (list->vector
             (map (lambda (elt-name pure-dcl type* type)
                    (list
                      (cons "name" (symbol->string elt-name))
                      (cons "pure" pure-dcl)
                      (cons
                        "argument-types"
                        (list->vector (map Type type*)))
                      (cons "result-type" (Type type))))
                  elt-name* pure-dcl* type** type*))))]
      [(ttuple ,src ,type* ...)
       (list
         (cons "type-name" "Tuple")
         (cons "types" (list->vector (map Type type*))))]
      [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
       (list
         (cons "type-name" "Struct")
         (cons "name" (symbol->string struct-name))
         (cons
           "elements"
           (list->vector
             (map (lambda (elt-name type)
                    (list
                      (cons "name" (symbol->string elt-name))
                      (cons "type" (Type type))))
                  elt-name* type*))))]
      [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
       (list
         (cons "type-name" "Enum")
         (cons "name" (symbol->string enum-name))
         (cons
           "elements"
           (list->vector (map symbol->string (cons elt-name elt-name*)))))]
      [(talias ,src ,nominal? ,type-name ,type)
       (if nominal?
           (list
             (cons "type-name" "Alias")
             (cons "name" (symbol->string type-name))
             (cons "type" (Type type)))
           (Type type))]
      [else (assert cannot-happen)]))

  (define-passes save-contract-info-passes
    (save-contract-info              Lnodisclose))
)
