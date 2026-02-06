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

(library (passes)
  (export generate-everything
          pass-name-condition?
          condition-pass-name
          )
  (import (except (chezscheme) errorf)
          (utils)
          (config-params)
          (nanopass)
          (langs)
          (parser)
          (formatter-test)
          (fixup-test)
          (pass-helpers)
          (sourcemaps)
          (frontend-passes)
          (analysis-passes)
          (save-contract-info-passes)
          (typescript-passes)
          (circuit-passes)
          (zkir-passes)
          (zkir-v3-passes))

  (define-condition-type &pass-name &condition
    make-pass-name-condition pass-name-condition?
    (pass-name condition-pass-name))

  (define zkir-warning-issued (make-parameter #f))

  (define generate-everything
    (case-lambda
      [(pathname output-directory-pathname)
       (generate-everything pathname output-directory-pathname #f #f)]
      [(pathname output-directory-pathname final-pass test-hook)
       (unless (string? pathname) (internal-errorf 'generate-everything "invalid pathname ~s" pathname))
       (unless (string? output-directory-pathname) (internal-errorf 'generate-everything "invalid pathname ~s" output-directory-pathname))
       (when final-pass (unless (symbol? final-pass) (internal-errorf 'generate-everything "invalid final-pass ~s" final-pass)))
       (when test-hook (unless (procedure? test-hook) (internal-errorf 'generate-everything "invalid test-hook ~s" test-hook)))
       (parameterize ([source-directory (path-parent pathname)]
                      [source-file-name (path-last (path-root pathname))]
                      [target-directory output-directory-pathname]
                      [relative-path (path-parent pathname)])
         (call/cc
           (lambda (quit)
             (define (run-passes passes x . extra*)
               (apply values
                 (fold-left
                   (lambda (x* p)
                     (let-values ([x* (with-exception-handler
                                        (lambda (c) (raise-continuable (condition c (make-pass-name-condition (passrec-name p)))))
                                        (lambda () (apply (passrec-pass p) x*)))])
                       (when (trace-passes)
                         (fprintf (console-output-port) "~s:\n" (passrec-name p))
                         (pretty-print (apply (passrec-unparse p) x*) (console-output-port)))
                       (when test-hook (apply test-hook (passrec-name p) (passrec-unparse p) (passrec-pretty-formats p) x*))
                       (let ([checker (hashtable-ref checkers (passrec-unparse p) #f)])
                         (when checker
                           (with-exception-handler
                             (lambda (c) (raise-continuable (condition c (make-pass-name-condition checker))))
                             (lambda () (apply checker x*)))))
                       (when (eq? (passrec-name p) final-pass)
                         (unless (null? (pending-conditions)) (raise (make-halt-condition)))
                         (quit (apply (passrec-unparse p) x*) (passrec-pretty-formats p)))
                       x*))
                   (cons x extra*)
                   passes)))
             (let ([created-dir* '()] [created-file* '()])
               (module (create-directory with-target-ports)
                 (define (create-hierarchy path)
                   (unless (or (equal? path "") (file-directory? path))
                     (create-hierarchy (path-parent path))
                     (guard (c [else (error-accessing-file c "creating output directory")]) (mkdir path))
                     (set! created-dir* (cons path created-dir*))))
                 (define (create-directory path)
                   (create-hierarchy (format "~a/~a" output-directory-pathname path)))
                 (define ($with-target-ports alist th preserve-preexisting?)
                   (define (open-target-port path)
                     (let ([path (format "~a/~a" output-directory-pathname path)])
                       (and (not (and preserve-preexisting? (file-exists? path)))
                            (begin
                              (create-hierarchy (path-parent path))
                              (let ([op (guard (c [else (error-accessing-file c "creating output file")])
                                          (if (equal? (path-extension path) "js")
                                              (begin
                                                (register-target-pathname! path)
                                                (open-output-file/line&col-positions path 'replace))
                                              (open-output-file path 'replace)))])
                                (set! created-file* (cons path created-file*))
                                op)))))
                   (let ([maybe-op* (map open-target-port (map cdr alist))])
                     (dynamic-wind
                       void
                       (lambda ()
                         (parameterize ([target-ports (append (map cons (map car alist) maybe-op*) (target-ports))])
                           (th)))
                       (lambda () (for-each (lambda (x) (when x (close-port x))) maybe-op*)))))
                 (define-syntax with-target-ports
                   (syntax-rules (preserve-preexisting)
                     [(_ preserve-preexisting alist b1 b2 ...)
                      ($with-target-ports alist (lambda () b1 b2 ...) #t)]
                     [(_ alist b1 b2 ...)
                      ($with-target-ports alist (lambda () b1 b2 ...) #f)])))
               (with-exception-handler
                 (lambda (c)
                   (unless (and (warning? c) (not (serious-condition? c)))
                     (for-each delete-file created-file*)
                     (for-each delete-directory created-dir*))
                   (raise-continuable c))
                 (lambda ()
                   (parameterize ([contract-ht (make-hashtable symbol-hash eq?)])
                     (cond
                       [(eq? final-pass 'parse-file/format/reparse)
                        (with-target-ports
                          `((formatter-output.compact . ,(format "formatter/~a" (path-last pathname))))
                          (run-passes formatter-testing-passes pathname))]
                       [(eq? final-pass 'parse-file/fixup/format/reparse)
                        (with-target-ports
                          `((fixup-output.compact . ,(format "fixup/~a" (path-last pathname))))
                          (run-passes fixup-testing-passes pathname))]
                       [else
                        (let* ([lsrc-ir (run-passes parser-passes pathname)]
                               [frontend-ir (run-passes frontend-passes lsrc-ir)]
                               [analyzed-ir (run-passes analysis-passes frontend-ir)]
                               [circuit-ir (run-passes circuit-passes analyzed-ir)]
                               [proof-circuit-name* (extract-circuit-names circuit-ir)])
                          (rm-rf (format "~a/compiler" output-directory-pathname))
                          (rm-rf (format "~a/zkir" output-directory-pathname))
                          (rm-rf (format "~a/keys" output-directory-pathname))
                          (with-target-ports
                            '((contract-info.json . "compiler/contract-info.json"))
                            (run-passes save-contract-info-passes analyzed-ir proof-circuit-name*))
                          (with-target-ports
                            (map (lambda (sym) (cons sym (format "zkir/~a.zkir" sym)))
                                 proof-circuit-name*)
                            (run-passes (if (zkir-v3) zkir-v3-passes zkir-passes) circuit-ir))
                          (unless (null? (pending-conditions)) (raise (make-halt-condition)))
                          (unless (skip-zk)
                            (if (zero? (system "command -v zkir > /dev/null"))
                              ;; If we have zero circuits, the zkir directory won't exist,
                              ;; and zkir will fail to read it. Skip in that case silently.
                              (when (file-exists? (format "~a/zkir" output-directory-pathname))
                                ;; TODO: Properly string escape!
                                (let ([res (system (format "exec ~a compile-many '~a/zkir' '~a/keys'"
                                                           (if (zkir-v3) "zkir-v3" "zkir")
                                                           output-directory-pathname
                                                           output-directory-pathname))])
                                  (unless (zero? res)
                                    (external-errorf "zkir returned a non-zero exit status ~d" res))))
                              (unless (zkir-warning-issued)
                                (zkir-warning-issued #t)
                                (fprintf (console-error-port)
                                         "Warning: ZKIR not found; skipping final circuit compilation.\n"))))
                          (with-target-ports
                           '((contract.js . "contract/index.js")
                             (contract.d.ts . "contract/index.d.ts")
                             (contract.js.map . "contract/index.js.map"))
                           (run-passes typescript-passes analyzed-ir))
                          (when final-pass (internal-errorf 'generate-everything "never encountered final pass ~s" final-pass)))]))))))))]))

  (define-pass extract-circuit-names : Lflattened (ir) -> * (ls)
    (definitions
      (define export-name-table (make-hashtable string-ci-hash string-ci=?))
      )
    (Program : Program (ir) -> * (circuit-name*)
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each
         (lambda (export-name name)
           (let ([a (hashtable-cell export-name-table (symbol->string export-name) #f)])
             (if (cdr a)
                 (let ([export-name^ (cadr a)] [name^ (cddr a)])
                   (define (format-export export-name name)
                     (let ([sym (id-sym name)])
                       (if (eq? sym export-name)
                           (format "~s" sym)
                           (format "~s for ~s" export-name sym))))
                   (source-errorf (id-src name)
                                  "the exported impure circuit name ~a is identical to the exported circuit name ~s at ~a modulo case; please rename to avoid zkir and prover-key filename clashes on case-insensitive filesystems"
                                  (format-export export-name name)
                                  (format-export export-name^ name^)
                                  (format-source-object (id-src name^))))
                 (set-cdr! a (cons export-name name)))))
         export-name*
         name*)
       export-name*])
    (Program ir))
)
