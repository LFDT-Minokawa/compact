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

(library (manifest-passes)
  (export manifest-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (json)
          (compiler-version)
          (language-version)
          (runtime-version)
          (langs)
          (pass-helpers))

  (define (save-manifest ir output-directory-pathname manifest-dir*)
    (define manifest-version-string "1")
    (define (sha256-hash pathname)
      (define (hex-digit? c)
        (or (char<=? #\0 c #\9)
            (char<=? #\a c #\f)
            (char<=? #\A c #\F)))
      (let-values ([(stdout stderr) (shell (format "exec sha256sum -b '~a'" pathname))])
        (unless (string=? stderr "")
          (external-errorf "attempt to invoke sha256sum failed with message ~a" stderr))
        (unless (>= (string-length stdout) 64)
          (external-errorf "unexpected output from sha256sum: ~a" stdout))
        (let ([hash (substring stdout 0 64)])
          (unless (andmap hex-digit? (string->list hash))
            (external-errorf "unexpected output from sha256sum: ~a" stdout))
          (string-downcase hash))))
    (define (file-entry root)
      (lambda (fn)
        (let ([pathname (format "~a/~a" root fn)])
          (cons
            fn
            (list
              (cons "type" "file")
              (cons "size" (call-with-port (open-file-input-port pathname) port-length))
              (cons "hash" (sha256-hash pathname)))))))
    (define (dir-entry root)
      (lambda (fn)
        (let* ([pathname (format "~a/~a" root fn)]
               [fn* (directory-list pathname)]
               [fn* (sort string<? fn*)]
               [fn* (remove "contract-manifest.json" fn*)])
          (let-values ([(dir-fn* file-fn*) (partition file-directory? fn*)])
            (cons
              fn
              (cons*
                (cons "type" "directory")
                (append
                  (map (file-entry pathname) file-fn*)
                  (map (dir-entry pathname) dir-fn*))))))))
    (let ([op (get-target-port 'contract-manifest.json)])
      (print-json op
        (cons*
          (cons
            "manifest-version"
            manifest-version-string)
          (cons
            "compiler-version"
            compiler-version-string)
          (cons
            "language-version"
            language-version-string)
          (cons
            "runtime-version"
            runtime-version-string)
          (map (dir-entry output-directory-pathname)
               (filter (lambda (d)
                         (file-exists? (format "~a/~a" output-directory-pathname d)))
                       manifest-dir*)))))
    ir)

  (define-passes manifest-passes
    (save-manifest              Lflattened))
)
