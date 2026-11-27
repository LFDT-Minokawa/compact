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
  (import (except (chezscheme) errorf) (utils))

  (define-syntax export-parameter
    (syntax-rules ()
      [(_ parameter-name default)
       (begin
         (define parameter-name (make-parameter default))
         (export parameter-name))]))

  (export-parameter no-communications-commitment #f)

  (export-parameter skip-zk #t)

  ; parallel zkir processes, or #f for automatic.  compactc reports an invalid
  ; COMPACT_ZK_JOBS; here it is ignored.
  (export-parameter zk-jobs
    (let ([s (getenv "COMPACT_ZK_JOBS")])
      (and s (let ([n (string->number s)]) (and n (fixnum? n) (fx> n 0) n)))))

  ; default source path
  (export-parameter compact-path (split-search-path (or (getenv "COMPACT_PATH") "")))

  ; formatter
  (export-parameter format-line-length 100)

  ; debugging
  (export-parameter trace-passes #f)

  (export-parameter trace-search #f)
)
