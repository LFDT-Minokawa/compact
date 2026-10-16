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

;;; Makes the record of a target from the name of its directory.
;;;
;;;   (make-target-here ledger-version)
;;;
;;; is the record for the target whose directory, compiler/targets/<target>/, is on
;;; the library path while the library it is used in is compiled.
;;; It is an error for no directory, or more than one, of
;;; compiler/targets/ to be on the library path, and for the directory not to be
;;; named ocrt-<major>_<minor>-zkir-<major>_<minor>.

(library (target-directory)
  (export make-target-here)
  (import (chezscheme)
          (for (target) run expand))

  (define-syntax make-target-here
    (lambda (x)
      (define prefix target-directory-prefix)
      (syntax-case x ()
        [(k ledger-version)
         (let ([dir* (target-library-directories)])
           (unless (= (length dir*) 1)
             (syntax-error x
               (format "expected exactly one target directory, compiler/targets/<target>, on the library path (CHEZSCHEMELIBDIRS) but found ~a"
                 (if (null? dir*) "none" dir*))))
           (let* ([dir (car dir*)]
                  [name (substring dir (string-length prefix) (string-length dir))]
                  [versions (parse-target-name name)])
             (unless versions
               (syntax-error x
                 (format "~a is not named like a target, ocrt-<major>_<minor>-zkir-<major>_<minor>" dir)))
             (with-syntax ([name (datum->syntax #'k name)]
                           [ocrt (datum->syntax #'k (car versions))]
                           [zkir (datum->syntax #'k (cadr versions))])
               #'(make-target name ocrt zkir ledger-version))))]))))
