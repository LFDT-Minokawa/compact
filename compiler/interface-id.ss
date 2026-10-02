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

;;; A host interface id names a runtime-provided interface the way the WebAssembly component
;;; model's interface language names one: `namespace:package/name`, each a kebab-case label,
;;; with an optional `@` and a Semantic Versioning 2.0 version.  The lexer validates the
;;; shape; the id travels through the compiler as its text.
(library (interface-id)
  (export interface-id-char? interface-id-initial? interface-id-parts)
  (import (chezscheme))

  (define (interface-id-initial? c)
    (and (char? c) (or (char<=? #\a c #\z) (char<=? #\A c #\Z))))

  (define (interface-id-char? c)
    (and (char? c)
         (or (char<=? #\a c #\z)
             (char<=? #\A c #\Z)
             (char<=? #\0 c #\9)
             (memv c '(#\- #\: #\/ #\@ #\. #\+)))))

  ;; split s at every occurrence of the character c
  (define (split s c)
    (let loop ([i 0] [start 0] [acc '()])
      (cond
        [(fx= i (string-length s)) (reverse (cons (substring s start i) acc))]
        [(char=? (string-ref s i) c) (loop (fx+ i 1) (fx+ i 1) (cons (substring s start i) acc))]
        [else (loop (fx+ i 1) start acc)])))

  (define (all? pred s)
    (let loop ([i 0])
      (or (fx= i (string-length s))
          (and (pred (string-ref s i)) (loop (fx+ i 1))))))

  ;; a word is all lowercase or all uppercase letters and digits, starting with a letter
  (define (word? s)
    (and (fx> (string-length s) 0)
         (let ([c (string-ref s 0)])
           (cond
             [(char<=? #\a c #\z) (all? (lambda (c) (or (char<=? #\a c #\z) (char<=? #\0 c #\9))) s)]
             [(char<=? #\A c #\Z) (all? (lambda (c) (or (char<=? #\A c #\Z) (char<=? #\0 c #\9))) s)]
             [else #f]))))

  ;; a label is words joined by single hyphens
  (define (label? s)
    (let ([word* (split s #\-)])
      (and (pair? word*) (andmap word? word*))))

  (define (numeric? s)
    (and (fx> (string-length s) 0)
         (all? (lambda (c) (char<=? #\0 c #\9)) s)
         (or (string=? s "0") (not (char=? (string-ref s 0) #\0)))))

  (define (semver-ident? s)
    (and (fx> (string-length s) 0)
         (all? (lambda (c) (or (char<=? #\a c #\z) (char<=? #\A c #\Z) (char<=? #\0 c #\9) (char=? c #\-))) s)))

  ;; a prerelease identifier is numeric without leading zeros, or alphanumeric
  (define (prerelease-ident? s)
    (and (semver-ident? s)
         (or (not (all? (lambda (c) (char<=? #\0 c #\9)) s)) (numeric? s))))

  (define (dotted? s ident?)
    (let ([ident* (split s #\.)])
      (and (pair? ident*) (andmap ident? ident*))))

  ;; Semantic Versioning 2.0: major.minor.patch, then an optional -prerelease, then an
  ;; optional +build
  (define (semver? s)
    (let* ([plus (split s #\+)]
           [core+pre (car plus)]
           [build* (cdr plus)])
      (and (fx<= (length build*) 1)
           (or (null? build*) (dotted? (car build*) semver-ident?))
           (let* ([i (let loop ([i 0])
                       (cond
                         [(fx= i (string-length core+pre)) #f]
                         [(char=? (string-ref core+pre i) #\-) i]
                         [else (loop (fx+ i 1))]))]
                  [core (if i (substring core+pre 0 i) core+pre)]
                  [pre (and i (substring core+pre (fx+ i 1) (string-length core+pre)))])
             (and (let ([num* (split core #\.)])
                    (and (fx= (length num*) 3) (andmap numeric? num*)))
                  (or (not pre) (dotted? pre prerelease-ident?)))))))

  ;; the parts of a well-formed id as the list (namespace package name version), version #f
  ;; when absent; #f for a malformed one
  (define (interface-id-parts s)
    (let* ([at* (split s #\@)]
           [path (car at*)]
           [version (and (pair? (cdr at*)) (cadr at*))])
      (if (or (fx> (length at*) 2)
              (and version (not (semver? version))))
          #f
          (let ([colon* (split path #\:)])
            (if (not (fx= (length colon*) 2))
                #f
                (let ([namespace (car colon*)]
                      [slash* (split (cadr colon*) #\/)])
                  (if (and (fx= (length slash*) 2)
                           (label? namespace)
                           (label? (car slash*))
                           (label? (cadr slash*)))
                      (list namespace (car slash*) (cadr slash*) version)
                      #f))))))))
