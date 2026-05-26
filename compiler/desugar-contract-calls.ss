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

;;; Desugar cross-contract call sugar at the Lnodisclose stage so both
;;; typescript-passes and the circuit-passes -> zkir chain see the same
;;; lowered form.  Each source-level (contract-call …) expression is
;;; rewritten into a self-contained `let*` that:
;;;
;;;   1. binds the receiver and each argument to locals (single
;;;      evaluation);
;;;   2. invokes the original contract-call against an *extended*
;;;      tcontract whose elt-name now returns
;;;        (ttuple <T> Field Bytes<32>)
;;;      so the dispatch primitive can carry cc-rand and the entry-point
;;;      bytes alongside the user-visible result;
;;;   3. projects the three tuple components via `tuple-ref`;
;;;   4. computes commComm via the synthesized `transientCommit(value,
;;;      cc-rand)` native (value = tuple of args + result);
;;;   5. stamps commComm + cc-rand on the callee proof-data via the
;;;      runtime helper `recordCalleeCommComm` (declared as a native);
;;;   6. emits the kernel-side `claimContractCall` public-ledger call,
;;;      flowing through the existing public-ledger handler in both
;;;      backends just like any other kernel update;
;;;   7. yields the user-visible result.
;;;
;;; With this rewrite, the runtime helper that backs the dispatch shrinks
;;; to a lean "do the dispatch, push the three private-transcript outputs,
;;; return [result, ccRand, entryPoint]" primitive — the commitment
;;; computation and the kernel claim become compiler-generated code,
;;; single-sourced through `transientCommit` and the public-ledger
;;; lowering, so the JS-side and ZKIR-side computations of commComm can
;;; no longer diverge.

(library (desugar-contract-calls)
  (export desugar-contract-calls desugar-contract-calls-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers))

  (define-pass desugar-contract-calls : Lnodisclose (ir) -> Lnodisclose ()
    (definitions
      ;; Populated when Program walks the kernel-declaration: the kernel's
      ;; ledger-field-name and the full ADT-Op record for `claimContractCall`.
      ;; Used when synthesizing the (public-ledger … claimContractCall …)
      ;; expression for each desugared contract-call site.
      (define kernel-field-name #f)
      (define kernel-claim-adt-op #f)

      ;; Synthesized internal (native …) Program-Elements created by this
      ;; pass.  Two flavours:
      ;;
      ;;   * `synth-record-cc-pelt` — single shared native for the runtime's
      ;;     `__compactRuntime.recordCalleeCommComm` helper.  Created lazily
      ;;     on the first contract-call rewrite and reused after that.  The
      ;;     gensym'd function-name id is unreachable from user code, so the
      ;;     symbol never enters the source language.  Witness class with
      ;;     Void return — ZKIR emits no gates for it.
      ;;
      ;;   * `synth-tc-natives` — per-call-site
      ;;     `__compactRuntime.transientCommit` natives.  The user-source
      ;;     `transientCommit` is polymorphic in the value type; analysis has
      ;;     already monomorphized any user call sites by the time this pass
      ;;     runs, so emitted call sites need their own monomorphic
      ;;     instances.  The function-name id is gensym'd but the symbol
      ;;     is `transientCommit` — the ZKIR std-circuits hashtable
      ;;     dispatches on `(id-sym function-name)`, so the symbol must
      ;;     match the existing handler key while the id uniq keeps each
      ;;     instance distinct.
      ;;
      ;; All synthesized natives are prepended to the program's pelt* list
      ;; in the Program clause below, before user-written elements, so both
      ;; backends see them when they process Program-Elements.
      (define synth-record-cc-pelt #f)
      (define synth-record-cc-name #f)
      (define synth-tc-natives '())

      (define (ensure-record-cc-native! src)
        (unless synth-record-cc-pelt
          (let ([fn-name           (make-temp-id src 'recordCalleeCommComm)]
                [commComm-arg      (make-temp-id src 'commComm)]
                [commCommRand-arg  (make-temp-id src 'commCommRand)]
                ;; native-entry fields, per (langs) make-native-entry:
                ;;   function       — JS-side function name
                ;;   class          — 'witness (no-op gates, runtime side effect).
                ;;   disclosure*    — one entry per argument
                ;;   maybe-type-param* — one per arg + return
                [entry             (make-native-entry
                                     "__compactRuntime.recordCalleeCommComm"
                                     'witness
                                     '(#f #f)
                                     '(#f #f #f))])
            (set! synth-record-cc-name fn-name)
            (set! synth-record-cc-pelt
              (with-output-language (Lnodisclose Program-Element)
                `(native ,src ,fn-name ,entry
                   ((,commComm-arg (tfield ,src)) (,commCommRand-arg (tfield ,src))) (ttuple ,src)))))))

      ;; Synthesize a per-call-site transientCommit native and
      ;; return the fresh function-name id.  `value-type` is the monomorphic
      ;; type of the value being committed — a `(ttuple Type ...)` over the
      ;; call site's argument types and the callee's return type — built by
      ;; the caller in the Type with-output-language block.
      (define (synth-tc-native! src value-type)
        (let ([fn-name    (make-temp-id src 'transientCommit)]
              [value-arg  (make-temp-id src 'value)]
              [rand-arg   (make-temp-id src 'rand)]
              ;; native-entry fields, per (langs) make-native-entry:
              ;;   function       — JS-side function name
              ;;   class          — 'circuit (lowers to transient_hash gate in ZKIR; user-source `transientCommit` uses
              ;;                    the same class).
              ;;   disclosure*    — '(#f #f) for the two args (neither discloses).
              ;;   maybe-type-param* — '(A #f #f).  The value arg's type-param symbol
              [entry      (make-native-entry "__compactRuntime.transientCommit" 'circuit '(#f #f) '(A #f #f))])
          (set! synth-tc-natives
            (cons (with-output-language (Lnodisclose Program-Element)
                    `(native ,src ,fn-name ,entry ((,value-arg ,value-type) (,rand-arg (tfield ,src))) (tfield ,src)))
                  synth-tc-natives))
          fn-name))

      (define (register-kernel! pelt)
        (nanopass-case (Lnodisclose Program-Element) pelt
          [(kernel-declaration ,public-binding)
           (nanopass-case (Lnodisclose Public-Ledger-Binding) public-binding
             [(,src ,ledger-field-name (,path-index* ...) ,type)
              (set! kernel-field-name ledger-field-name)
              (nanopass-case (Lnodisclose Type) type
                [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                 (for-each
                   (lambda (adt-op)
                     (nanopass-case (Lnodisclose ADT-Op) adt-op
                       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                        (when (eq? ledger-op 'claimContractCall)
                          (set! kernel-claim-adt-op adt-op))]))
                   adt-op*)]
                [else (void)])])]
          [else (void)]))

      ;; Look up the named elt's argument types and return type from a
      ;; tcontract.  Returns two values: (list-of-arg-types, return-type).
      (define (tcontract-elt-types type target-elt-name)
        (nanopass-case (Lnodisclose Type) type
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (let loop ([en* elt-name*] [tt* type**] [t* type*])
             (cond
               [(null? en*)
                (internal-errorf 'desugar-contract-calls
                  "elt-name ~s not found in tcontract ~s" target-elt-name contract-name)]
               [(eq? (car en*) target-elt-name)
                (values (car tt*) (car t*))]
               [else (loop (cdr en*) (cdr tt*) (cdr t*))]))]
          [else
           (internal-errorf 'desugar-contract-calls
             "contract-call type is not a tcontract")]))

      ;; Rebuild a tcontract with target-elt-name's return type extended
      ;; from T to (ttuple T Field (Bytes 32)).  Per-call-site: the
      ;; structural ttuple metadata only attaches to this one call's
      ;; tcontract annotation and doesn't leak to any other call site
      ;; using the same source-level tcontract.
      (define (extend-tcontract type target-elt-name)
        (nanopass-case (Lnodisclose Type) type
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (let ([new-type*
                  (map (lambda (en ret)
                         (if (eq? en target-elt-name)
                             (with-output-language (Lnodisclose Type)
                               `(ttuple ,src ,ret (tfield ,src) (tbytes ,src 32)))
                             ret))
                       elt-name* type*)])
             (with-output-language (Lnodisclose Type)
               `(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,new-type*) ...)))]
          [else
           (internal-errorf 'desugar-contract-calls "extend-tcontract: not a tcontract")])))

    (Expression : Expression (ir) -> Expression ()
      [(contract-call ,src ,elt-name (,[expr] ,type) ,[expr*] ...)
       (unless kernel-field-name
         (internal-errorf 'desugar-contract-calls
           "no kernel-declaration encountered before contract-call"))
       (unless kernel-claim-adt-op
         (internal-errorf 'desugar-contract-calls
           "kernel-declaration did not register a claimContractCall adt-op"))
       (ensure-record-cc-native! src)
       (let-values ([(arg-type* orig-return-type) (tcontract-elt-types type elt-name)])
         (unless (fx= (length arg-type*) (length expr*))
           (internal-errorf 'desugar-contract-calls
             "contract-call argument arity mismatch for ~s: ~s expected, ~s actual"
             elt-name (length arg-type*) (length expr*)))
         (let* ([extended-tcontract (extend-tcontract type elt-name)]
                [recv-var         (make-temp-id src 'recv)]
                [arg-var*         (map (lambda (i) (make-temp-id src (string->symbol (format "arg~s" i))))
                                       (iota (length expr*)))]
                [invocation-var   (make-temp-id src 'invocation)]
                [result-var       (make-temp-id src 'result)]
                [cc-rand-var      (make-temp-id src 'cc_rand)]
                [entry-point-var  (make-temp-id src 'entry_point)]
                [comm-comm-var    (make-temp-id src 'comm_comm)])
           (with-output-language (Lnodisclose Type)
             (let* ([field-type        `(tfield ,src)]
                    [bytes32-type      `(tbytes ,src 32)]
                    [tuple-type        `(ttuple ,src ,orig-return-type ,field-type ,bytes32-type)]
                    [value-tuple-type  `(ttuple ,src ,arg-type* ... ,orig-return-type)]
                    [tc-native-name    (synth-tc-native! src value-tuple-type)])
               (with-output-language (Lnodisclose Expression)
                 (let* ([recv-ref         `(var-ref ,src ,recv-var)]
                        [arg-ref*         (map (lambda (a) `(var-ref ,src ,a)) arg-var*)]
                        [invocation-ref   `(var-ref ,src ,invocation-var)]
                        [result-ref       `(var-ref ,src ,result-var)]
                        [cc-rand-ref      `(var-ref ,src ,cc-rand-var)]
                        [entry-point-ref  `(var-ref ,src ,entry-point-var)]
                        [comm-comm-ref    `(var-ref ,src ,comm-comm-var)]
                        [transient-value-tuple
                          `(tuple ,src
                             ,(map (lambda (a) `(single ,src ,a)) arg-ref*) ...
                             (single ,src ,result-ref))]
                        [outer-local*    (cons recv-var arg-var*)]
                        [outer-type*     (cons type arg-type*)]
                        [outer-expr*     (cons expr expr*)])
                   `(let* ,src
                      ([(,outer-local* ,outer-type*) ,outer-expr*] ...)
                      (let* ,src
                        ([(,invocation-var ,tuple-type)
                          (contract-call ,src ,elt-name (,recv-ref ,extended-tcontract) ,arg-ref* ...)])
                        (let* ,src
                          ([(,result-var ,orig-return-type) (tuple-ref ,src ,invocation-ref 0)]
                           [(,cc-rand-var ,field-type) (tuple-ref ,src ,invocation-ref 1)]
                           [(,entry-point-var ,bytes32-type) (tuple-ref ,src ,invocation-ref 2)])
                          (let* ,src
                            ([(,comm-comm-var ,field-type)
                              (call ,src ,tc-native-name ,transient-value-tuple ,cc-rand-ref)])
                            (seq ,src
                              (call ,src ,synth-record-cc-name ,comm-comm-ref ,cc-rand-ref)
                              ;; kernel.claimContractCall declares its first
                              ;; argument as Bytes<32> (the callee's address
                              ;; bytes).  At Lnodisclose, `recv` still has the
                              ;; tcontract type — flatten-datatypes (which
                              ;; rewrites contract values identically to
                              ;; (tbytes 32)) doesn't run until late in
                              ;; circuit-passes.  Wrap the receiver in a
                              ;; safe-cast so check-types/Linlined sees a
                              ;; Bytes<32>-typed expression; drop-safe-casts
                              ;; removes the wrapper before flatten-datatypes
                              ;; runs, so there's no runtime conversion.
                              (public-ledger ,src ,kernel-field-name #f ()
                                ,src ,kernel-claim-adt-op
                                (safe-cast ,src ,bytes32-type ,type ,recv-ref)
                                ,entry-point-ref
                                ,comm-comm-ref)
                              ,result-ref)))))))))))])

    (Program-Element : Program-Element (ir) -> Program-Element ())

    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       ;; First walk pelt* to discover the kernel-declaration's
       ;; ledger-field-name and claimContractCall adt-op, so the
       ;; Expression processor has them available when it rewrites
       ;; contract-call sites.
       (for-each register-kernel! pelt*)
       (let* ([new-pelt* (map (lambda (p) (Program-Element p)) pelt*)]
              [synthesized-pelt*
                (append (if synth-record-cc-pelt (list synth-record-cc-pelt) '())
                        (reverse synth-tc-natives))])
         `(program ,src (,contract-name* ...) ((,export-name* ,name*) ...)
            ,synthesized-pelt* ... ,new-pelt* ...))])

    (Program ir))

  (define-passes desugar-contract-calls-passes
    (desugar-contract-calls Lnodisclose))
)
