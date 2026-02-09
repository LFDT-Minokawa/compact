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
          print-runtime-version
          check-pathname
          handle-exceptions)
  (import (except (chezscheme) errorf)
          (utils)
          (state-case)
          (compiler-version)
          (language-version)
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

  (define (print-compiler-version)
    (fprintf (current-output-port)
             "~a\n"
             compiler-version-string))

  (define (print-language-version)
    (fprintf (current-output-port)
             "~a\n"
             language-version-string))

  (define (print-runtime-version)
    (fprintf (current-output-port)
             "~a\n"
             runtime-version-string))

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
