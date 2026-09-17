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

(library (pass-helpers)
  (export target-ports get-target-port target-directory source-directory source-file-name
          find-source-pathname
          proof-circuit-names verifier-key-hashes inner-verifying-key-blob
          define-passes define-checker checkers
          passrec-name passrec-pass passrec-unparse passrec-pretty-formats)
  (import (except (chezscheme) errorf)
          (utils)
          (config-params))

  (define target-ports (make-parameter '()))
  (define (get-target-port x)
    (cond
      [(assq x (target-ports)) => cdr]
      [else (internal-errorf 'get-target-port "~s not found" x)]))
  (define target-directory (make-parameter #f))
  (define source-directory (make-parameter #f))
  ; source-file-name is used for getting the contract name from the source file
  ; for the print-TS pass.
  (define source-file-name (make-parameter #f))

  (define (find-source-pathname extension pathname err)
    (define (try pathname)
      (let ([ex? (file-exists? pathname)])
        (when (trace-search)
          (fprintf (current-error-port) "looking for ~a...~a\n"
            pathname
            (if ex? "found" "not found")))
        (and ex? pathname)))
    (let ([pathname (format "~a~a" pathname extension)])
      (or (if (path-absolute? pathname)
              (try pathname)
              (ormap
                (lambda (dir)
                  (try (if (equal? dir "")
                           pathname
                           (format "~a/~a" dir pathname))))
                (cons (assert (relative-path)) (compact-path))))
          (err pathname))))

  (define proof-circuit-names (make-parameter '()))

  ;; Alist mapping each proof circuit's external name (string) to the lowercase hex SHA-256 of its
  ;; compiled `keys/<name>.verifier` file. Populated in `passes.ss` after key generation and read by
  ;; the TypeScript pass to emit the contract module's `expectedVk` fingerprints. Empty when keys are
  ;; not generated (e.g. a `--skip-zk` build).
  (define verifier-key-hashes (make-parameter '()))

  ;; Re-encodes an inner verifying key: takes a `verifying-key` record and returns
  ;; a pair of its `verify_proof_vks` blob and that blob's lowercase hex SHA-256.
  ;; Populated in `passes.ss` and read by the ZKIR v3 pass, which cannot derive
  ;; the blob itself -- a `.verifier` file is a tagged `VerifierKey` wrapped in a
  ;; SCALE length, and only `zkir-v3` knows how to unwrap it. `#f` when the tool
  ;; is unavailable, which `verifyProof` reports rather than emitting a key no
  ;; verifier could match.
  (define inner-verifying-key-blob (make-parameter #f))

  (define-record-type passrec
    (nongenerative)
    (fields name pass unparse pretty-formats))

  (define-syntax define-passes
    (lambda (x)
      (define (do-clause clause)
        (syntax-case clause ()
          [(pass lang)
           (with-syntax ([unparse (datum->syntax #'lang (string->symbol (format "unparse-~a" (datum lang))))]
                         [pretty-formats (datum->syntax #'lang (string->symbol (format "~a-pretty-formats" (datum lang))))])
             #'(make-passrec 'pass pass unparse (pretty-formats)))]))
      (syntax-case x ()
        [(_ name clause ...)
         #`(define name (list #,@(map do-clause #'(clause ...))))])))

  (module (define-checker checkers)
    (define checkers (make-eq-hashtable))
    (define-syntax define-checker
      (lambda (x)
        (define (unparser lang)
          (datum->syntax lang (string->symbol (format "unparse-~a" (syntax->datum lang)))))
        (syntax-case x ()
          [(_ pass lang)
           (with-syntax ([unparse (datum->syntax #'lang (string->symbol (format "unparse-~a" (datum lang))))])
             #`(hashtable-set! checkers unparse pass))])))
    (indirect-export define-checker checkers))
)
