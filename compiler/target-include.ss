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
;;;
;;; include-target also checks, at compile time, that the target directory exists
;;; and that the target's on-chain runtime version agrees with the
;;; @midnightntwrk/onchain-runtime-v<N> dependency of runtime/package.json.

(library (target-include)
  (export target-pathname include-target)
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
             #'(inc path)))]))))
