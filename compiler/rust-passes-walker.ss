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

      ;; witness-pelt?: returns #t if a Program-Element is a witness
      ;; declaration. Used by build-witness-id-ht to index witnesses.
      (define (witness-pelt? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(witness ,src ,function-name (,arg* ...) ,type) #t]
          [else #f]))

      ;; witness-pelt-function-name: extract function-name id from a witness
      ;; Program-Element.
      (define (witness-pelt-function-name pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(witness ,src ,function-name (,arg* ...) ,type) function-name]))

      ;; build-witness-id-ht: eq-hashtable from each witness function-name
      ;; id to the witness Program-Element itself. Lets call-site emission
      ;; recognise a `(call witness-id args)` and emit the matching
      ;; `self.witnesses.<name>(...)` invocation with the right private-state
      ;; threading shape.
      (define (build-witness-id-ht pelt*)
        (let ([ht (make-eq-hashtable)])
          (for-each
            (lambda (pelt)
              (when (witness-pelt? pelt)
                (eq-hashtable-set! ht
                  (witness-pelt-function-name pelt)
                  pelt)))
            pelt*)
          ht))

      ;; build-circuit-id-ht: eq-hashtable from each circuit function-name id
      ;; to the circuit Program-Element. Lets call-site emission recognise a
      ;; `(call circuit-id args)` and dispatch on `id-pure?` to either
      ;; `pure_circuits::<name>(...)` or (eventually) a circuit invocation.
      (define (build-circuit-id-ht pelt*)
        (let ([ht (make-eq-hashtable)])
          (for-each
            (lambda (pelt)
              (when (circuit? pelt)
                (eq-hashtable-set! ht
                  (circuit-function-name pelt)
                  pelt)))
            pelt*)
          ht))

      ;; enum-ref->u8: render a `(enum-ref type elt-name)` Expression as the
      ;; u8 discriminant of the named variant. Returns the integer or #f if
      ;; the type isn't a tenum we recognise.
      (define (enum-ref->u8 expr)
        (nanopass-case (Ltypescript Expression) expr
          [(enum-ref ,src ,type ,elt-name)
           (nanopass-case (Ltypescript Type) type
             [(tenum ,src ,enum-name ,elt-name^ ,elt-name* ...)
              (let loop ([variants (cons elt-name^ elt-name*)] [i 0])
                (cond
                  [(null? variants) #f]
                  [(eq? (car variants) elt-name) i]
                  [else (loop (cdr variants) (+ i 1))]))]
             [else #f])]
          [else #f]))

      ;; enum-ref->typed-rust: render `(enum-ref type elt-name)` as
      ;; `EnumName::r#variant`. Returns #f if the type isn't a tenum.
      ;; Used when the surrounding context (current-enum-ref-typed?)
      ;; expects a typed enum value rather than the integer discriminant.
      (define (enum-ref->typed-rust expr)
        (nanopass-case (Ltypescript Expression) expr
          [(enum-ref ,src ,type ,elt-name)
           (nanopass-case (Ltypescript Type) type
             [(tenum ,src ,enum-name ,elt-name^ ,elt-name* ...)
              (format "~a::~a"
                      (symbol->string enum-name)
                      (rust-variant-name elt-name))]
             [else #f])]
          [else #f]))

      ;; witness-call-return-tenum?: returns #t when `expr` is a direct call
      ;; into a witness whose declared return type is a tenum (possibly via
      ;; talias). Used by the `==` rendering to detect that one operand
      ;; renders as a typed enum value, so an `enum-ref` on the other side
      ;; needs to render as `EnumName::variant` rather than as the integer
      ;; discriminant. Strips talias chains.
      (define (witness-call-return-tenum? expr witness-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...)
             (let ([w (eq-hashtable-ref witness-id-ht function-name #f)])
               (and w
                    (let ([ret-type
                           (nanopass-case (Ltypescript Program-Element) w
                             [(witness ,src ,function-name (,arg* ...) ,type) type]
                             [else #f])])
                      (and ret-type (tenum-name-of-type ret-type) #t))))]
            [else #f])))

      ;; operand-typed-enum?: returns #t when `expr` should render as a
      ;; typed enum value in Rust. Currently triggers on:
      ;;   1. a direct witness call whose declared return type is a tenum
      ;;      (e.g. election's `private$state()` returns `PrivateState`)
      ;;   2. a var-ref resolving to a formal arg whose declared type is a
      ;;      tenum (e.g. election.vote_for's `vote: PermissibleVotes`)
      ;; Both flow through the current-formal-arg-types hashtable
      ;; (populated by the impure-circuit emitter) for the var-ref case.
      ;; Used by `ctor-expr-rust`'s `==` rendering to opt into typed
      ;; enum-ref emission on the other operand.
      (define (operand-typed-enum? expr witness-id-ht)
        (or (witness-call-return-tenum? expr witness-id-ht)
            (let ([e (expr-strip-cast expr)]
                  [ht (current-formal-arg-types)])
              (and ht
                   (nanopass-case (Ltypescript Expression) e
                     [(var-ref ,src ,var-name)
                      (let ([t (eq-hashtable-ref ht (id-sym var-name) #f)])
                        (and t (tenum-name-of-type t) #t))]
                     [else #f])))))

      ;; ctor-expr-rust: render a constructor-body Expression as a Rust
      ;; expression string. Tracks a local binding alist (var-name id ->
      ;; snake-cased Rust name) so var-refs resolve to the let-bound name
      ;; we emitted earlier. Falls back to expr-rust (which handles natives
      ;; etc.) for the remaining shapes.
      ;;
      ;; native-id-ht / witness-id-ht / circuit-id-ht let call-site
      ;; classification distinguish pure-circuit / witness / native calls.
      (define (ctor-expr-rust expr local-binds
                              native-id-ht witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(var-ref ,src ,var-name)
             (cond
               [(assq var-name local-binds) => cdr]
               [else (symbol->string (camel->snake (id-sym var-name)))])]
            [(enum-ref ,src ,type ,elt-name)
             (cond
               [(current-enum-ref-typed?)
                ;; M3.5: typed-enum context — render as `EnumName::r#variant`.
                ;; The `==` case below opts in to this rendering when the
                ;; other operand renders as a typed enum (e.g. a witness
                ;; call returning a tenum). Falls back to the integer
                ;; literal if the type isn't a recognised tenum.
                (or (enum-ref->typed-rust e)
                    (let ([n (enum-ref->u8 e)])
                      (if n (format "~au8" n)
                          "/* TODO M3-J2: unresolved enum-ref */ 0u8")))]
               [else
                (let ([n (enum-ref->u8 e)])
                  (if n (format "~au8" n)
                      "/* TODO M3-J2: unresolved enum-ref */ 0u8"))])]
            [(call ,src ,function-name ,expr* ...)
             (ctor-call-rust src function-name expr* local-binds
                             native-id-ht witness-id-ht circuit-id-ht)]
            [(default ,src ,type)
             ;; I3b/3: reuse the K1 zero-value helper.
             (default-value-rust type)]
            [(== ,src ,type ,expr1 ,expr2)
             ;; I3b/3: equality. Recurse via ctor-expr-rust so var-refs
             ;; still resolve through the current local-binds (the
             ;; inline-circuit-call formal substitution rides on this).
             ;;
             ;; M3.5: if either operand renders as a typed enum (currently
             ;; detected as: direct witness call whose return type is a
             ;; tenum), parameterize the recursion so any enum-ref on the
             ;; other side renders as `EnumName::variant` rather than the
             ;; integer discriminant. Election's
             ;; `private$state() == PrivateState.initial` hits this path:
             ;; the witness returns `PrivateState`, so `PrivateState.initial`
             ;; needs to be typed. The default integer rendering still
             ;; covers tiny.compact's `state == STATE.unset` (LHS is a
             ;; u8-decoded ledger read) and election's
             ;; `state.read() == PublicState.commit` (same: ledger decoder
             ;; produces u8).
             (let ([typed?
                    (or (operand-typed-enum? expr1 witness-id-ht)
                        (operand-typed-enum? expr2 witness-id-ht))])
               (parameterize ([current-enum-ref-typed? typed?])
                 (format "(~a == ~a)"
                         (ctor-expr-rust expr1 local-binds
                                         native-id-ht witness-id-ht circuit-id-ht)
                         (ctor-expr-rust expr2 local-binds
                                         native-id-ht witness-id-ht circuit-id-ht))))]
            [(not ,src ,expr)
             ;; F1.2: Boolean negation. Recurse through ctor-expr-rust to
             ;; keep local-binds threading. Parenthesise the operand so
             ;; the surrounding context can compose safely.
             (format "(!(~a))"
                     (ctor-expr-rust expr local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))]
            [(and ,src ,expr1 ,expr2)
             ;; F1.2: short-circuit Boolean AND.
             (format "(~a && ~a)"
                     (ctor-expr-rust expr1 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
                     (ctor-expr-rust expr2 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))]
            [(or ,src ,expr1 ,expr2)
             ;; F1.2: short-circuit Boolean OR.
             (format "(~a || ~a)"
                     (ctor-expr-rust expr1 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
                     (ctor-expr-rust expr2 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))]
            [(elt-ref ,src ,expr ,elt-name ,nat)
             ;; F1.2: struct field access (`struct.field`). The field
             ;; name comes from the source language; rust-variant-name
             ;; handles reserved-word escapes.
             ;;
             ;; F2.2: special-case `(elt-ref (public-ledger ... read) f 0)`
             ;; when the read returns a tstruct — the whole-struct
             ;; decoder doesn't exist (e.g. Maybe<Opaque<string>>), but
             ;; the first field's decoder applies directly to the
             ;; gathered AlignedValue (its layout starts with the
             ;; leading field's atoms). We render a gather block + the
             ;; field-0 decoder, skipping the intermediate
             ;; `<struct>.field` projection.
             (cond
               [(and (fx= nat 0)
                     (elt-ref-of-struct-read? expr))
                (emit-struct-field-zero-read
                  (struct-read-path-elts expr)
                  (struct-read-first-field-decoder expr))]
               [else
                (format "~a.~a"
                        (ctor-expr-rust expr local-binds
                                        native-id-ht witness-id-ht circuit-id-ht)
                        (symbol->string elt-name))])]
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             ;; I3b/3: ledger read in expression position. Goes through
             ;; emit-ledger-read-expr which uses current-qctx-ref to pick
             ;; the right QueryContext source. F1.2/2: passes expr* +
             ;; native-id-ht so ADT read-with-arg (Set.member, HMT.
             ;; checkRoot, Map.lookup) routes through the vm-code
             ;; expansion path.
             (emit-ledger-read-expr path-elt* adt-op expr* native-id-ht)]
            [(new ,src ,type ,expr* ...)
             ;; F2.2: struct-literal construction
             ;; (`Maybe<...>{ is_some: true, value: t }` or
             ;; `UserStruct{ f1: v1, ... }`). The IR carries the field
             ;; initialisers in source order; field names come off the
             ;; type. Maybe<T> renders as the L1 alias `Maybe`; other
             ;; tstructs render as their bare name (H5-H7 emit them as
             ;; concrete Rust structs in the contract module).
             (render-struct-literal
               src type expr* local-binds
               native-id-ht witness-id-ht circuit-id-ht)]
            [(map ,src ,len ,fun ,map-arg ,map-arg* ...)
             ;; Iter 7: `map(fn, iterable)` over a static-length literal
             ;; iterable. expr-supported? has already validated the
             ;; shape (single map-arg, bare-lambda over a single param,
             ;; iterable peels to a static tuple/vector literal, body
             ;; is identity). We render by per-element substitution:
             ;; for each literal in the iterable, substitute the param
             ;; with the literal in the body and render via expr-rust.
             ;; The result is a Rust array literal `[<v0>, <v1>, ...]`
             ;; with type `[T; N]`, which `new_cell_array` consumes
             ;; (the constructor-body walker routes Vector<N,T> writes
             ;; through `new_cell_array` via `current-ledger-field-types`).
             (render-map-mvp src fun map-arg native-id-ht)]
            [else
             ;; quote/tuple/etc. fall through to the existing expr-rust.
             (expr-rust e native-id-ht)])))

      ;; render-map-mvp: render a `(map src len fun map-arg)` IR node
      ;; as a Rust array literal `[v0, v1, ..., vN-1]`. Assumes
      ;; `map-expr-mvp-supported?` accepted the shape — i.e. fun is a
      ;; single-param bare lambda whose body is identity (a var-ref
      ;; to the param after expr-strip-cast), and map-arg's expr peels
      ;; to a static-tuple/vector literal whose elements are
      ;; integer-literal Expressions (per iterable-expr->literals).
      ;;
      ;; For identity-body, each iteration's rendered value is just
      ;; expr-rust on the i-th literal (so the resulting array is
      ;; the iterable's bare elements). Non-identity bodies are
      ;; rejected by map-expr-mvp-supported?; future iterations can
      ;; extend this helper to substitute the param into a richer
      ;; body via expr-subst-var-ref + expr-rust.
      (define (render-map-mvp src fun map-arg native-id-ht)
        (let* ([iter-expr (map-arg->expr map-arg)]
               [literals (iterable-expr->literals iter-expr)]
               [param-name (lambda-param-name fun)]
               [body (lambda-body-expr fun)]
               [ret-type (lambda-return-type fun)]
               ;; Type suffix for the leading literal so Rust can infer
               ;; the array's element type without an explicit `[T; N]`
               ;; ascription. Identity lambdas with a tunsigned return
               ;; type get `u<width>` (u8/u16/u32/u64/u128); other
               ;; element types fall back to no suffix (Rust will
               ;; default integer literals to i32 — that's OK for
               ;; `[i32; N]` consumers but `new_cell_array` only impls
               ;; `Into<AlignedValue>` for the specific widths upstream
               ;; supports, so a missing suffix here surfaces as a
               ;; type-check error in the generated code rather than
               ;; silently producing wrong Rust).
               [first-suffix (or (tunsigned-rust-suffix ret-type) "")])
          (cond
            [(or (not literals) (not param-name) (not body))
             (rust-feature-error src 'map-mvp-shape
               "map: shape changed between expr-supported? and ctor-expr-rust")]
            [else
             ;; Per-iteration: substitute param-name with the i-th
             ;; literal in the body (works trivially for the identity
             ;; body — the substituted Expression is just the literal
             ;; itself, possibly under safe-cast layers). Render via
             ;; expr-rust which handles `(quote ,src ,int)` shape. The
             ;; FIRST element gets the `u<width>` suffix so Rust infers
             ;; the array's element type; subsequent elements stay
             ;; bare (Rust infers them from the array's element type).
             (let ([rendered
                    (map (lambda (lit)
                           (let ([substituted
                                  (expr-subst-var-ref body param-name lit)])
                             (expr-rust substituted native-id-ht)))
                         literals)])
               (string-append
                 "["
                 (let join ([xs rendered] [first? #t] [acc ""])
                   (cond
                     [(null? xs) acc]
                     [else
                      (let ([part (if first?
                                      (string-append (car xs) first-suffix)
                                      (car xs))])
                        (cond
                          [(null? (cdr xs)) (string-append acc part)]
                          [else (join (cdr xs) #f
                                      (string-append acc part ", "))]))]))
                 "]"))])))

      ;; lambda-return-type: from a Function IR node, return the
      ;; declared return Type. Returns #f when the shape isn't a
      ;; `(circuit src args type stmt)`.
      (define (lambda-return-type fun)
        (nanopass-case (Ltypescript Function) fun
          [(circuit ,src (,arg* ...) ,type ,stmt) type]
          [else #f]))

      ;; tunsigned-rust-suffix: for a `(tunsigned ,nat)` Type, return
      ;; the matching Rust integer suffix string ("u8" / "u16" / ...
      ;; "u128"). Returns #f for any other type or for tunsigned widths
      ;; outside the 8/16/32/64/128 ladder (Uint<L..U> bounded ranges
      ;; need their own width handling — Iter 8's bounded-uint fixture
      ;; uses `new_cell_bounded_uint`, not `new_cell_array`, so we
      ;; don't intercept here). Mirrors decoder-for-type's tunsigned
      ;; ladder for consistency.
      (define (tunsigned-rust-suffix type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat)
           (cond
             [(= nat 255) "u8"]
             [(= nat 65535) "u16"]
             [(= nat 4294967295) "u32"]
             [(= nat 18446744073709551615) "u64"]
             [(= nat 340282366920938463463374607431768211455) "u128"]
             [else #f])]
          [(talias ,src ,nominal? ,type-name ,type) (tunsigned-rust-suffix type)]
          [else #f]))

      ;; arg-rust-clone-if-var: render a call argument expression and
      ;; suffix `.clone()` if the rendered form is a bare var-ref. Used
      ;; by E4.4's bare-call emitter so passing the same Compact-level
      ;; var as an argument twice (e.g. `private$add_coin(coin)` followed
      ;; by `pure_circuits::commitment_from_coin_info(coin, pk)`) doesn't
      ;; trip Rust's move semantics. Defensive: we don't have liveness
      ;; analysis, so we clone every var-ref arg. User structs derive
      ;; Clone (H5), so the clone is a no-op semantically and cheap for
      ;; the small struct shapes Compact emits.
      (define (arg-rust-clone-if-var e local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
        (let ([rendered (ctor-expr-rust e local-binds
                                        native-id-ht witness-id-ht circuit-id-ht)])
          (let ([stripped (expr-strip-cast e)])
            (nanopass-case (Ltypescript Expression) stripped
              [(var-ref ,src ,var-name)
               (if (var-ref-known-copy? var-name)
                   rendered
                   (string-append rendered ".clone()"))]
              ;; elt-ref of a (chain of) var-ref(s): `path.value`,
              ;; `dest_public_key.zk` etc. Borrow-of-moved-value errors
              ;; surface when the same field is passed to one call then
              ;; re-read after — defensive clone keeps the owner intact.
              ;; We clone whenever the leaf field's type is unknown or
              ;; non-Copy; for known-Copy field types we skip the clone.
              [(elt-ref ,src ,expr ,elt-name ,nat)
               (cond
                 [(not (elt-ref-rooted-in-var? stripped)) rendered]
                 [(elt-ref-known-copy? stripped) rendered]
                 [else (string-append rendered ".clone()")])]
              [else rendered]))))

      ;; var-ref-known-copy?: returns #t when the local has a declared
      ;; type recorded in `current-formal-arg-types` that lowers to a
      ;; Rust `Copy` type. Locals without a recorded type default to #f
      ;; (caller will clone — safe and a no-op for Copy types in
      ;; practice, but explicit knowledge keeps emitted code clean).
      (define (var-ref-known-copy? var-name)
        (let ([ht (current-formal-arg-types)])
          (and ht
               (let ([t (eq-hashtable-ref ht (id-sym var-name) #f)])
                 (and t (type-rust-copy? t))))))

      ;; elt-ref-rooted-in-var?: walk an elt-ref chain to its base; return
      ;; #t when the chain's leftmost expression is a var-ref (i.e. a
      ;; field projection on a local). Used by arg-rust-clone-if-var so
      ;; passing `path.value` as a call arg suffixes `.clone()`.
      (define (elt-ref-rooted-in-var? e)
        (nanopass-case (Ltypescript Expression) e
          [(var-ref ,src ,var-name) #t]
          [(elt-ref ,src ,expr ,elt-name ,nat)
           (elt-ref-rooted-in-var? (expr-strip-cast expr))]
          [else #f]))

      ;; elt-ref-known-copy?: walk an elt-ref to the base var; if the
      ;; base var has a recorded struct type, project to the named field
      ;; and check whether THAT field's type is Copy. Returns #f when any
      ;; step is unknown (caller defaults to cloning).
      (define (elt-ref-known-copy? e)
        (let walk ([n e])
          (nanopass-case (Ltypescript Expression) n
            [(var-ref ,src ,var-name)
             (let ([ht (current-formal-arg-types)])
               (and ht
                    (let ([t (eq-hashtable-ref ht (id-sym var-name) #f)])
                      (and t (type-rust-copy? t)))))]
            [(elt-ref ,src ,expr ,elt-name ,nat)
             ;; If inner is a known-Copy struct it doesn't matter (Copy
             ;; struct -> Copy fields). Otherwise we'd need to descend
             ;; into struct definitions to type the projected field; for
             ;; now, return #f (clone). This keeps the predicate
             ;; conservative — extra clones on field projections are
             ;; always safe.
             (walk (expr-strip-cast expr))]
            [else #f])))

      ;; stdlib-circuit-rust-path: if `function-name` is a Compact stdlib
      ;; circuit registered in stdlib-circuit-mappings, return its
      ;; runtime-side Rust callee path (with `::<T>` ascription where the
      ;; mapping needs it). Returns #f for non-stdlib callees.
      ;;
      ;; `cdefn` is the circuit pelt looked up via circuit-id-ht (or #f),
      ;; passed through to the mapping's rust-path-fn so it can inspect
      ;; the return type (e.g. some/none extract T from `Maybe<T>`).
      (define (stdlib-circuit-rust-path function-name cdefn)
        (let ([entry (lookup-stdlib-circuit (id-sym function-name))])
          (and entry ((car entry) cdefn))))

      ;; circuit-return-type: pull the declared return type out of a
      ;; Circuit-Definition Program-Element. Returns #f if `cdefn` is not
      ;; a circuit (defensive).
      (define (circuit-return-type cdefn)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt) type]
          [else #f]))

      ;; ctor-call-rust: render a `(call f args)` in the constructor body.
      ;; The witness case is special — witnesses don't appear as
      ;; sub-expressions in the constructor body, they always sit on the RHS
      ;; of a `const` binding, so the witness branch here just renders the
      ;; method call with a witness-context placeholder name we'll have
      ;; emitted on the line above. Pure circuit calls resolve to
      ;; `pure_circuits::<name>(...)`. Native and other circuit calls fall
      ;; back to call-rust.
      (define (ctor-call-rust src function-name expr* local-binds
                              native-id-ht witness-id-ht circuit-id-ht)
        (let* ([w (eq-hashtable-ref witness-id-ht function-name #f)]
               [c (eq-hashtable-ref circuit-id-ht function-name #f)]
               [stdlib (stdlib-circuit-rust-path function-name c)])
          (cond
            [w
             ;; Witness calls cannot be inlined as sub-expressions because
             ;; they return (PS, T). The body walker hoists witness calls
             ;; nested in assert-conditions to top-level `let`-bindings;
             ;; consult current-witness-call-binds (an alist keyed by
             ;; function-name + arg expr*) before falling back to a TODO.
             ;; We compare arg lists by eq?-on-each since assert-cond
             ;; rendering walks the same IR nodes the hoister scanned.
             (cond
               [(witness-call-bound function-name expr*
                                    (current-witness-call-binds))
                => (lambda (rust-name) rust-name)]
               [else
                (rust-feature-error src 'witness-inline
                  "witness call ~a appears as a sub-expression; only top-level binding shape is supported"
                  (id-sym function-name))])]
            [stdlib
             ;; I3b/4: stdlib circuits (`some`, `none`) live in
             ;; compact_runtime::std_lib. Render with the runtime path.
             (let ([args
                    (map (lambda (e)
                           (arg-rust-clone-if-var e local-binds
                                                  native-id-ht witness-id-ht circuit-id-ht))
                         expr*)])
               (format "~a(~a)"
                       stdlib
                       (let join ([xs args] [acc ""])
                         (cond
                           [(null? xs) acc]
                           [(null? (cdr xs)) (string-append acc (car xs))]
                           [else (join (cdr xs)
                                       (string-append acc (car xs) ", "))]))))]
            [(and c (id-pure? function-name))
             (let ([rust-name (camel->snake (id-sym function-name))]
                   [args
                    (map (lambda (e)
                           (arg-rust-clone-if-var e local-binds
                                                  native-id-ht witness-id-ht circuit-id-ht))
                         expr*)])
               (format "pure_circuits::~a(~a)"
                       rust-name
                       (let join ([xs args] [acc ""])
                         (cond
                           [(null? xs) acc]
                           [(null? (cdr xs)) (string-append acc (car xs))]
                           [else (join (cdr xs)
                                       (string-append acc (car xs) ", "))]))))]
            [else
             ;; Native or unrecognised — defer to existing call-rust. It
             ;; expects to receive expressions, so first transform var-refs
             ;; in expr* through local-binds. We do that by rendering each
             ;; arg through ctor-expr-rust and wrapping the result back as
             ;; the existing call-rust does after expr-rust on its args.
             ;; Simplest: only support natives whose args are var-refs we
             ;; can resolve. For tiny.compact, the constructor's only call
             ;; sites are witness + pure circuit, so this branch is just a
             ;; safety net.
             (call-rust src function-name expr* native-id-ht)])))

      ;; expr-supported?: predicate that returns #t when an Expression is
      ;; in a shape our body emitter can render cleanly (no
      ;; `unimplemented!()` placeholders, no unresolved enum/var refs).
      ;; Used as a pre-validation gate so circuits whose bodies contain
      ;; shapes we don't yet handle (e.g. tiny.compact's `clear` with its
      ;; `apk == authority` comparison and `default<T>` writes) fall back
      ;; to `unimplemented!()` rather than emitting partially-broken code.
      ;;
      ;; Witness/pure-circuit/native call sites are accepted even when the
      ;; underlying function returns from a non-emittable circuit, since
      ;; we render those as method/function invocations.
      (define (expr-supported? expr native-id-ht witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(var-ref ,src ,var-name) #t]
            [(quote ,src ,datum)
             (or (and (integer? datum) (exact? datum))
                 (boolean? datum)
                 (bytevector? datum))]
            [(enum-ref ,src ,type ,elt-name)
             ;; enum-ref->u8 returns #f on unknown variants.
             (and (enum-ref->u8 e) #t)]
            [(call ,src ,function-name ,expr* ...)
             (let ([ne (eq-hashtable-ref native-id-ht function-name #f)]
                   [w (eq-hashtable-ref witness-id-ht function-name #f)]
                   [c (eq-hashtable-ref circuit-id-ht function-name #f)])
               ;; F2.2: accept ALL user pure-circuit callees (exported
               ;; or not). Non-exported helpers (e.g. election's
               ;; `successor`) now land in the `pure_circuits` mod as
               ;; `pub(crate) fn` (per E4.4 / emit-pure-circuit), so
               ;; `pure_circuits::<name>(...)` is a valid in-crate
               ;; reference from impure-circuit bodies.
               (and (or ne
                        w
                        (and c (id-pure? function-name)))
                    (let loop ([xs expr*])
                      (cond
                        [(null? xs) #t]
                        [(expr-supported? (car xs) native-id-ht
                                          witness-id-ht circuit-id-ht)
                         (loop (cdr xs))]
                        [else #f]))))]
            [(tuple ,src ,tuple-arg* ...)
             (let loop ([xs tuple-arg*])
               (cond
                 [(null? xs) #t]
                 [else
                  (let ([ok?
                         (nanopass-case (Ltypescript Tuple-Argument) (car xs)
                           [(single ,src ,expr)
                            (expr-supported? expr native-id-ht
                                             witness-id-ht circuit-id-ht)]
                           [else #f])])
                    (and ok? (loop (cdr xs))))]))]
            [(default ,src ,type)
             ;; I3b/3: any type the default-value-rust helper can render
             ;; is fine. The helper has a Default::default() fallback so
             ;; this is effectively always supported, but we still gate
             ;; on the helper's recognised shapes to keep the codegen
             ;; faithful.
             (default-supported? type)]
            [(== ,src ,type ,expr1 ,expr2)
             ;; I3b/3: equality. Recurse into both operands.
             (and (expr-supported? expr1 native-id-ht
                                   witness-id-ht circuit-id-ht)
                  (expr-supported? expr2 native-id-ht
                                   witness-id-ht circuit-id-ht))]
            [(not ,src ,expr)
             ;; F1.2: Boolean negation. Recurse into the operand.
             (expr-supported? expr native-id-ht
                              witness-id-ht circuit-id-ht)]
            [(and ,src ,expr1 ,expr2)
             ;; F1.2: short-circuit AND.
             (and (expr-supported? expr1 native-id-ht
                                   witness-id-ht circuit-id-ht)
                  (expr-supported? expr2 native-id-ht
                                   witness-id-ht circuit-id-ht))]
            [(or ,src ,expr1 ,expr2)
             ;; F1.2: short-circuit OR.
             (and (expr-supported? expr1 native-id-ht
                                   witness-id-ht circuit-id-ht)
                  (expr-supported? expr2 native-id-ht
                                   witness-id-ht circuit-id-ht))]
            [(elt-ref ,src ,expr ,elt-name ,nat)
             ;; F1.2: struct field access. The inner expression must be
             ;; renderable; the field selection itself is unconditionally
             ;; supported (Rust structs use the same `.field` syntax,
             ;; emitter doesn't know whether the field name is a Rust
             ;; reserved word — current zerocash structs use safe names).
             ;;
             ;; F2.2: also accept `(elt-ref (public-ledger ... read) field N)`
             ;; when the read returns a tstruct and the projected field at
             ;; offset 0 has a decoder. The whole-struct path through
             ;; `ledger-read-supported?` would reject (no struct decoder),
             ;; so we provide a narrower acceptance criterion that lines
             ;; up with the special-case in `ctor-expr-rust`. Currently
             ;; only the leading boolean field is supported (e.g.
             ;; `topic.read().is_some` on `Maybe<T>` — `decode_bool` on the
             ;; resulting AlignedValue reads exactly the first atom).
             (or (expr-supported? expr native-id-ht
                                  witness-id-ht circuit-id-ht)
                 (and (fx= nat 0)
                      (elt-ref-of-struct-read? expr)))]
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             ;; I3b/3: ledger read in expression position. Supported when
             ;; op-class is `read`, the path is a single index, and the
             ;; result type has a decoder.
             (ledger-read-supported? path-elt* adt-op)]
            [(new ,src ,type ,expr* ...)
             ;; F2.2: struct-literal construction (e.g. election.set_topic's
             ;; `Maybe<Opaque<"string">>{ is_some: true, value: t }`).
             ;; Accept when the type is a tstruct (Maybe or user struct) and
             ;; all field initialiser exprs render. The arg count must equal
             ;; the struct's field count (lowered from named field initialisers
             ;; in source order). The Maybe path reuses the L1 runtime alias;
             ;; user structs are referenced by their bare name (H5-H7).
             (let ([st (struct-of-type type)])
               (and st
                    (fx= (length expr*) (length (cadr st)))
                    (for-all (lambda (e)
                               (expr-supported? e native-id-ht
                                                witness-id-ht circuit-id-ht))
                             expr*)))]
            [(map ,src ,len ,fun ,map-arg ,map-arg* ...)
             ;; Iter 7: `map(fn, iterable)` over a static-length literal
             ;; iterable. Single map-arg only (no zip-map); fun must be a
             ;; bare-lambda `(circuit (arg) ret-type body)` whose body is
             ;; an expr-supported? Expression after substituting the
             ;; element parameter with the i-th literal. The iterable
             ;; (map-arg's expr) must be a `(tuple ...)` or `(vector ...)`
             ;; literal whose elements are themselves expr-supported?
             ;; (the body substitution preserves each element verbatim,
             ;; so per-iteration we get an expression of the same shape
             ;; we just validated).
             (and (null? map-arg*)
                  (map-expr-mvp-supported? src fun map-arg
                                           native-id-ht witness-id-ht circuit-id-ht))]
            [else #f])))

      ;; map-expr-mvp-supported?: Iter 7 narrow-shape predicate for a
      ;; `(map ,src ,len ,fun ,map-arg)` expression. Accepts only the
      ;; literal-iterable MVP: `fun` is a bare-lambda over a single
      ;; param, iterable peels to a static `(tuple ...)` /
      ;; `(vector ...)` literal whose elements survive
      ;; `tuple-arg->literal`, and the lambda body is a `(var-ref
      ;; param)` (identity). Non-identity bodies (e.g. `x * 2`) require
      ;; additional emission infrastructure for `(* ...)`,
      ;; `downcast-unsigned`, etc.; we defer those to a follow-up
      ;; iteration.
      ;;
      ;; Returns #t on a supported shape, #f otherwise. The caller
      ;; (expr-supported?) is the gate; ctor-expr-rust's matching
      ;; map-clause assumes the same shape and renders accordingly.
      (define (map-expr-mvp-supported? src fun map-arg
                                       native-id-ht witness-id-ht circuit-id-ht)
        (let ([param-name (lambda-param-name fun)]
              [body (lambda-body-expr fun)]
              [iter-expr (map-arg->expr map-arg)])
          (and param-name
               body
               iter-expr
               (let ([literals (iterable-expr->literals iter-expr)])
                 (and literals
                      (lambda-body-identity? body param-name))))))

      ;; lambda-param-name: from a Function IR node of shape
      ;; `(circuit src ((var-name type)) ret-type expr)` (single-param
      ;; bare lambda), return the `var-name`. Returns #f for any other
      ;; shape (fref / multi-param / zero-param).
      (define (lambda-param-name fun)
        (nanopass-case (Ltypescript Function) fun
          [(circuit ,src (,arg* ...) ,type ,stmt)
           (and (fx= (length arg*) 1)
                (nanopass-case (Ltypescript Argument) (car arg*)
                  [(,var-name ,type) var-name]))]
          [else #f]))

      ;; lambda-body-expr: from a Function IR node, return the body
      ;; Expression iff the shape is `(circuit src (arg*) ret-type
      ;; expr)`. The map IR's fun slot is always an Expression-valued
      ;; lambda at Ltypescript (per langs.ss line 866 — Ltypescript's
      ;; Function uses the `stmt` slot but with a (statement-expression
      ;; expr) wrapper). Returns the underlying Expression after
      ;; peeling statement-expression wrappers, or #f if the shape
      ;; isn't recognisable.
      ;;
      ;; Note: at the Ltypescript layer, lambdas inside `map`/`fold`
      ;; that arrived from the frontend's pre-statement IR carry their
      ;; body as an Expression directly (see the trace from compactc
      ;; with --trace-passes: the map's fun is `(circuit ((%x ...))
      ;; ret-type %x)` where `%x` is a raw Expression, not a
      ;; Statement). Be defensive: if it's a Statement-shaped lambda,
      ;; peel `statement-expression` once.
      (define (lambda-body-expr fun)
        (nanopass-case (Ltypescript Function) fun
          [(circuit ,src (,arg* ...) ,type ,stmt)
           (nanopass-case (Ltypescript Statement) stmt
             [(statement-expression ,expr) expr]
             [else #f])]
          [else #f]))

      ;; lambda-body-identity?: returns #t when the lambda body is a
      ;; `(var-ref ,param-name)` (possibly with safe-cast wrappers).
      ;; Iter 7 ships only the identity-lambda case; arithmetic /
      ;; downcast bodies are deferred.
      (define (lambda-body-identity? body param-name)
        (let ([e (expr-strip-cast body)])
          (nanopass-case (Ltypescript Expression) e
            [(var-ref ,src ,var-name)
             (eq? (id-sym var-name) (id-sym param-name))]
            [else #f])))

      ;; default-supported?: returns #t when default-value-rust would
      ;; produce a faithful Rust expression for `type`. Mirrors the
      ;; helper's case analysis (sans the catch-all `Default::default()`
      ;; fallback) so we don't accept type shapes we'd silently lower
      ;; to a generic default.
      (define (default-supported? type)
        (nanopass-case (Ltypescript Type) type
          [(tunsigned ,src ,nat) #t]
          [(tfield ,src) #t]
          [(tboolean ,src) #t]
          [(tbytes ,src ,len) #t]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #t]
          [(talias ,src ,nominal? ,type-name ,type) (default-supported? type)]
          [else #f]))

      ;; tenum-name-of-type: if `type` is a tenum (possibly through a
      ;; talias chain), return the enum's name symbol; otherwise #f.
      ;; Used at pure-circuit call sites to detect that the formal arg
      ;; expects a user enum and a runtime coercion from the gathered
      ;; AlignedValue is needed.
      (define (tenum-name-of-type type)
        (nanopass-case (Ltypescript Type) type
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) enum-name]
          [(talias ,src ,nominal? ,type-name ,type) (tenum-name-of-type type)]
          [else #f]))

      ;; type-rust-copy?: returns #t when the Rust lowering of `type` is
      ;; `Copy` (so passing it to a callee doesn't move the original).
      ;; Used by `arg-rust-clone-if-var` to suppress redundant `.clone()`
      ;; on primitive locals — keeps counter / tiny snapshots byte-stable
      ;; while still defending non-Copy locals (user structs, MerklePath,
      ;; Vec<u8>, OpaqueString, ...) against move-then-reuse.
      ;;
      ;; Returns #f when we don't have a type (so the caller defaults to
      ;; cloning) — the defensive over-clone is safe for non-Copy types
      ;; and a no-op for Copy types we missed.
      (define (type-rust-copy? type)
        (and type
             (nanopass-case (Ltypescript Type) type
               [(tfield ,src) #t]
               [(tboolean ,src) #t]
               [(tunsigned ,src ,nat) #t]
               [(tbytes ,src ,len) #t]
               [(ttuple ,src ,type* ...)
                ;; A tuple is Copy iff every element is.
                (let loop ([ts type*])
                  (cond
                    [(null? ts) #t]
                    [(type-rust-copy? (car ts)) (loop (cdr ts))]
                    [else #f]))]
               [(tvector ,src ,len ,type)
                ;; Fixed-size array `[T; N]` is Copy iff T is. (We don't
                ;; lower tvector to Vec for bounded arrays.)
                (type-rust-copy? type)]
               [(talias ,src ,nominal? ,type-name ,type)
                (type-rust-copy? type)]
               [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                ;; User enums derive Clone but not Copy (the emitted
                ;; `#[derive]` at H1 does not include Copy).
                #f]
               [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                ;; User structs derive Clone but not Copy.
                #f]
               [(topaque ,src ,opaque-type) #f]
               [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...) #f]
               [(tunknown) #f]
               [else #f])))

      ;; circuit-formal-arg-types: pull the list of formal arg types from a
      ;; circuit Program-Element. Returns '() if cdefn is #f or not a
      ;; circuit. Used by F2.2 to align actual args with their declared
      ;; types when emitting pure-circuit call args.
      (define (circuit-formal-arg-types cdefn)
        (cond
          [(not cdefn) '()]
          [else
           (nanopass-case (Ltypescript Program-Element) cdefn
             [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
              (map (lambda (a)
                     (nanopass-case (Ltypescript Argument) a
                       [(,var-name ,type) type]))
                   arg*)]
             [else '()])]))

      ;; render-pure-circuit-arg: render a single actual arg expression
      ;; for a pure-circuit call. If the formal type is a tenum AND the
      ;; actual is a `(public-ledger ... read)` returning the matching
      ;; tenum, emit a gather block decoded via the enum's FromFieldRepr
      ;; (decode_via_field_repr::<EnumName>) so the call receives the
      ;; actual enum variant rather than the bare u8 discriminant. Other
      ;; shapes fall through to ctor-expr-rust.
      (define (render-pure-circuit-arg actual formal-type local-binds
                                       native-id-ht witness-id-ht circuit-id-ht)
        (let* ([enum-name (tenum-name-of-type formal-type)]
               [e (expr-strip-cast actual)])
          (cond
            [(and enum-name
                  (nanopass-case (Ltypescript Expression) e
                    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
                     (and (null? expr*)
                          (nanopass-case (Ltypescript ADT-Op) adt-op
                            [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                             (and (eq? op-class 'read)
                                  (tenum-name-of-type type))])
                          path-elt*)]
                    [else #f]))
             =>
             (lambda (path-elt*)
               (emit-struct-field-zero-read
                 path-elt*
                 (format "compact_runtime::std_lib::decode_via_field_repr::<~a>"
                         enum-name)))]
            [else
             (arg-rust-clone-if-var actual local-binds
                                    native-id-ht witness-id-ht circuit-id-ht)])))

      ;; elt-ref-of-struct-read?: predicate for the F2.2 narrow case
      ;; `(elt-ref (public-ledger ... read with tstruct return) field 0)`.
      ;; Returns #t when the inner expression is a public-ledger `read`
      ;; whose return type is a tstruct AND the field at index 0 has a
      ;; decoder-for-type. Used by expr-supported? + ctor-expr-rust to
      ;; light up `topic.read().is_some` on Maybe<Opaque<string>>: the
      ;; whole-struct read has no decoder, but projecting `.is_some`
      ;; only needs to decode the leading boolean field, which
      ;; `decode_bool` does on the gathered AlignedValue.
      (define (elt-ref-of-struct-read? inner-expr)
        (let ([e (expr-strip-cast inner-expr)])
          (nanopass-case (Ltypescript Expression) e
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             (nanopass-case (Ltypescript ADT-Op) adt-op
               [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                (and
                  (eq? op-class 'read)
                  (null? expr*)
                  (let loop ([xs path-elt*])
                    (cond
                      [(null? xs) #t]
                      [else
                       (and (nanopass-case (Ltypescript Path-Element) (car xs)
                              [,path-index #t]
                              [else #f])
                            (loop (cdr xs)))]))
                  ;; Result type is a tstruct whose first field has a
                  ;; decoder. We grab field-0's type via the tstruct's
                  ;; type list.
                  (nanopass-case (Ltypescript Type) type
                    [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                     (and (pair? type*)
                          (decoder-for-type (car type*))
                          #t)]
                    [else #f]))])]
            [else #f])))

      ;; struct-read-first-field-decoder: pull the decoder for the leading
      ;; field of the tstruct returned by `(public-ledger ... read)`. The
      ;; caller has already validated the inner shape via
      ;; elt-ref-of-struct-read?, so we just project here. Returns the
      ;; decoder string, or #f defensively.
      (define (struct-read-first-field-decoder inner-expr)
        (let ([e (expr-strip-cast inner-expr)])
          (nanopass-case (Ltypescript Expression) e
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             (nanopass-case (Ltypescript ADT-Op) adt-op
               [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                (nanopass-case (Ltypescript Type) type
                  [(tstruct ,src ,struct-name (,elt-name* ,type^*) ...)
                   (and (pair? type^*) (decoder-for-type (car type^*)))]
                  [else #f])])]
            [else #f])))

      ;; struct-read-path-elts: pull the path-elt* out of an inner
      ;; (public-ledger ... read) expression. Used by F2.2's elt-ref
      ;; projection emission to build the gather idx_at_index chain
      ;; against the original cell path.
      (define (struct-read-path-elts inner-expr)
        (let ([e (expr-strip-cast inner-expr)])
          (nanopass-case (Ltypescript Expression) e
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             path-elt*]
            [else #f])))

      ;; ledger-read-supported?: returns #t for the `(public-ledger ...
      ;; read)` shapes emit-ledger-read-expr can render — i.e. op-class
      ;; is `read`, every path-elt is a path-index, and the result type
      ;; has either a decoder-for-type or is a tbytes alias chain.
      (define (ledger-read-supported? path-elt* adt-op)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (and
             (eq? op-class 'read)
             (let loop ([xs path-elt*])
               (cond
                 [(null? xs) #t]
                 [else
                  (and
                    (nanopass-case (Ltypescript Path-Element) (car xs)
                      [,path-index #t]
                      [else #f])
                    (loop (cdr xs)))]))
             (and (decoder-for-type type) #t))]))

      ;; witness-call-bound: alist lookup for current-witness-call-binds.
      ;; Each entry is (list function-name arg-expr* rust-name). Match by
      ;; eq? on function-name and list of eq?-on-each arg expressions.
      ;; Returns the rust-name string on hit, #f otherwise.
      (define (witness-call-bound function-name expr* binds)
        (let loop ([bs binds])
          (cond
            [(null? bs) #f]
            [(and (eq? (car (car bs)) function-name)
                  (let walk ([as (cadr (car bs))] [bs2 expr*])
                    (cond
                      [(and (null? as) (null? bs2)) #t]
                      [(or (null? as) (null? bs2)) #f]
                      [(eq? (car as) (car bs2))
                       (walk (cdr as) (cdr bs2))]
                      [else #f])))
             (caddr (car bs))]
            [else (loop (cdr bs))])))

      ;; collect-witness-subcalls: walk an Expression and return the list
      ;; of (call <witness> args*) sub-expressions in source order. Used
      ;; by the body walker to hoist witness sub-calls out of assert
      ;; conditions before rendering them. Duplicates are dropped — a
      ;; second occurrence of the same eq?-identical node returns the
      ;; binding from the first hoist.
      (define (collect-witness-subcalls expr witness-id-ht)
        (let ([seen '()])
          (let walk ([e expr])
            (let ([e (expr-strip-cast e)])
              (nanopass-case (Ltypescript Expression) e
                [(call ,src ,function-name ,expr* ...)
                 (when (eq-hashtable-ref witness-id-ht function-name #f)
                   (unless (memq e seen)
                     (set! seen (cons e seen))))
                 (for-each walk expr*)]
                [(not ,src ,expr) (walk expr)]
                [(and ,src ,expr1 ,expr2) (walk expr1) (walk expr2)]
                [(or ,src ,expr1 ,expr2) (walk expr1) (walk expr2)]
                [(== ,src ,type ,expr1 ,expr2) (walk expr1) (walk expr2)]
                [(elt-ref ,src ,expr ,elt-name ,nat) (walk expr)]
                [(tuple ,src ,tuple-arg* ...)
                 (for-each
                   (lambda (ta)
                     (nanopass-case (Ltypescript Tuple-Argument) ta
                       [(single ,src ,expr) (walk expr)]
                       [(spread ,src ,nat ,expr) (walk expr)]
                       [else (void)]))
                   tuple-arg*)]
                [else (void)])))
          (reverse seen)))

      ;; emit-hoisted-witnesses: for each witness call expression in
      ;; subcalls, emit the witness-context + bind lines and return a
      ;; list of (lines binds witness-emitted?) tracking the accumulated
      ;; pre-lines, the per-call rust-name bindings (to feed
      ;; current-witness-call-binds), and the updated witness-emitted?
      ;; flag. `counter-start` is the starting index for _witness_ctx_N
      ;; numbering (typically `(length pre-lines)`).
      ;;
      ;; Returns (list rev-lines new-binds new-witness-emitted?), where
      ;; rev-lines is in reverse (so the caller can prepend them onto
      ;; pre-lines in the natural order) and new-binds is the list of
      ;; (list function-name arg-expr* rust-name) entries.
      (define (emit-hoisted-witnesses subcalls counter-start mode
                                      local-binds witness-emitted?
                                      native-id-ht witness-id-ht circuit-id-ht)
        (let loop ([subs subcalls]
                   [counter counter-start]
                   [we? witness-emitted?]
                   [rev-lines '()]
                   [binds '()])
          (cond
            [(null? subs) (list rev-lines binds we?)]
            [else
             (let* ([call-expr (car subs)]
                    [function-name
                     (nanopass-case (Ltypescript Expression) call-expr
                       [(call ,src ,function-name ,expr* ...) function-name])]
                    [arg-exprs
                     (nanopass-case (Ltypescript Expression) call-expr
                       [(call ,src ,function-name ,expr* ...) expr*])]
                    [wname (camel->snake (id-sym function-name))]
                    [rust-name (format "_w_~a_~a" wname counter)]
                    [ctx-name (format "_witness_ctx_h~a" counter)]
                    [state-expr (if (eq? mode 'ctor)
                                    "&qctx.state"
                                    "&ctx.current_query_context.state")]
                    [qctx-ref (if (eq? mode 'ctor)
                                  "&qctx"
                                  "&ctx.current_query_context")]
                    [prev-priv
                     (cond
                       [we? "current_private_state"]
                       [(eq? mode 'ctor) "ctx.initial_private_state"]
                       [else "ctx.current_private_state"])]
                    [arg-strs
                     (map (lambda (e)
                            (arg-rust-clone-if-var
                              e local-binds
                              native-id-ht witness-id-ht circuit-id-ht))
                          arg-exprs)]
                    [call-line
                     (format "        let ~a = WitnessContext::new(ledger(~a), ~a, ~a);\n"
                             ctx-name state-expr prev-priv qctx-ref)]
                    [bind-line
                     (format "        let (current_private_state, ~a) = self.witnesses.~a(&~a~a);\n"
                             rust-name wname ctx-name
                             (let join ([xs arg-strs] [acc ""])
                               (cond
                                 [(null? xs) acc]
                                 [else (join (cdr xs)
                                             (string-append acc ", " (car xs)))])))])
               (loop (cdr subs)
                     (fx+ counter 1)
                     #t
                     (cons bind-line (cons call-line rev-lines))
                     (cons (list function-name arg-exprs rust-name) binds)))])))

      ;; assert-cond-supported?: like expr-supported? but additionally
      ;; accepts a (call ...) into a non-exported / impure circuit — we
      ;; render those as `true` placeholders. This means an assert whose
      ;; sole content is `in_state(STATE.unset)` is supported, but an
      ;; assert containing `apk == authority` is not (no expr-supported?
      ;; branch for `==`).
      (define (assert-cond-supported? expr native-id-ht witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...) #t]
            [else
             (expr-supported? e native-id-ht witness-id-ht circuit-id-ht)])))

      ;; body-walkable?: pre-validate that the flat statement sequence is
      ;; one our walker can emit without producing TODO/unimplemented
      ;; markers. Mirrors emit-body-or-fallback's case analysis but only
      ;; inspects (never emits).
      (define (body-walkable? stmt native-id-ht witness-id-ht circuit-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (let loop ([stmts stmts])
            (cond
              [(null? stmts) #t]
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
                            ;; M3.5-E4.4: accept ALL user pure-circuit
                            ;; callees (both exported and non-exported).
                            ;; Non-exported ones now land in
                            ;; `pure_circuits` as `pub(crate) fn`
                            ;; (Blocker 1), so they're equally callable.
                            (eq? (car classified) 'pure-circuit)
                            ;; M3.5-E5: accept exported impure circuit
                            ;; callees — emitted as `self.<name>(ctx, ...)`
                            ;; with context threading via `_cr_N`.
                            (eq? (car classified) 'impure-exported)
                            ;; I3b/3: also accept plain const RHS shapes
                            ;; (e.g. `const tmp = default<Bytes<32>>;`)
                            ;; whose expression is something expr-rust
                            ;; can render. emit-body-or-fallback's else
                            ;; branch already handles these.
                            (expr-supported? rhs native-id-ht
                                             witness-id-ht circuit-id-ht))
                        (loop (cdr stmts)))))]
              ;; E4.2: witness / pure-circuit call as a statement (no
              ;; const binding). zerocash_mint's `private$add_coin(coin);`
              ;; takes this shape — the return value is discarded but the
              ;; call still has side effects (witness updates private state).
              ;; Only accept non-terminal positions: a bare call at the end
              ;; would leave us without a ledger-write to anchor the
              ;; OpProgramVerify chain, which we can't currently emit.
              ;; Pure-circuit callees must additionally be exported (only
              ;; exported pure circuits land in the `pure_circuits` mod).
              [(and (pair? (cdr stmts))
                    (stmt->bare-call (car stmts))) =>
               (lambda (c)
                 (let* ([fn-id (car c)]
                        [arg* (cdr c)]
                        [classified
                         (classify-call fn-id arg* witness-id-ht circuit-id-ht)])
                   (and (or (eq? (car classified) 'witness)
                            ;; M3.5-E4.4: accept ALL user pure-circuit
                            ;; bare-call callees, exported or not — both
                            ;; now land in pure_circuits.
                            (eq? (car classified) 'pure-circuit)
                            ;; M3.5-E5: accept bare calls to exported
                            ;; impure circuits — emitted as
                            ;; `self.<name>(ctx, ...)?` with context
                            ;; rebound from the returned CircuitResults.
                            (eq? (car classified) 'impure-exported))
                        (for-all (lambda (e)
                                   (expr-supported?
                                     e native-id-ht witness-id-ht circuit-id-ht))
                                 arg*)
                        (loop (cdr stmts)))))]
              ;; E4.3: terminal `public-ledger` call. The legacy
              ;; stmt->public-ledger-write handles Cell.write specifically;
              ;; for ADT update ops (e.g. HistoricMerkleTree.insert) we
              ;; admit any single-index path whose arg expressions are
              ;; expr-supported? — the emission path will lift each arg
              ;; into a vm-rust-expr carrier and let expand-vm-code +
              ;; vminstr->builder-call render the OpProgramVerify chain.
              [(and (null? (cdr stmts))
                    (stmt->public-ledger-call (car stmts))) =>
               (lambda (parts)
                 (let ([adt-op (cadr parts)]
                       [path-elt* (caddr parts)]
                       [expr* (cadddr parts)])
                   (and (fx= (length path-elt*) 1)
                        (nanopass-case (Ltypescript Path-Element) (car path-elt*)
                          [,path-index #t]
                          [else #f])
                        (for-all (lambda (e)
                                   (expr-supported?
                                     e native-id-ht witness-id-ht circuit-id-ht))
                                 expr*))))]
              ;; E6.2: terminal `(if cond then-stmt else-stmt)` where
              ;; each branch is a single non-write public-ledger ADT
              ;; update call (e.g. `tally_yes.increment(1);`). The
              ;; emission path emits an `if` whose branches each carry
              ;; their own OpProgramVerify + query_for_verify; ctx is
              ;; threaded out via the if-expression's QueryResults.
              ;;
              ;; Local-binds aren't available in body-walkable? (we only
              ;; have the flat-statement view), so the per-branch
              ;; emittability check here is a coarse one — match the
              ;; shape but defer expr support to expr-supported?. The
              ;; emitter does the precise check via
              ;; if-then-else-branch-pl-call? and falls back if either
              ;; branch's builder lines can't be computed.
              [(and (null? (cdr stmts))
                    (stmt->if-then-else (car stmts))) =>
               (lambda (parts)
                 (let* ([then-stmt (cadr parts)]
                        [else-stmt (caddr parts)]
                        [then-call (branch->single-pl-call then-stmt)]
                        [else-call (branch->single-pl-call else-stmt)])
                   (and then-call else-call
                        ;; Both branches must be single-index path
                        ;; public-ledger calls whose arg expressions are
                        ;; expr-supported?. Mirror the predicate above.
                        (let ([then-path (caddr then-call)]
                              [then-exprs (cadddr then-call)]
                              [else-path (caddr else-call)]
                              [else-exprs (cadddr else-call)])
                          (and (fx= (length then-path) 1)
                               (fx= (length else-path) 1)
                               (nanopass-case (Ltypescript Path-Element) (car then-path)
                                 [,path-index #t]
                                 [else #f])
                               (nanopass-case (Ltypescript Path-Element) (car else-path)
                                 [,path-index #t]
                                 [else #f])
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        then-exprs)
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        else-exprs)
                               (expr-supported?
                                 (car parts) native-id-ht witness-id-ht circuit-id-ht))))))]
              ;; Iter 4: terminal `(for var-name tsize0 tsize1 #f body)`
              ;; range loop with literal nat bounds whose body is a
              ;; single non-write public-ledger ADT update call (e.g.
              ;; `c.increment(1);`). Emitted by unrolling the body's
              ;; builder lines (hi - lo) times into a single
              ;; OpProgramVerify chain. Bounds must be literal tsize
              ;; nats — variable bounds and iterable loops are deferred
              ;; to a future iteration.
              [(and (null? (cdr stmts))
                    (stmt->for-range (car stmts))) =>
               (lambda (fr)
                 (let* ([lo (cadr fr)]
                        [hi (caddr fr)]
                        [body-stmt (cadddr fr)]
                        [body-call (branch->single-pl-call body-stmt)])
                   (and body-call
                        ;; Body must be a single non-write public-ledger
                        ;; ADT-update call whose arg expressions are
                        ;; expr-supported?. Reject Cell.write (the
                        ;; emit-body-writes path) so we stick to ADT-update
                        ;; vm-code emission.
                        (not (stmt->public-ledger-write body-stmt))
                        (let ([body-path (caddr body-call)]
                              [body-exprs (cadddr body-call)])
                          (and (fx= (length body-path) 1)
                               (nanopass-case (Ltypescript Path-Element) (car body-path)
                                 [,path-index #t]
                                 [else #f])
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        body-exprs))))))]
              ;; Iter 5/6: terminal `(statement-expression (fold ...))`
              ;; from a desugared `for (const x of <static-len iterable>)
              ;; { body }`. Body must be a single non-write public-
              ;; ledger ADT update call with a literal-index path. The
              ;; loop variable may appear in the body's args — Iter 6's
              ;; emit-for-iter-terminal substitutes per-iteration via
              ;; iterable-expr->literals. We require the iterable to be
              ;; a static array literal whose elements are integer
              ;; constants (or safe-cast over the same), so the
              ;; substitution can always materialise a `(quote …)`
              ;; integer at each iteration.
              [(and (null? (cdr stmts))
                    (stmt->for-iter (car stmts))) =>
               (lambda (fi)
                 (let* ([body-stmt (caddr fi)]
                        [iter-expr (cadddr fi)]
                        [literals (iterable-expr->literals iter-expr)]
                        [body-call (branch->single-pl-call body-stmt)])
                   (and body-call
                        literals
                        (fx= (length literals) (car fi))
                        (not (stmt->public-ledger-write body-stmt))
                        (let ([body-path (caddr body-call)]
                              [body-exprs (cadddr body-call)])
                          (and (fx= (length body-path) 1)
                               (nanopass-case (Ltypescript Path-Element) (car body-path)
                                 [,path-index #t]
                                 [else #f])
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        body-exprs))))))]
              [else
               (let ([w (stmt->public-ledger-write (car stmts))])
                 (and w
                      (expr-supported?
                        (cdr w) native-id-ht witness-id-ht circuit-id-ht)
                      (loop (cdr stmts))))]))))

      ;; stmt->assert: detect a `(statement-expression (assert expr msg))`
      ;; and return (cons expr msg). The IR exposes `assert` as an Expression
      ;; that lives in statement position via `statement-expression`. Returns
      ;; #f for anything else.
      (define (stmt->assert stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(assert ,src ,expr^ ,mesg) (cons expr^ mesg)]
             [else #f])]
          [else #f]))

      ;; assert-cond-rust: render the assert condition. Witness / pure-
      ;; circuit / native calls route through ctor-expr-rust. Non-exported
      ;; circuit calls whose body we can inline (currently any circuit
      ;; whose body is a single return-expression — e.g. tiny.compact's
      ;; `in_state(s) => state == s`) get inlined via inline-circuit-call;
      ;; everything else falls back to a `true` placeholder so the assert
      ;; is a no-op rather than a compile error.
      (define (assert-cond-rust expr local-binds
                                native-id-ht witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...)
             (let ([ne (eq-hashtable-ref native-id-ht function-name #f)]
                   [w (eq-hashtable-ref witness-id-ht function-name #f)]
                   [c (eq-hashtable-ref circuit-id-ht function-name #f)])
               (cond
                 ;; Witness / pure-circuit / native — use ctor-expr-rust.
                 [(or ne w (and c (id-pure? function-name)))
                  (ctor-expr-rust e local-binds
                                  native-id-ht witness-id-ht circuit-id-ht)]
                 [c
                  ;; Non-exported (or impure) circuit call. Try to inline
                  ;; its body (the I3b/3 trick that turns the in_state
                  ;; placeholder into a semantically real comparison).
                  (or (inline-circuit-call c expr* local-binds
                                           native-id-ht witness-id-ht circuit-id-ht)
                      (format "/* TODO M3: inline ~a in assert */ true"
                              (id-sym function-name)))]
                 [else
                  (format "/* TODO M3: inline ~a in assert */ true"
                          (id-sym function-name))]))]
            [else
             (ctor-expr-rust e local-binds
                             native-id-ht witness-id-ht circuit-id-ht)])))

      ;; inline-circuit-call: attempt to inline a circuit invocation by
      ;; rendering the callee's body as a Rust expression with the
      ;; formals locally bound to the rendered actuals. Returns the
      ;; Rust expression string on success, #f if the body shape isn't a
      ;; single statement-expression we can render.
      ;;
      ;; The callee's body is walked via stmt-flatten — supported shape
      ;; is a single `(statement-expression expr)`. The formal-to-actual
      ;; map injects the rendered actual as the "Rust name" associated
      ;; with the formal id, so any `(var-ref formal)` inside the body
      ;; lowers to the actual's already-rendered Rust text. This works
      ;; because local-binds is consulted by ctor-expr-rust before
      ;; emitting var-ref's snake-cased name.
      (define (inline-circuit-call cdefn actual-expr* outer-local-binds
                                   native-id-ht witness-id-ht circuit-id-ht)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
           (let ([stmts (stmt-flatten stmt)])
             (cond
               [(or (null? stmts) (not (null? (cdr stmts)))) #f]
               [else
                (nanopass-case (Ltypescript Statement) (car stmts)
                  [(statement-expression ,expr)
                   (cond
                     [(not (fx= (length arg*) (length actual-expr*))) #f]
                     [else
                      (let* ([formal-binds
                              (map (lambda (formal actual)
                                     (let ([rendered
                                            (ctor-expr-rust actual outer-local-binds
                                                            native-id-ht witness-id-ht circuit-id-ht)])
                                       (nanopass-case (Ltypescript Argument) formal
                                         [(,var-name ,type) (cons var-name rendered)])))
                                   arg* actual-expr*)]
                             [extended-binds (append formal-binds outer-local-binds)])
                        (ctor-expr-rust expr extended-binds
                                        native-id-ht witness-id-ht circuit-id-ht))])]
                  [else #f])]))]))

      ;; emit-body-or-fallback: walk the body of a constructor or circuit and
      ;; emit `let` bindings, optional leading asserts, and an OpProgramVerify
      ;; chain that writes each ledger field. Returns #t on success, #f if the
      ;; body shape isn't one we know how to handle (caller should fall back
      ;; to its placeholder/default return).
      ;;
      ;; The supported shape is the flat sequence
      ;;   (assert <expr> "msg")*
      ;;   (const local (call <witness-or-pure>) ...)*
      ;;   (public-ledger field idx write <expr>)+
      ;; matching tiny.compact's constructor and `set` circuit.
      ;;
      ;; `mode` is 'ctor or 'circuit and controls the witness-context shape
      ;; and final return wrapping (see emit-body-writes).
      (define (emit-body-or-fallback stmt mode
                                     native-id-ht witness-id-ht circuit-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (let loop ([stmts stmts]
                     [local-binds '()]     ; (var-name . rust-name)
                     [witness-emitted? #f] ; have we emitted any witness call?
                     [pre-lines '()]       ; reverse-accumulated Rust lines
                     [writes '()])         ; reverse-accumulated (path-idx . expr)
            (cond
              [(null? stmts)
               (cond
                 [(null? writes) #f]
                 [else
                  (emit-ctor-prelude (reverse pre-lines))
                  (emit-body-writes (reverse writes) mode local-binds
                                    native-id-ht witness-id-ht circuit-id-ht
                                    witness-emitted?)
                  #t])]
              ;; E4.3: a TERMINAL `public-ledger` call whose op-class is
              ;; not `write` (e.g. HistoricMerkleTree.insert). The vm-code
              ;; expansion path renders it via expand-vm-code +
              ;; vminstr->builder-call, mirroring emit-public-ledger-call-body
              ;; but with the const-bindings + pre-lines already emitted.
              ;; Only fire when (a) there are no plain writes accumulated
              ;; (mixing Cell.write + ADT-insert in the same body isn't
              ;; supported yet) and (b) this is the last statement.
              [(and (null? (cdr stmts))
                    (null? writes)
                    (let ([parts (stmt->public-ledger-call (car stmts))])
                      (and parts
                           (not (stmt->public-ledger-write (car stmts)))
                           parts))) =>
               (lambda (parts)
                 (let ([src (car parts)]
                       [adt-op (cadr parts)]
                       [path-elt* (caddr parts)]
                       [expr* (cadddr parts)])
                   (and
                     (emit-non-write-public-ledger-terminal
                       src adt-op path-elt* expr* local-binds mode witness-emitted?
                       (reverse pre-lines)
                       native-id-ht witness-id-ht circuit-id-ht))))]
              ;; E6.2: terminal `(if cond then-stmt else-stmt)` whose
              ;; branches are each a single non-write public-ledger
              ;; ADT-update call. Emit Rust `if/else` where each branch
              ;; carries its own OpProgramVerify + query_for_verify; the
              ;; if-expression's QueryResults is threaded into the final
              ;; CircuitResults return. Mirrors the constraint above:
              ;; only fire when no plain writes accumulated and this is
              ;; the body's last statement.
              [(and (null? (cdr stmts))
                    (null? writes)
                    (let ([if-parts (stmt->if-then-else (car stmts))])
                      (and if-parts
                           (let ([then-parts
                                  (if-then-else-branch-pl-call?
                                    (cadr if-parts) local-binds
                                    native-id-ht witness-id-ht circuit-id-ht)]
                                 [else-parts
                                  (if-then-else-branch-pl-call?
                                    (caddr if-parts) local-binds
                                    native-id-ht witness-id-ht circuit-id-ht)])
                             (and then-parts else-parts
                                  (list (car if-parts) then-parts else-parts)))))) =>
               (lambda (bundle)
                 (emit-if-then-else-terminal
                   (car bundle) (cadr bundle) (caddr bundle)
                   local-binds mode witness-emitted? (reverse pre-lines)
                   native-id-ht witness-id-ht circuit-id-ht))]
              ;; Iter 4: terminal `(for var-name tsize0 tsize1 #f body)`
              ;; range loop with literal nat bounds. Body must be a single
              ;; non-write public-ledger ADT update call (e.g. Counter
              ;; increment). Unroll (hi - lo) iterations of the body's
              ;; builder lines into a single OpProgramVerify chain. The
              ;; loop var is not currently substituted into the body —
              ;; bodies that read `i` (e.g. `mp.insert(i)`) are deferred.
              [(and (null? (cdr stmts))
                    (null? writes)
                    (let ([fr (stmt->for-range (car stmts))])
                      (and fr
                           (let ([body-parts
                                  (branch->single-pl-call (cadddr fr))])
                             (and body-parts
                                  (not (stmt->public-ledger-write (cadddr fr)))
                                  (list (cadr fr) (caddr fr) body-parts)))))) =>
               (lambda (bundle)
                 (let ([lo (car bundle)]
                       [hi (cadr bundle)]
                       [body-parts (caddr bundle)])
                   (emit-for-range-terminal
                     lo hi
                     (car body-parts) (cadr body-parts)
                     (caddr body-parts) (cadddr body-parts)
                     local-binds mode witness-emitted? (reverse pre-lines)
                     native-id-ht witness-id-ht circuit-id-ht)))]
              ;; Iter 5/6: terminal `(statement-expression (fold ...))`
              ;; from a desugared `for (const x of <static-len iterable>)
              ;; { body }`. Unroll `len` iterations of the body's
              ;; builder lines into a single OpProgramVerify chain, with
              ;; the loop var substituted to the i-th literal from the
              ;; iterable on each iteration (Iter 6). The literals are
              ;; extracted up front so the loop body's expr* shape we
              ;; need to substitute into is captured once.
              [(and (null? (cdr stmts))
                    (null? writes)
                    (let ([fi (stmt->for-iter (car stmts))])
                      (and fi
                           (let* ([body-parts
                                   (branch->single-pl-call (caddr fi))]
                                  [literals
                                   (iterable-expr->literals (cadddr fi))])
                             (and body-parts
                                  literals
                                  (fx= (length literals) (car fi))
                                  (not (stmt->public-ledger-write (caddr fi)))
                                  (list (car fi) (cadr fi) body-parts literals)))))) =>
               (lambda (bundle)
                 (let ([len (car bundle)]
                       [elt-name (cadr bundle)]
                       [body-parts (caddr bundle)]
                       [literals (cadddr bundle)])
                   (emit-for-iter-terminal
                     len elt-name literals
                     (car body-parts) (cadr body-parts)
                     (caddr body-parts) (cadddr body-parts)
                     local-binds mode witness-emitted? (reverse pre-lines)
                     native-id-ht witness-id-ht circuit-id-ht)))]
              [(stmt->assert (car stmts)) =>
               (lambda (a)
                 (let* ([expr (car a)]
                        [msg (cdr a)]
                        [subcalls (collect-witness-subcalls
                                    expr witness-id-ht)]
                        [hoist (emit-hoisted-witnesses
                                 subcalls (length pre-lines) mode
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
                                             native-id-ht witness-id-ht circuit-id-ht))]
                        [line
                         (format "        compact_assert!(~a, ~s);\n"
                                 cond-str msg)])
                   (loop (cdr stmts)
                         local-binds
                         we2
                         (cons line (append hoist-lines pre-lines))
                         writes)))]
              [(const-binding (car stmts)) =>
               (lambda (b)
                 (let* ([var-name (car b)]
                        [rhs (cdr b)]
                        [rust-name (symbol->string (camel->snake (id-sym var-name)))]
                        [classified
                         (classify-const-rhs rhs witness-id-ht circuit-id-ht)])
                   ;; M3.5: record the var's declared type so later `==`
                   ;; rendering can detect tenum-typed locals.
                   (record-const-binding-type! var-name rhs
                                               witness-id-ht circuit-id-ht)
                   (case (car classified)
                     [(witness)
                      ;; Witness call. Emit:
                      ;;   let witness_ctx_N = WitnessContext::new(ledger(<state>), <prev-priv>, <qctx-ref>);
                      ;;   let (current_private_state, <name>) = self.witnesses.<m>(&witness_ctx_N, args...);
                      ;; In ctor mode the state/qctx live in the local
                      ;; `qctx` we built from the K1 seed; in circuit mode
                      ;; they come off `ctx.current_query_context`.
                      ;; For the first witness call, the source of the
                      ;; private state is `ctx.initial_private_state` (ctor)
                      ;; or `ctx.current_private_state` (circuit); for
                      ;; subsequent calls it's the `current_private_state`
                      ;; bound by the previous witness call.
                      (let* ([wname (cadr classified)]
                             [wargs (caddr classified)]
                             [ctx-name (format "_witness_ctx_~a" (length pre-lines))]
                             [state-expr (if (eq? mode 'ctor)
                                             "&qctx.state"
                                             "&ctx.current_query_context.state")]
                             [qctx-ref (if (eq? mode 'ctor)
                                           "&qctx"
                                           "&ctx.current_query_context")]
                             [prev-priv
                              (cond
                                [witness-emitted? "current_private_state"]
                                [(eq? mode 'ctor) "ctx.initial_private_state"]
                                [else "ctx.current_private_state"])]
                             [arg-strs
                              (map (lambda (e)
                                     (arg-rust-clone-if-var
                                       e local-binds
                                       native-id-ht witness-id-ht circuit-id-ht))
                                   wargs)]
                             [call-line
                              (format "        let ~a = WitnessContext::new(ledger(~a), ~a, ~a);\n"
                                      ctx-name state-expr prev-priv qctx-ref)]
                             [bind-line
                              (format "        let (current_private_state, ~a) = self.witnesses.~a(&~a~a);\n"
                                      rust-name wname ctx-name
                                      (let join ([xs arg-strs] [acc ""])
                                        (cond
                                          [(null? xs) acc]
                                          [else (join (cdr xs)
                                                      (string-append acc ", " (car xs)))])))])
                        (loop (cdr stmts)
                              (cons (cons var-name rust-name) local-binds)
                              #t
                              (cons bind-line (cons call-line pre-lines))
                              writes))]
                     [(pure-circuit)
                      (let* ([pname (cadr classified)]
                             [pargs (caddr classified)]
                             ;; F2.2: peek at the callee's formal types so
                             ;; per-arg rendering can coerce tenum ledger
                             ;; reads to the actual enum variant.
                             [callee
                              (nanopass-case (Ltypescript Expression) (expr-strip-cast rhs)
                                [(call ,src ,function-name ,expr* ...)
                                 (eq-hashtable-ref circuit-id-ht function-name #f)]
                                [else #f])]
                             [formal-types (circuit-formal-arg-types callee)]
                             [arg-strs
                              (let loop ([as pargs] [fs formal-types] [acc '()])
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
                                     (loop (cdr as)
                                           (if (pair? fs) (cdr fs) '())
                                           (cons s acc)))]))]
                             [bind-line
                              (format "        let ~a = pure_circuits::~a(~a);\n"
                                      rust-name pname
                                      (let join ([xs arg-strs] [acc ""])
                                        (cond
                                          [(null? xs) acc]
                                          [(null? (cdr xs)) (string-append acc (car xs))]
                                          [else (join (cdr xs)
                                                      (string-append acc (car xs) ", "))])))])
                        (loop (cdr stmts)
                              (cons (cons var-name rust-name) local-binds)
                              witness-emitted?
                              (cons bind-line pre-lines)
                              writes))]
                     [(impure-exported)
                      ;; E5: const binding whose RHS is a call to an
                      ;; exported impure circuit. Emit
                      ;;     let _cr_N = self.<name>(ctx, args)?;
                      ;;     let ctx = _cr_N.context;
                      ;;     let <rust-name> = _cr_N.result;
                      ;; Subsequent witness / write code reads off the
                      ;; rebound `ctx`, so private state and gas state
                      ;; flow through transparently.
                      (let* ([cname (cadr classified)]
                             [cargs (caddr classified)]
                             [counter (length pre-lines)]
                             [cr-name (format "_cr_~a" counter)]
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
                                              (string-append acc ", " (car xs)))]))]
                             [call-line
                              (format "        let ~a = self.~a(ctx~a)?;\n"
                                      cr-name cname arg-tail)]
                             [ctx-line
                              (format "        let ctx = ~a.context;\n" cr-name)]
                             [bind-line
                              (format "        let ~a = ~a.result;\n"
                                      rust-name cr-name)])
                        (loop (cdr stmts)
                              (cons (cons var-name rust-name) local-binds)
                              witness-emitted?
                              (cons bind-line
                                    (cons ctx-line
                                          (cons call-line pre-lines)))
                              writes))]
                     [else
                      ;; Unknown rhs shape — try a generic ctor-expr-rust
                      ;; render and emit a plain `let`.
                      ;;
                      ;; Prod-9: when the binding's declared type is `Field`
                      ;; (`tfield`) AND the RHS strips down to a bare integer
                      ;; literal, wrap as `Fr::from(<n>u64)` so downstream
                      ;; ledger-write builders (which demand `Into<AlignedValue>`)
                      ;; see the correct `Fr` type rather than an i32. Without
                      ;; this, contracts like
                      ;;     ledger v: Field;
                      ;;     constructor() { v = 42; }
                      ;; emit `let tmp = 42;` and fail to compile.
                      (let* ([decl-type (const-binding-decl-type (car stmts))]
                             [coerced (coerce-literal-rhs-rendered decl-type rhs)]
                             [rendered
                              (or coerced
                                  (ctor-expr-rust rhs local-binds
                                                  native-id-ht witness-id-ht circuit-id-ht))])
                        (loop (cdr stmts)
                              (cons (cons var-name rust-name) local-binds)
                              witness-emitted?
                              (cons (format "        let ~a = ~a;\n" rust-name rendered)
                                    pre-lines)
                              writes))])))]
              ;; E4.2: a bare call statement (witness or pure-circuit whose
              ;; return value is discarded). zerocash_mint's
              ;; `private$add_coin(coin);` lands here. We emit a `let _ = ...`
              ;; (re-binding `current_private_state` for witness calls so
              ;; subsequent witness invocations see the updated state).
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
                             [ctx-name (format "_witness_ctx_~a" (length pre-lines))]
                             [state-expr (if (eq? mode 'ctor)
                                             "&qctx.state"
                                             "&ctx.current_query_context.state")]
                             [qctx-ref (if (eq? mode 'ctor)
                                           "&qctx"
                                           "&ctx.current_query_context")]
                             [prev-priv
                              (cond
                                [witness-emitted? "current_private_state"]
                                [(eq? mode 'ctor) "ctx.initial_private_state"]
                                [else "ctx.current_private_state"])]
                             [arg-strs
                              (map (lambda (e)
                                     (arg-rust-clone-if-var
                                       e local-binds
                                       native-id-ht witness-id-ht circuit-id-ht))
                                   wargs)]
                             [call-line
                              (format "        let ~a = WitnessContext::new(ledger(~a), ~a, ~a);\n"
                                      ctx-name state-expr prev-priv qctx-ref)]
                             [bind-line
                              (format "        let (current_private_state, _) = self.witnesses.~a(&~a~a);\n"
                                      wname ctx-name
                                      (let join ([xs arg-strs] [acc ""])
                                        (cond
                                          [(null? xs) acc]
                                          [else (join (cdr xs)
                                                      (string-append acc ", " (car xs)))])))])
                        (loop (cdr stmts)
                              local-binds
                              #t
                              (cons bind-line (cons call-line pre-lines))
                              writes))]
                     [(pure-circuit)
                      (let* ([pname (cadr classified)]
                             [pargs (caddr classified)]
                             [arg-strs
                              (map (lambda (e)
                                     (arg-rust-clone-if-var
                                       e local-binds
                                       native-id-ht witness-id-ht circuit-id-ht))
                                   pargs)]
                             [bind-line
                              (format "        let _ = pure_circuits::~a(~a);\n"
                                      pname
                                      (let join ([xs arg-strs] [acc ""])
                                        (cond
                                          [(null? xs) acc]
                                          [(null? (cdr xs)) (string-append acc (car xs))]
                                          [else (join (cdr xs)
                                                      (string-append acc (car xs) ", "))])))])
                        (loop (cdr stmts)
                              local-binds
                              witness-emitted?
                              (cons bind-line pre-lines)
                              writes))]
                     [(impure-exported)
                      ;; E5: bare statement-position call to an exported
                      ;; impure circuit. Discard the result value, but
                      ;; thread the returned context into a rebound `ctx`
                      ;; so subsequent statements see the updated state.
                      (let* ([cname (cadr classified)]
                             [cargs (caddr classified)]
                             [counter (length pre-lines)]
                             [cr-name (format "_cr_~a" counter)]
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
                                              (string-append acc ", " (car xs)))]))]
                             [call-line
                              (format "        let ~a = self.~a(ctx~a)?;\n"
                                      cr-name cname arg-tail)]
                             [ctx-line
                              (format "        let ctx = ~a.context;\n" cr-name)])
                        (loop (cdr stmts)
                              local-binds
                              witness-emitted?
                              (cons ctx-line (cons call-line pre-lines))
                              writes))]
                     [else #f])))]
              [else
               ;; Expect a `(statement-expression (public-ledger ... write expr))`.
               (let ([w (stmt->public-ledger-write (car stmts))])
                 (cond
                   [w (loop (cdr stmts) local-binds witness-emitted?
                            pre-lines (cons w writes))]
                   [else #f]))]))))

      ;; emit-ctor-body-or-fallback: backwards-compatible wrapper that calls
      ;; emit-body-or-fallback in 'ctor mode. Kept for emit-initial-state's
      ;; existing call site.
      (define (emit-ctor-body-or-fallback stmt
                                          native-id-ht witness-id-ht circuit-id-ht)
        (emit-body-or-fallback stmt 'ctor
                               native-id-ht witness-id-ht circuit-id-ht))

      ;; classify-const-rhs: inspect a `const` binding's RHS expression and
      ;; classify the call (or return 'unknown). Returns
      ;;   (list 'witness rust-name args)         for witness calls
      ;;   (list 'pure-circuit rust-name args)    for pure circuit calls
      ;;   (list 'impure-exported rust-name args) for exported impure circuit
      ;;                                          method calls (`self.<name>`)
      ;;   (list 'unknown)                        otherwise
      (define (classify-const-rhs rhs witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast rhs)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...)
             (cond
               [(eq-hashtable-ref witness-id-ht function-name #f)
                (list 'witness
                      (camel->snake (id-sym function-name))
                      expr*)]
               [(and (eq-hashtable-ref circuit-id-ht function-name #f)
                     (id-pure? function-name))
                (list 'pure-circuit
                      (camel->snake (id-sym function-name))
                      expr*)]
               ;; E5: exported impure circuit. The callee is emitted as
               ;; `pub fn <name>(&self, ctx, ...) -> Result<CircuitResults<PS,T>>`
               ;; on the Contract impl, so the call shape is
               ;; `self.<snake>(ctx, args)?` returning a CircuitResults.
               [(and (eq-hashtable-ref circuit-id-ht function-name #f)
                     (id-exported? function-name)
                     (not (id-pure? function-name)))
                (list 'impure-exported
                      (camel->snake (id-sym function-name))
                      expr*)]
               [else (list 'unknown)])]
            [else (list 'unknown)])))

      ;; stmt->public-ledger-write: detect a single statement of shape
      ;; `(statement-expression (public-ledger field (idx) write expr))` and
      ;; return (cons path-idx expr). The path must be a single path-index;
      ;; ledger-op must be `write`. Returns #f for anything else.
      (define (stmt->public-ledger-write stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
              (nanopass-case (Ltypescript ADT-Op) adt-op
                [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                 (cond
                   [(not (eq? ledger-op 'write)) #f]
                   [(not (fx= (length path-elt*) 1)) #f]
                   [(not (fx= (length expr*) 1)) #f]
                   [else
                    (let ([path-idx
                           (nanopass-case (Ltypescript Path-Element) (car path-elt*)
                             [,path-index path-index]
                             [else #f])])
                      (and path-idx (cons path-idx (car expr*))))])])]
             [else #f])]
          [else #f]))

      ;; stmt->public-ledger-call: detect a single statement of shape
      ;; `(statement-expression (public-ledger field (idx) <op> expr*))` for
      ;; any ledger-op (including non-write ADT update ops like `insert`).
      ;; Returns (list src adt-op path-elt* expr*) on a match, #f otherwise.
      ;; Distinct from stmt->public-ledger-write — this terminal-call helper
      ;; is used by the body walker to dispatch the vm-code-driven emission
      ;; path (matching emit-public-ledger-call-body) for ADT inserts etc.
      (define (stmt->public-ledger-call stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
              (list src adt-op path-elt* expr*)]
             [else #f])]
          [else #f]))

      ;; stmt->bare-call: detect a single statement of shape
      ;; `(statement-expression (call <fn-id> <arg-expr>*))` and return
      ;; (cons fn-id args*). Used for witness or pure-circuit calls in
      ;; statement position whose return value is discarded (e.g.
      ;; zerocash_mint's `private$add_coin(coin);`). Returns #f otherwise.
      (define (stmt->bare-call stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (let ([e (expr-strip-cast expr)])
             (nanopass-case (Ltypescript Expression) e
               [(call ,src ,function-name ,expr* ...)
                (cons function-name expr*)]
               [else #f]))]
          [else #f]))

      ;; classify-call: same shape as classify-const-rhs but for a bare
      ;; (call <fn-id> args*) at statement position. Returns
      ;;   (list 'witness rust-name args)
      ;;   (list 'pure-circuit rust-name args)
      ;;   (list 'impure-exported rust-name args)
      ;;   (list 'unknown)
      (define (classify-call fn-id arg* witness-id-ht circuit-id-ht)
        (cond
          [(eq-hashtable-ref witness-id-ht fn-id #f)
           (list 'witness (camel->snake (id-sym fn-id)) arg*)]
          [(and (eq-hashtable-ref circuit-id-ht fn-id #f)
                (id-pure? fn-id))
           (list 'pure-circuit (camel->snake (id-sym fn-id)) arg*)]
          ;; E5: bare-call to an exported impure circuit (statement
          ;; position, return value discarded). Emit `self.<snake>(ctx, ...)`
          ;; and thread the returned context into a rebound `ctx`.
          [(and (eq-hashtable-ref circuit-id-ht fn-id #f)
                (id-exported? fn-id)
                (not (id-pure? fn-id)))
           (list 'impure-exported (camel->snake (id-sym fn-id)) arg*)]
          [else (list 'unknown)]))

      ;; stmt->if-then-else: detect a `(if cond then-stmt else-stmt)`
      ;; statement and return (list cond then-stmt else-stmt). Used by
      ;; E6.2's impure if-mid-body walker extension.
      (define (stmt->if-then-else stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(if ,src ,expr0 ,stmt1 ,stmt2) (list expr0 stmt1 stmt2)]
          [else #f]))

      ;; tsize->int / stmt->for-range: HISTORICAL — the original Iter 4
      ;; path dispatched on Ltypescript Type-Size + Statement `for` forms,
      ;; but those non-terminals/forms don't exist at the Ltypescript
      ;; layer. Type-Size is removed at the Lexpanded boundary
      ;; (langs.ss:611-613), and the Statement `for` form is removed at
      ;; Lexpr (langs.ss:367-376). The frontend lowers range loops
      ;;   `for (const i of N..M) { body }`
      ;; to an iterable form `(for src var-name (tuple ... lits ...) body)`
      ;; in expand-modules-and-types (analysis-passes.ss:1247-1261), and
      ;; infer-types then desugars the iterable form to a `(fold ...)`
      ;; expression (analysis-passes.ss:2878-2894). By the time we reach
      ;; Ltypescript every for-loop — range or iterable — is a `fold`.
      ;;
      ;; The dispatch sites in body-walkable? / emit-body-or-fallback
      ;; still reference these helpers; they're kept as always-#f stubs
      ;; so the call sites are no-ops and the fold-based Iter 5/6 path
      ;; (extended below to also recognise the lowered range form's
      ;; `(tuple src ...)` iterable shape) handles every case.
      (define (tsize->int t) #f)
      (define (stmt->for-range stmt) #f)

      ;; Iter 5: detect a Compact `for (const _ of <static-len iterable>)
      ;; { body }` after frontend desugaring. The Ltypescript IR has
      ;; already lowered the `for...of` form to a `fold`:
      ;;   (statement-expression
      ;;     (fold src len (circuit ((acc-var atype) (elt-var etype)) atype
      ;;                            (seq body-stmt acc-var-ref))
      ;;           init-expr
      ;;           map-arg))
      ;; with `len` known statically. We accept the shape only when the
      ;; body's accumulator is threaded unchanged (the trailing
      ;; statement-expression is a var-ref to `acc-var`), so the fold
      ;; degenerates into N side-effecting body executions — the same
      ;; semantics Iter 4's for-range covers.
      ;;
      ;; Returns (list len elt-var body-stmt iterable-expr) on match,
      ;; #f otherwise. `elt-var` is the loop-variable name (the element
      ;; binding in the desugared fold lambda). `iterable-expr` is the
      ;; iterable Expression extracted from the fold's single Map-
      ;; Argument slot — Iter 6 consumers (emit-for-iter-terminal) walk
      ;; it via `iterable-expr->literals` to recover the per-iteration
      ;; literal values used to substitute `elt-var` in the body.
      (define (stmt->for-iter stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(fold ,src ,len ,fun (,expr0 ,type0) ,map-arg ,map-arg* ...)
              ;; Single map-arg only — multi-zip folds (multiple
              ;; iterables) aren't covered by the MVP. The `(expr0
              ;; type0)` grouping is the fold's initial-accumulator
              ;; value + its type; we don't use either (Iter 6 only
              ;; substitutes the element binding) but the pattern must
              ;; destructure them so `map-arg` lines up.
              (and (null? map-arg*)
                   (nanopass-case (Ltypescript Function) fun
                     [(circuit ,src (,arg* ...) ,type ,stmt^)
                      ;; Expect exactly two args: (acc, elt).
                      (cond
                        [(not (fx= (length arg*) 2)) #f]
                        [else
                         (let ([acc-arg (car arg*)]
                               [elt-arg (cadr arg*)])
                           (nanopass-case (Ltypescript Argument) acc-arg
                             [(,var-name ,type)
                              (let ([acc-name var-name])
                                (nanopass-case (Ltypescript Argument) elt-arg
                                  [(,var-name ,type)
                                   (let ([elt-name var-name]
                                         [stripped
                                          (fold-body-strip-acc-return
                                            stmt^ acc-name)]
                                         [iter-expr
                                          (map-arg->expr map-arg)])
                                     (and stripped
                                          iter-expr
                                          (list len elt-name stripped iter-expr)))]))]))])]
                     [else #f]))]
             [else #f])]
          [else #f]))

      ;; map-arg->expr: peel the leading Expression out of a fold's
      ;; Map-Argument node. The Map-Argument shape is `(expr type type^)`
      ;; per langs.ss's Ltypescript Map-Argument definition. Returns the
      ;; inner Expression, or #f if the node isn't recognised.
      (define (map-arg->expr m)
        (nanopass-case (Ltypescript Map-Argument) m
          [(,expr ,type ,type^) expr]
          [else #f]))

      ;; iterable-expr->literals: returns a list of N literal Expression
      ;; nodes when `expr` is a statically-extractable iterable, #f
      ;; otherwise. Recognises two shapes:
      ;;
      ;;   (vector src (single src lit) ...)   ; user-written `[1,2,3]`
      ;;   (tuple  src (single src lit) ...)   ; synthesised by
      ;;                                       ; expand-modules-and-types
      ;;                                       ; for range loops
      ;;                                       ; `for (const i of N..M)`
      ;;                                       ; (analysis-passes.ss:1257-1258)
      ;;
      ;; Every element must be a `(quote src datum)` with an exact-
      ;; integer datum (optionally wrapped in safe-cast layers, peeled
      ;; by `tuple-arg->literal`).
      ;;
      ;; The returned list is in iteration order: the i-th element is
      ;; what `elt-name` binds to during iteration i.
      (define (iterable-expr->literals expr)
        (let ([e (expr-strip-cast expr)])
          (define (peel-tuple-args xs)
            (let loop ([xs xs] [acc '()])
              (cond
                [(null? xs) (reverse acc)]
                [else
                 (let ([elt (tuple-arg->literal (car xs))])
                   (and elt (loop (cdr xs) (cons elt acc))))])))
          (nanopass-case (Ltypescript Expression) e
            [(vector ,src ,tuple-arg* ...) (peel-tuple-args tuple-arg*)]
            [(tuple ,src ,tuple-arg* ...) (peel-tuple-args tuple-arg*)]
            [else #f])))

      ;; tuple-arg->literal: peel a `(single src expr)` Tuple-Argument
      ;; and return the inner Expression iff it strips down to a
      ;; `(quote src <int>)` literal. Spread args (`(spread src nat
      ;; expr)`) are rejected — Iter 6 only handles flat array
      ;; literals. Returns the original Expression (with casts intact)
      ;; on success, #f otherwise.
      (define (tuple-arg->literal t)
        (nanopass-case (Ltypescript Tuple-Argument) t
          [(single ,src ,expr)
           (let ([stripped (expr-strip-cast expr)])
             (nanopass-case (Ltypescript Expression) stripped
               [(quote ,src ,datum)
                (and (integer? datum) (exact? datum) expr)]
               [else #f]))]
          [else #f]))

      ;; expr-subst-var-ref: walk an Expression and replace every
      ;; `(var-ref src target-name)` with `replacement` (also an
      ;; Expression). Recurses through safe-cast layers, leaves all
      ;; other shapes alone — the Iter 6 MVP only needs to handle the
      ;; loop variable appearing directly (or under a safe-cast) as a
      ;; top-level `c.increment(x)` arg.
      ;;
      ;; Returns the (possibly identical) Expression. Used by
      ;; emit-for-iter-terminal to specialise the body's expr-list
      ;; per iteration before feeding it to compute-pl-builder-lines.
      (define (expr-subst-var-ref e target-name replacement)
        (nanopass-case (Ltypescript Expression) e
          [(var-ref ,src ,var-name)
           (if (eq? (id-sym var-name) (id-sym target-name))
               replacement
               e)]
          [(safe-cast ,src ,type ,type^ ,expr)
           (let ([sub (expr-subst-var-ref expr target-name replacement)])
             (with-output-language (Ltypescript Expression)
               `(safe-cast ,src ,type ,type^ ,sub)))]
          [else e]))

      ;; fold-body-strip-acc-return: given a fold body (Statement) and
      ;; the accumulator's var-name, peel off a trailing
      ;; `(statement-expression (var-ref acc-name))` that the desugar
      ;; emits to thread the accumulator through unchanged. Returns the
      ;; body Statement with that tail removed, or #f if no such tail.
      ;; The returned Statement is what we feed to branch->single-pl-call
      ;; to extract the side-effecting public-ledger call.
      (define (fold-body-strip-acc-return stmt acc-name)
        ;; Extract the outer stmt's src once; we reuse it as the
        ;; rebuilt-seq's src below. The `seq` form's src field is
        ;; constructor-validated as source-object?, so passing #f
        ;; would error at IR-construction time.
        (let ([outer-src
               (nanopass-case (Ltypescript Statement) stmt
                 [(seq ,src ,stmt* ... ,stmt^) src]
                 [else #f])]
              [flat (stmt-flatten stmt)])
          (cond
            [(null? flat) #f]
            [else
             ;; Last element should be a statement-expression wrapping a
             ;; var-ref to acc-name. Drop it and rebuild a seq from the
             ;; remaining stmts.
             (let ([rev (reverse flat)])
               (let ([tail (car rev)]
                     [rest (reverse (cdr rev))])
                 (and (stmt-is-var-ref? tail acc-name)
                      (cond
                        [(null? rest) #f]
                        [(null? (cdr rest)) (car rest)]
                        [(not outer-src) #f]
                        [else
                         ;; rest = (stmt0 stmt1 ... stmtN). seq's shape is
                         ;; (seq src stmt* ... stmt) — last in tail
                         ;; position.
                         (let ([rest-rev (reverse rest)])
                           (let ([last-stmt (car rest-rev)]
                                 [stmt* (reverse (cdr rest-rev))])
                             (with-output-language (Ltypescript Statement)
                               `(seq ,outer-src ,stmt* ... ,last-stmt))))]))))])))

      ;; stmt-is-var-ref?: detect `(statement-expression (var-ref name))`
      ;; matching `target-name`.
      (define (stmt-is-var-ref? stmt target-name)
        (nanopass-case (Ltypescript Statement) stmt
          [(statement-expression ,expr)
           (nanopass-case (Ltypescript Expression) expr
             [(var-ref ,src ,var-name)
              (eq? (id-sym var-name) (id-sym target-name))]
             [else #f])]
          [else #f]))

      ;; branch->single-pl-call: walk a single branch of an if-then-else
      ;; and extract a single `(public-ledger ...)` ADT-update call,
      ;; possibly preceded by safe-cast `const` bindings (which the
      ;; frontend inserts for literal-typed args, e.g. lowering
      ;; `tally_yes.increment(1)` to `const _tmp = safe-cast 1;
      ;; tally_yes.increment(_tmp);`).
      ;;
      ;; Returns (list src adt-op path-elt* resolved-expr*) on match
      ;; (mirroring `stmt->public-ledger-call`'s shape), #f otherwise.
      ;; `resolved-expr*` has had var-refs chased through any preceding
      ;; consts in the branch, and safe-cast layers stripped.
      (define (branch->single-pl-call stmt)
        (let loop ([stmts (stmt-flatten stmt)] [binds '()])
          (cond
            [(null? stmts) #f]
            [(const-binding (car stmts)) =>
             (lambda (b) (loop (cdr stmts) (cons b binds)))]
            [(and (null? (cdr stmts))
                  (stmt->public-ledger-call (car stmts))) =>
             (lambda (parts)
               ;; stmt->public-ledger-call returns (src adt-op path-elt*
               ;; expr*); rewrite expr* through `expr-resolve` so any
               ;; var-refs to preceding consts get chased.
               (let* ([src (car parts)]
                      [adt-op (cadr parts)]
                      [path-elt* (caddr parts)]
                      [expr* (cadddr parts)]
                      [resolved-expr* (map (lambda (e) (expr-resolve e binds))
                                           expr*)])
                 (and (not (memv #f resolved-expr*))
                      (list src adt-op path-elt* resolved-expr*))))]
            [else #f])))

      ;; compute-pl-builder-lines: given a public-ledger ADT-op + path +
      ;; arg expressions + local bindings, compute the list of builder-
      ;; call lines for the OpProgramVerify chain (push/idx/ins/...) via
      ;; expand-vm-code + vminstr->builder-call. Returns the list of
      ;; strings on success, #f on any failure (so caller falls back).
      ;;
      ;; Extracted from emit-non-write-public-ledger-terminal so both
      ;; that emitter and the E6.2 if-branch emitter can share the
      ;; vm-code translation without duplicating logic.
      (define (compute-pl-builder-lines
                src adt-op path-elt* expr* local-binds
                native-id-ht witness-id-ht circuit-id-ht)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (cond
             [(not (fx= (length expr*) (length var-name*))) #f]
             [else
              (let ([path-vals (map path-elt->vm-value path-elt*)]
                    [expr-vals
                     (map (lambda (e)
                            ;; Integer literals must stay as plain Scheme
                            ;; integers so `addi`'s `vm-immediate->int`
                            ;; unwraps the `(VMvalue->int n)` cleanly.
                            ;; Non-literal args go through the
                            ;; `vm-rust-expr` carrier (lifts the rendered
                            ;; Rust string into expand-vm-code).
                            (let ([stripped (expr-strip-cast e)])
                              (nanopass-case (Ltypescript Expression) stripped
                                [(quote ,src ,datum)
                                 (if (and (integer? datum) (exact? datum))
                                     datum
                                     (let ([rendered
                                            (guard (c [#t #f])
                                              (arg-rust-clone-if-var e local-binds
                                                                     native-id-ht
                                                                     witness-id-ht
                                                                     circuit-id-ht))])
                                       (and rendered (make-vm-rust-expr rendered))))]
                                [else
                                 (let ([rendered
                                        (guard (c [#t #f])
                                          (arg-rust-clone-if-var e local-binds
                                                                 native-id-ht
                                                                 witness-id-ht
                                                                 circuit-id-ht))])
                                   (and rendered (make-vm-rust-expr rendered)))])))
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
                             (expand-vm-code src path-vals #f arg-alist
                               (vm-code-code vm-code)))]
                          [lines (and vminstr* (map vminstr->builder-call vminstr*))])
                     (cond
                       [(or (not lines) (memv #f lines)) #f]
                       [else lines]))]))])]))

      ;; if-then-else-branch-pl-call?: returns the (list src adt-op
      ;; path-elt* expr*) parts when `branch-stmt` is a single non-write
      ;; public-ledger call, AND the builder lines compute successfully
      ;; against the given local-binds. Returns #f otherwise.
      ;;
      ;; This is the predicate used by both body-walkable? (E6.2
      ;; pre-validation) and emit-body-or-fallback (E6.2 emission) to
      ;; decide if a branch is emittable.
      (define (if-then-else-branch-pl-call?
                branch-stmt local-binds
                native-id-ht witness-id-ht circuit-id-ht)
        (let ([parts (branch->single-pl-call branch-stmt)])
          (and parts
               ;; Reject write-class (Cell.write) — its emission lives in
               ;; the emit-body-writes path and would need a different
               ;; OpProgramVerify chain shape. ADT-update calls (insert,
               ;; increment, etc.) are what E6.2 targets.
               (let ([adt-op (cadr parts)])
                 (not (stmt->public-ledger-write branch-stmt)))
               (let ([lines (compute-pl-builder-lines
                              (car parts) (cadr parts) (caddr parts)
                              (cadddr parts) local-binds
                              native-id-ht witness-id-ht circuit-id-ht)])
                 (and lines parts)))))

      ;; emit-ctor-prelude: emit the accumulated witness/pure-circuit/let
      ;; lines from the constructor body walk. They're already complete Rust
      ;; lines (with indentation + trailing newline), so just splat them out.
      (define (emit-ctor-prelude lines)
        (for-each out lines))

      ;; emit-body-writes: emit the OpProgramVerify chain for the collected
      ;; ledger field writes, then the query_for_verify call and the final
      ;; return value. `writes` is a list of (path-idx . expr). `mode` is
      ;; 'ctor (constructor) or 'circuit (impure circuit body); they differ
      ;; in the QueryContext source (`&qctx` vs `&ctx.current_query_context`)
      ;; and the return shape (`ConstructorResult` vs `CircuitResults`).
      ;; `witness-emitted?` controls whether we use `current_private_state`
      ;; (threaded through witness calls) or `ctx.initial_private_state`
      ;; (ctor mode) / falls back to the inline `..ctx` spread (circuit mode).
      (define (emit-body-writes writes mode local-binds
                                native-id-ht witness-id-ht circuit-id-ht
                                witness-emitted?)
        (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
        (for-each
          (lambda (w)
            (let* ([idx (car w)]
                   [val-expr (cdr w)]
                   [rust-val (arg-rust-clone-if-var val-expr local-binds
                                                    native-id-ht witness-id-ht circuit-id-ht)]
                   ;; Iter 7: Vector<N,T> ledger fields require
                   ;; `new_cell_array([T; N])` since `[T; N]: Into<AlignedValue>`
                   ;; isn't impl'd upstream (orphan rules). Look up the
                   ;; destination field's binding-type via the path-idx
                   ;; → Type map populated by `emit-initial-state`; if the
                   ;; field's read-op type is a tvector, switch the value
                   ;; builder from `new_cell` to `new_cell_array`.
                   ;; current-ledger-field-types defaults to #f (e.g. when
                   ;; this code runs in a circuit-body that hasn't been
                   ;; seeded yet — circuit bodies don't currently write
                   ;; Vector fields, but if they do, the fallback to
                   ;; `new_cell` matches the pre-Iter 7 shape).
                   [dest-type
                    (let ([ht (current-ledger-field-types)])
                      (and ht (hashtable-ref ht idx #f)))]
                   [dest-read-type
                    (and dest-type
                         (guard (c [#t #f]) (tadt-read-op-type dest-type)))]
                   [use-cell-array?
                    (and dest-read-type (type-is-tvector? dest-read-type))]
                   [cell-builder (if use-cell-array? "new_cell_array" "new_cell")])
              ;; Cell.write vm-code for a single-element path is exactly:
              ;;   push false (state-value 'cell (align idx 1))
              ;;   push true  (state-value 'cell <value>)
              ;;   ins false 1
              ;; (The leading idx and trailing ins are suppressed when the
              ;; path before the last element is empty, which it is here.)
              (out (format "            .push(false, new_cell(~au8))\n" idx))
              (out (format "            .push(true, ~a(~a))\n" cell-builder rust-val))
              (out "            .ins(false, 1)\n")))
          writes)
        (out "            .build();\n")
        (out "\n")
        (cond
          [(eq? mode 'ctor)
           (out "        let results = query_for_verify(&qctx, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?;\n")
           (out "\n")
           (out "        Ok(ConstructorResult {\n")
           (out "            current_contract_state: results.context.state,\n")
           (out (if witness-emitted?
                    "            current_private_state,\n"
                    "            current_private_state: ctx.initial_private_state,\n"))
           (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
           (out "        })\n")]
          [else
           ;; 'circuit mode: results live on the inbound ctx and we wrap
           ;; everything in a CircuitResults with unit result.
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
           (when witness-emitted?
             (out "                current_private_state,\n"))
           (out "                ..ctx\n")
           (out "            },\n")
           (out "            gas_cost: results.gas_cost,\n")
           (out "        })\n")]))

      ;; emit-ctor-writes: backwards-compatible alias used by the ctor path.
      (define (emit-ctor-writes writes local-binds
                                native-id-ht witness-id-ht circuit-id-ht
                                witness-emitted?)
        (emit-body-writes writes 'ctor local-binds
                          native-id-ht witness-id-ht circuit-id-ht
                          witness-emitted?))

      ;; emit-non-write-public-ledger-terminal: emit a terminal
      ;; `(public-ledger field (idx) <op> expr*)` whose op-class is NOT
      ;; `write`. Used for ADT update ops like HistoricMerkleTree.insert
      ;; that drive the OpProgramVerify chain through expand-vm-code +
      ;; vminstr->builder-call (the I3a infrastructure from E4.1) rather
      ;; than the hardcoded Cell.write pattern in emit-body-writes.
      ;;
      ;; The walker's accumulated `pre-lines` (witness / pure-circuit /
      ;; let bindings) are emitted first; then each arg expression is
      ;; resolved through `local-binds` and rendered to a Rust string,
      ;; lifted into a vm-rust-expr carrier that survives vm-code
      ;; expansion intact.
      ;;
      ;; Returns #t on success, #f if any step fails so the caller can
      ;; fall back to `unimplemented!()`.
      (define (emit-non-write-public-ledger-terminal
                src adt-op path-elt* expr* local-binds mode witness-emitted?
                pre-lines native-id-ht witness-id-ht circuit-id-ht)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (cond
             [(not (fx= (length expr*) (length var-name*))) #f]
             [else
              (let ([path-vals (map path-elt->vm-value path-elt*)]
                    [expr-vals
                     (map (lambda (e)
                            ;; Lift each arg to a vm-rust-expr carrier so
                            ;; expand-vm-code transports the rendered Rust
                            ;; intact down to vminstr->builder-call's push
                            ;; value rendering. Resolution via local-binds
                            ;; chases var-refs through the const-bindings
                            ;; the walker accumulated above.
                            (let ([rendered
                                   (guard (c [#t #f])
                                     (arg-rust-clone-if-var e local-binds
                                                            native-id-ht
                                                            witness-id-ht
                                                            circuit-id-ht))])
                              (and rendered (make-vm-rust-expr rendered))))
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
                             (expand-vm-code src path-vals #f arg-alist
                               (vm-code-code vm-code)))]
                          [lines (and vminstr* (map vminstr->builder-call vminstr*))])
                     (cond
                       [(or (not lines) (memv #f lines)) #f]
                       [else
                        ;; Emit the accumulated prelude (witness / pure /
                        ;; bare-call lines), then the OpProgramVerify
                        ;; chain, then query_for_verify + the final return.
                        (emit-ctor-prelude pre-lines)
                        (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
                        (for-each out lines)
                        (out "            .build();\n")
                        (out "\n")
                        (cond
                          [(eq? mode 'ctor)
                           (out "        let results = query_for_verify(&qctx, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?;\n")
                           (out "\n")
                           (out "        Ok(ConstructorResult {\n")
                           (out "            current_contract_state: results.context.state,\n")
                           (out (if witness-emitted?
                                    "            current_private_state,\n"
                                    "            current_private_state: ctx.initial_private_state,\n"))
                           (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
                           (out "        })\n")]
                          [else
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
                           (when witness-emitted?
                             (out "                current_private_state,\n"))
                           (out "                ..ctx\n")
                           (out "            },\n")
                           (out "            gas_cost: results.gas_cost,\n")
                           (out "        })\n")])
                        #t]))]))])]))

      ;; emit-if-then-else-terminal: E6.2's impure if-mid-body emission.
      ;; Emits the prelude (witness / pure-circuit / assert lines the
      ;; walker accumulated), then a Rust `if cond { ... } else { ... }`
      ;; where each branch is an OpProgramVerify chain + query_for_verify
      ;; producing a QueryResults; the if-expression yields that
      ;; QueryResults, which we unpack into the final CircuitResults
      ;; return.
      ;;
      ;; Narrow shape:
      ;;   - terminal `(if cond then-stmt else-stmt)` (last statement
      ;;     of the body's flat sequence; no post-if statements yet)
      ;;   - each branch is a single non-write public-ledger ADT-update
      ;;     call (e.g. `tally_yes.increment(1);`)
      ;;
      ;; Returns #t on success, #f if any sub-step fails (caller falls
      ;; back to `unimplemented!()`).
      (define (emit-if-then-else-terminal
                cond-expr then-parts else-parts
                local-binds mode witness-emitted? pre-lines
                native-id-ht witness-id-ht circuit-id-ht)
        (let* ([cond-str
                (guard (c [#t #f])
                  (cond-rust cond-expr local-binds
                             native-id-ht witness-id-ht circuit-id-ht))]
               [then-lines
                (and then-parts
                     (compute-pl-builder-lines
                       (car then-parts) (cadr then-parts) (caddr then-parts)
                       (cadddr then-parts) local-binds
                       native-id-ht witness-id-ht circuit-id-ht))]
               [else-lines
                (and else-parts
                     (compute-pl-builder-lines
                       (car else-parts) (cadr else-parts) (caddr else-parts)
                       (cadddr else-parts) local-binds
                       native-id-ht witness-id-ht circuit-id-ht))])
          (cond
            [(or (not cond-str) (not then-lines) (not else-lines)) #f]
            [(rendered-has-todo? cond-str) #f]
            [else
             (emit-ctor-prelude pre-lines)
             (let ([qctx-ref (if (eq? mode 'ctor)
                                 "&qctx"
                                 "&ctx.current_query_context")])
               (out (format "        let _if_results = if ~a {\n" cond-str))
               (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
               (for-each (lambda (l) (out (format "    ~a" l))) then-lines)
               (out "                .build();\n")
               (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                            qctx-ref))
               (out "        } else {\n")
               (out "            let ops = OpProgramVerify::<DefaultDB>::new()\n")
               (for-each (lambda (l) (out (format "    ~a" l))) else-lines)
               (out "                .build();\n")
               (out (format "            query_for_verify(~a, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?\n"
                            qctx-ref))
               (out "        };\n")
               (out "\n"))
             (cond
               [(eq? mode 'ctor)
                (out "        Ok(ConstructorResult {\n")
                (out "            current_contract_state: _if_results.context.state,\n")
                (out (if witness-emitted?
                         "            current_private_state,\n"
                         "            current_private_state: ctx.initial_private_state,\n"))
                (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
                (out "        })\n")]
               [else
                (out "        Ok(CircuitResults {\n")
                (out "            result: (),\n")
                (out "            context: CircuitContext {\n")
                (out "                current_query_context: _if_results.context,\n")
                (when witness-emitted?
                  (out "                current_private_state,\n"))
                (out "                ..ctx\n")
                (out "            },\n")
                (out "            gas_cost: _if_results.gas_cost,\n")
                (out "        })\n")])
             #t])))

      ;; emit-for-range-terminal: Iter 4 — emit a terminal
      ;; `(for var-name lo..hi body)` range loop whose body is a single
      ;; non-write public-ledger ADT update call. Compile-time unrolls
      ;; the body's builder lines (hi - lo) times into a single
      ;; OpProgramVerify chain, then emits one `query_for_verify` plus
      ;; the standard ConstructorResult / CircuitResults return. The
      ;; loop var is not substituted into the body — bodies that
      ;; reference `i` (e.g. `mp.insert(i)`) currently fall back to the
      ;; emitter's unimplemented path. Returns #t on success, #f
      ;; otherwise so the caller falls back.
      ;; emit-for-iter-terminal: Iter 5/6 — emit a terminal
      ;; `(statement-expression (fold ...))` desugared from a Compact
      ;; `for (const x of <static-len iterable>) { body }`. Unrolls the
      ;; body's builder lines `len` times, substituting `elt-name` with
      ;; the i-th literal expression from `literals` before computing
      ;; the per-iteration builder lines. Returns #t on success, #f
      ;; otherwise.
      ;;
      ;; When the body doesn't reference `elt-name`, the substitution
      ;; is a no-op and each iteration produces identical builder
      ;; lines — recovering Iter 5's behaviour. When the body uses the
      ;; element directly as a call argument (e.g. `c.increment(x)`),
      ;; the per-iteration substitution materialises the literal
      ;; integer at compute-pl-builder-lines time so addi's immediate
      ;; resolves to a plain integer.
      (define (emit-for-iter-terminal
                len elt-name literals
                src adt-op path-elt* expr* local-binds mode witness-emitted?
                pre-lines native-id-ht witness-id-ht circuit-id-ht)
        (let ([per-iter-lines
               (let loop ([lits literals] [acc '()])
                 (cond
                   [(null? lits) (and (not (memv #f acc)) (reverse acc))]
                   [else
                    (let* ([lit (car lits)]
                           [subst-expr*
                            (map (lambda (e)
                                   (expr-subst-var-ref e elt-name lit))
                                 expr*)]
                           [lines
                            (compute-pl-builder-lines
                              src adt-op path-elt* subst-expr* local-binds
                              native-id-ht witness-id-ht circuit-id-ht)])
                      (loop (cdr lits) (cons lines acc)))]))])
          (cond
            [(or (not per-iter-lines) (not (fx= (length per-iter-lines) len))) #f]
            [else
             (emit-ctor-prelude pre-lines)
             (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
             (for-each (lambda (group) (for-each out group)) per-iter-lines)
             (out "            .build();\n")
             (out "\n")
             (cond
               [(eq? mode 'ctor)
                (out "        let results = query_for_verify(&qctx, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?;\n")
                (out "\n")
                (out "        Ok(ConstructorResult {\n")
                (out "            current_contract_state: results.context.state,\n")
                (out (if witness-emitted?
                         "            current_private_state,\n"
                         "            current_private_state: ctx.initial_private_state,\n"))
                (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
                (out "        })\n")]
               [else
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
                (when witness-emitted?
                  (out "                current_private_state,\n"))
                (out "                ..ctx\n")
                (out "            },\n")
                (out "            gas_cost: results.gas_cost,\n")
                (out "        })\n")])
             #t])))

      (define (emit-for-range-terminal
                lo hi
                src adt-op path-elt* expr* local-binds mode witness-emitted?
                pre-lines native-id-ht witness-id-ht circuit-id-ht)
        (let ([body-lines
               (compute-pl-builder-lines
                 src adt-op path-elt* expr* local-binds
                 native-id-ht witness-id-ht circuit-id-ht)]
              [iter-count (- hi lo)])
          (cond
            [(or (not body-lines) (< iter-count 0)) #f]
            [else
             (emit-ctor-prelude pre-lines)
             (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
             ;; Compile-time unroll: emit the body's builder lines N
             ;; times. Since the loop body doesn't read `i`, the N
             ;; emitted line groups are identical — the VM state
             ;; mutates N times because each .ins() commits an in-place
             ;; update independently.
             (let loop ([k 0])
               (cond
                 [(fx= k iter-count) #f]
                 [else
                  (for-each out body-lines)
                  (loop (+ k 1))]))
             (out "            .build();\n")
             (out "\n")
             (cond
               [(eq? mode 'ctor)
                (out "        let results = query_for_verify(&qctx, &ops, ctx.gas_limit.clone(), &ctx.cost_model)?;\n")
                (out "\n")
                (out "        Ok(ConstructorResult {\n")
                (out "            current_contract_state: results.context.state,\n")
                (out (if witness-emitted?
                         "            current_private_state,\n"
                         "            current_private_state: ctx.initial_private_state,\n"))
                (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
                (out "        })\n")]
               [else
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
                (when witness-emitted?
                  (out "                current_private_state,\n"))
                (out "                ..ctx\n")
                (out "            },\n")
                (out "            gas_cost: results.gas_cost,\n")
                (out "        })\n")])
             #t])))
