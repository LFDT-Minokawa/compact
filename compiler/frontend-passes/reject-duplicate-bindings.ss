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

(define-pass reject-duplicate-bindings : Lhoisted (ir) -> Lhoisted ()
  (definitions
    (define reject-duplicate!
      (let ([ht (make-hashtable symbol-hash eq?)])
        (lambda (src what sym*)
          (hashtable-clear! ht)
          (for-each
            (lambda (sym)
              (let ([a (hashtable-cell ht sym #f)])
                (when (cdr a) (source-errorf src "duplicate ~a ~s" what sym))
                (set-cdr! a #t)))
            sym*))))
    (define (arg->sym arg)
      (nanopass-case (Lhoisted Argument) arg
        [(,src ,var-name ,type) var-name]))
    (define (type-param->tvar-name type-param)
      (nanopass-case (Lhoisted Type-Param) type-param
        [(nat-valued ,src ,tvar-name) tvar-name]
        [(type-valued ,src ,tvar-name) tvar-name]))
    )
  (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
    [(witness ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
     (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
     (reject-duplicate! src "parameter name" (map arg->sym arg*))
     ir])
  (Module-Definition : Module-Definition (ir) -> Module-Definition ()
    [(module ,src ,exported? ,module-name (,type-param* ...) ,[pelt*] ...)
     (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
     ir])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,[blck])
     (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
     (reject-duplicate! src "parameter name" (map arg->sym arg*))
     ir])
  (Structure-Definition : Structure-Definition (ir) -> Structure-Definition ()
    [(struct ,src ,exported? ,struct-name (,type-param* ...) ,arg* ...)
     (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
     (reject-duplicate! src "field name" (map arg->sym arg*))
     ir])
  (Enum-Definition : Enum-Definition (ir) -> Enum-Definition ()
    [(enum ,src ,exported? ,enum-name ,elt-name ,elt-name* ...)
     (reject-duplicate! src "element name" (cons elt-name elt-name*))
     ir])
  (Type-Definition : Type-Definition (ir) -> Type-Definition ()
    [(typedef ,src ,exported? ,nominal? ,type-name (,type-param* ...) ,type)
     (reject-duplicate! src "generic parameter name" (map type-param->tvar-name type-param*))
     ir])
  (Function : Function (ir) -> Function ()
    [(circuit ,src (,arg* ...) ,type ,[blck])
     (reject-duplicate! src "parameter name" (map arg->sym arg*))
     ir]))
