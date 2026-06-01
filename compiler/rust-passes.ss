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

;;; Rust code generator. Mirrors typescript-passes.ss in spirit: walks
;;; the post-prepare-for-typescript `Ltypescript` IR and emits a Rust
;;; crate (contract/lib.rs) that depends on the `compact-runtime` crate.
;;;
;;; See docs/superpowers/specs/2026-05-25-rust-codegen-design.md for the
;;; full mapping between Compact constructs and Rust output.

(library (rust-passes)
  (export rust-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (nanopass)
          (langs)
          (vm)
          (pass-helpers)
          (runtime-version))

  (define-pass print-rust : Ltypescript (ir) -> Ltypescript ()
    (definitions
      (include "rust-passes-helpers.ss")
      (include "rust-passes-types.ss")

      (include "rust-passes-prelude.ss")
      (include "rust-passes-decls.ss")

      (include "rust-passes-walker.ss")

      (include "rust-passes-streaming.ss")

      (include "rust-passes-emit.ss"))

    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,tdescs ,pelt* ...)
       (header)
       ;; M3.5-E4.4 Blocker 2: promote user types referenced ONLY by
       ;; non-exported pure circuits (e.g. zerocash's
       ;; `derive_nullifier(...): nullifier` — `nullifier` is mentioned
       ;; nowhere else on a publicly-reachable surface so the E2 walker
       ;; (analysis-passes) didn't promote it). We run a tiny scan here,
       ;; AFTER purity inference has set `id-pure?` correctly: collect
       ;; tstruct/tenum types referenced in non-exported user-pure
       ;; circuit sigs, then synthesise additional Ltypescript
       ;; export-typedef pelts and pass them to emit-type-decls.
       (let* ([all-tdefns (program-export-tdefns pelt*)]
              [extra-tdefns (collect-pure-circuit-tdefns pelt* all-tdefns)])
         (emit-type-decls (append all-tdefns extra-tdefns)))
       (emit-witnesses (program-witnesses pelt*))
       (emit-contract-struct)
       (emit-initial-state (program-ledger-fields pelt*)
                           (program-constructor-args pelt*)
                           pelt*)
       ;; Walk circuit declarations and split on purity. Impure circuits
       ;; become methods on the open Contract impl block; pure circuits are
       ;; collected for the pure_circuits module below.
       (let* ([circuit* (program-circuits pelt*)]
              [pure-circuit*
               (let loop ([c* circuit*] [acc '()])
                 (cond
                   [(null? c*) (reverse acc)]
                   [(id-pure? (circuit-function-name (car c*)))
                    (loop (cdr c*) (cons (car c*) acc))]
                   [else (loop (cdr c*) acc)]))]
              [native-id-ht (build-native-id-ht pelt*)]
              [witness-id-ht (build-witness-id-ht pelt*)]
              [circuit-id-ht (build-circuit-id-ht pelt*)])
         (for-each
           (lambda (c)
             (when (and (not (id-pure? (circuit-function-name c)))
                        (id-exported? (circuit-function-name c)))
               (emit-impure-circuit c native-id-ht witness-id-ht circuit-id-ht)))
           circuit*)
         (close-contract-struct)
         (emit-ledger-view (program-ledger-fields pelt*))
         (emit-pure-circuits pure-circuit* native-id-ht))
       (emit-cargo-toml)
       ir]))

  (define-passes rust-passes
    (print-rust          Ltypescript)))
