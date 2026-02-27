;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

#!chezscheme

(library (ledger-version)
  (export ledger-version-strings)
  (import (chezscheme))

  (define ledger-version-strings
    (let-syntax ([a (lambda (x)
                      ;; Extract the substring between the last slash and the last double quote.
                      ;; This will not fail gracefully if it doesn't see the slash or double quote.
                      (define (version-substring str)
                        (let ([end (let loop ([i (1- (string-length str))])
                                     (if (char=? (string-ref str i) #\") i (loop (1- i))))])
                          (let loop ([i end])
                            (if (char=? (string-ref str i) #\/)
                                (substring str (1+ i) end)
                                (loop (1- i))))))

                      ;; Grep flake.nix for an end of line comment matching `# key`.  Allow only one.
                      (define (grep-for key)
                        (let* ([ip (car (process (string-append "grep 'url =.*# " key "[[:space:]]*$' flake.nix")))]
                               [lines (let loop ([line (get-line ip)] [lines '()])
                                        (if (eof-object? line)
                                            (reverse lines)
                                            (loop (get-line ip) (cons line lines))))])
                          (cond
                            [(null? lines) (errorf 'grep "No ledger version for ~s\n" key)]
                            [(not (null? (cdr lines))) (errorf 'grep "More than one ledger version for ~s\n" key)]
                            [else (car lines)])))

                      ;; List of keys.
                      (define keys '("zkir-v2" "zkir-v3"))

                      #`'#,(map (lambda (key)
                                  (cons key (version-substring (grep-for key))))
                             keys))])
      a)))
