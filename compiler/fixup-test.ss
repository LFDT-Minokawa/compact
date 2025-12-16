#!chezscheme

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

(library (fixup-test)
  (export fixup-testing-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (langs)
          (parser)
          (fixup)
          (pass-helpers))

  (define (parse-file/fixup/format/reparse pathname)
    (let* ([op (get-target-port 'fixup-output.compact)]
           [fixup-pathname (port-name op)])
      (put-string op (parse-file/fixup/format pathname))
      (flush-output-port op)
      (parse-file fixup-pathname)))

  (define-passes fixup-testing-passes
    (parse-file/fixup/format/reparse Lsrc))
)
