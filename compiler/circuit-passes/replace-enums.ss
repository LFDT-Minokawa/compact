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

(define-pass replace-enums : Lposttypescript (ir) -> Lnoenums ()
  (Expression : Expression (ir) -> Expression ()
    [(enum-ref ,src ,type ,elt-name^)
     (nanopass-case (Lposttypescript Type) type
       [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
        (let ([maxval (length elt-name*)])
          (let loop ([elt-name elt-name] [elt-name* elt-name*] [i 0])
            (if (eq? elt-name elt-name^)
                (if (= i maxval)
                    `(quote ,src ,i)
                    `(safe-cast ,src (tunsigned ,src ,maxval) (tunsigned ,src ,i) (quote ,src ,i)))
                (begin
                  (assert (not (null? elt-name*)))
                  (loop (car elt-name*) (cdr elt-name*) (fx+ i 1))))))]
       [else (assert cannot-happen)])]
    [(cast-from-enum ,src ,[type] ,[type^] ,[expr])
     (nanopass-case (Lnoenums Type) type
       [(tfield ,src^ ,ftype) `(safe-cast ,src ,type ,type^ ,expr)]
       [(tunsigned ,src^ ,nat)
        (let ([maxval (nanopass-case (Lnoenums Type) type^
                        [(tunsigned ,src ,nat) nat]
                        [else (assert cannot-happen)])])
          (cond
            [(> nat maxval) `(safe-cast ,src ,type ,type^ ,expr)]
            [(< nat maxval) `(downcast-unsigned ,src ,maxval ,nat ,expr)]
            [else expr]))]
       [else (assert cannot-happen)])]
    [(cast-to-enum ,src ,[type] ,[type^] ,[expr])
     (let ([maxval (nanopass-case (Lnoenums Type) type
                     [(tunsigned ,src ,nat) nat]
                     [else (assert cannot-happen)])])
       (nanopass-case (Lnoenums Type) type^
         [(tfield ,src^ ,ftype)
          `(cast-from-field ,src ,maxval
             ,(with-output-language (Lnoenums Field-Type) `(field-native))
             ,expr)]
         [(tunsigned ,src^ ,nat)
          (cond
            [(> nat maxval) `(downcast-unsigned ,src ,nat ,maxval ,expr)]
            [(< nat maxval) `(safe-cast ,src ,type ,type^ ,expr)]
            [else expr])]
         [else (assert cannot-happen)]))])
  (Type : Type (ir) -> Type ()
    [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
     (let ([maxval (length elt-name*)])
       `(tunsigned ,src ,maxval))]))
