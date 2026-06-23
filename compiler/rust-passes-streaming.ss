;;; This file is part of Compact.
;;; Copyright (C) 2026 Midnight Foundation
;;; SPDX-License-Identifier: Apache-2.0
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;  	http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

      ;; -------------------------------------------------------------
      ;; Multi-stage streaming body walker
      ;; -------------------------------------------------------------
      ;; The existing emit-body-or-fallback recognises a narrow shape:
      ;; leading const-bindings/asserts, then terminal Cell.write batch
      ;; OR terminal non-write public-ledger call OR terminal if-then-else.
      ;; Bodies like zerocash.spend, election.vote$commit, election.vote$reveal
      ;; need interleaved public-ledger calls, if-statements, and bare-call
      ;; statements in the middle of the body.
      ;;
      ;; The streaming walker below dispatches per-statement and emits one
      ;; mini-OpProgramVerify chain per ledger-mutating statement; ctx is
      ;; threaded out via let-bound `_results_N` / `_if_results_N` values so
      ;; subsequent steps see the updated QueryContext. Gas costs are
      ;; accumulated through `__gas_acc += results.gas_cost`. Existing simple
      ;; shapes still go through emit-body-or-fallback for byte-stable output;
      ;; only richer shapes fall through to this walker.

      ;; statement-needs-streaming?: a body has shapes the existing walker
      ;; doesn't handle, requiring the streaming walker. Currently triggered
      ;; by:
      ;;   - non-terminal public-ledger call (insert / write mid-body)
      ;;   - non-terminal if-then-else (followed by more statements)
      ;;   - terminal bare-call (witness or pure-circuit at end)
      (define (body-needs-streaming? stmt native-id-ht witness-id-ht circuit-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (let loop ([stmts stmts])
            (cond
              [(null? stmts) #f]
              [(and (pair? (cdr stmts))
                    (stmt->public-ledger-call (car stmts)))
               #t]
              [(and (pair? (cdr stmts))
                    (stmt->if-then-else (car stmts)))
               #t]
              [(and (null? (cdr stmts))
                    (stmt->bare-call (car stmts)))
               #t]
              [else (loop (cdr stmts))]))))

      ;; body-streaming-walkable?: pre-validate that the streaming walker can
      ;; handle every statement in the flat sequence without emitting a
      ;; placeholder. Mirrors emit-streaming-body's per-statement dispatch.
      (define (body-streaming-walkable? stmt native-id-ht witness-id-ht circuit-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (let loop ([stmts stmts])
            (cond
              [(null? stmts) #t]
              [(const-decl-only? (car stmts))
               (loop (cdr stmts))]
              [(stmt->assignment (car stmts)) =>
               (lambda (a)
                 (and (expr-supported? (cdr a) native-id-ht witness-id-ht circuit-id-ht)
                      (loop (cdr stmts))))]
              [(stmt->assert (car stmts)) =>
               (lambda (a)
                 (and (assert-cond-supported?
                        (car a) native-id-ht witness-id-ht circuit-id-ht)
                      (loop (cdr stmts))))]
              [(const-binding (car stmts)) =>
               (lambda (b)
                 (let* ([rhs (cdr b)]
                        [classified
                         (classify-const-rhs rhs witness-id-ht circuit-id-ht)])
                   (and (or (eq? (car classified) 'witness)
                            (eq? (car classified) 'pure-circuit)
                            (eq? (car classified) 'impure-exported)
                            (expr-supported? rhs native-id-ht
                                             witness-id-ht circuit-id-ht))
                        (loop (cdr stmts)))))]
              [(stmt->bare-call (car stmts)) =>
               (lambda (c)
                 (let* ([fn-id (car c)]
                        [arg* (cdr c)]
                        [classified
                         (classify-call fn-id arg* witness-id-ht circuit-id-ht)])
                   (and (or (eq? (car classified) 'witness)
                            (eq? (car classified) 'pure-circuit)
                            (eq? (car classified) 'impure-exported))
                        (for-all (lambda (e)
                                   (expr-supported?
                                     e native-id-ht witness-id-ht circuit-id-ht))
                                 arg*)
                        (loop (cdr stmts)))))]
              [(stmt->public-ledger-call (car stmts)) =>
               (lambda (parts)
                 (let ([path-elt* (caddr parts)]
                       [expr* (cadddr parts)])
                   ;; A10: admit any path depth. Each element must still be a
                   ;; path-index (numeric ledger-field index); path-elt->vm-value
                   ;; rejects runtime-keyed paths with #f at emission.
                   (and (for-all (lambda (pe)
                                   (nanopass-case (Ltypescript Path-Element) pe
                                     [,path-index #t]
                                     [else #f]))
                                 path-elt*)
                        (for-all (lambda (e)
                                   (expr-supported?
                                     e native-id-ht witness-id-ht circuit-id-ht))
                                 expr*)
                        (loop (cdr stmts)))))]
              [(stmt->if-then-else (car stmts)) =>
               (lambda (parts)
                 (let* ([cond-expr (car parts)]
                        [then-stmt (cadr parts)]
                        [else-stmt (caddr parts)]
                        [then-call (branch->single-pl-call then-stmt)]
                        [else-call (branch->single-pl-call else-stmt)])
                   (cond
                     ;; Existing E6.2 shape: both branches are single
                     ;; non-write pl-calls.
                     [(and then-call else-call)
                      (and (expr-supported? cond-expr native-id-ht
                                            witness-id-ht circuit-id-ht)
                           (let ([then-path (caddr then-call)]
                                 [else-path (caddr else-call)])
                             (and (for-all (lambda (pe)
                                             (nanopass-case (Ltypescript Path-Element) pe
                                               [,path-index #t]
                                               [else #f]))
                                           then-path)
                                  (for-all (lambda (pe)
                                             (nanopass-case (Ltypescript Path-Element) pe
                                               [,path-index #t]
                                               [else #f]))
                                           else-path)
                                  (loop (cdr stmts)))))]
                     ;; A12 shape: every arm is an assert+pl-call,
                     ;; chained via else-if; optional final else also of
                     ;; the same shape, OR no final else.
                     [(branch->assert-and-pl-call then-stmt)
                      (and (expr-supported? cond-expr native-id-ht
                                            witness-id-ht circuit-id-ht)
                           (let walk-tail ([t else-stmt])
                             (cond
                               [(branch->assert-and-pl-call t) #t]
                               [(let ([inner (stmt->if-then-else t)])
                                  (and inner
                                       (branch->assert-and-pl-call (cadr inner))
                                       inner)) =>
                                (lambda (inner)
                                  (and (expr-supported?
                                         (car inner) native-id-ht
                                         witness-id-ht circuit-id-ht)
                                       (walk-tail (caddr inner))))]
                               [else
                                ;; No final else: accept iff the tail is
                                ;; a "no body" marker. In the current IR
                                ;; that's `(tuple #f)` rendered as an
                                ;; empty unit; conservatively we accept
                                ;; if branch->assert-and-pl-call returns
                                ;; #f *and* stmt->if-then-else returns
                                ;; #f — i.e. no else.
                                (not (stmt->if-then-else t))]))
                           (loop (cdr stmts)))]
                     [else #f])))]
              [else #f]))))

      ;; Cell.write builder lines: emit the hardcoded
      ;;   .push(false, new_cell(<idx>u8))
      ;;   .push(true,  new_cell(<value>))
      ;;   .ins(false, 1)
      ;; chain for a single Cell.write op. Returns a list of indented Rust
      ;; lines (matching compute-pl-builder-lines's output shape).
      (define (cell-write-builder-lines idx rust-val)
        (list (format "            .push(false, new_cell(~au8))\n" idx)
              (format "            .push(true, new_cell(~a))\n" rust-val)
              "            .ins(false, 1)\n"))

      ;; emit-streaming-body: walk the flat statement sequence and emit
      ;; per-statement Rust. ctx-expr is a string holding the current Rust
      ;; expression that yields the active &QueryContext; it starts as
      ;; "&ctx.current_query_context" and after each ledger-mutation flush
      ;; becomes "&_results_N.context" (or "&_if_results_N.context").
      ;;
      ;; gas-emitted? becomes #t after the first flush; from that point on
      ;; subsequent flushes `+=` into __gas_acc rather than starting fresh.
      ;;
      ;; The walker is `circuit` mode only — multi-stage constructor bodies
      ;; aren't observed in any current test and would need the
      ;; ConstructorResult return shape; ctor mode keeps its existing single-
      ;; flush emit-ctor-body-or-fallback path.
      (define (emit-streaming-body stmt native-id-ht witness-id-ht circuit-id-ht)
        ;; gas-acc init: emit once at top so subsequent flushes can `+=` it.
        ;; We track step-count via a state-machine variable.
        (out "        let mut __gas_acc = compact_runtime::RunningCost::default();\n")
        (let loop ([stmts (stmt-flatten stmt)]
                   [local-binds '()]
                   [witness-emitted? #f]
                   [step 0]
                   [ctx-expr "&ctx.current_query_context"])
          (cond
            [(null? stmts)
             ;; Final return. If no flush ever happened, ctx-expr is still
             ;; "&ctx.current_query_context" and we have no results context
             ;; to forward — but body-needs-streaming? guarantees at least
             ;; one flush. The current_query_context owned form is the
             ;; ctx-expr with leading '&' stripped.
             (let ([owned-ctx
                    (if (and (> (string-length ctx-expr) 0)
                             (char=? (string-ref ctx-expr 0) #\&))
                        (substring ctx-expr 1 (string-length ctx-expr))
                        ctx-expr)])
               (out "\n")
               (out "        Ok(CircuitResults {\n")
               (out "            result: (),\n")
               (out "            context: CircuitContext {\n")
               (out (format "                current_query_context: ~a,\n" owned-ctx))
               (when witness-emitted?
                 (out "                current_private_state,\n"))
               (out "                ..ctx\n")
               (out "            },\n")
               (out "            gas_cost: __gas_acc,\n")
               (out "        })\n"))
             #t]
            [(const-decl-only? (car stmts))
             ;; Forward declaration of a let* lifted temp — no Rust emission
             ;; needed; the eventual `(= ...)` assignment will emit the
             ;; `let <name> = <expr>;` binding.
             (loop (cdr stmts) local-binds witness-emitted? step ctx-expr)]
            [(stmt->assignment (car stmts)) =>
             (lambda (a)
               (let* ([var-name (car a)]
                      [rhs (cdr a)]
                      [rust-name (symbol->string (camel->snake (id-sym var-name)))]
                      [rendered
                       (guard (c [#t #f])
                         (ctor-expr-rust rhs local-binds
                                         native-id-ht witness-id-ht circuit-id-ht))])
                 (cond
                   [(not rendered) #f]
                   [else
                    (out (format "        let ~a = ~a;\n" rust-name rendered))
                    (loop (cdr stmts)
                          (cons (cons var-name rust-name) local-binds)
                          witness-emitted? (+ step 1) ctx-expr)])))]
            [(stmt->assert (car stmts)) =>
             (lambda (a)
               (let* ([expr (car a)]
                      [msg (cdr a)]
                      [subcalls (collect-witness-subcalls expr witness-id-ht)]
                      [hoist (emit-hoisted-witnesses
                               subcalls step 'circuit
                               local-binds witness-emitted?
                               native-id-ht witness-id-ht circuit-id-ht)]
                      [hoist-lines (car hoist)]
                      [hoist-binds (cadr hoist)]
                      [we2 (caddr hoist)]
                      [cond-str
                       (parameterize ([current-witness-call-binds
                                        (append hoist-binds
                                                (current-witness-call-binds))])
                         (assert-cond-rust expr local-binds
                                           native-id-ht witness-id-ht circuit-id-ht))])
                 ;; Hoisted witness lines come back in reverse order (the
                 ;; existing walker prepends them onto pre-lines). Reverse
                 ;; before emitting so the WitnessContext::new line lands
                 ;; first, then the actual witness call binding.
                 (for-each out (reverse hoist-lines))
                 (out (format "        compact_assert!(~a, ~s);\n" cond-str msg))
                 (loop (cdr stmts) local-binds we2 (+ step (length hoist-lines)) ctx-expr)))]
            [(const-binding (car stmts)) =>
             (lambda (b)
               (let* ([var-name (car b)]
                      [rhs (cdr b)]
                      [rust-name (symbol->string (camel->snake (id-sym var-name)))]
                      [classified
                       (classify-const-rhs rhs witness-id-ht circuit-id-ht)])
                 ;; M3.5: record the var's declared type (when inferable
                 ;; from the RHS — currently direct witness / pure-circuit
                 ;; calls) so later `==` rendering can detect tenum-typed
                 ;; locals.
                 (record-const-binding-type! var-name rhs
                                             witness-id-ht circuit-id-ht)
                 (case (car classified)
                   [(witness)
                    (let* ([wname (cadr classified)]
                           [wargs (caddr classified)]
                           [ctx-name (format "_witness_ctx_~a" step)]
                           [state-expr
                            (format "&~a.state"
                                    (if (and (> (string-length ctx-expr) 0)
                                             (char=? (string-ref ctx-expr 0) #\&))
                                        (substring ctx-expr 1 (string-length ctx-expr))
                                        ctx-expr))]
                           [prev-priv
                            (if witness-emitted?
                                "current_private_state"
                                "ctx.current_private_state")]
                           [arg-strs
                            (map (lambda (e)
                                   (arg-rust-clone-if-var
                                     e local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))
                                 wargs)])
                      (out (format "        let ~a = WitnessContext::new(ledger(~a), ~a, ~a);\n"
                                   ctx-name state-expr prev-priv ctx-expr))
                      (out (format "        let (current_private_state, ~a) = self.witnesses.~a(&~a~a);\n"
                                   rust-name wname ctx-name
                                   (let join ([xs arg-strs] [acc ""])
                                     (cond
                                       [(null? xs) acc]
                                       [else (join (cdr xs)
                                                   (string-append acc ", " (car xs)))]))))
                      (loop (cdr stmts)
                            (cons (cons var-name rust-name) local-binds)
                            #t (+ step 2) ctx-expr))]
                   [(pure-circuit)
                    (let* ([pname (cadr classified)]
                           [pargs (caddr classified)]
                           [callee
                            (nanopass-case (Ltypescript Expression) (expr-strip-cast rhs)
                              [(call ,src ,function-name ,expr* ...)
                               (eq-hashtable-ref circuit-id-ht function-name #f)]
                              [else #f])]
                           [formal-types (circuit-formal-arg-types callee)]
                           [arg-strs
                            (let loop2 ([as pargs] [fs formal-types] [acc '()])
                              (cond
                                [(null? as) (reverse acc)]
                                [else
                                 (let* ([ft (and (pair? fs) (car fs))]
                                        [s (if ft
                                               (render-pure-circuit-arg
                                                 (car as) ft local-binds
                                                 native-id-ht witness-id-ht circuit-id-ht)
                                               (arg-rust-clone-if-var (car as) local-binds
                                                                      native-id-ht witness-id-ht circuit-id-ht))])
                                   (loop2 (cdr as)
                                          (if (pair? fs) (cdr fs) '())
                                          (cons s acc)))]))])
                      (out (format "        let ~a = pure_circuits::~a(~a);\n"
                                   rust-name pname
                                   (let join ([xs arg-strs] [acc ""])
                                     (cond
                                       [(null? xs) acc]
                                       [(null? (cdr xs)) (string-append acc (car xs))]
                                       [else (join (cdr xs) (string-append acc (car xs) ", "))]))))
                      (loop (cdr stmts)
                            (cons (cons var-name rust-name) local-binds)
                            witness-emitted? (+ step 1) ctx-expr))]
                   [(impure-exported)
                    ;; Cross-circuit call. The callee takes/returns a
                    ;; CircuitContext, but our streaming walker is now
                    ;; operating on a QueryContext (ctx-expr might be
                    ;; `_results_N.context`). We can only invoke nested
                    ;; impure circuits when ctx-expr is still the original
                    ;; `&ctx.current_query_context` (no flushes happened
                    ;; yet) — bail otherwise.
                    (cond
                      [(not (string=? ctx-expr "&ctx.current_query_context")) #f]
                      [else
                       (let* ([cname (cadr classified)]
                              [cargs (caddr classified)]
                              [cr-name (format "_cr_~a" step)]
                              [arg-strs
                               (map (lambda (e)
                                      (arg-rust-clone-if-var
                                        e local-binds
                                        native-id-ht witness-id-ht circuit-id-ht))
                                    cargs)]
                              [arg-tail
                               (let join ([xs arg-strs] [acc ""])
                                 (cond
                                   [(null? xs) acc]
                                   [else (join (cdr xs)
                                               (string-append acc ", " (car xs)))]))])
                         (out (format "        let ~a = self.~a(ctx~a)?;\n"
                                      cr-name cname arg-tail))
                         (out (format "        let ctx = ~a.context;\n" cr-name))
                         (out (format "        let ~a = ~a.result;\n" rust-name cr-name))
                         ;; After this, ctx is a NEW CircuitContext; reset
                         ;; ctx-expr to point into it.
                         (loop (cdr stmts)
                               (cons (cons var-name rust-name) local-binds)
                               witness-emitted? (+ step 3)
                               "&ctx.current_query_context"))])]
                   [else
                    (let ([rendered
                           (guard (c [#t #f])
                             (ctor-expr-rust rhs local-binds
                                             native-id-ht witness-id-ht circuit-id-ht))])
                      (cond
                        [(not rendered) #f]
                        [else
                         (out (format "        let ~a = ~a;\n" rust-name rendered))
                         (loop (cdr stmts)
                               (cons (cons var-name rust-name) local-binds)
                               witness-emitted? (+ step 1) ctx-expr)]))])))]
            [(stmt->bare-call (car stmts)) =>
             (lambda (c)
               (let* ([fn-id (car c)]
                      [arg* (cdr c)]
                      [classified
                       (classify-call fn-id arg* witness-id-ht circuit-id-ht)])
                 (case (car classified)
                   [(witness)
                    (let* ([wname (cadr classified)]
                           [wargs (caddr classified)]
                           [ctx-name (format "_witness_ctx_~a" step)]
                           [state-expr
                            (format "&~a.state"
                                    (if (and (> (string-length ctx-expr) 0)
                                             (char=? (string-ref ctx-expr 0) #\&))
                                        (substring ctx-expr 1 (string-length ctx-expr))
                                        ctx-expr))]
                           [prev-priv
                            (if witness-emitted?
                                "current_private_state"
                                "ctx.current_private_state")]
                           [arg-strs
                            (map (lambda (e)
                                   (arg-rust-clone-if-var
                                     e local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))
                                 wargs)])
                      (out (format "        let ~a = WitnessContext::new(ledger(~a), ~a, ~a);\n"
                                   ctx-name state-expr prev-priv ctx-expr))
                      (out (format "        let (current_private_state, _) = self.witnesses.~a(&~a~a);\n"
                                   wname ctx-name
                                   (let join ([xs arg-strs] [acc ""])
                                     (cond
                                       [(null? xs) acc]
                                       [else (join (cdr xs)
                                                   (string-append acc ", " (car xs)))]))))
                      (loop (cdr stmts) local-binds #t (+ step 2) ctx-expr))]
                   [(pure-circuit)
                    (let* ([pname (cadr classified)]
                           [pargs (caddr classified)]
                           [arg-strs
                            (map (lambda (e)
                                   (arg-rust-clone-if-var
                                     e local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))
                                 pargs)])
                      (out (format "        let _ = pure_circuits::~a(~a);\n"
                                   pname
                                   (let join ([xs arg-strs] [acc ""])
                                     (cond
                                       [(null? xs) acc]
                                       [(null? (cdr xs)) (string-append acc (car xs))]
                                       [else (join (cdr xs)
                                                   (string-append acc (car xs) ", "))]))))
                      (loop (cdr stmts) local-binds witness-emitted? (+ step 1) ctx-expr))]
                   [(impure-exported)
                    (cond
                      [(not (string=? ctx-expr "&ctx.current_query_context")) #f]
                      [else
                       (let* ([cname (cadr classified)]
                              [cargs (caddr classified)]
                              [cr-name (format "_cr_~a" step)]
                              [arg-strs
                               (map (lambda (e)
                                      (arg-rust-clone-if-var
                                        e local-binds
                                        native-id-ht witness-id-ht circuit-id-ht))
                                    cargs)]
                              [arg-tail
                               (let join ([xs arg-strs] [acc ""])
                                 (cond
                                   [(null? xs) acc]
                                   [else (join (cdr xs)
                                               (string-append acc ", " (car xs)))]))])
                         (out (format "        let ~a = self.~a(ctx~a)?;\n"
                                      cr-name cname arg-tail))
                         (out (format "        let ctx = ~a.context;\n" cr-name))
                         (loop (cdr stmts) local-binds witness-emitted?
                               (+ step 2) "&ctx.current_query_context"))])]
                   [else #f])))]
            [(stmt->public-ledger-call (car stmts)) =>
             (lambda (parts)
               ;; Public-ledger op (write or non-write). Emit a mini
               ;; OpProgramVerify chain, accumulate gas, update ctx-expr.
               (let* ([src (car parts)]
                      [adt-op (cadr parts)]
                      [path-elt* (caddr parts)]
                      [expr* (cadddr parts)]
                      [is-write? (stmt->public-ledger-write (car stmts))]
                      [lines
                       (cond
                         [is-write?
                          (let* ([w (stmt->public-ledger-write (car stmts))]
                                 [idx (car w)]
                                 [val-expr (cdr w)]
                                 [rust-val
                                  (guard (c [#t #f])
                                    (arg-rust-clone-if-var val-expr local-binds
                                                           native-id-ht witness-id-ht circuit-id-ht))])
                            (and rust-val (cell-write-builder-lines idx rust-val)))]
                         [else
                          (compute-pl-builder-lines
                            src adt-op path-elt* expr* local-binds
                            native-id-ht witness-id-ht circuit-id-ht)])])
                 (cond
                   [(not lines) #f]
                   [else
                    (let ([ops-name (format "_ops_~a" step)]
                          [res-name (format "_results_~a" step)])
                      (out "\n")
                      (out (format "        let ~a = OpProgramVerify::<DefaultDB>::new()\n" ops-name))
                      (for-each out lines)
                      (out "            .build();\n")
                      (out (format "        let ~a = query_for_verify(~a, &~a, ctx.gas_limit.clone(), &ctx.cost_model)?;\n"
                                   res-name ctx-expr ops-name))
                      (out (format "        __gas_acc += ~a.gas_cost.clone();\n" res-name))
                      (loop (cdr stmts) local-binds witness-emitted?
                            (+ step 1)
                            (format "&~a.context" res-name)))])))]
            ;; A12: if/else-if chain where at least one arm carries a
            ;; leading `(assert ...)` OR the else-branch is itself a
            ;; nested if-then-else (else-if pattern). did.compact's
            ;; setAlsoKnownAs / setVerificationMethodRelation are the
            ;; canonical cases. We accept N arms with optional final
            ;; else. Emission: a Rust `if cond1 { ... } else if cond2
            ;; { ... } else { ... };` chain, each branch laying its
            ;; own `compact_assert!(...)` then OpProgramVerify chain.
            ;;
            ;; This clause runs BEFORE the legacy E6.2 clause below;
            ;; both fall through to the legacy clause when both branches
            ;; are E6.2-shaped (single non-write pl-call, no assert),
            ;; preserving byte-parity on if_stmt_fixture / election /
            ;; zerocash.spend.
            [(let ([p (stmt->if-then-else (car stmts))])
               (and p
                    ;; Defer to E6.2 when both branches match the older
                    ;; single-pl-call shape.
                    (not (and (if-then-else-branch-pl-call?
                                (cadr p) local-binds
                                native-id-ht witness-id-ht circuit-id-ht)
                              (if-then-else-branch-pl-call?
                                (caddr p) local-binds
                                native-id-ht witness-id-ht circuit-id-ht)))
                    p)) =>
             (lambda (parts)
               (let loop-arms ([arms (list (cons (car parts) (cadr parts)))]
                               [tail (caddr parts)])
                 (cond
                   [(let ([inner (stmt->if-then-else tail)])
                      (and inner
                           (branch->assert-and-pl-call (cadr inner))
                           inner)) =>
                    (lambda (inner)
                      (loop-arms (cons (cons (car inner) (cadr inner)) arms)
                                 (caddr inner)))]
                   [else
                    (let* ([source-arms (reverse arms)]
                           [final-else
                            (and (branch->assert-and-pl-call tail) tail)]
                           [arm-info
                            (map (lambda (a)
                                   (let* ([cond-expr (car a)]
                                          [branch-stmt (cdr a)]
                                          [b (branch->assert-and-pl-call
                                               branch-stmt)])
                                     (and b
                                          (let* ([assert-pair (car b)]
                                                 [pre-stmts (cadr b)]
                                                 [src (caddr b)]
                                                 [adt-op (cadddr b)]
                                                 [path-elt* (car (cddddr b))]
                                                 [expr* (cadr (cddddr b))]
                                                 ;; A14: src=#f marks an
                                                 ;; assert-only branch — emit
                                                 ;; an empty OpProgramVerify
                                                 ;; chain (no-op verify) so
                                                 ;; all branches return a
                                                 ;; uniform QueryResults.
                                                 [lines
                                                  (cond
                                                    [(not src) '()]
                                                    [else
                                                     (compute-pl-builder-lines
                                                       src adt-op path-elt* expr*
                                                       local-binds
                                                       native-id-ht witness-id-ht
                                                       circuit-id-ht)])]
                                                 [cond-str
                                                  (guard (c [#t #f])
                                                    (cond-rust cond-expr
                                                               local-binds
                                                               native-id-ht
                                                               witness-id-ht
                                                               circuit-id-ht))])
                                            (and lines cond-str
                                                 (not (rendered-has-todo?
                                                        cond-str))
                                                 (list cond-str assert-pair
                                                       lines pre-stmts))))))
                                 source-arms)]
                           [else-info
                            (and final-else
                                 (let* ([b (branch->assert-and-pl-call
                                             final-else)]
                                        [assert-pair (car b)]
                                        [pre-stmts (cadr b)]
                                        [src (caddr b)]
                                        [adt-op (cadddr b)]
                                        [path-elt* (car (cddddr b))]
                                        [expr* (cadr (cddddr b))]
                                        [lines
                                         (cond
                                           [(not src) '()]
                                           [else
                                            (compute-pl-builder-lines
                                              src adt-op path-elt* expr*
                                              local-binds
                                              native-id-ht witness-id-ht
                                              circuit-id-ht)])])
                                   (and lines (list assert-pair lines pre-stmts))))])
                      (cond
                        [(memv #f arm-info) #f]
                        [(and final-else (not else-info)) #f]
                        [else
                         (let ([res-name (format "_if_results_~a" step)])
                           (out "\n")
                           (let loop-emit ([xs arm-info] [first? #t])
                             (cond
                               [(null? xs) (void)]
                               [else
                                (let* ([a (car xs)]
                                       [cond-str (car a)]
                                       [assert-pair (cadr a)]
                                       [lines (caddr a)]
                                       [pre-stmts (cadddr a)])
                                  (out (format "        ~a~a ~a {\n"
                                               (if first? "let " "} else ")
                                               (if first?
                                                   (format "~a = if" res-name)
                                                   "if")
                                               cond-str))
                                  ;; A14: render in-branch let-bindings
                                  ;; (lifted-let assignments + branch-local
                                  ;; const-bindings) before the assert /
                                  ;; OpProgramVerify chain. Naming uses
                                  ;; ctor-expr-rust's `(camel->snake id-sym)`
                                  ;; var-ref fallback so subsequent
                                  ;; references resolve via Rust scoping.
                                  (for-each
                                    (lambda (b)
                                      (let* ([var-name (car b)]
                                             [expr (cdr b)]
                                             [rust-name (symbol->string
                                                          (camel->snake
                                                            (id-sym var-name)))]
                                             [rendered
                                              (guard (c [#t "/* TODO A14 */"])
                                                (ctor-expr-rust expr local-binds
                                                                native-id-ht
                                                                witness-id-ht
                                                                circuit-id-ht))])
                                        (out (format "            let ~a = ~a;\n"
                                                     rust-name rendered))))
                                    pre-stmts)
                                  (when assert-pair
                                    (let ([ae (car assert-pair)]
                                          [msg (cdr assert-pair)])
                                      (out (format "            compact_assert!(~a, ~s);\n"
                                                   (assert-cond-rust
                                                     ae local-binds
                                                     native-id-ht witness-id-ht
                                                     circuit-id-ht)
                                                   msg))))
                                  (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
                                  (for-each (lambda (l) (out (format "    ~a" l)))
                                            lines)
                                  (out "                .build();\n")
                                  (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                                               ctx-expr))
                                  (loop-emit (cdr xs) #f))]))
                           (out "        } else {\n")
                           (cond
                             [else-info
                              (let ([assert-pair (car else-info)]
                                    [lines (cadr else-info)]
                                    [pre-stmts (caddr else-info)])
                                (for-each
                                  (lambda (b)
                                    (let* ([var-name (car b)]
                                           [expr (cdr b)]
                                           [rust-name (symbol->string
                                                        (camel->snake
                                                          (id-sym var-name)))]
                                           [rendered
                                            (guard (c [#t "/* TODO A14 */"])
                                              (ctor-expr-rust expr local-binds
                                                              native-id-ht
                                                              witness-id-ht
                                                              circuit-id-ht))])
                                      (out (format "            let ~a = ~a;\n"
                                                   rust-name rendered))))
                                  pre-stmts)
                                (when assert-pair
                                  (let ([ae (car assert-pair)]
                                        [msg (cdr assert-pair)])
                                    (out (format "            compact_assert!(~a, ~s);\n"
                                                 (assert-cond-rust
                                                   ae local-binds
                                                   native-id-ht witness-id-ht
                                                   circuit-id-ht)
                                                 msg))))
                                (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
                                (for-each (lambda (l) (out (format "    ~a" l)))
                                          lines)
                                (out "                .build();\n")
                                (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                                             ctx-expr)))]
                             [else
                              (out "            let ops = OpProgramVerify::<DefaultDB>::new().build();\n")
                              (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                                           ctx-expr))])
                           (out "        };\n")
                           (out (format "        __gas_acc += ~a.gas_cost.clone();\n" res-name))
                           ;; A12: rebind ctx so subsequent stmts (e.g.
                           ;; the `recordUpdate()` call after the if in
                           ;; did.compact's setAlsoKnownAs) see the
                           ;; updated context through the default
                           ;; `&ctx.current_query_context` ctx-expr.
                           ;; `_if_results_N.context` is a QueryContext;
                           ;; wrap it in CircuitContext via `..ctx`.
                           (out (format "        let ctx = CircuitContext { current_query_context: ~a.context, ..ctx };\n"
                                        res-name))
                           (loop (cdr stmts) local-binds witness-emitted?
                                 (+ step 1)
                                 "&ctx.current_query_context"))]))])))]
            [(stmt->if-then-else (car stmts)) =>
             (lambda (parts)
               (let* ([cond-expr (car parts)]
                      [then-stmt (cadr parts)]
                      [else-stmt (caddr parts)]
                      [then-parts (if-then-else-branch-pl-call?
                                    then-stmt local-binds
                                    native-id-ht witness-id-ht circuit-id-ht)]
                      [else-parts (if-then-else-branch-pl-call?
                                    else-stmt local-binds
                                    native-id-ht witness-id-ht circuit-id-ht)]
                      [cond-str
                       (guard (c [#t #f])
                         (cond-rust cond-expr local-binds
                                    native-id-ht witness-id-ht circuit-id-ht))])
                 (cond
                   [(or (not then-parts) (not else-parts) (not cond-str)) #f]
                   [(rendered-has-todo? cond-str) #f]
                   [else
                    (let* ([then-lines (compute-pl-builder-lines
                                         (car then-parts) (cadr then-parts)
                                         (caddr then-parts) (cadddr then-parts)
                                         local-binds
                                         native-id-ht witness-id-ht circuit-id-ht)]
                           [else-lines (compute-pl-builder-lines
                                         (car else-parts) (cadr else-parts)
                                         (caddr else-parts) (cadddr else-parts)
                                         local-binds
                                         native-id-ht witness-id-ht circuit-id-ht)]
                           [res-name (format "_if_results_~a" step)])
                      (cond
                        [(or (not then-lines) (not else-lines)) #f]
                        [else
                         (out "\n")
                         (out (format "        let ~a = if ~a {\n" res-name cond-str))
                         (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
                         (for-each (lambda (l) (out (format "    ~a" l))) then-lines)
                         (out "                .build();\n")
                         (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                                      ctx-expr))
                         (out "        } else {\n")
                         (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
                         (for-each (lambda (l) (out (format "    ~a" l))) else-lines)
                         (out "                .build();\n")
                         (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                                      ctx-expr))
                         (out "        };\n")
                         (out (format "        __gas_acc += ~a.gas_cost.clone();\n" res-name))
                         (loop (cdr stmts) local-binds witness-emitted?
                               (+ step 1)
                               (format "&~a.context" res-name))]))])))]
            [else #f])))

