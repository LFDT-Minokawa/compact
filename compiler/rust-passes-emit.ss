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

      ;; emit-initial-state: emits the `initial_state` constructor method
      ;; inside the open Contract impl block. K1 seeds each ledger field
      ;; with its type's default value; J2 then walks the constructor body
      ;; and emits the witness / pure-circuit prelude + a single
      ;; OpProgramVerify chain that writes each field its source-declared
      ;; value. If the constructor body shape isn't one we recognise, we
      ;; fall back to the K1-only return.
      (define (emit-initial-state ledger-field* ctor-arg* all-pelt*)
        (out "    pub fn initial_state(\n")
        (out "        &self,\n")
        (out "        ctx: ConstructorContext<PS>")
        ;; Constructor parameters: one per (var-name type) pair, emitted
        ;; after ctx in the same multi-line shape used elsewhere. Names go
        ;; through camel->snake (handles `$` and CamelCase); types via
        ;; type-rust.
        (for-each
          (lambda (arg)
            (nanopass-case (Ltypescript Argument) arg
              [(,var-name ,type)
               (out (format ",\n        ~a: ~a"
                            (camel->snake (id-sym var-name))
                            (type-rust type)))]))
          ctor-arg*)
        (out ",\n    ) -> Result<ConstructorResult<PS>, CompactError> {\n")
        ;; K1: walk the pl-array bindings (all fields, not just exported)
        ;; and emit one new_cell per binding using the read-op's result
        ;; type as the source of truth for the default value. This produces
        ;; one Cell per field in declaration order — the path indices in
        ;; the IR confirm fields land at indices 0,1,2,...
        ;; J2 (constructor body emission) then overrides these defaults
        ;; with whatever the source constructor assigns.
        (out "        let sv = new_array(vec![\n")
        (let* ([all-bindings
                (apply append
                  (map (lambda (lf)
                         (nanopass-case (Ltypescript Program-Element) lf
                           [(public-ledger-declaration ,pl-array ,lconstructor)
                            (pl-array->public-bindings pl-array)]
                           [else '()]))
                       ledger-field*))]
               [_
                (begin
                  (for-each
                    (lambda (pb)
                      (let ([t (binding-type pb)])
                        (cond
                          ;; ADT-aware seeding (R1 / K1.1). The Compact ADTs
                          ;; whose initial-value isn't a plain Cell — Map, Set,
                          ;; MerkleTree, HistoricMerkleTree — have dedicated
                          ;; builders in compact-runtime that produce the exact
                          ;; StateValue shape declared in midnight-ledger.ss.
                          [(tadt-name=? t 'Set)
                           (out "            new_map(),\n")]
                          [(tadt-name=? t 'Map)
                           (out "            new_map(),\n")]
                          [(tadt-name=? t 'List)
                           (out "            new_list(),\n")]
                          [(tadt-name=? t 'MerkleTree)
                           (out (format "            new_merkle_tree(~a),\n"
                                        (tadt-merkle-height t)))]
                          [(tadt-name=? t 'HistoricMerkleTree)
                           (out (format "            new_historic_merkle_tree(~a),\n"
                                        (tadt-merkle-height t)))]
                          ;; Cell / Counter / anything else with a read op:
                          ;; keep the K1 path — emit new_cell(<default>).
                          ;; Special case: tvector defaults to [T; N] which doesn't
                          ;; impl Into<AlignedValue> upstream — route through
                          ;; new_cell_array which concatenates per-element AVs.
                          ;; Special case: tunsigned with a byte-length that doesn't
                          ;; match the Rust integer width's byte count (e.g.
                          ;; `Uint<0..70000>` is u32 in Rust but uses 3 bytes on
                          ;; state) — route through `new_cell_bounded_uint(0u128, N)`
                          ;; so the on-state `AlignmentAtom::Bytes` width matches TS.
                          [else
                           (let ([read-type (tadt-read-op-type t)])
                             (cond
                               [(type-is-tvector? read-type)
                                (out (format "            new_cell_array(~a),\n"
                                             (default-value-rust read-type)))]
                               [(tunsigned-bounded? read-type)
                                (out (format "            new_cell_bounded_uint(0u128, ~a),\n"
                                             (tunsigned-byte-length read-type)))]
                               [else
                                (out (format "            new_cell(~a),\n"
                                             (default-value-rust read-type)))]))])))
                    all-bindings)
                  (out "        ]);\n")
                  (out "        let state = ChargedState::new(sv);\n")
                  ;; Bucket-1: fully-qualify ContractAddress so a user struct
                  ;; named `ContractAddress` (e.g. midnight-did) does not
                  ;; shadow the upstream coin-structure type required by
                  ;; QueryContext::new.
                  (out "        let qctx = QueryContext::new(state, compact_runtime::ContractAddress::default());\n"))]
               ;; J2: emit the constructor body if we have one and its shape
               ;; matches. Fall back to the K1-only return otherwise (counter has
               ;; no constructor body, so it lands here naturally).
               [stmt (and (pair? ledger-field*)
                          (ldecl-constructor-stmt (car ledger-field*)))]
               [native-id-ht (build-native-id-ht all-pelt*)]
               [witness-id-ht (build-witness-id-ht all-pelt*)]
               [circuit-id-ht (build-circuit-id-ht all-pelt*)]
               [emitted?
                (and stmt
                     ;; Seed current-formal-arg-types with the
                     ;; constructor's args so var-ref-known-copy? can
                     ;; suppress redundant `.clone()` on primitive ctor
                     ;; parameters (`v: Field` in tiny.compact, etc.).
                     ;; The body walker mutates the same hashtable as it
                     ;; classifies const-bindings, so witness/pure-circuit
                     ;; results get their declared types recorded too.
                     ;;
                     ;; Iter 7: current-ledger-field-types is seeded by
                     ;; print-rust at the pass top (so impure circuits
                     ;; that write Vector<N,T> fields also see the map),
                     ;; not here.
                     (parameterize
                       ([current-formal-arg-types
                          (build-formal-arg-type-ht ctor-arg*)])
                       (emit-ctor-body-or-fallback stmt
                                                   native-id-ht witness-id-ht circuit-id-ht)))])
          (unless emitted?
            (out "        Ok(ConstructorResult {\n")
            (out "            current_contract_state: qctx.state,\n")
            (out "            current_private_state: ctx.initial_private_state,\n")
            (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
            (out "        })\n")))
        (out "    }\n\n"))

      ;; emit-circuit-args: emit each Argument as ",\n        name: type"
      ;; after the leading `&self` / `ctx` params on an impure circuit method,
      ;; matching the existing multi-line method signature shape.
      (define (emit-circuit-args arg*)
        (for-each
          (lambda (arg)
            (nanopass-case (Ltypescript Argument) arg
              [(,var-name ,type)
               (out (format ",\n        ~a: ~a"
                            (camel->snake (id-sym var-name))
                            (type-rust type)))]))
          arg*))

      ;; unit-type?: returns #t if a Type IR node is the empty tuple `()`
      ;; (Compact's `Void` / Ltypescript `(ttuple src)` with no element
      ;; types). I3a only emits bodies for unit-returning circuits; richer
      ;; return shapes (e.g. tiny.compact's `get(): Maybe<Fr>`) keep the
      ;; `unimplemented!()` fallback until I3b.
      (define (unit-type? type)
        (nanopass-case (Ltypescript Type) type
          [(ttuple ,src ,type* ...) (null? type*)]
          [else #f]))

      ;; struct-of-type: if `type` is a tstruct (possibly through a talias
      ;; chain), return (list struct-name elt-name* type*); otherwise #f.
      ;; Used by F2.2's struct-literal emission to recover the field-name
      ;; list (the IR's `(new ...)` carries field initialisers in source
      ;; order but not the names — those come off the struct's type).
      (define (struct-of-type type)
        (nanopass-case (Ltypescript Type) type
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (list struct-name elt-name* type*)]
          [(talias ,src ,nominal? ,type-name ,type) (struct-of-type type)]
          [else #f]))

      ;; render-struct-literal: F2.2 — emit a Rust struct construction
      ;; expression for an Ltypescript `(new src type expr*)`. The struct
      ;; name comes off the type (via struct-of-type); for Maybe<T> we emit
      ;; the L1 runtime alias `Maybe` (in scope via the contract module
      ;; preamble), for user structs the bare struct name (H5-H7 emit the
      ;; struct definition into the contract module).
      ;;
      ;; Field initialiser exprs are rendered through ctor-expr-rust so
      ;; var-refs resolve against the current local-binds and nested
      ;; ledger reads / calls / etc. lower correctly.
      (define (render-struct-literal src type expr* local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
        (let* ([st (struct-of-type type)]
               [struct-name (and st (car st))]
               [elt-name* (and st (cadr st))])
          (cond
            [(not st)
             (rust-feature-error src 'struct-literal-non-tstruct
               "struct-literal of non-tstruct type")]
            [(not (fx= (length expr*) (length elt-name*)))
             (rust-feature-error src 'struct-literal-field-count-mismatch
               "struct-literal field-count mismatch for ~a (expected ~a, got ~a)"
               struct-name (length elt-name*) (length expr*))]
            [else
             (let* ([rust-struct-name (symbol->string struct-name)]
                    [field-strs
                     (map (lambda (name e)
                            (format "~a: ~a"
                                    (symbol->string name)
                                    (ctor-expr-rust e local-binds
                                                    native-id-ht witness-id-ht circuit-id-ht)))
                          elt-name* expr*)])
               (string-append
                 rust-struct-name
                 " { "
                 (let join ([xs field-strs] [acc ""])
                   (cond
                     [(null? xs) acc]
                     [(null? (cdr xs)) (string-append acc (car xs))]
                     [else (join (cdr xs)
                                 (string-append acc (car xs) ", "))]))
                 " }"))])))

      ;; maybe-value-type: if `type` is `Maybe<T>` (a tstruct named Maybe with
      ;; a `value` field), return T. Otherwise return #f. Used by the
      ;; I3b/4 if-expression emitter to render `some::<T>` / `none::<T>` with
      ;; an explicit generic argument so Rust's type inference doesn't need
      ;; help from surrounding context.
      (define (maybe-value-type type)
        (nanopass-case (Ltypescript Type) type
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (cond
             [(eq? struct-name 'Maybe)
              (let loop ([names elt-name*] [types type*])
                (cond
                  [(null? names) #f]
                  [(eq? (car names) 'value) (car types)]
                  [else (loop (cdr names) (cdr types))]))]
             [else #f])]
          [(talias ,src ,nominal? ,type-name ,type^) (maybe-value-type type^)]
          [else #f]))

      ;; stmt->if-expression-body: detect the I3b/4 "single if-expression body"
      ;; shape — a flat statement sequence whose only element is
      ;; `(if cond then-stmt else-stmt)`, where each branch is a
      ;; `(statement-expression expr)` carrying a single expression
      ;; representing the circuit's return value. Returns
      ;;   (list cond-expr then-expr else-expr)
      ;; on success, #f otherwise.
      (define (stmt->if-expression-body stmt)
        (let ([stmts (stmt-flatten stmt)])
          (cond
            [(or (null? stmts) (not (null? (cdr stmts)))) #f]
            [else
             (nanopass-case (Ltypescript Statement) (car stmts)
               [(if ,src ,expr0 ,stmt1 ,stmt2)
                (let ([then-expr (stmt->return-expr stmt1)]
                      [else-expr (stmt->return-expr stmt2)])
                  (and then-expr else-expr (list expr0 then-expr else-expr)))]
               [else #f])])))

      ;; stmt->return-expr: pull the single return expression out of a
      ;; branch Statement. The branches of a return-value if-expression
      ;; come out of typescript-passes lowering as a single
      ;; `(statement-expression expr)` (possibly wrapped in a `seq` with
      ;; a trailing unit tuple, which stmt-flatten strips). Returns the
      ;; expression on success, #f otherwise.
      (define (stmt->return-expr stmt)
        (let ([stmts (stmt-flatten stmt)])
          (cond
            [(or (null? stmts) (not (null? (cdr stmts)))) #f]
            [else
             (nanopass-case (Ltypescript Statement) (car stmts)
               [(statement-expression ,expr) expr]
               [else #f])])))

      ;; stmt-flatten: collapse nested `seq`s and trailing-`(tuple)` unit
      ;; statements into a flat list of leaf Statements. The unit
      ;; `(statement-expression (tuple src))` at the end of a `seq` is
      ;; pure (returns ()), so dropping it preserves semantics for our
      ;; void-returning circuits. Any other shape is left alone — callers
      ;; treat unexpected leaves as a non-match and fall back.
      ;; lift-seq-prefix-exprs: walk an Expression, find any (seq es ... e)
      ;; nodes in interior positions, collect the prefix `es` as lifted
      ;; assignment-statements, and return two values:
      ;;   (values lifted-stmts cleaned-expr)
      ;; where cleaned-expr has every seq replaced by just its trailing
      ;; expression. Lifting is order-preserving (left-to-right traversal)
      ;; so dependent assignments stay in order.
      ;;
      ;; This is what enables the streaming walker to see `let %tmp = ...;`
      ;; lifted out of complex assert conditions and similar nested
      ;; expressions.
      (define (lift-seq-prefix-exprs expr)
        (define lifted '())
        (define (push-lifted! e)
          (set! lifted
                (cons (with-output-language (Ltypescript Statement)
                        `(statement-expression ,e))
                      lifted)))
        (define (walk e)
          (nanopass-case (Ltypescript Expression) e
            [(seq ,src ,expr* ... ,expr^)
             (for-each (lambda (ex) (push-lifted! (walk ex))) expr*)
             (walk expr^)]
            [(assert ,src ,expr^ ,mesg)
             (let ([new-cond (walk expr^)])
               (with-output-language (Ltypescript Expression)
                 `(assert ,src ,new-cond ,mesg)))]
            [(not ,src ,expr^)
             (let ([n (walk expr^)])
               (with-output-language (Ltypescript Expression)
                 `(not ,src ,n)))]
            [(and ,src ,expr1 ,expr2)
             (let ([a (walk expr1)]
                   [b (walk expr2)])
               (with-output-language (Ltypescript Expression)
                 `(and ,src ,a ,b)))]
            [(or ,src ,expr1 ,expr2)
             (let ([a (walk expr1)]
                   [b (walk expr2)])
               (with-output-language (Ltypescript Expression)
                 `(or ,src ,a ,b)))]
            [(== ,src ,type ,expr1 ,expr2)
             (let ([a (walk expr1)]
                   [b (walk expr2)])
               (with-output-language (Ltypescript Expression)
                 `(== ,src ,type ,a ,b)))]
            [else e]))
        (let ([cleaned (walk expr)])
          (values (reverse lifted) cleaned)))

      (define (stmt-flatten stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(seq ,src ,stmt* ... ,stmt^)
           (let ([all (append stmt* (list stmt^))])
             (apply append (map stmt-flatten all)))]
          [(statement-expression ,expr)
           ;; Drop a bare unit `(tuple src)` — common terminal of a `seq`
           ;; for void-returning circuits.
           ;;
           ;; Also lift a `(seq src expr* ... expr^)` Expression out into
           ;; separate statement-expressions, so the streaming walker can
           ;; see each assignment and the final body as flat siblings. This
           ;; is what typescript-passes produces for `let*` lifted out of
           ;; expression contexts (e.g. `disclose(merkleTreePathRoot<...>
           ;; (path))` introducing a temp variable for the inner call).
           (nanopass-case (Ltypescript Expression) expr
             [(tuple ,src ,tuple-arg* ...)
              (if (null? tuple-arg*) '() (list stmt))]
             [(seq ,src ,expr* ... ,expr^)
              (apply append
                (map (lambda (e)
                       (stmt-flatten
                         (with-output-language (Ltypescript Statement)
                           `(statement-expression ,e))))
                     (append expr* (list expr^))))]
             [else
              ;; Try lifting any inner seq-prefix assignments from a
              ;; structured expression (assert / and / or / not / ==). If
              ;; lifting produced any prefix statements, return them
              ;; followed by the cleaned statement; otherwise return the
              ;; original statement unchanged.
              (let-values ([(lifted cleaned) (lift-seq-prefix-exprs expr)])
                (cond
                  [(null? lifted) (list stmt)]
                  [else
                   (let ([new-stmt
                          (with-output-language (Ltypescript Statement)
                            `(statement-expression ,cleaned))])
                     (append
                       (apply append (map stmt-flatten lifted))
                       (list new-stmt)))]))])]
          [else (list stmt)]))

      ;; const-binding?: detect a `(const src local expr)` and pull out
      ;; the binder's var-name and the bound expression. Returns
      ;; (cons var-name expr) on a match, #f otherwise.
      (define (const-binding stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(const ,src ,local ,expr)
           (nanopass-case (Ltypescript Argument) local
             [(,var-name ,type) (cons var-name expr)])]
          [else #f]))

      ;; const-binding-decl-type: like const-binding, but returns the
      ;; binder's declared Type (or #f if `stmt` isn't a const-binding).
      ;; Used by Prod-9 to detect Field-typed integer literals at RHS
      ;; (e.g. `const tmp_0: Field = 42n;`) so the emitter can wrap them
      ;; in `Fr::from(<n>u64)` instead of leaving a bare i32 literal that
      ;; later fails the `Into<AlignedValue>` bound at the ledger-write
      ;; builder call site.
      (define (const-binding-decl-type stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(const ,src ,local ,expr)
           (nanopass-case (Ltypescript Argument) local
             [(,var-name ,type) type])]
          [else #f]))

      ;; literal-int-expr?: returns the integer datum when `expr` strips
      ;; (through safe-cast layers) down to a `(quote ... <int>)` literal,
      ;; or #f otherwise.
      (define (literal-int-expr? expr)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(quote ,src ,datum)
             (and (integer? datum) (exact? datum) datum)]
            [else #f])))

      ;; type-is-tfield?: is `type` a (tfield ...)? Peels nominal/transparent
      ;; talias layers so `type Foo = Field;` also matches.
      (define (type-is-tfield? type)
        (and type
             (nanopass-case (Ltypescript Type) type
               [(tfield ,src) #t]
               [(talias ,src ,nominal? ,type-name ,type^)
                (type-is-tfield? type^)]
               [else #f])))

      ;; type-peel-tunsigned: if `type` is a (tunsigned src nat) (possibly
      ;; through a talias chain), return the `nat` upper bound; otherwise #f.
      ;; Companion to `type-is-tfield?` for Prod-13's Uint<N> literal path.
      (define (type-peel-tunsigned type)
        (and type
             (nanopass-case (Ltypescript Type) type
               [(tunsigned ,src ,nat) nat]
               [(talias ,src ,nominal? ,type-name ,type^)
                (type-peel-tunsigned type^)]
               [else #f])))

      ;; uniquify-rust-name: Prod-14 — Compact's frontend lowering produces
      ;; per-statement `const tmp = ...; <ledger> = tmp;` shapes, so a
      ;; constructor body like
      ;;     admin = 42;
      ;;     count = 7;
      ;; lowers into TWO const-bindings both named `tmp`. Each binding maps
      ;; to a distinct id (and `local-binds` keys are eq-compared), but the
      ;; emitted Rust shares the same `let tmp = ...` string and shadows.
      ;; By the time the OpProgram builder consumes each `new_cell(<rust-name>.
      ;; clone())`, only the LAST `let tmp = …` is in scope, so every cell
      ;; reads the wrong value.
      ;;
      ;; Suffix the proposed name with `_N` until it doesn't collide with
      ;; any prior `local-binds` entry's rust-name. First occurrence keeps
      ;; the unsuffixed form to preserve existing snapshots (most fixtures
      ;; have at most one literal-RHS slot per body).
      (define (uniquify-rust-name proposed local-binds)
        (let ([taken (map cdr local-binds)])
          (cond
            [(not (member proposed taken)) proposed]
            [else
             (let loop ([n 0])
               (let ([candidate (format "~a_~a" proposed n)])
                 (cond
                   [(member candidate taken) (loop (fx+ n 1))]
                   [else candidate])))])))

      ;; coerce-literal-rhs-rendered: Prod-9/Prod-13 — typed integer literals
      ;; need to be rendered with the correct Rust type so the ledger-write
      ;; builder's `Into<AlignedValue>` bound is satisfied.
      ;;   - `tfield`: wrap as `Fr::from(<n>u64)`.
      ;;   - `tunsigned`: append the width suffix (`<n>u8` .. `<n>u128`) so
      ;;     the literal types as the same Rust primitive the ledger field
      ;;     uses. Without this, `ledger v: Uint<64>; v = 42;` lowered into
      ;;     `let tmp = 42; new_cell(tmp.clone())` — the bare i32 fails the
      ;;     `Into<AlignedValue>` bound (Prod-13).
      ;; All other RHS shapes return #f so the caller falls back to its
      ;; existing rendering.
      (define (coerce-literal-rhs-rendered decl-type rhs)
        (cond
          [(type-is-tfield? decl-type)
           (let ([n (literal-int-expr? rhs)])
             (and n (format "Fr::from(~au64)" n)))]
          [(type-peel-tunsigned decl-type) =>
           (lambda (nat)
             (let ([n (literal-int-expr? rhs)])
               (and n (format "~a~a" n (uint-rust-width nat)))))]
          [else #f]))

      ;; const-decl-only?: detect a `(const ,src (,local* ...))` Statement —
      ;; the "forward declaration" form produced by typescript-passes when a
      ;; `let* ([%tmp ...])` is lifted out of an expression context. These
      ;; carry no initializer; the actual assignment lands later as a
      ;; `(statement-expression (= ,src ,var-name ,expr))`. In the Rust
      ;; emission this is a no-op — the eventual `(= ...)` becomes a
      ;; plain `let <name> = <expr>;`. Returns #t on match, #f otherwise.
      (define (const-decl-only? stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(const ,src (,local* ...)) #t]
          [else #f]))

      ;; stmt->assignment: detect a `(statement-expression (= src var-name
      ;; expr))` and return (cons var-name expr). The assignment Expression
      ;; is what typescript-passes emits for `<name> = <expr>` after lifting
      ;; a let* temp out of a containing expression — see lifted-temp
      ;; comments above. Returns #f for anything else.
      (define (stmt->assignment stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(= ,src ,var-name ,expr^) (cons var-name expr^)]
             [else #f])]
          [else #f]))

      ;; expr-strip-cast: peel safe-cast layers from an Expression. The
      ;; typechecker inserts `safe-cast` to widen the source literal
      ;; (e.g. `1: Uint<1>`) up to the ADT op's declared parameter type
      ;; (e.g. `Uint16` for `Counter.increment`). For literal-int
      ;; arguments the cast is value-preserving, so we look through it
      ;; before extracting the literal.
      (define (expr-strip-cast expr)
        (nanopass-case (Ltypescript Expression) expr
          [(safe-cast ,src ,type ,type^ ,expr^) (expr-strip-cast expr^)]
          [else expr]))

      ;; expr-resolve: chase a `var-ref` through the local-binding alist
      ;; built from preceding `const` statements, then strip any
      ;; cast layers. Returns the underlying Expression or #f if the
      ;; chain hits something we don't recognise.
      (define (expr-resolve expr binds)
        ;; Pass through unknown var-refs unchanged. Originally this
        ;; returned #f to signal "unresolvable", but that prevented
        ;; legitimate Iter 6 use cases (the fold loop variable is bound
        ;; outside `binds` and substituted per-iteration by
        ;; emit-for-iter-terminal). Downstream callers (e.g.
        ;; branch->single-pl-call, stmt->single-public-ledger-call)
        ;; still test for #f via `(memv #f resolved)`; with this change
        ;; that test never fires for var-refs alone. Other shapes (e.g.
        ;; an unsupported expression form via expr-strip-cast) still
        ;; fall through to the `[else e]` arm — they keep their original
        ;; representation, and downstream emission rejects them through
        ;; `expr-supported?` / vm-code expansion rather than via #f here.
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(var-ref ,src ,var-name)
             (cond
               [(assq var-name binds) =>
                (lambda (p) (expr-resolve (cdr p) binds))]
               [else e])]
            [else e])))

      ;; stmt->single-public-ledger-call: detect the narrow I3a shape —
      ;; a flat statement sequence consisting of zero or more `const`
      ;; bindings followed by exactly one `(public-ledger ...)` call
      ;; (e.g. counter.compact's `round.increment(1);` which the
      ;; frontend lowers to `const tmp = safe-cast 1; round.increment(tmp);`).
      ;; On a match returns
      ;;   (list path-elt* adt-op resolved-expr*)
      ;; where each resolved-expr has had var-refs chased through the
      ;; const-binding alist and surrounding safe-casts peeled. Returns
      ;; #f for anything we don't yet support.
      (define (stmt->single-public-ledger-call stmt)
        (let loop ([stmts (stmt-flatten stmt)] [binds '()])
          (cond
            [(null? stmts) #f]
            [(const-binding (car stmts)) =>
             (lambda (b) (loop (cdr stmts) (cons b binds)))]
            [else
             (and
               ;; Exactly one terminal statement-expression.
               (null? (cdr stmts))
               (nanopass-case (Ltypescript Statement) (car stmts)
                 [(statement-expression ,expr)
                  (nanopass-case (Ltypescript Expression) expr
                    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
                     (let ([resolved (map (lambda (e) (expr-resolve e binds)) expr*)])
                       (if (memv #f resolved)
                           #f
                           (list path-elt* adt-op resolved)))]
                    [else #f])]
                 [else #f]))])))

      ;; path-elt->vm-value: turn a Path-Element into the VM value that
      ;; `expand-vm-code` expects to see in the `f` argument. For path
      ;; indices (constant nats locating a ledger field) we emit a
      ;; `(VMalign path-index 1)` exactly as typescript-passes.ss does
      ;; (see line 695). Typed path elements (`(src type expr)`) — used
      ;; when the path includes a runtime expression, e.g. a Map key —
      ;; are not part of the I3a wedge; we return #f so the caller falls
      ;; back to `unimplemented!()` for those.
      (define (path-elt->vm-value path-elt)
        (nanopass-case (Ltypescript Path-Element) path-elt
          [,path-index (VMalign path-index 1)]
          [else #f]))

      ;; vm-rust-expr is a thin carrier record used to ferry a pre-rendered
      ;; Rust expression string through `expand-vm-code`. It lets the I3a
      ;; entry collapse non-literal circuit arguments (e.g. a Bytes32 var-ref
      ;; like `pk` or a pure-circuit result like `cm`) into a single Scheme
      ;; value that survives macro expansion intact, then surfaces back out
      ;; at `vminstr->builder-call` time so the push for that arg lowers to
      ;; the right Rust expression. Counter's literal-int path is preserved
      ;; unchanged (integers are still plain Scheme numbers).
      (define-record-type vm-rust-expr
        (nongenerative)
        (fields text))

      ;; expr->vm-value: turn a circuit argument Expression into a value
      ;; that the VM code can consume. Counter's `round.increment(1)`
      ;; passes the constant `1`; the vm-code wraps that in
      ;; `(rt-value->int amount)`, producing `(VMvalue->int <int>)` after
      ;; expansion, which we unwrap in vminstr->builder-call. For E4 the
      ;; insert ops pass a non-literal (e.g. `pk` / `cm`), so we also
      ;; accept any expression `expr-rust` can render and lift it into a
      ;; `vm-rust-expr` carrier — vminstr->builder-call recognises the
      ;; carrier when surfacing the push value. Returns #f only when the
      ;; expression itself can't be rendered.
      ;;
      ;; `native-id-ht` lets us route var-refs to native bindings (e.g.
      ;; arg names that came in via emit-circuit-args) when needed; the
      ;; counter literal-only path doesn't need it (and historically
      ;; didn't take it), so it defaults to #f and we only invoke
      ;; expr-rust when the expression isn't a plain literal.
      (define (expr->vm-value expr . opt-native-ht)
        (nanopass-case (Ltypescript Expression) expr
          [(quote ,src ,datum)
           (if (and (integer? datum) (exact? datum)) datum #f)]
          [else
           (let ([native-ht (and (pair? opt-native-ht) (car opt-native-ht))])
             (and native-ht
                  (let ([rendered (guard (c [#t #f]) (expr-rust expr native-ht))])
                    (and rendered
                         (make-vm-rust-expr
                           (expr-rust-arg-cloned expr rendered))))))]))

      ;; expr-rust-arg-cloned: given the original expression and its
      ;; expr-rust-rendered text, suffix `.clone()` when the expression
      ;; is a var-ref / elt-ref to a non-Copy local. Mirrors
      ;; arg-rust-clone-if-var's predicate (without re-rendering, since
      ;; expr-rust has already produced the text). Used by the
      ;; assert-cond / read-with-arg path where `expr-rust` (not
      ;; `ctor-expr-rust`) produces the inner text.
      (define (expr-rust-arg-cloned expr rendered)
        (let ([stripped (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) stripped
            [(var-ref ,src ,var-name)
             (if (var-ref-known-copy? var-name)
                 rendered
                 (string-append rendered ".clone()"))]
            [(elt-ref ,src ,expr ,elt-name ,nat)
             (cond
               [(not (elt-ref-rooted-in-var? stripped)) rendered]
               [(elt-ref-known-copy? stripped) rendered]
               [else (string-append rendered ".clone()")])]
            [else rendered])))

      ;; vm-immediate->int: given the value the vm-code computed for an
      ;; `[immediate ...]` argument, unwrap a `(VMvalue->int n)` (the
      ;; standard wrap produced by `(rt-value->int amount)`) into the
      ;; underlying integer. Returns #f if the value isn't a plain
      ;; literal-flavoured immediate.
      (define (vm-immediate->int v)
        (cond
          [(and (integer? v) (exact? v)) v]
          [(VMop? v)
           (VMop-case v
             [(VMvalue->int x)
              (if (and (integer? x) (exact? x)) x #f)]
             [else #f])]
          [else #f]))

      ;; vm-path->indices: given the value bound to `path` (typically the
      ;; whole `f` list in the vm-code), return a list of integer indices
      ;; if every element is a `(VMalign nat 1)`. Returns #f otherwise so
      ;; richer paths fall back to `unimplemented!()`.
      (define (vm-path->indices v)
        (cond
          [(not (list? v)) #f]
          [else
           (let loop ([xs v] [acc '()])
             (cond
               [(null? xs) (reverse acc)]
               [(VMop? (car xs))
                (VMop-case (car xs)
                  [(VMalign value bytes)
                   (if (and (= bytes 1) (integer? value) (exact? value))
                       (loop (cdr xs) (cons value acc))
                       #f)]
                  [else #f])]
               [else #f]))]))

      ;; vm-cell-elem->rust: render the inner expression of a
      ;; (VMstate-value-cell <elem>) form as the Rust expression that
      ;; should be wrapped in `new_cell(...)`. Recognises:
      ;;   - a plain integer literal              → "<n>u8"  (counter-style)
      ;;   - a VMalign with bytes=1               → "<n>u8"
      ;;   - a vm-rust-expr carrier               → the carrier's text
      ;;   - a VMleaf-hash wrapping any of the above
      ;;       → "leaf_hash(&ValueReprAlignedValue(AlignedValue::from(<inner>)))"
      ;;     (matches midnight-onchain-runtime's program_fragments shape)
      ;; Returns #f for anything we don't yet know how to render so the
      ;; caller can fall back to `unimplemented!()`.
      (define (vm-cell-elem->rust elem)
        (cond
          [(and (integer? elem) (exact? elem))
           (format "~au8" elem)]
          [(vm-rust-expr? elem)
           (vm-rust-expr-text elem)]
          [(VMop? elem)
           (VMop-case elem
             [(VMalign value bytes)
              (cond
                [(and (= bytes 1) (integer? value) (exact? value))
                 (format "~au8" value)]
                [else #f])]
             [(VMleaf-hash x)
              (let ([inner (vm-cell-elem->rust x)])
                (and inner
                     (format
                       "leaf_hash(&ValueReprAlignedValue(AlignedValue::from(~a)))"
                       inner)))]
             [else #f])]
          [else #f]))

      ;; ltypescript-type-is-tadt?: returns #t when an Ltypescript Type is a
      ;; tadt (public-adt) form, peeling talias layers. Used by
      ;; vm-value->rust-state-value below to decide whether a
      ;; `VMstate-value-ADT val type` form wraps its `val` in `new_cell(...)`
      ;; (the leaf path — value_type is a non-ADT like Field/Uint/Bytes) or
      ;; surfaces the ADT directly (the recursive path — value_type is a
      ;; nested Map/Set/MerkleTree). Mirrors typescript-passes.ss's
      ;; `public-adt?` branch for `VMstate-value-ADT`.
      (define (ltypescript-type-is-tadt? type)
        (nanopass-case (Ltypescript Type) type
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
          [(talias ,src ,nominal? ,type-name ,type) (ltypescript-type-is-tadt? type)]
          [else #f]))

      ;; vm-value->rust-state-value: render a state-value form (the kind
      ;; that appears as the `value` arg of a `push` vm-instruction) as
      ;; a Rust expression of type `StateValue<DefaultDB>`. Returns #f if
      ;; the form isn't one we yet know how to translate.
      ;;
      ;; G: `VMstate-value-ADT val type` — Map.insert's value-side push uses
      ;; this form because `state-value 'ADT value value_type` carries the
      ;; declared value_type. For non-public-adt value types (Field, Uint*,
      ;; Bytes<N>, …) the runtime semantics are identical to a plain
      ;; `VMstate-value-cell val` (typescript-passes wraps with
      ;; `StateValue.newCell`); we mirror that here so Map<K, leaf> insert
      ;; lowers to the same `.push(true, new_cell(<v>))` shape Set.insert
      ;; uses with its `(state-value 'null)`. tadt-typed values aren't yet
      ;; needed (Map<K, Map<…>> etc.) — return #f for those so the caller
      ;; falls back to `unimplemented!()`.
      (define (vm-value->rust-state-value val)
        (cond
          [(VMop? val)
           (VMop-case val
             [(VMstate-value-null) "StateValue::Null"]
             [(VMstate-value-cell inner)
              (let ([rust-inner (vm-cell-elem->rust inner)])
                (and rust-inner (format "new_cell(~a)" rust-inner)))]
             [(VMstate-value-ADT inner adt-type)
              (cond
                [(ltypescript-type-is-tadt? adt-type) #f]
                [else
                 (let ([rust-inner (vm-cell-elem->rust inner)])
                   (and rust-inner (format "new_cell(~a)" rust-inner)))])]
             [else #f])]
          [else #f]))

      ;; vminstr->builder-call: render a single vminstr as one line of the
      ;; OpProgramVerify builder chain (already indented for inclusion
      ;; inside the `let ops = ...` block). Recognises the ops needed by
      ;; counter (`idx`, `addi`, `ins`) plus the vm-ops emitted by Set /
      ;; MerkleTree / HistoricMerkleTree `insert` vm-code (`push`, `dup`,
      ;; `root`). Anything else returns #f so the caller can bail out to
      ;; the `unimplemented!()` fallback rather than emit syntactically-
      ;; valid but semantically-wrong Rust.
      (define (vminstr->builder-call v)
        (let ([op (vminstr-op v)]
              [args (vminstr-arg* v)])
          (cond
            [(string=? op "idx")
             (let* ([cached-pair (assoc "cached" args)]
                    [push-pair (assoc "pushPath" args)]
                    [path-pair (assoc "path" args)])
               (cond
                 [(not (and cached-pair push-pair path-pair)) #f]
                 [else
                  (let ([indices (vm-path->indices (cdr path-pair))]
                        [push-path (cdr push-pair)])
                    (cond
                      ;; Single-element path → use the .idx_at_index
                      ;; shorthand (matches the existing read template;
                      ;; restores byte-parity with counter's snapshot).
                      [(and indices (= (length indices) 1))
                       (format "            .idx_at_index(~au8, ~a)\n"
                               (car indices)
                               (if push-path "true" "false"))]
                      [else #f]))]))]
            [(string=? op "addi")
             (let ([imm-pair (assoc "immediate" args)])
               (cond
                 [(not imm-pair) #f]
                 [else
                  (let* ([imm (cdr imm-pair)]
                         [n (vm-immediate->int imm)])
                    (cond
                      ;; Literal integer (counter's `round.increment(1)`
                      ;; lowers the `1` to a Scheme exact int that
                      ;; vm-immediate->int unwraps directly).
                      [n (format "            .addi(~a)\n" n)]
                      ;; A4: when a multi-stmt body lowers an integer
                      ;; literal arg through a const-binding (Prod-14's
                      ;; `let tmp = 1u16; ops.increment(tmp);` shape),
                      ;; the `addi` immediate carries a vm-rust-expr
                      ;; whose `.text` is the rendered Rust reference
                      ;; (e.g. "tmp.clone()"). Emit it as a Rust
                      ;; expression cast to u32 (the addi parameter
                      ;; width per runtime-rs/src/op_builder.rs:61).
                      ;; The const-binding's source type might be
                      ;; u8/u16/u32/u64 depending on the literal's
                      ;; declared Uint<N> bound; `as u32` is the
                      ;; conservative target. Counter.increment's amount
                      ;; is typed Uint<32> on the runtime side, so this
                      ;; cast never silently truncates valid inputs.
                      [(vm-rust-expr? imm)
                       (format "            .addi(~a as u32)\n"
                               (vm-rust-expr-text imm))]
                      ;; Some `(VMvalue->int <vm-rust-expr>)` wrapping is
                      ;; also possible if the immediate went through the
                      ;; full vm-value path. Unwrap once.
                      [(and (VMop? imm)
                            (VMop-case imm
                              [(VMvalue->int x) (vm-rust-expr? x)]
                              [else #f]))
                       (let ([inner
                              (VMop-case imm
                                [(VMvalue->int x) x]
                                [else #f])])
                         (format "            .addi(~a as u32)\n"
                                 (vm-rust-expr-text inner)))]
                      [else #f]))]))]
            [(string=? op "ins")
             (let ([cached-pair (assoc "cached" args)]
                   [n-pair (assoc "n" args)])
               (cond
                 [(not (and cached-pair n-pair)) #f]
                 [else
                  (let ([n (cdr n-pair)])
                    (and (integer? n) (exact? n)
                         (format "            .ins(~a, ~a)\n"
                                 (if (cdr cached-pair) "true" "false")
                                 n)))]))]
            [(string=? op "push")
             (let ([storage-pair (assoc "storage" args)]
                   [value-pair (assoc "value" args)])
               (cond
                 [(not (and storage-pair value-pair)) #f]
                 [else
                  (let ([rust-val (vm-value->rust-state-value (cdr value-pair))])
                    (and rust-val
                         (format "            .push(~a, ~a)\n"
                                 (if (cdr storage-pair) "true" "false")
                                 rust-val)))]))]
            [(string=? op "dup")
             (let ([n-pair (assoc "n" args)])
               (cond
                 [(not n-pair) #f]
                 [else
                  (let ([n (cdr n-pair)])
                    (and (integer? n) (exact? n)
                         (format "            .dup(~a)\n" n)))]))]
            [(string=? op "root")
             (cond
               [(null? args) "            .root()\n"]
               [else #f])]
            [else #f])))

      ;; vminstr->gather-builder-call: like vminstr->builder-call but for
      ;; OpProgramGather chains emitted inline by emit-ledger-read-expr
      ;; (ADT `read` ops with args, e.g. Set.member, HistoricMerkleTree
      ;; .checkRoot, Map.member). Uses 16-space indentation to match the
      ;; existing read-expr block template and emits the additional ops
      ;; that read vm-code uses but write vm-code doesn't: `popeq` (no
      ;; result value in Gather mode), `member`, and `eq`. The `popeq`
      ;; arg layout matches Op::Popeq's `(cached, ())` Gather signature
      ;; via OpProgramGather::popeq(cached). Returns #f for ops we don't
      ;; know how to render so the caller falls back to the no-arg
      ;; hardcoded template.
      (define (vminstr->gather-builder-call v)
        (let ([op (vminstr-op v)]
              [args (vminstr-arg* v)])
          (cond
            [(string=? op "idx")
             (let* ([cached-pair (assoc "cached" args)]
                    [push-pair (assoc "pushPath" args)]
                    [path-pair (assoc "path" args)])
               (cond
                 [(not (and cached-pair push-pair path-pair)) #f]
                 [else
                  (let ([indices (vm-path->indices (cdr path-pair))]
                        [push-path (cdr push-pair)])
                    (cond
                      [(and indices (= (length indices) 1))
                       (format "                .idx_at_index(~au8, ~a)\n"
                               (car indices)
                               (if push-path "true" "false"))]
                      [else #f]))]))]
            [(string=? op "dup")
             (let ([n-pair (assoc "n" args)])
               (cond
                 [(not n-pair) #f]
                 [else
                  (let ([n (cdr n-pair)])
                    (and (integer? n) (exact? n)
                         (format "                .dup(~a)\n" n)))]))]
            [(string=? op "push")
             (let ([storage-pair (assoc "storage" args)]
                   [value-pair (assoc "value" args)])
               (cond
                 [(not (and storage-pair value-pair)) #f]
                 [else
                  (let ([rust-val (vm-value->rust-state-value (cdr value-pair))])
                    (and rust-val
                         (format "                .push(~a, ~a)\n"
                                 (if (cdr storage-pair) "true" "false")
                                 rust-val)))]))]
            [(string=? op "member")
             (cond
               [(null? args) "                .member()\n"]
               [else #f])]
            [(string=? op "eq")
             (cond
               [(null? args) "                .eq()\n"]
               [else #f])]
            [(string=? op "root")
             (cond
               [(null? args) "                .root()\n"]
               [else #f])]
            [(string=? op "popeq")
             (let ([cached-pair (assoc "cached" args)])
               (cond
                 [(not cached-pair) #f]
                 [else
                  (format "                .popeq(~a)\n"
                          (if (cdr cached-pair) "true" "false"))]))]
            [else #f])))

      ;; emit-public-ledger-call-body: emit the I3a body — an
      ;; OpProgramVerify builder chain matching the adt-op's vm-code,
      ;; followed by the query_for_verify wrapper + Ok return. Returns #t
      ;; on success, #f if any step (path translation, vm-code expansion,
      ;; vminstr rendering) couldn't be handled — the caller falls back
      ;; to `unimplemented!()` in that case.
      (define (emit-public-ledger-call-body src adt-op path-elt* expr*)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (cond
             [(not (fx= (length expr*) (length var-name*))) #f]
             [else
              ;; Lift each path-elt + expr to a VM value (#f on anything
              ;; we don't yet know how to translate) before invoking
              ;; expand-vm-code. We bail out as soon as we hit something
              ;; unsupported so the placeholder is preserved.
              (let ([path-vals (map path-elt->vm-value path-elt*)]
                    [expr-vals (map expr->vm-value expr*)])
                (cond
                  [(memv #f path-vals) #f]
                  [(memv #f expr-vals) #f]
                  [else
                   (let* ([arg-alist
                           (append (map cons adt-formal* adt-arg*)
                                   (map (lambda (var-name v)
                                          (cons (id-sym var-name) v))
                                        var-name*
                                        expr-vals))]
                          [vminstr*
                           (expand-vm-code src path-vals #f arg-alist
                             (vm-code-code vm-code))]
                          [lines (map vminstr->builder-call vminstr*)])
                     (cond
                       [(memv #f lines) #f]
                       [else
                        (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
                        (for-each out lines)
                        (out "            .build();\n")
                        (out "\n")
                        (out "        let results = query_for_verify(\n")
                        (out "            &ctx.current_query_context,\n")
                        (out "            &ops,\n")
                        (out "            ctx.gas_limit.clone(),\n")
                        (out "            &ctx.cost_model,\n")
                        (out "        )?;\n")
                        (out "\n")
                        (out "        Ok(CircuitResults {\n")
                        (out "            result: (),\n")
                        (out "            context: CircuitContext {\n")
                        (out "                current_query_context: results.context,\n")
                        (out "                ..ctx\n")
                        (out "            },\n")
                        (out "            gas_cost: results.gas_cost,\n")
                        (out "        })\n")
                        #t]))]))])]))

      ;; emit-if-expression-body: emit the I3b/4 body shape — a single
      ;; if-expression in statement position producing a non-unit value.
      ;; The cond / then / else are rendered via ctor-expr-rust so existing
      ;; logic for inlining `in_state`, ledger reads in expression position,
      ;; and `some` / `none` runtime mapping all apply uniformly.
      ;;
      ;; Returns #t on success, #f if any rendered sub-expression contains
      ;; an `unimplemented!()` marker (caller falls back to `unimplemented!()`).
      ;;
      ;; The wrap uses `RunningCost::default()` since there are no ledger
      ;; writes — pure read-only circuits don't run query_for_verify.
      (define (emit-if-expression-body return-type cond-expr then-expr else-expr
                                       native-id-ht witness-id-ht circuit-id-ht)
        (let* ([cond-str (cond-rust cond-expr '()
                                    native-id-ht witness-id-ht circuit-id-ht)]
               [then-str (ctor-expr-rust then-expr '()
                                         native-id-ht witness-id-ht circuit-id-ht)]
               [else-str (ctor-expr-rust else-expr '()
                                         native-id-ht witness-id-ht circuit-id-ht)])
          (cond
            [(or (rendered-has-todo? cond-str)
                 (rendered-has-todo? then-str)
                 (rendered-has-todo? else-str))
             #f]
            [else
             (out (format "        let result = if ~a {\n" cond-str))
             (out (format "            ~a\n" then-str))
             (out "        } else {\n")
             (out (format "            ~a\n" else-str))
             (out "        };\n")
             (out "        Ok(CircuitResults {\n")
             (out "            result,\n")
             (out "            context: ctx,\n")
             (out "            gas_cost: compact_runtime::RunningCost::default(),\n")
             (out "        })\n")
             #t])))

      ;; rendered-has-todo?: returns #t if the rendered Rust string
      ;; contains a TODO marker (`/* TODO`). Used by body emitters to
      ;; bail out (fall through to the method-level rust-feature-error)
      ;; when a sub-render produced a partially-supported placeholder
      ;; like `/* TODO ... */ true` (still valid Rust, but not
      ;; production-ready). Sub-renders that hit truly-unsupported
      ;; paths now raise via rust-feature-error rather than emit an
      ;; `unimplemented!()` string, so the predicate only needs to
      ;; scan for the `/* TODO` form.
      (define (rendered-has-todo? s)
        (and (string? s)
             (substring? s "/* TODO")))

      ;; substring?: simple substring search. Returns #t if `needle` appears
      ;; anywhere in `haystack`.
      (define (substring? haystack needle)
        (let ([hl (string-length haystack)]
              [nl (string-length needle)])
          (and (fx>= hl nl)
               (let loop ([i 0])
                 (cond
                   [(fx> (fx+ i nl) hl) #f]
                   [(string=? (substring haystack i (fx+ i nl)) needle) #t]
                   [else (loop (fx+ i 1))])))))

      ;; cond-rust: render a boolean condition expression. Like
      ;; ctor-expr-rust but for `(call ...)` of an impure circuit
      ;; (e.g. tiny.compact's `in_state`) we try inline-circuit-call
      ;; first, since impure circuits can't be a direct Rust call target.
      (define (cond-rust expr local-binds
                         native-id-ht witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...)
             (let ([ne (eq-hashtable-ref native-id-ht function-name #f)]
                   [w (eq-hashtable-ref witness-id-ht function-name #f)]
                   [c (eq-hashtable-ref circuit-id-ht function-name #f)])
               (cond
                 [(or ne w (and c (id-pure? function-name)))
                  (ctor-expr-rust e local-binds
                                  native-id-ht witness-id-ht circuit-id-ht)]
                 [c
                  (or (inline-circuit-call c expr* local-binds
                                           native-id-ht witness-id-ht circuit-id-ht)
                      (format "/* TODO M3-I3b/4: inline ~a in if-cond */ true"
                              (id-sym function-name)))]
                 [else
                  (format "/* TODO M3-I3b/4: inline ~a in if-cond */ true"
                          (id-sym function-name))]))]
            [else
             (ctor-expr-rust e local-binds
                             native-id-ht witness-id-ht circuit-id-ht)])))

      ;; emit-impure-circuit: emit an impure circuit as a method on
      ;; `impl<PS, W> Contract<PS, W>`. Takes `&self, ctx: CircuitContext<PS>`
      ;; plus the source-level args typed via type-rust, and returns
      ;; `Result<CircuitResults<PS, T>, CompactError>` for the declared T.
      ;;
      ;; I3a recognises the narrow shape — a single `(public-ledger ...)`
      ;; statement returning `()` (e.g. counter.compact's
      ;; `round.increment(1);`) — and emits the corresponding Op program
      ;; via `expand-vm-code`. Anything richer keeps the `unimplemented!()`
      ;; placeholder so I3b+ can take it on without losing the build.
      (define (emit-impure-circuit cdefn native-id-ht witness-id-ht circuit-id-ht)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
           ;; Exported impure circuits land on the public Contract API.
           ;; Non-exported ones are private helpers callable from bare-call
           ;; statements in other circuit bodies — same emission shape, but
           ;; `pub(crate)` so downstream crates don't see them. Mirrors the
           ;; pure-circuit visibility convention in emit-pure-circuit.
           (out (format "    ~a fn ~a(\n"
                        (if (id-exported? function-name) "pub" "pub(crate)")
                        (camel->snake (id-sym function-name))))
           (out "        &self,\n")
           (out "        ctx: CircuitContext<PS>")
           (emit-circuit-args arg*)
           (out (format ",\n    ) -> Result<CircuitResults<PS, ~a>, CompactError> {\n"
                        (type-rust type)))
           (parameterize ([current-formal-arg-types (build-formal-arg-type-ht arg*)])
           (let ([emitted?
                  (or
                    ;; I3b/4: single if-expression body returning non-unit.
                    ;; tiny.compact's `get()` lowers to this shape. We dispatch
                    ;; before the unit-only paths so a non-unit if-body
                    ;; doesn't fall through to `unimplemented!()`.
                    (let ([parts (stmt->if-expression-body stmt)])
                      (and parts
                           (not (unit-type? type))
                           (emit-if-expression-body
                             type (car parts) (cadr parts) (caddr parts)
                             native-id-ht witness-id-ht circuit-id-ht)))
                    (and (unit-type? type)
                         (or
                           ;; I3a: counter-style single public-ledger call.
                           (let ([call (stmt->single-public-ledger-call stmt)])
                             (and call
                                  (emit-public-ledger-call-body
                                    src
                                    (cadr call)        ; adt-op
                                    (car call)         ; path-elt*
                                    (caddr call))))    ; expr*
                           ;; I3b/2: tiny.compact `set`-style body — leading
                           ;; asserts + const bindings + ledger writes. We
                           ;; pre-validate via body-walkable? so partial /
                           ;; broken emissions (e.g. tiny's `clear`, which
                           ;; needs `==` and `default<T>`) fall back to
                           ;; `unimplemented!()` rather than producing
                           ;; uncompilable Rust.
                           (and (body-walkable? stmt
                                                native-id-ht witness-id-ht circuit-id-ht)
                                (emit-body-or-fallback stmt 'circuit
                                                       native-id-ht witness-id-ht circuit-id-ht))
                           ;; Streaming walker for richer multi-stage bodies
                           ;; (zerocash.spend, election.vote$commit /
                           ;; vote$reveal). Triggered only when the simpler
                           ;; emit-body-or-fallback shape doesn't apply.
                           (and (body-streaming-walkable?
                                  stmt native-id-ht witness-id-ht circuit-id-ht)
                                (body-needs-streaming?
                                  stmt native-id-ht witness-id-ht circuit-id-ht)
                                (emit-streaming-body
                                  stmt native-id-ht witness-id-ht circuit-id-ht)))))])
             (unless emitted?
               (rust-feature-error src 'circuit-body-emission
                 "no walker shape matched circuit body for ~a"
                 (id-sym function-name))))
           (out "    }\n\n"))]))

      ;; bytevector->rust-array-literal: render a Scheme bytevector as a Rust
      ;; array literal `[N1u8, N2, ..., NK]`. The first element carries the
      ;; explicit `u8` suffix so the literal infers as `[u8; K]` without an
      ;; ascription. Used by expr-rust for `(quote src #vu8(...))`.
      (define (bytevector->rust-array-literal bv)
        (let* ([n (bytevector-length bv)]
               [parts
                (let loop ([i 0] [acc '()])
                  (cond
                    [(fx= i n) (reverse acc)]
                    [else
                     (let ([byte (bytevector-u8-ref bv i)])
                       (loop (fx+ i 1)
                             (cons
                               (if (fx= i 0)
                                   (format "~au8" byte)
                                   (format "~a" byte))
                               acc)))]))])
          (string-append
            "["
            (let join ([xs parts] [acc ""])
              (cond
                [(null? xs) acc]
                [(null? (cdr xs)) (string-append acc (car xs))]
                [else (join (cdr xs) (string-append acc (car xs) ", "))]))
            "]")))

      ;; arith-operand-rust: render an arithmetic operand and, when
      ;; `current-arith-suffix` is set and the rendered output is a
      ;; bare integer literal, append the suffix so Rust resolves the
      ;; surrounding wrapping_* inherent method against a concrete
      ;; integer type. Non-literal operands (var-refs, method calls,
      ;; nested arithmetic with their own suffix) are returned unmodified
      ;; — they already carry typing information through the enclosing
      ;; `as u<width>` cast emitted by the downcast-unsigned clause.
      ;;
      ;; Iter 7 follow-up: introduced to support non-identity lambdas
      ;; in `map()` (`x * 2 as Uint<64>` and friends).
      (define (arith-operand-rust expr native-id-ht)
        (let ([rendered (expr-rust expr native-id-ht)]
              [s (current-arith-suffix)])
          (cond
            [(and s (integer-literal-rendering? rendered))
             (string-append rendered s)]
            [else rendered])))

      ;; expr-rust: emit a Rust expression string for an Ltypescript
      ;; Expression. I3b/1 covers the variants needed by tiny.compact's
      ;; public_key body — bytevector literal, var-ref, tuple (array
      ;; literal), and call. Unknown variants emit a TODO placeholder so
      ;; the gap is visible in the generated code rather than crashing.
      ;;
      ;; `native-id-ht` is the eq-hashtable built by build-native-id-ht;
      ;; consulted at every `call` site to resolve the function-name id
      ;; back to its native-entry (and thus its Rust binding name).
      (define (expr-rust expr native-id-ht)
        (nanopass-case (Ltypescript Expression) expr
          [(safe-cast ,src ,type ,type^ ,expr^)
           ;; Iter 7: peel safe-cast layers transparently. The IR uses
           ;; safe-cast to widen literals (e.g. `1: Uint<1>` → `Uint<64>`)
           ;; inside tuple/vector arguments and map iterables. For our
           ;; rendering purposes the cast is value-preserving — the
           ;; underlying integer literal carries the right Rust integer
           ;; type once we ascribe it at the surrounding context (or
           ;; rely on Rust's inference from the array element type).
           ;; Mirrors `expr-strip-cast` but for the rendering path.
           (expr-rust expr^ native-id-ht)]
          [(quote ,src ,datum)
           (cond
             [(bytevector? datum) (bytevector->rust-array-literal datum)]
             [(boolean? datum) (if datum "true" "false")]
             [(and (integer? datum) (exact? datum)) (format "~a" datum)]
             [else (rust-feature-error src 'quote-variant
                     "unsupported quote datum: ~s" datum)])]
          [(var-ref ,src ,var-name)
           (symbol->string (camel->snake (id-sym var-name)))]
          [(tuple ,src ,tuple-arg* ...)
           ;; Compact's `Vector<N, T>` lowers to a Rust `[T; N]`. The IR
           ;; uses `tuple` for both tuples and vectors at the value level;
           ;; the immediate caller (e.g. a native taking a Vector) knows
           ;; which form is wanted. For I3b/1 we render every `tuple` as a
           ;; Rust array literal — the only consumer is persistent_hash,
           ;; where the elements have identical type ([u8; 32]).
           (let ([parts
                  (map (lambda (ta) (tuple-arg-rust ta native-id-ht))
                       tuple-arg*)])
             (string-append
               "["
               (let join ([xs parts] [acc ""])
                 (cond
                   [(null? xs) acc]
                   [(null? (cdr xs)) (string-append acc (car xs))]
                   [else (join (cdr xs) (string-append acc (car xs) ", "))]))
               "]"))]
          [(call ,src ,function-name ,expr* ...)
           (call-rust src function-name expr* native-id-ht)]
          [(default ,src ,type)
           ;; I3b/3: `default<T>` lowers to the type's zero value. Reuses
           ;; the K1 helper so tunsigned/tfield/tbytes/tenum/talias are
           ;; handled consistently with initial_state's per-field seed.
           (default-value-rust type)]
          [(== ,src ,type ,expr1 ,expr2)
           ;; I3b/3: equality comparison. Parenthesised so it composes
           ;; safely inside larger expressions (e.g. inside a Rust assert
           ;; macro call without surrounding parens being implicit).
           (format "(~a == ~a)"
                   (expr-rust expr1 native-id-ht)
                   (expr-rust expr2 native-id-ht))]
          [(not ,src ,expr)
           ;; F1.2: Boolean negation.
           (format "(!(~a))" (expr-rust expr native-id-ht))]
          [(and ,src ,expr1 ,expr2)
           ;; F1.2: short-circuit Boolean AND.
           (format "(~a && ~a)"
                   (expr-rust expr1 native-id-ht)
                   (expr-rust expr2 native-id-ht))]
          [(or ,src ,expr1 ,expr2)
           ;; F1.2: short-circuit Boolean OR.
           (format "(~a || ~a)"
                   (expr-rust expr1 native-id-ht)
                   (expr-rust expr2 native-id-ht))]
          [(elt-ref ,src ,expr ,elt-name ,nat)
           ;; F1.2: struct field access.
           (format "~a.~a"
                   (expr-rust expr native-id-ht)
                   (symbol->string elt-name))]
          [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
           ;; I3b/3: ledger read in expression position (e.g. inside an
           ;; `(==)` or as the RHS of a const-binding). Emits an inline
           ;; gather query against (current-qctx-ref) and decodes the
           ;; resulting AlignedValue using the same decoder table the
           ;; Ledger view uses. F1.2/2: passes expr* + native-id-ht to
           ;; cover ADT read-with-arg (Set.member etc).
           (emit-ledger-read-expr path-elt* adt-op expr* native-id-ht)]
          [(enum-ref ,src ,type ,elt-name)
           ;; E6: enum variant in expression position (pure circuit body).
           ;; Render as `EnumName::variant` (with Rust keyword escaping
           ;; via rust-variant-name). Used by election.successor — the
           ;; declared return type is the enum itself, so we must emit
           ;; typed variants rather than the bare u8 discriminant.
           (nanopass-case (Ltypescript Type) type
             [(tenum ,src^ ,enum-name ,elt-name^ ,elt-name* ...)
              (format "~a::~a"
                      (symbol->string enum-name)
                      (rust-variant-name elt-name))]
             [else
              (rust-feature-error src 'enum-ref-non-tenum
                "enum-ref ~a on non-tenum type"
                elt-name)])]
          [(+ ,src ,mbits ,expr1 ,expr2)
           ;; Iter 7 follow-up: unsigned addition. Renders via Rust's
           ;; `wrapping_add` so the bounded-Uint contract holds even if
           ;; the operation would overflow at the inferred Rust width —
           ;; Compact's typer requires an explicit `downcast-unsigned`
           ;; or wider target type around any expression that could
           ;; produce a value outside the source-side type's range, so
           ;; the wrap matches the post-downcast semantics.
           (format "(~a).wrapping_add(~a)"
                   (arith-operand-rust expr1 native-id-ht)
                   (arith-operand-rust expr2 native-id-ht))]
          [(- ,src ,mbits ,expr1 ,expr2)
           ;; Iter 7 follow-up: unsigned subtraction. See `+` clause.
           (format "(~a).wrapping_sub(~a)"
                   (arith-operand-rust expr1 native-id-ht)
                   (arith-operand-rust expr2 native-id-ht))]
          [(* ,src ,mbits ,expr1 ,expr2)
           ;; Iter 7 follow-up: unsigned multiplication. See `+` clause.
           (format "(~a).wrapping_mul(~a)"
                   (arith-operand-rust expr1 native-id-ht)
                   (arith-operand-rust expr2 native-id-ht))]
          [(downcast-unsigned ,src ,nat? ,nat ,expr)
           ;; Iter 7 follow-up: cast the inner expression to the Rust
           ;; unsigned type whose upper bound is `nat`. The downcast
           ;; appears around arithmetic whose declared output type is
           ;; narrower than its operands' inferred type (Compact's typer
           ;; inserts it for `(x * 2) as Uint<64>` and similar). The
           ;; expr-supported? gate already rejected non-ladder widths.
           ;;
           ;; The target width is also pushed down via `current-arith-suffix`
           ;; so nested arithmetic operands can apply a type suffix to
           ;; integer literals — Rust's `wrapping_mul` etc. are inherent
           ;; methods on `uN`, so the receiver must be a concrete `uN`
           ;; type (an unsuffixed `1.wrapping_mul(2)` would be rejected
           ;; with "can't call method on ambiguous numeric type").
           (let ([w (cond
                      [(= nat 255) "u8"]
                      [(= nat 65535) "u16"]
                      [(= nat 4294967295) "u32"]
                      [(= nat 18446744073709551615) "u64"]
                      [(= nat 340282366920938463463374607431768211455) "u128"]
                      [else #f])])
             (cond
               [(not w)
                (rust-feature-error src 'downcast-unsigned-width
                  "downcast-unsigned: unsupported target width ~s" nat)]
               [else
                (format "(~a) as ~a"
                        (parameterize ([current-arith-suffix w])
                          (expr-rust expr native-id-ht))
                        w)]))]
          [(new ,src ,type ,expr* ...)
           ;; F2.2: struct-literal in pure-expression context (e.g. nested
           ;; inside a quote/tuple consumer). Renders each field via the
           ;; raw expr-rust path; for the body-walker context the
           ;; corresponding case in ctor-expr-rust is used instead.
           (let* ([st (struct-of-type type)]
                  [struct-name (and st (car st))]
                  [elt-name* (and st (cadr st))])
             (cond
               [(or (not st)
                    (not (fx= (length expr*) (length elt-name*))))
                (rust-feature-error src 'struct-literal-mismatch
                  "struct-literal mismatch (st=~s, expected=~a, got=~a)"
                  (and st (car st))
                  (and st (length elt-name*))
                  (length expr*))]
               [else
                (let* ([field-strs
                        (map (lambda (name e)
                               (format "~a: ~a"
                                       (symbol->string name)
                                       (expr-rust e native-id-ht)))
                             elt-name* expr*)])
                  (string-append
                    (symbol->string struct-name)
                    " { "
                    (let join ([xs field-strs] [acc ""])
                      (cond
                        [(null? xs) acc]
                        [(null? (cdr xs)) (string-append acc (car xs))]
                        [else (join (cdr xs)
                                    (string-append acc (car xs) ", "))]))
                    " }"))]))]
          [else
           (rust-feature-error #f 'expr-variant
             "unhandled Expression variant in expr-rust")]))

      ;; emit-ledger-read-expr: render a `(public-ledger ... read)` IR
      ;; node as a Rust block expression that runs a gather query and
      ;; decodes the result. Used by expr-rust / ctor-expr-rust when the
      ;; read appears in expression position (clear()'s `apk == authority`,
      ;; in_state's inlined `state == s`, zerocash.spend's
      ;; `nullifiers.member(old)` and `commitments.checkRoot(...)`).
      ;;
      ;; The qctx source comes from the (current-qctx-ref) dynamic
      ;; parameter so circuit-body emissions read from
      ;; `&ctx.current_query_context` while constructor-body emissions
      ;; would read from `&qctx`.
      ;;
      ;; Optional `expr*` carries the ADT-read's runtime arguments (the
      ;; element for Set.member, the candidate root for
      ;; HistoricMerkleTree.checkRoot, the key for Map.member / lookup).
      ;; When present, we route through expand-vm-code + the gather
      ;; vminstr renderer so the resulting OpProgramGather chain mirrors
      ;; the adt-op's vm-code (including the additional push and
      ;; member / eq / root steps). When absent — the no-arg
      ;; Counter.read / cell.read case — we keep the original hardcoded
      ;; dup / idx / popeq template intact (no behaviour change for the
      ;; counter / tiny snapshots).
      ;; emit-struct-field-zero-read: F2.2 — emit a gather block for
      ;; reading a ledger cell whose value is a tstruct, decoding only
      ;; the leading (field-0) atom with the provided decoder. The
      ;; AlignedValue layout for a tstruct prepends field-0's atoms,
      ;; so `decoder(_av)` reads exactly the projected field's bytes.
      ;; Mirrors the no-arg branch of emit-ledger-read-expr but skips
      ;; the whole-struct decoder check.
      (define (emit-struct-field-zero-read path-elt* decoder)
        (let* ([path-idx*
                (map (lambda (pe)
                       (nanopass-case (Ltypescript Path-Element) pe
                         [,path-index path-index]
                         [else #f]))
                     path-elt*)]
               [idx-lines
                (let join ([xs path-idx*] [acc ""])
                  (cond
                    [(null? xs) acc]
                    [else
                     (join (cdr xs)
                           (string-append
                             acc
                             (format "                .idx_at_index(~au8, false)\n" (car xs))))]))])
          (string-append
            "{\n"
            "            let _gather_ops = OpProgramGather::<DefaultDB>::new()\n"
            "                .dup(0)\n"
            idx-lines
            "                .popeq(true)\n"
            "                .build();\n"
            "            let _gather_results = query_for_read(\n"
            "                " (current-qctx-ref) ",\n"
            "                &_gather_ops,\n"
            "                None,\n"
            "                &initial_cost_model(),\n"
            "            )\n"
            "            .map_err(|e| CompactError::AssertionFailed(format!(\"ledger query failed: {:?}\", e)))?;\n"
            "            let _av = match _gather_results.events.last() {\n"
            "                Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av,\n"
            "                _ => return Err(CompactError::AssertionFailed(\"ledger: expected Read event\".into())),\n"
            "            };\n"
            "            " decoder "(_av)?\n"
            "        }")))

      (define (emit-ledger-read-expr path-elt* adt-op . opt-args)
        (let* ([expr* (if (pair? opt-args) (car opt-args) '())]
               [native-ht (and (pair? opt-args) (pair? (cdr opt-args)) (cadr opt-args))])
          (nanopass-case (Ltypescript ADT-Op) adt-op
            [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
             (cond
               [(not (eq? op-class 'read))
                (rust-feature-error #f 'ledger-op-non-read
                  "non-read public-ledger op in expression position (op-class=~a)"
                  op-class)]
               [else
                (let* ([path-idx*
                        (map (lambda (pe)
                               (nanopass-case (Ltypescript Path-Element) pe
                                 [,path-index path-index]
                                 [else #f]))
                             path-elt*)]
                       [decoder (decoder-for-type type)])
                  (cond
                    [(memv #f path-idx*)
                     (rust-feature-error #f 'ledger-read-non-index-path
                       "ledger read with non-index path element")]
                    [(not decoder)
                     (rust-feature-error #f 'ledger-read-decoder-missing
                       "no decoder available for ledger read type")]
                    [(not (null? expr*))
                     ;; F1.2/2: ADT read-with-arg path. Run the adt-op's
                     ;; vm-code through expand-vm-code with the concrete
                     ;; path + lifted-arg substitutions, then render each
                     ;; vminstr as one line of the OpProgramGather chain.
                     ;; Falls back to `unimplemented!()` if any step is
                     ;; unsupported (e.g. an arg shape vm-value->rust
                     ;; doesn't yet handle).
                     (or
                       (emit-ledger-read-expr-with-args
                         path-elt* adt-op expr* native-ht decoder)
                       (rust-feature-error #f 'adt-read-with-arg-lowering
                         "ADT read-with-arg lowering failed for ledger op"))]
                    [else
                     (let ([idx-lines
                            (let join ([xs path-idx*] [acc ""])
                              (cond
                                [(null? xs) acc]
                                [else
                                 (join (cdr xs)
                                       (string-append
                                         acc
                                         (format "                .idx_at_index(~au8, false)\n" (car xs))))]))])
                       (string-append
                         "{\n"
                         "            let _gather_ops = OpProgramGather::<DefaultDB>::new()\n"
                         "                .dup(0)\n"
                         idx-lines
                         "                .popeq(true)\n"
                         "                .build();\n"
                         "            let _gather_results = query_for_read(\n"
                         "                " (current-qctx-ref) ",\n"
                         "                &_gather_ops,\n"
                         "                None,\n"
                         "                &initial_cost_model(),\n"
                         "            )\n"
                         "            .map_err(|e| CompactError::AssertionFailed(format!(\"ledger query failed: {:?}\", e)))?;\n"
                         "            let _av = match _gather_results.events.last() {\n"
                         "                Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av,\n"
                         "                _ => return Err(CompactError::AssertionFailed(\"ledger: expected Read event\".into())),\n"
                         "            };\n"
                         "            " decoder "(_av)?\n"
                         "        }"))]))])])))

      ;; emit-ledger-read-expr-with-args: F1.2/2 — render the ADT read
      ;; via expand-vm-code, producing a Rust block expression. Returns
      ;; #f if the path / args / vminstrs can't be lowered, so the
      ;; caller can fall back to the placeholder. `native-ht` may be #f
      ;; for cases where the caller didn't supply one — we then can't
      ;; render non-literal args and bail out.
      (define (emit-ledger-read-expr-with-args path-elt* adt-op expr* native-ht decoder)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (cond
             [(not (fx= (length expr*) (length var-name*))) #f]
             [else
              (let ([path-vals (map path-elt->vm-value path-elt*)]
                    [expr-vals
                     (map (lambda (e)
                            (if native-ht
                                (expr->vm-value e native-ht)
                                (expr->vm-value e)))
                          expr*)])
                (cond
                  [(memv #f path-vals) #f]
                  [(memv #f expr-vals) #f]
                  [else
                   (let* ([arg-alist
                           (append (map cons adt-formal* adt-arg*)
                                   (map (lambda (vn v)
                                          (cons (id-sym vn) v))
                                        var-name* expr-vals))]
                          [vminstr*
                           (guard (c [#t #f])
                             (expand-vm-code #f path-vals #f arg-alist
                               (vm-code-code vm-code)))]
                          [lines (and vminstr*
                                      (map vminstr->gather-builder-call vminstr*))])
                     (cond
                       [(or (not lines) (memv #f lines)) #f]
                       [else
                        (string-append
                          "{\n"
                          "            let _gather_ops = OpProgramGather::<DefaultDB>::new()\n"
                          (apply string-append lines)
                          "                .build();\n"
                          "            let _gather_results = query_for_read(\n"
                          "                " (current-qctx-ref) ",\n"
                          "                &_gather_ops,\n"
                          "                None,\n"
                          "                &initial_cost_model(),\n"
                          "            )\n"
                          "            .map_err(|e| CompactError::AssertionFailed(format!(\"ledger query failed: {:?}\", e)))?;\n"
                          "            let _av = match _gather_results.events.last() {\n"
                          "                Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av,\n"
                          "                _ => return Err(CompactError::AssertionFailed(\"ledger: expected Read event\".into())),\n"
                          "            };\n"
                          "            " decoder "(_av)?\n"
                          "        }")]))]))])]))

      ;; tuple-arg-rust: emit a Rust expression for a Tuple-Argument
      ;; (`single` or `spread`). I3b/1 only needs `single`; `spread` emits a
      ;; TODO placeholder.
      (define (tuple-arg-rust ta native-id-ht)
        (nanopass-case (Ltypescript Tuple-Argument) ta
          [(single ,src ,expr) (expr-rust expr native-id-ht)]
          [(spread ,src ,nat ,expr)
           (rust-feature-error src 'tuple-spread
             "tuple spread (`...expr`) not supported")]))

      ;; call-rust: emit a Rust call expression for `(call src function-name
      ;; expr* ...)`. Resolves the function-name id to a native binding via
      ;; native-id-ht. For native calls whose Rust signature doesn't line up
      ;; 1:1 with Compact's (e.g. persistent_hash takes `&[u8]` whereas
      ;; Compact's persistentHash takes a typed value), emit a specialised
      ;; form. For natives with a clean 1:1 mapping (none yet exercised by
      ;; tiny.compact), emit a vanilla `<rust-name>(<arg>, ...)`. For
      ;; non-native (user-defined) circuit calls, fall back to the
      ;; snake-cased local name — a follow-up wedge will resolve these
      ;; properly.
      (define (call-rust src function-name expr* native-id-ht)
        (let ([ne (eq-hashtable-ref native-id-ht function-name #f)]
              [sym (id-sym function-name)])
          (cond
            [(or (eq? sym 'some) (eq? sym 'none))
             ;; I3b/4: stdlib circuits with no native binding — go through
             ;; the runtime-side `std_lib` path. Without the circuit pelt
             ;; here we can't inject `::<T>`, but tiny.compact's get()
             ;; reaches this through ctor-call-rust which does have the
             ;; pelt and ascribes the generic — this branch is a safety
             ;; net for any future ascription-free use site.
             (let ([args
                    (map (lambda (e) (expr-rust e native-id-ht)) expr*)])
               (format "compact_runtime::std_lib::~a(~a)"
                       sym
                       (let join ([xs args] [acc ""])
                         (cond
                           [(null? xs) acc]
                           [(null? (cdr xs)) (string-append acc (car xs))]
                           [else (join (cdr xs)
                                       (string-append acc (car xs) ", "))]))))]
            [(and ne (equal? (native-entry-rust-function ne)
                             "compact_runtime::persistent_hash"))
             ;; R3: alignment-aware lowering of Compact's
             ;; `persistentHash<T>(value)`. The TS path constructs an
             ;; `AlignedValue` from `value` (via the runtime type
             ;; descriptor) and feeds the alignment-framed byte stream to
             ;; SHA-256; see `node_modules/@midnight-ntwrk/compact-runtime/
             ;; src/built-ins.ts::persistentHash` and the wasm-side
             ;; `onchain-runtime-wasm/src/primitives.rs::persistent_hash`.
             ;;
             ;; We mirror that by converting each constituent of the
             ;; argument to an `AlignedValue` and calling
             ;; `persistent_hash_aligned`, which delegates to
             ;; `ValueReprAlignedValue::binary_repr` + the upstream SHA-256
             ;; persistent hash. When the argument is a `Vector<N, T>` the
             ;; IR represents it as a `(tuple ...)` and we lift each
             ;; element separately so each gets its own alignment atom; for
             ;; any other shape we wrap the single argument in a one-element
             ;; slice.
             ;;
             ;; Previous emit (I3b/1):
             ;;   `persistent_hash(&[a, b, ...].concat()).0`
             ;; produces byte-identical output for uniform `Bytes<N>` inputs
             ;; (tiny.compact's `public_key`), but diverges for mixed-type,
             ;; `Field`-, or `Compress`-bearing inputs because raw byte
             ;; concat skips the per-atom framing (Bytes<n> zero-padding,
             ;; Fr little-endian normalisation, Compress hashing).
             (cond
               [(fx= (length expr*) 1)
                (let ([arg (car expr*)])
                  (let ([elt-strs
                         ;; If the single argument is a `tuple` IR node
                         ;; (Compact-level Vector), break it apart so each
                         ;; element becomes its own AlignedValue. Otherwise,
                         ;; emit a one-element slice.
                         (nanopass-case (Ltypescript Expression) arg
                           [(tuple ,src ,tuple-arg* ...)
                            (map (lambda (ta)
                                   (format "compact_runtime::AlignedValue::from(~a)"
                                           (tuple-arg-rust ta native-id-ht)))
                                 tuple-arg*)]
                           [else
                            (list (format "compact_runtime::AlignedValue::from(~a)"
                                          (expr-rust arg native-id-ht)))])])
                    (string-append
                      "compact_runtime::std_lib::persistent_hash_aligned(&["
                      (let join ([xs elt-strs] [acc ""])
                        (cond
                          [(null? xs) acc]
                          [(null? (cdr xs)) (string-append acc (car xs))]
                          [else (join (cdr xs)
                                      (string-append acc (car xs) ", "))]))
                      "])")))]
               [else
                (rust-feature-error src 'persistent-hash-arity
                  "persistentHash arity ~a not yet supported (expected 1)"
                  (length expr*))])]
            [ne
             ;; A native with a 1:1 binding. Emit `<rust-name>(<arg>, ...)`.
             (let ([rust-name (native-call-site-rust ne)]
                   [args
                    (map (lambda (e) (expr-rust e native-id-ht)) expr*)])
               (string-append
                 rust-name
                 "("
                 (let join ([xs args] [acc ""])
                   (cond
                     [(null? xs) acc]
                     [(null? (cdr xs)) (string-append acc (car xs))]
                     [else (join (cdr xs) (string-append acc (car xs) ", "))]))
                 ")"))]
            [else
             ;; A user-defined circuit call. We don't yet resolve these
             ;; to their Rust paths in this pure-expression path.
             (rust-feature-error src 'non-native-call
               "call to non-native circuit ~a not supported in this position"
               (id-sym function-name))])))

      ;; stmt-pure-body-rust: try to render the body of a pure circuit as a
      ;; single Rust expression (no trailing semicolon — used in tail
      ;; position). Accepts:
      ;;   - a `statement-expression` whose expression is a `call`
      ;;     (tiny.compact's `public_key` shape)
      ;;   - a statement-level `(if cond then-stmt else-stmt)` (election's
      ;;     `successor` / `ballot_repr` shape — branches recurse so an
      ;;     if/else-if/else chain emits nested Rust `if … else { if … }`)
      ;; Returns the Rust expression string on success, #f to signal the
      ;; caller should fall back to `unimplemented!()`.
      (define (stmt-pure-body-rust stmt native-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (cond
            [(or (null? stmts) (not (null? (cdr stmts)))) #f]
            [else
             (nanopass-case (Ltypescript Statement) (car stmts)
               [(if ,src ,expr0 ,stmt1 ,stmt2)
                ;; E6: statement-position if-then-else. Render the cond via
                ;; expr-rust and recurse into each branch. A failing branch
                ;; (returns #f) propagates so the whole body falls back to
                ;; `unimplemented!()` rather than emitting a half-built if.
                (let ([cond-str (expr-rust expr0 native-id-ht)]
                      [then-str (stmt-pure-body-rust stmt1 native-id-ht)]
                      [else-str (stmt-pure-body-rust stmt2 native-id-ht)])
                  (cond
                    [(or (not then-str) (not else-str)) #f]
                    [(or (rendered-has-todo? cond-str)
                         (rendered-has-todo? then-str)
                         (rendered-has-todo? else-str))
                     #f]
                    [else
                     (format "if ~a {\n            ~a\n        } else {\n            ~a\n        }"
                             cond-str then-str else-str)]))]
               [(statement-expression ,expr)
                ;; Render the trailing expression through expr-rust. Any
                ;; variant expr-rust can't handle falls through to its
                ;; TODO placeholder, which rendered-has-todo? catches at
                ;; the caller (or here, for nested if branches).
                (let ([s (expr-rust expr native-id-ht)])
                  (cond
                    [(rendered-has-todo? s) #f]
                    [else s]))]
               [else #f])])))

      ;; emit-pure-circuit: emit a pure circuit as a free function inside
      ;; `mod pure_circuits`. No ctx — just the declared args and a direct
      ;; return type. For the narrow tiny.compact-style shape (a single
      ;; expression in statement position) we render the expression
      ;; directly; everything else keeps an `unimplemented!()` placeholder.
      ;;
      ;; Exported circuits become `pub fn` (part of the crate's public
      ;; surface). Non-exported user pure circuits (e.g. zerocash's
      ;; `commitment_from_coin_info`, `derive_nullifier`) become
      ;; `pub(crate) fn` — callable from anywhere in the generated
      ;; contract crate (notably impure-circuit bodies via
      ;; `pure_circuits::foo(...)`) but not part of the contract's
      ;; downstream API.
      (define (emit-pure-circuit cdefn native-id-ht)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
           (out (format "    ~a fn ~a("
                        (if (id-exported? function-name) "pub" "pub(crate)")
                        (camel->snake (id-sym function-name))))
           (let loop ([arg* arg*] [first? #t])
             (cond
               [(null? arg*) (void)]
               [else
                (nanopass-case (Ltypescript Argument) (car arg*)
                  [(,var-name ,type)
                   (out (format "~a~a: ~a"
                                (if first? "" ", ")
                                (camel->snake (id-sym var-name))
                                (type-rust type)))])
                (loop (cdr arg*) #f)]))
           (out (format ") -> ~a {\n" (type-rust type)))
           (parameterize ([current-formal-arg-types (build-formal-arg-type-ht arg*)])
             (let ([body (stmt-pure-body-rust stmt native-id-ht)])
               (cond
                 [body (out (format "        ~a\n" body))]
                 [else
                  (rust-feature-error src 'pure-circuit-body-emission
                    "no walker shape matched pure circuit body for ~a"
                    (id-sym function-name))])))
           (out "    }\n\n")]))

      ;; pl-array->public-bindings: flatten a `public-ledger-array` IR node
      ;; into a list of `public-binding`s. Ported from
      ;; typescript-passes.ss::pl-array->public-bindings — nested arrays are
      ;; walked recursively; leaves (`public-binding`) accumulate.
      (define (pl-array->public-bindings pl-array)
        (let f ([pl-array pl-array] [pb* '()])
          (nanopass-case (Ltypescript Public-Ledger-Array) pl-array
            [(public-ledger-array ,pl-array-elt* ...)
             (fold-right
               (lambda (pl-array-elt pb*)
                 (nanopass-case (Ltypescript Public-Ledger-Array-Element) pl-array-elt
                   [,pl-array (f pl-array pb*)]
                   [,public-binding (cons public-binding pb*)]))
               pb*
               pl-array-elt*)])))

      ;; exported-public-binding?: #t if the binding's field-name id is
      ;; marked `id-exported?`. Mirrors typescript-passes.ss's predicate of
      ;; the same name. Non-exported ledger fields (e.g. tiny.compact's
      ;; `authority`, `state`) are dropped from the Rust public surface.
      (define (exported-public-binding? public-binding)
        (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,type)
           (id-exported? ledger-field-name)]))

      ;; binding-field-name: extract the (snake-cased) Rust identifier for a
      ;; reader method from a public-binding.
      (define (binding-field-name public-binding)
        (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,type)
           (camel->snake (id-sym ledger-field-name))]))

      ;; binding-path-indices: extract the list of path indices (integers)
      ;; that locate this field inside the on-chain state.
      (define (binding-path-indices public-binding)
        (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,type) path-index*]))

      ;; binding-type: extract the binding's declared type (the ADT, e.g.
      ;; `(tadt Counter ...)` or `(tadt Cell ...)`).
      (define (binding-type public-binding)
        (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,type) type]))

      ;; tadt-name=?: returns #t when `type` is a tadt with the given
      ;; adt-name (symbol). Used by emit-initial-state's R1/K1.1 dispatch
      ;; to pick the right per-ADT builder (new_map / new_merkle_tree /
      ;; new_historic_merkle_tree) instead of new_cell(Default::default()).
      (define (tadt-name=? type name)
        (nanopass-case (Ltypescript Type) type
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (eq? adt-name name)]
          [(talias ,src ,nominal? ,type-name ,type) (tadt-name=? type name)]
          [else #f]))

      ;; type-is-tvector?: returns #t when `type` is a tvector (after
      ;; de-aliasing). Used by emit-initial-state to route vector ledger
      ;; field seeds through new_cell_array (since `[T; N]: Into<AlignedValue>`
      ;; isn't impl'd upstream).
      (define (type-is-tvector? type)
        (nanopass-case (Ltypescript Type) type
          [(tvector ,src ,len ,type) #t]
          [(talias ,src ,nominal? ,type-name ,type) (type-is-tvector? type)]
          [else #f]))

      ;; tunsigned-bounded?: returns #t when `type` is a `tunsigned` whose
      ;; byte-length doesn't match the underlying Rust integer width's byte
      ;; count — i.e. a `Uint<L..U>` with a non-power-of-two byte-length.
      ;; Used by emit-initial-state to route those seeds through
      ;; `new_cell_bounded_uint(0u128, N)` so the on-state alignment
      ;; descriptor matches TS. Fixed-width `Uint<N>` (N ∈ {8,16,32,64,128})
      ;; stays on the `new_cell(0uN)` path.
      (define (tunsigned-bounded? type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat) (not (uint-byte-length-matches-rust-width? nat))]
          [(talias ,src ,nominal? ,type-name ,type) (tunsigned-bounded? type)]
          [else #f]))

      ;; tunsigned-byte-length: byte-length of the `AlignmentAtom::Bytes`
      ;; descriptor for a `tunsigned` type. Mirrors TS's `byte-length` —
      ;; ceil(bit_length(max_value) / 8). Used by tunsigned-bounded? routing.
      (define (tunsigned-byte-length type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat) (number->string (uint-byte-length nat))]
          [(talias ,src ,nominal? ,type-name ,type) (tunsigned-byte-length type)]
          [else "0"]))

      ;; tadt-merkle-height: given a MerkleTree / HistoricMerkleTree tadt,
      ;; extract the Nat height argument (the first adt-arg). The Public-
      ;; Ledger-ADT-Arg grammar permits either a nat or a type; for the
      ;; height position we expect a nat literal (see midnight-ledger.ss
      ;; declarations — `[Nat nat]` formal). Falls back to "32" if the
      ;; shape is unexpected so the emitter never crashes.
      (define (tadt-merkle-height type)
        (nanopass-case (Ltypescript Type) type
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (cond
             [(and (pair? adt-arg*) (number? (car adt-arg*)))
              (number->string (car adt-arg*))]
             [else "32"])]
          [(talias ,src ,nominal? ,type-name ,type) (tadt-merkle-height type)]
          [else "32"]))

      ;; tadt-read-op-type: given a binding's tadt, find the ADT operation
      ;; with op-class `read` and return its result type. Falls back to the
      ;; binding type itself if no read op is present (shouldn't happen for
      ;; ledger fields, but keep us robust).
      (define (tadt-read-op-type type)
        (nanopass-case (Ltypescript Type) type
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (let loop ([ops adt-op*])
             (cond
               [(null? ops) type]
               [else
                (let ([result
                       (nanopass-case (Ltypescript ADT-Op) (car ops)
                         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                          (if (eq? op-class 'read) type #f)])])
                  (or result (loop (cdr ops))))]))]
          [else type]))

      ;; decoder-for-type: pick the `compact_runtime::std_lib::decode_*`
      ;; helper that turns an AlignedValue back into the Rust type returned
      ;; by `type-rust`. Mirrors `uint-rust-width` for the integer cases.
      (define (decoder-for-type type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat)
           (cond
             [(<= nat 255) "compact_runtime::std_lib::decode_u8"]
             [(<= nat 65535) "compact_runtime::std_lib::decode_u16"]
             [(<= nat 4294967295) "compact_runtime::std_lib::decode_u32"]
             [(<= nat 18446744073709551615) "compact_runtime::std_lib::decode_u64"]
             [else "compact_runtime::std_lib::decode_u128"])]
          [(tfield ,src) "compact_runtime::std_lib::decode_fr"]
          [(tboolean ,src) "compact_runtime::std_lib::decode_bool"]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           ;; Enums are FieldRepr'd as a u8 discriminant on chain. The
           ;; in_state inlining (and any other tenum ledger read in
           ;; expression position) decodes to u8 — the discriminant
           ;; comparison stays a u8-vs-u8 check, matching the way
           ;; enum-ref->u8 emits literals.
           "compact_runtime::std_lib::decode_u8"]
          [(tbytes ,src ,len)
           (format "compact_runtime::std_lib::decode_bytes::<~a>" len)]
          [(tvector ,src ,len ,type)
           ;; Vector<N, T>: dispatch on element type. For Vector<N, Field>
           ;; and Vector<N, Uint<64>> we have dedicated decoders. Other
           ;; element types (Bytes<M>, user structs, nested vectors) need
           ;; their own helpers — leave them flagged so the gap is visible.
           (nanopass-case (Ltypescript Type) type
             [(tfield ,src)
              (format "compact_runtime::std_lib::decode_vector_fr::<~a>" len)]
             [(tunsigned ,src ,nat)
              ;; Iter 7: Uint<64> element → decode_vector_u64<N>. Wider
              ;; widths (u128) and narrower (u8/u16/u32) would each need
              ;; their own per-element decoder; ship only the common case.
              (cond
                [(and (> nat 4294967295)
                      (<= nat 18446744073709551615))
                 (format "compact_runtime::std_lib::decode_vector_u64::<~a>" len)]
                [else #f])]
             [else #f])]
          [(talias ,src ,nominal? ,type-name ,type) (decoder-for-type type)]
          ;; A5: struct types (user-defined or stdlib like
          ;; `ContractAddress`) decode via the FromFieldRepr trait —
          ;; the H6/H7 emitter derives it for user structs, and
          ;; upstream stdlib structs in midnight-coin-structure /
          ;; midnight-base-crypto derive it natively. The Rust type
          ;; name comes through unqualified — it must already be in
          ;; scope at the call site (the codegen's `use
          ;; compact_runtime::*` import covers re-exported stdlib
          ;; types; user structs are emitted at module scope).
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (format "compact_runtime::std_lib::decode_via_field_repr::<~a>" struct-name)]
          [else #f]))

      ;; adt-is-collection?: ADTs whose `read` op-class is a per-element
      ;; presence/lookup check rather than a value extractor. For these,
      ;; the ledger view method (which currently decodes a single
      ;; AlignedValue → T) has incoherent semantics. Skip view emission
      ;; for collection-shaped ADTs; users access them through the typed
      ;; wrapper (E3 territory) or via direct StateValue inspection.
      (define (adt-is-collection? type)
        (nanopass-case (Ltypescript Type) type
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (memq adt-name '(Map Set MerkleTree HistoricMerkleTree List))]
          [else #f]))

      ;; default-value-rust: emit the Rust expression for a type's default
      ;; (zero) value. Used by emit-initial-state to seed each ledger field
      ;; before the constructor body runs. Mirrors `type-rust`'s structure.
      ;; - tunsigned → `0u<width>` matching uint-rust-width
      ;; - tfield → `Fr::default()` (Fr derives Default = zero)
      ;; - tboolean → `false`
      ;; - tbytes N → `[0u8; N]`
      ;; - tenum → `0u8` (the first variant's discriminant; works whether
      ;;   the enum is exported as a Rust type or not, since the on-chain
      ;;   FieldRepr is u8 regardless)
      ;; - else → `Default::default()` as a best-effort fallback.
      (define (default-value-rust type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat) (format "0~a" (uint-rust-width nat))]
          [(tfield ,src) "Fr::default()"]
          [(tboolean ,src) "false"]
          [(tbytes ,src ,len) (format "[0u8; ~a]" len)]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) "0u8"]
          [(tvector ,src ,len ,type)
           ;; Vector<N, T> defaults to an N-element array of T's default.
           ;; Requires T's default expression to be Copy (true for the
           ;; common primitives Fr/u*/bool/Bytes<M>).
           (format "[~a; ~a]" (default-value-rust type) len)]
          [(talias ,src ,nominal? ,type-name ,type) (default-value-rust type)]
          [(topaque ,src ,opaque-type)
           ;; Cat 4: give Opaque<"X"> a typed default so `new_cell(...)`
           ;; doesn't need explicit turbofish at the call site.
           ;; "string" goes through the OpaqueString newtype (orphan-rule
           ;; workaround for Aligned/FieldRepr on bare String); other
           ;; opaques stay as their direct mapping.
           (cond
             [(equal? opaque-type "string") "compact_runtime::std_lib::OpaqueString::default()"]
             [(equal? opaque-type "Uint8Array") "Vec::<u8>::new()"]
             [else "Default::default()"])]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           ;; Maybe<T> needs an explicit type parameter so `Default::default()`
           ;; can infer the payload. Other named structs derive Default
           ;; (H5 emits `#[derive(... Default)]`), so the bare struct name works.
           (cond
             [(eq? struct-name 'Maybe)
              (let loop ([names elt-name*] [types type*])
                (cond
                  [(null? names) "Maybe::<()>::default()"]
                  [(eq? (car names) 'value)
                   (format "Maybe::<~a>::default()" (type-rust (car types)))]
                  [else (loop (cdr names) (cdr types))]))]
             [else (format "~a::default()" struct-name)])]
          [else "Default::default()"]))

      ;; emit-ledger-view: emits the module-level `ledger()` factory and the
      ;; `Ledger<'a, D>` view struct with one accessor method per *exported*
      ;; ledger field. Each method reads its field via a dup + N idx_at_index
      ;; ops + popeq Op program, then decodes the resulting AlignedValue
      ;; through the appropriate `decode_*` helper based on the binding's
      ;; ADT `read` op result type. The popeq uses ResultModeGather so the
      ;; read value is captured as a GatherEvent::Read(AlignedValue).
      (define (emit-ledger-view ledger-field*)
        (out "pub struct Ledger<'a, D: DB = DefaultDB> {\n")
        (out "    state: &'a ChargedState<D>,\n")
        (out "}\n\n")
        (out "pub fn ledger<D: DB>(state: &ChargedState<D>) -> Ledger<'_, D> {\n")
        (out "    Ledger { state }\n")
        (out "}\n\n")
        (out "impl<'a, D: DB> Ledger<'a, D> {\n")
        ;; Flatten ledger-declaration -> bindings, keep only exported ones.
        (let* ([all-bindings
                (apply append
                  (map (lambda (ldecl)
                         (nanopass-case (Ltypescript Program-Element) ldecl
                           [(public-ledger-declaration ,pl-array ,lconstructor)
                            (pl-array->public-bindings pl-array)]
                           [else '()]))
                       ledger-field*))]
               [exported-bindings
                (filter exported-public-binding? all-bindings)])
          (for-each
            (lambda (pb)
              ;; R4: skip collection-shaped ADTs (Map/Set/MerkleTree/HMT/List).
              ;; Their `read` op returns Boolean (presence check), not a value
              ;; extractor — emitting a `fn name(&self) -> Result<bool, ...>`
              ;; that ignores the key/element being checked produces a
              ;; nonsensical API. Direct StateValue inspection or the typed
              ;; wrapper (E3) is the right access path for these.
              (unless (adt-is-collection? (binding-type pb))
              (let* ([name (binding-field-name pb)]
                     [path* (binding-path-indices pb)]
                     [read-type (tadt-read-op-type (binding-type pb))]
                     [rust-ret (type-rust read-type)]
                     [decoder (or (decoder-for-type read-type)
                                  (format "/* TODO M3-R4: decoder for ~a */ compact_runtime::std_lib::decode_u64"
                                          rust-ret))])
                (out (format "    pub fn ~a(&self) -> Result<~a, CompactError> {\n" name rust-ret))
                ;; Bucket-1: see note in J2 emitter — fully-qualify the
                ;; upstream ContractAddress so user-defined shadow types
                ;; don't break QueryContext::new.
                (out "        let qctx = QueryContext::new(self.state.clone(), compact_runtime::ContractAddress::default());\n")
                (out "        let ops = OpProgramGather::<D>::new()\n")
                (out "            .dup(0)\n")
                (for-each
                  (lambda (idx)
                    (out (format "            .idx_at_index(~au8, false)\n" idx)))
                  path*)
                (out "            .popeq(true)\n")
                (out "            .build();\n")
                (out "        let results = query_for_read(&qctx, &ops, None, &initial_cost_model())\n")
                (out "            .map_err(|e| CompactError::AssertionFailed(format!(\"ledger query failed: {:?}\", e)))?;\n")
                (out "        let av = match results.events.last() {\n")
                (out "            Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av,\n")
                (out "            _ => return Err(CompactError::AssertionFailed(\"ledger: expected Read event\".into())),\n")
                (out "        };\n")
                (out (format "        ~a(av)\n" decoder))
                (out "    }\n"))))
            exported-bindings))
        (out "}\n\n"))

      ;; emit-pure-circuits: emits the `pure_circuits` module containing one
      ;; free function per pure circuit declaration. Contracts with no pure
      ;; circuits (e.g. counter.compact) get an empty module.
      ;;
      ;; When any non-exported user pure circuit is present (e.g. zerocash's
      ;; `commitment_from_coin_info`), inject `use super::*;` at the top
      ;; so the function body can refer to crate-level types (user structs
      ;; emitted by H5-H7, Maybe<T> re-exports, etc.) without qualification.
      ;; For contracts whose pure_circuits module contains only exported
      ;; circuits or is empty (counter, tiny), no `use` is emitted — keeping
      ;; their snapshots byte-identical.
      (define (emit-pure-circuits pure-circuit* native-id-ht)
        (out "pub mod pure_circuits {\n")
        (let ([has-non-exported?
               (let loop ([c* pure-circuit*])
                 (cond
                   [(null? c*) #f]
                   [(not (id-exported? (circuit-function-name (car c*)))) #t]
                   [else (loop (cdr c*))]))])
          (when has-non-exported?
            (out "    use super::*;\n\n")))
        (for-each (lambda (c) (emit-pure-circuit c native-id-ht)) pure-circuit*)
        (out "}\n"))

      ;; emit-cargo-toml: emits a Cargo.toml alongside lib.rs so users can
      ;; `cargo build` the emitted contract directly. The compact-runtime
      ;; dep is pinned to the same version the lib.rs embeds via
      ;; check_runtime_version!.
      (define (emit-cargo-toml)
        (let ([port (get-target-port 'contract-cargo.toml)])
          (display-string
            (format
              "[package]
name = \"compact-contract\"
version = \"0.1.0\"
edition = \"2021\"

[lib]
path = \"lib.rs\"

[dependencies]
compact-runtime = \"~a\"
"
              runtime-version-string)
            port)))
