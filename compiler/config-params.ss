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

(library (config-params)
  (export)
  (import (chezscheme))

  (define-syntax export-parameter
    (syntax-rules ()
      [(_ parameter-name default)
       (begin
         (define parameter-name (make-parameter default))
         (export parameter-name))]))

  (export-parameter no-communications-commitment #f)

  (export-parameter skip-zk #t)

  ; default source path
  (export-parameter compact-path
    (let ()
      (define (split-search-path str)
        (let ([n (string-length str)])
          (let f ([i 0] [j 0])
            (if (fx= j n)
                (if (fx= i j) '() (list (substring str i j)))
                (if (char=? (string-ref str j) (if (directory-separator? #\\) #\; #\:))
                    (cons (substring str i j) (f (fx+ j 1) (fx+ j 1)))
                    (f i (fx+ j 1)))))))
      (split-search-path (or (getenv "COMPACT_PATH") ""))))

  ; formatter
  (export-parameter format-line-length 100)

  ; debugging
  (export-parameter trace-passes #f)

  ; feature flags
  (export-parameter zkir-v3 #f)
)
