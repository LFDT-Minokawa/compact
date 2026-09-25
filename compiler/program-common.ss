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

(library (program-common)
  (export usage
          print-usage
          print-compiler-version
          print-language-version
          print-ledger-version
          print-runtime-version
          check-pathname
          handle-exceptions)
  (import (except (chezscheme) errorf)
          (utils)
          (state-case)
          (compiler-version)
          (language-version)
          (ledger-version)
          (runtime-version))

  (define usage (make-parameter #f))

  (define (print-usage err?)
    (fprintf (if err? (current-error-port) (current-output-port))
      "Usage: ~a ~a\n"
      (path-last (car (command-line)))
      (assert (usage)))
    (when err?
      (fprintf (current-error-port)
        "       --help displays detailed usage information\n")))

  ;; Verbose prints every field always, `unknown` where the build recorded
  ;; nothing, so the shape does not depend on how the compiler was built and
  ;; `--version --verbose | grep commit-hash` always answers. `rustc -vV` does
  ;; the same.
  (define print-compiler-version
    (case-lambda
      [() (print-compiler-version #f)]
      [(verbose?)
       (define (or-unknown s)
         (if (string=? s "") "unknown" s))
       ;; Nine characters, as `rustc` and `cargo` show: enough to read and to
       ;; `git show`. Verbose and contract-info.json keep all forty. Must match
       ;; `${COMMIT:0:9}` in scripts/stamp-compiler-version.sh; release-build.yml
       ;; asserts the two agree.
       (define short-commit-length 9)
       (define (abbreviate-commit commit)
         (if (fx> (string-length commit) short-commit-length)
             (substring commit 0 short-commit-length)
             commit))
       (let ([op (current-output-port)])
         (if verbose?
             (begin
               (fprintf op "release:          ~a\n" compiler-version-string)
               (fprintf op "commit-hash:      ~a\n" (or-unknown compiler-version-commit))
               (fprintf op "commit-date:      ~a\n" (or-unknown compiler-version-commit-date))
               (fprintf op "language-version: ~a\n" language-version-string)
               (fprintf op "runtime-version:  ~a\n" runtime-version-string))
             (cond
               [(string=? compiler-version-commit "")
                (fprintf op "~a\n" compiler-version-string)]
               [(string=? compiler-version-commit-date "")
                (fprintf op "~a (~a)\n"
                         compiler-version-string
                         (abbreviate-commit compiler-version-commit))]
               [else
                (fprintf op "~a (~a ~a)\n"
                         compiler-version-string
                         (abbreviate-commit compiler-version-commit)
                         compiler-version-commit-date)])))]))

  (define (print-language-version)
    (fprintf (current-output-port)
             "~a\n"
             language-version-string))

  (define (print-runtime-version)
    (fprintf (current-output-port)
             "~a\n"
             runtime-version-string))

  (define (print-ledger-version zkir-v3)
    (fprintf (current-output-port)
             "~a\n"
             (cdr (assoc (if zkir-v3 "zkir-v3" "zkir-v2") ledger-version-strings))))

  (define (check-pathname pathname)
    (when (and (>= (string-length pathname) 1)
               (char=? (string-ref pathname 0) #\-))
      (print-usage #t)
      (exit 1)))

  (define (condition-printer vscode?)
    (lambda (cnd)
      (if vscode?
          (let ([ip (open-string-input-port (with-output-to-string (lambda () (display-condition cnd))))])
            (define-syntax define-state-case
              (syntax-rules (eof else)
                [(_ (?def-id arg ...) ?char-id (eof eof1) clause ... (else else1 else2 ...))
                 (and (identifier? #'?def-id) (identifier? #'?char-id))
                 (define (?def-id arg ...)
                   (let ([?char-id (get-char ip)])
                     (state-case ?char-id (eof eof1) clause ... (else else1 else2 ...))))]))
            (define (err-lexer)
              (define punctuation '(#\, #\: #\;))
              (define-state-case (lex-error sep?) c
                [eof (void)]
                [#\newline (seen-newline sep?)]
                [else
                 (put-char (current-error-port) c)
                 (lex-error (memq c punctuation))])
              (define-state-case (seen-newline sep?) c
                [eof (void)]
                [(#\space #\newline) (seen-newline sep?)]
                [else
                 (unless sep? (put-char (current-error-port) #\;))
                 (put-char (current-error-port) #\space)
                 (put-char (current-error-port) c)
                 (lex-error (memq c punctuation))])
              (lex-error #f))
            (err-lexer)
            (newline (current-error-port)))
          (fprintf (current-error-port) "~a\n" (format-condition cnd)))))

  (define-syntax handle-exceptions
    (syntax-rules ()
      [(_ vscode? b1 b2 ...)
       (let ()
         (define print-condition (condition-printer vscode?))
         (parameterize ([pending-conditions '()])
           (guard (c [else
                      (for-each print-condition (reverse (pending-conditions)))
                      (cond
                        [(source-error-condition? c)
                         (print-condition c)
                         (exit 255)]
                        [(halt-condition? c)
                         (exit 255)]
                        [else
                         (fprintf (current-error-port) "Internal error (please report): ")
                         (print-condition c)
                         (exit 254)])])
             (with-exception-handler
               (lambda (c)
                 (if (warning? c)
                     (print-condition c)
                     (raise-continuable c)))
               (lambda () b1 b2 ...)))))]))

  (indirect-export handle-exceptions condition-printer)
)
