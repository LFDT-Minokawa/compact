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
          (zkir-v3-passes)
          (manifest-passes))

  (define-condition-type &pass-name &condition
    make-pass-name-condition pass-name-condition?
    (pass-name condition-pass-name))

  (define zkir-warning-issued (make-parameter #f))

  (define (shell-quote str)
    (let ([op (open-output-string)])
      (write-char #\' op)
      (string-for-each
        (lambda (c) (if (char=? c #\') (put-string op "'\\''") (write-char c op)))
        str)
      (write-char #\' op)
      (get-output-string op)))

  ;; Generates the keys for <dir>/zkir/*.zkir in <dir>/keys and returns the exit status.
  ;; Runs one zkir process per circuit, largest first, (zk-jobs) at a time.
  ;; When (zk-jobs) is #f: half the processors (one job uses about two), and at most
  ;; one job per COMPACT_ZK_JOB_MB (default 5120) of available memory.  Both limits
  ;; include cgroup v1 and v2 limits.  The script is POSIX sh, plus xargs -0 -P.
  (define (run-zkir zkir dir)
    (if (eqv? (zk-jobs) 1)
        (system (format "exec ~a compile-many ~a ~a"
                  zkir
                  (shell-quote (format "~a/zkir" dir))
                  (shell-quote (format "~a/keys" dir))))
        (system
          (string-append
            (format "zkir=~a; dir=~a; jobs=~a\n" zkir (shell-quote dir) (or (zk-jobs) "auto"))
            "serial() { exec \"$zkir\" compile-many \"$dir/zkir\" \"$dir/keys\"; }\n"
            ; free MB in a cgroup: limit, usage and stat files, name of the reclaimable cache stat
            "cgmem() {\n"
            "  awk -v key=\"$4\" '\n"
            "    FILENAME == ARGV[1] && FNR == 1 { lim = $1 }\n"
            "    FILENAME == ARGV[2] && FNR == 1 { use = $1 }\n"
            "    FILENAME == ARGV[3] && $1 == key { cache = $2 }\n"
            "    END {\n"
            "      if (lim ~ /^[0-9]+$/ && use ~ /^[0-9]+$/) {\n"
            "        mb = (lim - use + cache) / 1048576\n"
            "        if (mb < 0) mb = 0\n"
            "        if (mb > 1000000000) mb = 1000000000\n"
            "        printf \"%d\\n\", mb\n"
            "      }\n"
            "    }' \"$1\" \"$2\" \"$3\" 2>/dev/null\n"
            "}\n"
            ; processors allowed by "quota period" on stdin
            "cgcpu() { awk '$1 ~ /^[0-9]+$/ && $1 > 0 && $2 > 0 { c = int($1 / $2); print c < 1 ? 1 : c; exit }' 2>/dev/null; }\n"
            ; minimum of $1 and $2; empty is unknown
            "least() { if [ -z \"$2\" ]; then echo \"$1\"; elif [ -z \"$1\" ] || [ \"$2\" -lt \"$1\" ]; then echo \"$2\"; else echo \"$1\"; fi; }\n"
            "if [ \"$jobs\" = auto ]; then\n"
            "  jobmb=${COMPACT_ZK_JOB_MB:-5120}\n"
            "  case $jobmb in 0*|*[!0-9]*) jobmb=5120;; esac\n"
            "  ncpu=$(getconf _NPROCESSORS_ONLN 2>/dev/null)\n"
            "  case $ncpu in ''|*[!0-9]*) ncpu=2;; esac\n"
            "  mem=$(awk '/^MemAvailable:/ { print int($2 / 1024) }' /proc/meminfo 2>/dev/null)\n"
            ; macOS: half of the installed memory
            "  [ -n \"$mem\" ] || mem=$(sysctl -n hw.memsize 2>/dev/null | awk '/^[0-9]+$/ { print int($1 / 2097152) }')\n"
            ; cgroup v2: this group and each parent
            "  cg=$(sed -n 's/^0:://p' /proc/self/cgroup 2>/dev/null)\n"
            "  d=/sys/fs/cgroup${cg%/}\n"
            "  while :; do\n"
            "    [ ! -r \"$d/memory.max\" ] || mem=$(least \"$mem\" \"$(cgmem \"$d/memory.max\" \"$d/memory.current\" \"$d/memory.stat\" inactive_file)\")\n"
            "    [ ! -r \"$d/cpu.max\" ] || ncpu=$(least \"$ncpu\" \"$(cgcpu < \"$d/cpu.max\")\")\n"
            "    d=${d%/*}\n"
            "    case $d in /sys/fs/cgroup*) ;; *) break;; esac\n"
            "  done\n"
            ; cgroup v1
            "  d=/sys/fs/cgroup/memory\n"
            "  [ ! -r $d/memory.limit_in_bytes ] || mem=$(least \"$mem\" \"$(cgmem $d/memory.limit_in_bytes $d/memory.usage_in_bytes $d/memory.stat total_inactive_file)\")\n"
            "  d=/sys/fs/cgroup/cpu\n"
            "  [ ! -r $d/cpu.cfs_quota_us ] || ncpu=$(least \"$ncpu\" \"$(cat $d/cpu.cfs_quota_us $d/cpu.cfs_period_us 2>/dev/null | tr '\\n' ' ' | cgcpu)\")\n"
            "  jobs=$((ncpu / 2))\n"
            ; memory unknown: at most two jobs
            "  if [ -n \"$mem\" ]; then mem=$((mem / jobmb)); else mem=2; fi\n"
            "  [ \"$jobs\" -le \"$mem\" ] || jobs=$mem\n"
            "  [ \"$jobs\" -ge 1 ] || jobs=1\n"
            "fi\n"
            "n=$(ls \"$dir/zkir\" | grep -c '\\.zkir$')\n"
            "[ \"$jobs\" -le \"$n\" ] || jobs=$n\n"
            "[ \"$jobs\" -gt 1 ] || serial\n"
            "if ! command -v xargs > /dev/null || ! printf 'x\\000' | xargs -0 -P 2 -n 1 true > /dev/null 2>&1; then\n"
            "  echo \"No xargs that supports -0 and -P: compiling the circuits one at a time.\" >&2\n"
            "  serial\n"
            "fi\n"
            "echo \"Compiling $n circuits, $jobs at a time:\" >&2\n"
            "mkdir -p \"$dir/keys\" || exit 1\n"
            ; one NUL-terminated "k/n name" argument per job
            "ls -S \"$dir/zkir\" | sed -n 's/\\.zkir$//p' | awk -v n=\"$n\" '{ print NR \"/\" n \" \" $0 }' | tr '\\n' '\\000' |\n"
            "  xargs -0 -P \"$jobs\" -n 1 sh -c '\n"
            "    k=${3%% *}; c=${3#* }\n"
            "    printf \"%s\\n\" \"  [$k] circuit $c started\" >&2\n"
            "    if out=$(\"$1\" compile \"$2/zkir/$c.zkir\" \"$2/keys/$c.prover\" \"$2/keys/$c.verifier\" 2>&1)\n"
            "    then printf \"%s\\n\" \"  [$k] circuit $c done\" >&2\n"
            "    else printf \"%s\\n\" \"zkir failed for circuit $c:\" \"$out\" >&2; exit 255\n"
            "    fi' sh \"$zkir\" \"$dir\"\n"))))

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
                        (for-each
                          (lambda (fn) (rm-rf (format "~a/~a" output-directory-pathname fn)))
                          output-subdirectories)
                        (with-target-ports
                          '((contract-info.json . "compiler/contract-info.json"))
                          (run-passes save-contract-info-passes analyzed-ir proof-circuit-name*))
                        (with-target-ports
                          (map (lambda (sym) (cons sym (format "zkir/~a.zkir" sym)))
                               proof-circuit-name*)
                          (run-passes zkir-v3-passes circuit-ir))
                        (unless (null? (pending-conditions)) (raise (make-halt-condition)))
                        (unless (skip-zk)
                          (if (zero? (system "command -v zkir-v3 > /dev/null"))
                              ;; If we have zero circuits, the zkir directory won't exist,
                              ;; and zkir will fail to read it. Skip in that case silently.
                              (when (file-exists? (format "~a/zkir" output-directory-pathname))
                                (let ([res (run-zkir "zkir-v3" output-directory-pathname)])
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
                                          [verifier-key-hashes verifier-key-hash*])
                             (run-passes typescript-passes analyzed-ir))))
                        (let ([manifest-pathname* created-file*])
                          (with-target-ports
                            '((contract-manifest.json . "compiler/contract-manifest.json"))
                            (run-passes manifest-passes circuit-ir
                              output-directory-pathname
                              output-subdirectories)))
                        (when final-pass (internal-errorf 'generate-everything "never encountered final pass ~s" final-pass)))])))))))]))

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
