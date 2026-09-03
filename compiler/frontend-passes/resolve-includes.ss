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

#!chezscheme

(define-pass resolve-includes : Lsrc (ir) -> Lnoinclude ()
  (definitions
    (define already-seen '()))
  (expand-pelt : Program-Element (ir pelt*) -> * (pelt*)
    [(include ,src ,file)
     (let ([pathname (find-source-pathname src file
                       (lambda (pathname)
                         (if (string=? file "std")
                             (source-errorf src "failed to locate file ~s: possibly replace include with import CompactStandardLibrary" pathname)
                             (source-errorf src "failed to locate file ~s" pathname))))])
       (when (member pathname already-seen)
         (source-errorf src "include cycle involving ~s" pathname))
       (fluid-let ([already-seen (cons pathname already-seen)])
         (nanopass-case (Lsrc Program) (parse-file pathname)
           [(program ,src ,pelt^* ...)
            (parameterize ([relative-path (path-parent pathname)])
              (fold-right expand-pelt pelt* pelt^*))])))]
    [else (cons (Program-Element ir) pelt*)])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Program : Program (ir) -> Program ()
    [(program ,src ,pelt* ...)
     `(program ,src ,(fold-right expand-pelt '() pelt*) ...)])
  (Module-Definition : Module-Definition (ir) -> Module-Definition ()
    [(module ,src ,exported? ,module-name (,[type-param*] ...) ,pelt* ...)
     `(module ,src ,exported? ,module-name (,type-param* ...) ,(fold-right expand-pelt '() pelt*) ...)]))
