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

(define (save-manifest ir output-directory-pathname manifest-dir*)
  (define manifest-version-string "1")
  ; pathname => hash.  filled before the entries are built, so that hashing can be parallel.
  (define hash-ht (make-hashtable string-hash string=?))
  (define (file-size pathname)
    (call-with-port (open-file-input-port pathname) port-length))
  (define (directory-contents pathname) ; => subdirectory names, file names
    (partition
      (lambda (fn) (file-directory? (format "~a/~a" pathname fn)))
      (remove "contract-manifest.json" (sort string<? (directory-list pathname)))))
  (define (file-pathnames pathname) ; recursive
    (let-values ([(dir-fn* file-fn*) (directory-contents pathname)])
      (append
        (map (lambda (fn) (format "~a/~a" pathname fn)) file-fn*)
        (apply append (map (lambda (fn) (file-pathnames (format "~a/~a" pathname fn))) dir-fn*)))))
  (define (file-entry root)
    (lambda (fn)
      (let ([pathname (format "~a/~a" root fn)])
        (cons
          fn
          (list
            (cons "type" "file")
            (cons "size" (file-size pathname))
            (cons "hash" (or (hashtable-ref hash-ht pathname #f) (sha256-file pathname))))))))
  (define (dir-entry root)
    (lambda (fn)
      (let ([pathname (format "~a/~a" root fn)])
        (let-values ([(dir-fn* file-fn*) (directory-contents pathname)])
          (cons
            fn
            (cons*
              (cons "type" "directory")
              (append
                (map (file-entry pathname) file-fn*)
                (map (dir-entry pathname) dir-fn*))))))))
  (define manifest-dir-present*
    (filter (lambda (d)
              (file-exists? (format "~a/~a" output-directory-pathname d)))
            manifest-dir*))
  (let ([pathname* (apply append
                     (map (lambda (d) (file-pathnames (format "~a/~a" output-directory-pathname d)))
                          manifest-dir-present*))])
    (for-each
      (lambda (pathname hash) (hashtable-set! hash-ht pathname hash))
      pathname*
      (sha256-files pathname* (apply + (map file-size pathname*)))))
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
          "compiler-commit"
          compiler-version-commit)
        (cons
          "language-version"
          language-version-string)
        (cons
          "runtime-version"
          runtime-version-string)
        (map (dir-entry output-directory-pathname) manifest-dir-present*))))
  ir)
