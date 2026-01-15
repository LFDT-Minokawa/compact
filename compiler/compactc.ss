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
        (command-line-parsing)
        (config-params)
        (program-common)
        (passes)
        (utils))

(define (print-help)
  (print-usage #f)
  (fprintf (current-output-port) "
This program compiles the Compact source program in the file specified by
<source-pathname> and puts the resulting target files into the directory
specified by <target-directory-pathname>.  These target files include
a Typescript equivalent of the Compact source file, Zkir circuit equivalents
of the exported circuits, and proving keys created by running zkir on the
zkir circuits.

The following flags, if present, affect the compiler's behavior as follows:
  --help prints help text and exits.

  --version prints the compiler version and exits.

  --language-version prints the language version and exits.

  --vscode causes error messages to be printed on a single line so they are
    rendered properly within the VS Code extension for Compact.

  --skip-zk causes the compiler to skip the generation of proving keys.
    Generating proving keys can be time-consuming, so this option is useful
    when debugging only the Typescript output.  The compiler also skips,
    after printing a warning message, the generation of proving keys when
    it cannot find zkir.

  --no-communications-commitment omits the contract communications
    commitment that enables data integrity for contract-to-contract calls.

  --sourceRoot <sourceRoot value> overrides the compiler's setting of the
    sourceRoot field in the generated source-map (.js.map) file.  By default,
    the compiler tries to determine a useful value based on the source and
    target-directory pathnames, but this value might not be appropriate for
    the deployed structure of the application.

  --trace-passes causes the compiler to print tracing information that is
    generally useful only to compiler developers.
"))

(usage "<flag> ... <source-pathname> <target-directory-pathname>")

(parameterize ([reset-handler abort])
  (command-line-case (command-line)
    [((flags [(--help) $ (begin (print-help) (exit))]
             [(--version) $ (begin (print-compiler-version) (exit))]
             [(--language-version) $ (begin (print-language-version) (exit))]
             [(--vscode)]
             [(--skip-zk)]
             [(--no-communications-commitment)]
             [(--sourceRoot) (string source-root)]
             [(--trace-passes)]
             [(--zkir-v3)])
      (string source-pathname)
      (string target-directory-pathname))
     (check-pathname source-pathname)
     (check-pathname target-directory-pathname)
     (parameterize ([trace-passes ?--trace-passes]
                    [skip-zk ?--skip-zk]
                    [no-communications-commitment ?--no-communications-commitment]
                    [zkir-v3 ?--zkir-v3])
       (when source-root (register-source-root! source-root))
       (handle-exceptions ?--vscode
         (generate-everything source-pathname target-directory-pathname)))]
    [((flags [(--help) $ (begin (print-help) (exit))]
             [(--version) $ (begin (print-compiler-version) (exit))]
             [(--language-version) $ (begin (print-language-version) (exit))])
      (string arg) ...)
     (print-usage #t)
     (exit 1)]))
