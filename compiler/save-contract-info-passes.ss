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
          (compiler-version)
          (language-version)
          (runtime-version)
          (pass-helpers))

  ; NB: must come after identify-pure-circuits
  (define-pass save-contract-info : Lnodisclose (ir proof-circuit-name*) -> Lnodisclose ()
    (definitions
      ; Map an ADT name symbol to its storage-kind string for the "storage" key.
      (define (adt-name->storage-kind adt-name)
        (cond
          [(or (eq? adt-name '__compact_Cell) (eq? adt-name 'Cell)) "cell"]
          [(eq? adt-name 'Counter)                                   "counter"]
          [(eq? adt-name 'Set)                                       "set"]
          [(eq? adt-name 'Map)                                       "map"]
          [(eq? adt-name 'List)                                      "list"]
          [(eq? adt-name 'MerkleTree)                                "merkle-tree"]
          [(eq? adt-name 'HistoricMerkleTree)                        "historic-merkle-tree"]
          [else                                                       (symbol->string adt-name)]))
      ; Serialize one adt-arg (Public-Ledger-ADT-Arg: nat or type).
      (define (adt-arg->json adt-arg)
        (nanopass-case (Lnodisclose Public-Ledger-ADT-Arg) adt-arg
          [,nat  nat]
          [,type (Type type)]))
      ; Return the ADT-specific key-value pairs for a given ADT name and its args.
      (define (adt-fields->json adt-name adt-arg*)
        (cond
          [(or (eq? adt-name '__compact_Cell) (eq? adt-name 'Cell))
           (assert (= (length adt-arg*) 1))
           (list (cons "type" (adt-arg->json (car adt-arg*))))]
          [(eq? adt-name 'Counter)
           '()]
          [(eq? adt-name 'Set)
           (assert (= (length adt-arg*) 1))
           (list (cons "element-type" (adt-arg->json (car adt-arg*))))]
          [(eq? adt-name 'Map)
           (assert (= (length adt-arg*) 2))
           (list
             (cons "key-type"   (adt-arg->json (car adt-arg*)))
             (cons "value-type" (adt-arg->json (cadr adt-arg*))))]
          [(or (eq? adt-name 'MerkleTree) (eq? adt-name 'HistoricMerkleTree))
           (assert (= (length adt-arg*) 2))
           (list
             (cons "size"         (adt-arg->json (car adt-arg*)))
             (cons "element-type" (adt-arg->json (cadr adt-arg*))))]
          [(eq? adt-name 'List)
           (assert (= (length adt-arg*) 1))
           (list (cons "element-type" (adt-arg->json (car adt-arg*))))]
          [else '()]))
      ; Flatten a nested Public-Ledger-Array into a flat list of Public-Ledger-Bindings.
      (define (pl-array->bindings pl-array)
        (let loop ([pla pl-array] [acc '()])
          (nanopass-case (Lnodisclose Public-Ledger-Array) pla
            [(public-ledger-array ,pl-array-elt* ...)
             (fold-right
               (lambda (elt acc)
                 (nanopass-case (Lnodisclose Public-Ledger-Array-Element) elt
                   [,pl-array    (loop pl-array acc)]
                   [,public-binding (cons public-binding acc)]))
               acc
               pl-array-elt*)])))
      ; Serialize one Public-Ledger-Binding to a JSON object.
      (define (ledger-binding->json public-binding)
        (nanopass-case (Lnodisclose Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,type)
           (let* ([name-str   (symbol->string (id-sym ledger-field-name))]
                  [index-val  (if (= (length path-index*) 1)
                                  (car path-index*)
                                  (list->vector path-index*))]
                  ; Peel off any non-nominal talias wrappers to expose the tadt.
                  [inner-type (let peel ([t type])
                                (nanopass-case (Lnodisclose Type) t
                                  [(talias ,src ,nominal? ,type-name ,wrapped)
                                   (if nominal? t (peel wrapped))]
                                  [else t]))])
             (nanopass-case (Lnodisclose Type) inner-type
               [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                (append
                  (list
                    (cons "name"    name-str)
                    (cons "index"   index-val)
                    (cons "storage" (adt-name->storage-kind adt-name)))
                  (adt-fields->json adt-name adt-arg*))]
               [else (assert cannot-happen)]))])))
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       (let ([op (get-target-port 'contract-info.json)])
         (print-json op
           (list
             (cons
               "compiler-version"
               compiler-version-string)
             (cons
               "language-version"
               language-version-string)
             (cons
               "runtime-version"
               runtime-version-string)
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
               (list->vector (map symbol->string contract-name*)))
             (cons
               "ledger"
               (list->vector (fold-right Ledger '() pelt*))))))
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
    (Ledger : Program-Element (ir ledger*) -> * (json)
      [(public-ledger-declaration ,pl-array ,lconstructor)
       (fold-right
         (lambda (pb ledger*) (cons (ledger-binding->json pb) ledger*))
         ledger*
         (pl-array->bindings pl-array))]
      [else ledger*])
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
                 "proof"
                 (and (memq (id-sym function-name) proof-circuit-name*) #t))
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
      [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
       ; ADT types can appear as value types inside ledger ADT args (e.g. Map<F, Map<F,V>>).
       (append
         (list (cons "type-name" (adt-name->storage-kind adt-name)))
         (adt-fields->json adt-name adt-arg*))]
      [else (assert cannot-happen)]))

  (define-passes save-contract-info-passes
    (save-contract-info              Lnodisclose))
)
