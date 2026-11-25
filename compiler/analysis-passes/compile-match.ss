;;; This file is part of Compact.
;;; Copyright (C) 2026 Minokawa project contributors
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

;;; compile-match replaces each match by a chain of conditionals, first arm first.
;;; An arm's condition is the conjunction of the variant tests its pattern requires,
;;; and its bindings read fields only where those tests hold.  infer-types has checked
;;; that the arms are exhaustive, so the last arm needs no condition for a valid value.
;;; A value read from the ledger is not known to be valid, however, and one whose tag
;;; names no variant would be taken by whichever arm is written last, so the last arm
;;; asserts those of its tests that such a tag fails.

(define-pass compile-match : Ltypes (ir) -> Lnomatch ()
  (definitions
    ; returns the tests a value must pass to match mpattern and the bindings it then
    ; makes, both in pattern order; expr yields the value and is duplicated freely.
    ; A test is paired with #t when a tag that names no variant fails it, which a
    ; Boolean tag cannot do.
    (define (pattern-tests+bindings src mpattern expr)
      (with-output-language (Lnomatch Expression)
        (let f ([mpattern mpattern] [expr expr])
          (nanopass-case (Ltypes Match-Pattern) mpattern
            [(mwild ,src^) (values '() '())]
            [(mbind ,src^ ,var-name ,[Type : type])
             (values '() (list (cons (with-output-language (Lnomatch Argument) `(,var-name ,type)) expr)))]
            [(mvariant ,src^ ,[Type : type] ,elt-name ,mpattern* ...)
             (let-values ([(test* binding*)
                           (f* f mpattern*
                             (map (lambda (i) `(variant-field ,src ,type ,expr ,elt-name ,i))
                                  (enumerate mpattern*)))])
               (values
                 (cons (cons `(variant-test ,src ,type ,expr ,elt-name)
                             (nanopass-case (Lnomatch Type) type
                               [(tsum ,src^ ,enum-name ,ledger-layout? (,elt-name* ,type** ...) ...)
                                (fx> (length elt-name*) 2)]
                               [else (assert cannot-happen)]))
                       test*)
                 binding*))]
            [(menum ,src^ ,[Type : type] ,elt-name)
             (values (list (cons `(== ,src ,type ,expr (enum-ref ,src ,type ,elt-name)) #t)) '())]
            [(mtuple ,src^ ,type ,mpattern* ...)
             (f* f mpattern*
               (map (lambda (i) `(tuple-ref ,src ,expr ,i)) (enumerate mpattern*)))]
            [(mstruct ,src^ ,type (,elt-name* ,nat* ,mpattern*) ...)
             (f* f mpattern*
               (map (lambda (elt-name nat) `(elt-ref ,src ,expr ,elt-name ,nat)) elt-name* nat*))]))))
    (define (f* f mpattern* expr*)
      (if (null? mpattern*)
          (values '() '())
          (let*-values ([(test1* binding1*) (f (car mpattern*) (car expr*))]
                        [(test2* binding2*) (f* f (cdr mpattern*) (cdr expr*))])
            (values (append test1* test2*) (append binding1* binding2*)))))
    (define (conjunction src test*)
      (with-output-language (Lnomatch Expression)
        (if (null? (cdr test*))
            (car test*)
            `(if ,src ,(car test*) ,(conjunction src (cdr test*)) (quote ,src #f)))))
    ; the tests of test* through the last one that an invalid tag fails: a test of a
    ; field is meaningful only under the tests before it, so those are kept
    (define (tests-through-last-strict test*)
      (if (ormap cdr test*)
          (cons (caar test*) (tests-through-last-strict (cdr test*)))
          '()))
    )
  (Type : Type (ir) -> Type ())
  (Expression : Expression (ir) -> Expression ()
    [(match ,src ,[type] ,[expr] (,mpattern* ,[expr*]) ...)
     (let ([t (make-temp-id src 't)])
       `(let* ,src ([(,t ,type) ,expr])
          ,(let f ([mpattern* mpattern*] [expr* expr*])
             (let-values ([(test* binding*) (pattern-tests+bindings src (car mpattern*) `(var-ref ,src ,t))])
               (let ([arm (if (null? binding*)
                              (car expr*)
                              `(let* ,src ([,(map car binding*) ,(map cdr binding*)] ...) ,(car expr*)))])
                 (cond
                   [(null? test*) arm]
                   [(null? (cdr mpattern*))
                    (let ([test* (tests-through-last-strict test*)])
                      (if (null? test*)
                          arm
                          `(seq ,src
                             (assert ,src ,(conjunction src test*) "match on an invalid enum value")
                             ,arm)))]
                   [else `(if ,src ,(conjunction src (map car test*)) ,arm ,(f (cdr mpattern*) (cdr expr*)))]))))))]))
