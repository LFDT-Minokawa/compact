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

(define-pass drop-ledger-runtime : Lloweredemit (ir) -> Lposttypescript ()
  (Program : Program (ir) -> Program ()
    [(program ,src (,contract-type* ...) ((,export-name* ,name*) ...) ,pelt* ...)
     `(program ,src ((,export-name* ,name*) ...)
        ,(fold-right
           (lambda (pelt pelt*)
             (if (Lloweredemit-Export-Type-Definition? pelt)
                 pelt*
                 (cons (Program-Element pelt) pelt*)))
           '()
           pelt*)
        ...)])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [,export-tdefn (assert cannot-happen)])
  (Expression : Expression (ir) -> Expression ()
    (definitions
      (define (do-not src expr)
        (with-output-language (Lposttypescript Expression)
          `(if ,src ,expr (quote ,src #f) (quote ,src #t))))
      )
    [(elt-ref ,src ,[expr] ,elt-name ,nat) `(elt-ref ,src ,expr ,elt-name)]
    [(return ,src ,[expr]) expr]
    [(<= ,src ,bits ,[expr1] ,[expr2]) (do-not src `(< ,src ,bits ,expr2 ,expr1))]
    [(> ,src ,bits ,[expr1] ,[expr2]) `(< ,src ,bits ,expr2 ,expr1)]
    [(>= ,src ,bits ,[expr1] ,[expr2]) (do-not src `(< ,src ,bits ,expr1 ,expr2))]
    [(!= ,src ,[type] ,[expr1] ,[expr2]) (do-not src `(== ,src ,type ,expr1 ,expr2))]
    [(cast-from-bytes ,src ,[type] ,len ,[expr])
     ;; The target `type` should be an unsigned integer type, the native field type, or one of the
     ;; secp256k1 field types.
     (nanopass-case (Lposttypescript Type) type
       [(tunsigned ,src ,nat)
        (let ([native (with-output-language (Lposttypescript Field-Type) `(field-native))])
          `(cast-from-field ,src ,nat ,native (bytes->field ,src ,native ,len ,expr)))]
       [(tfield ,src ,ftype)
        (guard (nanopass-case (Lposttypescript Field-Type) ftype
                 [(field-native) #t]
                 [(field-base (curve-secp256k1)) #t]
                 [(field-scalar (curve-secp256k1)) #t]
                 [else #f]))
        `(bytes->field ,src ,ftype ,len ,expr)]
       [else (assert cannot-happen)])])
  (Type : Type (ir) -> Type ()
    [,tvar-name (assert cannot-happen)]
    [(tadt ,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op*] ...) (,adt-rt-op* ...))
     `(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))]
    [(talias ,src ,nominal? ,type-name ,[type]) type]))
