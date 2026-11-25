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

;;; Coverage of match arms, after Maranget, "Warnings for Pattern Matching" (JFP 2007).
;;; A coverage pattern is the symbol _ or a cpat: a constructor applied to coverage
;;; patterns.  A constructor knows its siblings, i.e., every constructor of its type
;;; including itself, so the code here needs no types: a variant's siblings are its
;;; enum's variants, and a tuple or struct constructor is its own only sibling.
;;; A row is a list of coverage patterns, one per column.

(module (make-ctor ctor-siblings-set! make-cpat match-row-useful? match-missing-rows format-coverage-pattern)
  (define-record-type ctor
    (nongenerative)
    ; format maps the formatted arguments to the formatted pattern
    (fields name arity (mutable siblings) format))
  (define-record-type cpat
    (nongenerative)
    (fields ctor arg*))
  (define max-missing-rows 4)
  (define (wildcards n) (make-list n '_))
  (define (same-ctor? ctor1 ctor2) (eq? (ctor-name ctor1) (ctor-name ctor2)))
  (define (head-ctors row*)
    (fold-right
      (lambda (row ctor*)
        (let ([x (car row)])
          (if (and (cpat? x) (not (memp (lambda (ctor) (same-ctor? ctor (cpat-ctor x))) ctor*)))
              (cons (cpat-ctor x) ctor*)
              ctor*)))
      '()
      row*))
  (define (complete? ctor*)
    (and (not (null? ctor*))
         (fx= (length ctor*) (length (ctor-siblings (car ctor*))))))
  (define (specialize ctor row*)
    (fold-right
      (lambda (row row*)
        (let ([x (car row)])
          (cond
            [(eq? x '_) (cons (append (wildcards (ctor-arity ctor)) (cdr row)) row*)]
            [(same-ctor? (cpat-ctor x) ctor) (cons (append (cpat-arg* x) (cdr row)) row*)]
            [else row*])))
      '()
      row*))
  (define (default row*)
    (fold-right
      (lambda (row row*) (if (eq? (car row) '_) (cons (cdr row) row*) row*))
      '()
      row*))
  ; true when some value matches row and none of row*
  (define (match-row-useful? row* row)
    (cond
      [(null? row) (null? row*)]
      [(cpat? (car row))
       (let ([ctor (cpat-ctor (car row))])
         (match-row-useful? (specialize ctor row*) (append (cpat-arg* (car row)) (cdr row))))]
      [else
       (let ([ctor* (head-ctors row*)])
         (if (complete? ctor*)
             (ormap (lambda (ctor)
                      (match-row-useful? (specialize ctor row*)
                        (append (wildcards (ctor-arity ctor)) (cdr row))))
                    (ctor-siblings (car ctor*)))
             (match-row-useful? (default row*) (cdr row))))]))
  (define (list-head-upto ls n)
    (if (or (null? ls) (fx= n 0)) '() (cons (car ls) (list-head-upto (cdr ls) (fx- n 1)))))
  ; returns rows of n patterns that together describe values no row of row* matches,
  ; at most max-missing-rows of them, and none when row* is exhaustive
  (define (match-missing-rows row* n)
    (if (fx= n 0)
        (if (null? row*) '(()) '())
        (let ([ctor* (head-ctors row*)])
          (define (applied ctor row*)
            (map (lambda (row)
                   (let ([arity (ctor-arity ctor)])
                     (cons (make-cpat ctor (list-head row arity)) (list-tail row arity))))
                 row*))
          (list-head-upto
            (if (complete? ctor*)
                (apply append
                  (map (lambda (ctor)
                         (applied ctor
                           (match-missing-rows (specialize ctor row*) (fx+ (ctor-arity ctor) (fx- n 1)))))
                       (ctor-siblings (car ctor*))))
                (let ([rest* (match-missing-rows (default row*) (fx- n 1))])
                  (if (null? ctor*)
                      (map (lambda (rest) (cons '_ rest)) rest*)
                      (apply append
                        (map (lambda (ctor)
                               (map (lambda (rest) (cons (make-cpat ctor (wildcards (ctor-arity ctor))) rest))
                                    rest*))
                             (remp (lambda (ctor) (memp (lambda (ctor^) (same-ctor? ctor ctor^)) ctor*))
                                   (ctor-siblings (car ctor*))))))))
            max-missing-rows))))
  (define (format-coverage-pattern x)
    (if (eq? x '_)
        "_"
        ((ctor-format (cpat-ctor x)) (map format-coverage-pattern (cpat-arg* x)))))
  )
