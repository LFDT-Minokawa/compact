#! /usr/bin/env -S scheme --compile-imported-libraries --program
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

(import (except (chezscheme) errorf)
        (config-params)
        (utils)
        (fixup)
        (command-line-parsing)
        (program-common))

(define line-length 100)

(define (print-help)
  (print-usage #f)
  (fprintf (current-output-port) "
This program processes the Compact source program in the file specified by
<source-pathname>, attempts to update it to account for recent changes in the
Compact language, formats it, and writes the updated and reformatted program to
<target-pathname>, if specified, otherwise to standard output.  <target-pathname>
may be the same as <source-pathname>, in which case the source program is replaced
with the reformatted equivalent.  (Though we recommend that you direct the output
to a different file and compare it with the original, to verify that the changes
make sense.)

The following flags, if present, affect the tool's behavior as follows:
  --help prints help text and exits.

  --version prints the compiler version and exits.

  --language-version prints the language version and exits.

  --vscode causes error messages to be printed on a single line so they are
    rendered properly within the VS Code extension for Compact.
"))

(usage "<flag> ... <source-pathname> [ <target-pathname> ]")

(parameterize ([reset-handler abort])
  (command-line-case (command-line)
    [((flags [(--help) $ (begin (print-help) (exit))]
             [(--version) $ (begin (print-compiler-version) (exit))]
             [(--language-version) $ (begin (print-language-version) (exit))]
             [(--vscode)]
             [(--update-Uint-ranges)])
      (string source-pathname)
      (optional string target-pathname #f))
     (check-pathname source-pathname)
     (when target-pathname (check-pathname target-pathname))
     (handle-exceptions ?--vscode
       (let ([s (parameterize ([update-Uint-ranges ?--update-Uint-ranges]
                               [relative-path (path-parent source-pathname)])
                  (parse-file/fixup/format source-pathname))])
         (if target-pathname
             (let ([op (guard (c [else (error-accessing-file c "creating output file")])
                         (open-output-file target-pathname 'replace))])
               (guard (c [else (error-accessing-file c "writing output file")])
                 (put-string op s)
                 (close-output-port op)))
             (put-string (current-output-port) s))))]
    [((flags [(--help) $ (begin (print-help) (exit))]
             [(--version) $ (begin (print-compiler-version) (exit))]
             [(--language-version) $ (begin (print-language-version) (exit))])
      (string arg) ...)
     (print-usage #t)
     (exit 1)]))
