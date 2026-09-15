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
          (zkir-v3-passes)
          (manifest-passes))

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
               (module (with-target-ports)
                 (define (create-hierarchy path)
                   (unless (or (equal? path "") (file-directory? path))
                     (create-hierarchy (path-parent path))
                     (guard (c [else (error-accessing-file c "creating output directory")]) (mkdir path))
                     (set! created-dir* (cons path created-dir*))))
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
                        (define output-subdirectories '("compiler" "contract" "zkir" "keys"))
                        ;; One converter for both emitters: the TypeScript pass
                        ;; runs after the ZKIR one, so it finds the table warm
                        ;; and hands the contract the same bytes the circuit
                        ;; committed to.
                        (define convert-inner-verifying-key
                          (make-inner-verifying-key-converter output-directory-pathname))
                        (for-each
                          (lambda (fn) (rm-rf (format "~a/~a" output-directory-pathname fn)))
                          output-subdirectories)
                        (with-target-ports
                          '((contract-info.json . "compiler/contract-info.json"))
                          (run-passes save-contract-info-passes analyzed-ir proof-circuit-name*))
                        (with-target-ports
                          (map (lambda (sym) (cons sym (format "zkir/~a.zkir" sym)))
                               proof-circuit-name*)
                          (parameterize ([inner-verifying-key-blob convert-inner-verifying-key])
                            (run-passes (if (feature-zkir-v3) zkir-v3-passes zkir-passes) circuit-ir)))
                        (unless (null? (pending-conditions)) (raise (make-halt-condition)))
                        (unless (skip-zk)
                          (if (zero? (system "command -v zkir > /dev/null"))
                              ;; If we have zero circuits, the zkir directory won't exist,
                              ;; and zkir will fail to read it. Skip in that case silently.
                              (when (file-exists? (format "~a/zkir" output-directory-pathname))
                                ;; TODO: Properly string escape!
                                (let ([res (system (format "exec ~a compile-many '~a/zkir' '~a/keys'"
                                                     (if (feature-zkir-v3) "zkir-v3" "zkir")
                                                     output-directory-pathname
                                                     output-directory-pathname))])
                                  (unless (zero? res)
                                    (external-errorf "zkir returned a non-zero exit status ~d" res))))
                              (unless (zkir-warning-issued)
                                (zkir-warning-issued #t)
                                (fprintf (console-error-port)
                                  "Warning: ZKIR not found; skipping final circuit compilation.\n"))))
                        ;; Fingerprint each proof circuit's compiled verifier key (its
                        ;; `keys/<name>.verifier`, produced by the zkir step above) so the TypeScript
                        ;; pass can embed `expectedVk` in the contract module. A `--skip-zk` build
                        ;; generates no keys, leaving the alist empty.
                        (let ([verifier-key-hash*
                               (fold-right
                                 (lambda (name acc)
                                   (let ([vk-pathname
                                          (format "~a/keys/~a.verifier" output-directory-pathname name)])
                                     (if (file-exists? vk-pathname)
                                         (cons (cons (symbol->string name) (sha256-file vk-pathname)) acc)
                                         acc)))
                                 '()
                                 proof-circuit-name*)])
                          (with-target-ports
                           '((contract.js . "contract/index.js")
                             (contract.d.ts . "contract/index.d.ts")
                             (contract.js.map . "contract/index.js.map"))
                           (parameterize ([proof-circuit-names proof-circuit-name*]
                                          [verifier-key-hashes verifier-key-hash*]
                                          [inner-verifying-key-blob convert-inner-verifying-key])
                             (run-passes typescript-passes analyzed-ir))))
                        (let ([manifest-pathname* created-file*])
                          (with-target-ports
                            '((contract-manifest.json . "compiler/contract-manifest.json"))
                            (run-passes manifest-passes circuit-ir
                              output-directory-pathname
                              output-subdirectories)))
                        (when final-pass (internal-errorf 'generate-everything "never encountered final pass ~s" final-pass)))])))))))]))

  ;; Re-encodes each distinct inner verifying key through `zkir-v3 inner-vk`,
  ;; returning a pair of the `verify_proof_vks` blob and its lowercase hex
  ;; SHA-256. The tool is asked rather than the bytes reshaped here, because a
  ;; `.verifier` file wraps the key in a tag and a SCALE length that only zkir
  ;; knows how to strip. Memoized on the resolved pathname: one contract may
  ;; verify against the same key more than once, and the conversion is a
  ;; subprocess.
  (define (make-inner-verifying-key-converter output-directory-pathname)
    (let ([table (make-hashtable string-hash string=?)]
          [n 0])
      (lambda (vk)
        (let* ([key-pathname (verifying-key-resolved-pathname vk)]
               [a (hashtable-cell table key-pathname #f)])
          (or (cdr a)
              (begin
                (unless (zero? (system "command -v zkir-v3 > /dev/null"))
                  (external-errorf
                    "verifyProof needs the zkir-v3 tool to encode the verifying key ~s, but it is not on PATH"
                    (verifying-key-pathname vk)))
                (let ([blob-pathname
                       (let ([dir (format "~a/zkir" output-directory-pathname)])
                         (unless (file-directory? dir) (mkdir dir))
                         (let ([blob-pathname (format "~a/inner-vk-~d.ivk" dir n)])
                           (set! n (fx+ n 1))
                           blob-pathname))])
                  ;; `--decider 0` is the only place the decider kind is
                  ;; chosen, and every key reaching Compact today comes from
                  ;; outside it -- but a key that itself verifies a proof would
                  ;; need `1`, and declaring `0` for it is a silent soundness
                  ;; bug.
                  ;; TODO: Properly string escape, as for compile-many below.
                  (let ([res (system (format "exec zkir-v3 inner-vk --decider 0 '~a' '~a'"
                                       key-pathname
                                       blob-pathname))])
                    (unless (zero? res)
                      (external-errorf "zkir-v3 inner-vk returned a non-zero exit status ~d for ~s"
                                       res
                                       (verifying-key-pathname vk))))
                  (let ([entry (cons (let ([x (call-with-port (open-file-input-port blob-pathname)
                                                get-bytevector-all)])
                                       (if (eof-object? x) (bytevector) x))
                                     (sha256-file blob-pathname))])
                    ;; Build scratch, not an output: the blob reaches the
                    ;; emitters through this memo table, so leaving the file
                    ;; behind would only put a compiler intermediate in a tree
                    ;; someone else copies. Deleted here rather than on exit so
                    ;; a crash leaves it to look at.
                    (delete-file blob-pathname #f)
                    (set-cdr! a entry)
                    entry))))))))

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
