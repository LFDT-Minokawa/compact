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

;;; Resolves target-dependent files through the directory of the current target.
;;; The target-dependent files live in compiler/targets/<target>/.
;;;
;;;   (target-pathname "f")  -- the pathname of f in the target directory.
;;;   (include-target "f")   -- like (include "f"), but f is in the target directory.
;;;   (available-targets)    -- the names of the targets, i.e., the directories of
;;;                             compiler/targets/ when the compiler is built, sorted.
;;;
;;; include-target also checks, at compile time, that the target directory on the
;;; library path is the one named by current-target.ss (and exists), and that the
;;; target's on-chain runtime version agrees with the
;;; @midnightntwrk/onchain-runtime-v<N> dependency of runtime/package.json.
;;; available-targets checks that every directory is named like a target.  (The
;;; name and versions of the current target are those of its directory, see
;;; target-directory.ss, so the directory check of include-target only fails for
;;; an object file of another target that is being reused.)

(library (target-include)
  (export target-pathname include-target available-targets)
  (import (chezscheme)
          (for (target) run expand)
          (for (current-target) run expand))

  (define (target-pathname name)
    (string-append "compiler/targets/" (target-name current-target) "/" name))

  (define-syntax include-target
    (lambda (x)
      (define package-json "runtime/package.json")
      (define (path name)
        (string-append "compiler/targets/" (target-name current-target) "/" name))
      (define (contains? str sub)
        (let ([n (string-length str)] [m (string-length sub)])
          (let loop ([i 0])
            (and (fx<= (fx+ i m) n)
                 (or (string=? (substring str i (fx+ i m)) sub)
                     (loop (fx+ i 1)))))))
      (define (validate-target! who)
        ;; The record of the current target is made from the name of its directory,
        ;; so the directory on the library path and the name of the record can only
        ;; differ when the compiled (current-target) library is the one of another
        ;; target, i.e., object files of that target are being reused.
        (let* ([prefix "compiler/targets/"]
               [dir* (filter
                       (lambda (d)
                         (and (fx>= (string-length d) (string-length prefix))
                              (string=? (substring d 0 (string-length prefix)) prefix)))
                       (map car (library-directories)))])
          (unless (member (string-append prefix (target-name current-target)) dir*)
            (syntax-error who
              (format "the target directory on the library path is ~a but the compiled current-target library is the one of target ~a: object files of another target are being reused; remove the object directory (obj/, e.g. with ./clean.sh, or use ./compiler/go --rebuild) and build again"
                (if (null? dir*) "none" (car dir*))
                (target-name current-target)))))
        (let ([dir (path "")])
          (unless (file-directory? dir)
            (syntax-error who (format "target directory ~a does not exist" dir))))
        (let* ([v (target-onchain-runtime-version current-target)]
               [major (let loop ([i 0])
                        (if (or (fx= i (string-length v)) (char=? (string-ref v i) #\.))
                            (substring v 0 i)
                            (loop (fx+ i 1))))]
               [dependency (string-append "@midnightntwrk/onchain-runtime-v" major "\"")])
          (#%$require-include package-json)
          (unless (contains? (call-with-input-file package-json get-string-all) dependency)
            (syntax-error who
              (format "target ~a expects on-chain runtime ~a but ~a does not depend on ~a"
                (target-name current-target) v package-json
                (substring dependency 0 (fx- (string-length dependency) 1)))))))
      (syntax-case x ()
        [(k name)
         (string? (syntax->datum #'name))
         (begin
           (validate-target! x)
           (with-syntax ([inc (datum->syntax #'k 'include)]
                         [path (datum->syntax #'k (path (syntax->datum #'name)))])
             #'(inc path)))])))

  ;; Read when the library that uses this is compiled, so the list is the
  ;; directories of compiler/targets/ of that build.
  (define-syntax available-targets
    (lambda (x)
      (syntax-case x ()
        [(k)
         (let ([name* (sort string<?
                        (filter
                          (lambda (name) (file-directory? (string-append "compiler/targets/" name)))
                          (directory-list "compiler/targets")))])
           (for-each
             (lambda (name)
               (unless (parse-target-name name)
                 (syntax-error x
                   (format "compiler/targets/~a is not named like a target, ocrt-<major>_<minor>-zkir-<major>_<minor>" name))))
             name*)
           (with-syntax ([(name ...) (datum->syntax #'k name*)])
             #'(quote (name ...))))]))))
