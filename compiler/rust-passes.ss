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
      (define (out s)
        (display-string s (get-target-port 'contract.rs)))

      ;; camel->snake: convert a CamelCase / mixedCase identifier symbol
      ;; into snake_case. Used for witness method names. Also sanitises
      ;; Compact-allowed `$` characters (which Rust doesn't permit in
      ;; identifiers) by mapping them to `_`.
      (define (camel->snake s)
        (let* ([str (symbol->string s)]
               [chars (string->list str)])
          (string->symbol
            (apply string-append
              (let loop ([chars chars] [first? #t])
                (cond
                  [(null? chars) '()]
                  [(char-upper-case? (car chars))
                   (cons (if first? "" "_")
                         (cons (string (char-downcase (car chars)))
                               (loop (cdr chars) #f)))]
                  [(char=? (car chars) #\$)
                   (cons "_" (loop (cdr chars) #f))]
                  [else (cons (string (car chars)) (loop (cdr chars) #f))]))))))

      ;; uint-rust-width: given the declared max value `nat` of a
      ;; (tunsigned src nat) Compact type, pick the smallest Rust
      ;; unsigned integer type that fits. Compact's `tunsigned` stores
      ;; the maximum value (not bit width), e.g. `Uint<0..65535>` lowers
      ;; to (tunsigned src 65535). Mirrors the TS emitter's bigint
      ;; pattern but specializes to a sized Rust primitive.
      (define (uint-rust-width nat)
        (cond
          [(<= nat 255) "u8"]
          [(<= nat 65535) "u16"]
          [(<= nat 4294967295) "u32"]
          [(<= nat 18446744073709551615) "u64"]
          [else "u128"]))

      ;; type-rust: walk an Ltypescript Type IR node and produce the
      ;; corresponding Rust type string. Covers M3-F1 scope: primitives
      ;; (tfield, tboolean, tunsigned, tbytes), ttuple, and tvector.
      ;; Aggregate / nominal forms (talias, tenum, tstruct, tcontract,
      ;; tjubjub, topaque, tunknown, ...) emit a placeholder TODO string
      ;; tagged with the variant name so later tasks (F2-F4) can locate
      ;; missing cases. Never crashes on unknown variants.
      (define (type-rust type)
        (nanopass-case (Ltypescript Type) type
          [(tfield ,src) "Fr"]
          [(tboolean ,src) "bool"]
          [(tunsigned ,src ,nat) (uint-rust-width nat)]
          [(tbytes ,src ,len) (format "[u8; ~a]" len)]
          [(ttuple ,src ,type* ...)
           (let ([parts (map type-rust type*)])
             (cond
               [(null? parts) "()"]
               ;; Rust 1-tuples need a trailing comma: (T,)
               [(null? (cdr parts)) (format "(~a,)" (car parts))]
               [else
                (format "(~a)"
                  (let loop ([xs parts] [acc ""])
                    (cond
                      [(null? (cdr xs)) (string-append acc (car xs))]
                      [else (loop (cdr xs)
                                  (string-append acc (car xs) ", "))])))]))]
          [(tvector ,src ,len ,type)
           (format "[~a; ~a]" (type-rust type) len)]
          [(talias ,src ,nominal? ,type-name ,type)
           ;; Aliases are transparent; recurse. (Nominal aliases will
           ;; later become named Rust types in F2/F3.)
           (type-rust type)]
          [(topaque ,src ,opaque-type)
           (format "/* TODO M3-F4: topaque ~a */" opaque-type)]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           ;; L1: Maybe<T> resolves to the canonical struct exposed by
           ;; compact-runtime. We locate the `value` field's type and
           ;; emit Maybe<<that-type>>. Other named structs lower to their
           ;; bare name; their definitions are emitted by emit-type-decls
           ;; (H5 / future tasks).
           (cond
             [(eq? struct-name 'Maybe)
              (let loop ([names elt-name*] [types type*])
                (cond
                  [(null? names) "Maybe</* L1: no value field */>"]
                  [(eq? (car names) 'value) (format "Maybe<~a>" (type-rust (car types)))]
                  [else (loop (cdr names) (cdr types))]))]
             [else (symbol->string struct-name)])]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           ;; Enum references in type position emit the bare name. The
           ;; definition (with #[repr(u8)] + variant discriminants) is
           ;; emitted by emit-type-decls when the enum is exported.
           ;; Non-exported enum references in circuit bodies are lowered
           ;; to numeric literals before this pass (see typescript-passes.ss
           ;; enum-ref handling), so a tenum here implies the enum *is*
           ;; in scope as a Rust type.
           (symbol->string enum-name)]
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (format "/* TODO M3-F4: tcontract ~a */" contract-name)]
          [(tunknown) "/* TODO M3-F4: tunknown */"]
          [else "/* TODO M3-F4: unhandled type variant */"]))

      (define (header)
        (out "// SPDX-License-Identifier: Apache-2.0\n")
        (out "// Generated by compactc. Do not edit by hand.\n")
        (out "\n")
        (out "#![allow(clippy::all, dead_code, unused_imports, unused_variables)]\n")
        (out "\n")
        (out "use compact_runtime::*;\n")
        (out "use std::marker::PhantomData;\n")
        (out "\n")
        (out (format "compact_runtime::check_runtime_version!(\"~a\");\n" runtime-version-string))
        (out "\n"))

      ;; emit-witnesses: emits the per-contract Witnesses<PS> trait.
      ;; For contracts with no witness declarations (e.g. counter.compact),
      ;; also emits an `impl<PS> Witnesses<PS> for NoWitnesses {}` blanket
      ;; impl so the generated Contract<PS, W = NoWitnesses> default works
      ;; out-of-the-box.
      (define (emit-witnesses witness-decl*)
        (out "pub trait Witnesses<PS> {\n")
        (for-each
          (lambda (w)
            (nanopass-case (Ltypescript Witness-Declaration) w
              [(witness ,src ,function-name (,arg* ...) ,type)
               ;; function-name is an id record with a uniquified internal symbol
               ;; (e.g. %private$secret_key.14). Use (id-sym) to extract the
               ;; original user-facing symbol before snake-casing.
               (out (format "    fn ~a<'a>(&self, ctx: &WitnessContext<Ledger<'a>, PS>"
                            (camel->snake (id-sym function-name))))
               ;; Emit each witness argument as `, name: type` after the
               ;; ctx arg. var-name is an id record — use (id-sym) before
               ;; snake-casing, matching the function-name treatment above.
               (for-each
                 (lambda (arg)
                   (nanopass-case (Ltypescript Argument) arg
                     [(,var-name ,type)
                      (out (format ", ~a: ~a"
                                   (camel->snake (id-sym var-name))
                                   (type-rust type)))]))
                 arg*)
               (out (format ") -> (PS, ~a);\n" (type-rust type)))]))
          witness-decl*)
        (out "}\n")
        (when (null? witness-decl*)
          (out "impl<PS> Witnesses<PS> for NoWitnesses {}\n"))
        (out "\n"))

      ;; emit-contract-struct: emits the public `Contract<PS, W>` struct
      ;; generic over private state type PS and a witnesses impl W
      ;; (defaulting to NoWitnesses), and opens an `impl` block containing
      ;; the `new()` constructor. The impl block is left open so that
      ;; subsequent helpers (initial_state, circuits — Tasks D4-D7) can
      ;; emit methods inside it. The caller must invoke
      ;; `close-contract-struct` after emitting those methods.
      (define (emit-contract-struct)
        (out "pub struct Contract<PS, W = NoWitnesses>\n")
        (out "where\n")
        (out "    W: Witnesses<PS>,\n")
        (out "{\n")
        (out "    pub witnesses: W,\n")
        (out "    _ps: PhantomData<PS>,\n")
        (out "}\n")
        (out "\n")
        (out "impl<PS, W> Contract<PS, W>\n")
        (out "where\n")
        (out "    W: Witnesses<PS>,\n")
        (out "{\n")
        (out "    pub fn new(witnesses: W) -> Self {\n")
        (out "        Self { witnesses, _ps: PhantomData }\n")
        (out "    }\n"))

      ;; close-contract-struct: closes the impl block opened by
      ;; emit-contract-struct.
      (define (close-contract-struct)
        (out "}\n\n"))

      ;; witness?: returns #t if a Program-Element is a Witness-Declaration.
      (define (witness? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(witness ,src ,function-name (,arg* ...) ,type) #t]
          [else #f]))

      ;; Collect witness declarations from a list of program elements.
      (define (program-witnesses pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(witness? (car pelt*))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))

      ;; lfield?: returns #t if a Program-Element is a Ledger-Declaration
      ;; (i.e. a `public-ledger-declaration` form). In Ltypescript the
      ;; Program-Element nonterminal includes `ldecl`, whose Ltypescript
      ;; form is `(public-ledger-declaration pl-array lconstructor)`.
      (define (lfield? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(public-ledger-declaration ,pl-array ,lconstructor) #t]
          [else #f]))

      ;; Collect ledger field declarations from a list of program elements.
      (define (program-ledger-fields pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(lfield? (car pelt*))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))

      ;; ldecl-constructor-args: from a Program-Element of shape
      ;; (public-ledger-declaration pl-array lconstructor), extract the
      ;; constructor's Argument list. The lconstructor has shape
      ;; (constructor src (arg* ...) stmt). Returns '() if none.
      (define (ldecl-constructor-args ldecl)
        (nanopass-case (Ltypescript Program-Element) ldecl
          [(public-ledger-declaration ,pl-array ,lconstructor)
           (nanopass-case (Ltypescript Ledger-Constructor) lconstructor
             [(constructor ,src (,arg* ...) ,stmt) arg*])]
          [else '()]))

      ;; program-constructor-args: locate the (single) public-ledger-declaration
      ;; in the Program and return its constructor's arg list. Used by
      ;; emit-initial-state to emit user-supplied constructor parameters.
      (define (program-constructor-args pelt*)
        (let ([ldecl* (program-ledger-fields pelt*)])
          (if (null? ldecl*) '() (ldecl-constructor-args (car ldecl*)))))

      ;; export-tdefn?: returns #t if a Program-Element is an
      ;; `export-typedef` form. Non-exported user enums/structs/aliases
      ;; are dropped before Ltypescript and therefore never appear here;
      ;; their values are lowered to numeric discriminants in expressions
      ;; during the language transition (see typescript-passes.ss).
      (define (export-tdefn? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(export-typedef ,src ,type-name (,tvar-name* ...) ,type) #t]
          [else #f]))

      ;; Collect exported type definitions from a list of program elements.
      (define (program-export-tdefns pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(export-tdefn? (car pelt*))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))

      ;; circuit?: returns #t if a Program-Element is a Circuit-Definition.
      (define (circuit? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt) #t]
          [else #f]))

      ;; Collect circuit definitions from a list of program elements.
      ;; Only exported circuits make the public surface — non-exported
      ;; helpers (e.g. tiny.compact's `in_state`) and stdlib circuits
      ;; reached via specialisation (e.g. `some<Field>`, `none<Field>`)
      ;; live in the IR with id-exported? = #f. The TS path inlines them
      ;; at the use site; the Rust path will do the same once I3 handles
      ;; circuit body emission.
      (define (program-circuits pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(and (circuit? (car pelt*))
                  (id-exported? (circuit-function-name (car pelt*))))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))

      ;; circuit-function-name: extract the function-name id record from a
      ;; Circuit-Definition Program-Element. Used to query (id-pure?) at the
      ;; dispatch site without re-pattern-matching.
      (define (circuit-function-name pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt) function-name]))

      ;; emit-type-decls: emit one Rust type declaration per exported
      ;; user type. For `tenum`, emit a `#[repr(u8)] pub enum` with
      ;; explicit discriminants. `tstruct` and `talias` emit TODO
      ;; placeholders for later M3 tasks; anything else also emits a
      ;; TODO so unknown variants stay visible.
      (define (emit-type-decls export-tdefn*)
        (unless (null? export-tdefn*)
          (for-each
            (lambda (pelt)
              (nanopass-case (Ltypescript Program-Element) pelt
                [(export-typedef ,src ,type-name (,tvar-name* ...) ,type)
                 (nanopass-case (Ltypescript Type) type
                   [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                    (out "#[derive(Clone, Copy, Debug, PartialEq, Eq)]\n")
                    (out "#[repr(u8)]\n")
                    (out (format "pub enum ~a {\n" enum-name))
                    (let loop ([variants (cons elt-name elt-name*)] [i 0])
                      (unless (null? variants)
                        (out (format "    ~a = ~a,\n" (car variants) i))
                        (loop (cdr variants) (+ i 1))))
                    (out "}\n")
                    ;; H2: Aligned impl — delegate to u8.
                    (out (format "impl Aligned for ~a {\n" enum-name))
                    (out "    fn alignment() -> Alignment {\n")
                    (out "        u8::alignment()\n")
                    (out "    }\n")
                    (out "}\n")
                    ;; H3: FieldRepr impl — delegate to u8.
                    (out (format "impl FieldRepr for ~a {\n" enum-name))
                    (out "    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {\n")
                    (out "        (*self as u8).field_repr(writer);\n")
                    (out "    }\n")
                    (out "    fn field_size(&self) -> usize { 1 }\n")
                    (out "}\n")
                    ;; H4: FromFieldRepr impl — match u8 discriminant to variant.
                    (out (format "impl FromFieldRepr for ~a {\n" enum-name))
                    (out "    const FIELD_SIZE: usize = 1;\n")
                    (out "    fn from_field_repr(r: &[Fr]) -> Option<Self> {\n")
                    (out "        let n = u8::from_field_repr(r)?;\n")
                    (out "        match n {\n")
                    (let loop ([variants (cons elt-name elt-name*)] [i 0])
                      (unless (null? variants)
                        (out (format "            ~a => Some(Self::~a),\n" i (car variants)))
                        (loop (cdr variants) (+ i 1))))
                    (out "            _ => None,\n")
                    (out "        }\n")
                    (out "    }\n")
                    (out "}\n")]
                   [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                    (cond
                      [(eq? struct-name 'Maybe)
                       ;; L1: Maybe<T> is provided by compact-runtime as a
                       ;; canonical generic struct — skip per-contract
                       ;; redefinition. Other named structs still emit a
                       ;; TODO placeholder until H5 lands.
                       (void)]
                      [else
                       (out (format "// TODO M3-H5: struct ~a\n" struct-name))])]
                   [(talias ,src ,nominal? ,type-name ,type)
                    (out (format "// TODO M3-F2: talias ~a\n" type-name))]
                   [else
                    (out "// TODO M3: unhandled export-typedef variant\n")])]
                [else (void)]))
            export-tdefn*)
          (out "\n")))

      ;; emit-initial-state: emits the `initial_state` constructor method
      ;; inside the open Contract impl block. For counter.compact this
      ;; seeds the single Counter ledger field to 0.
      ;;
      ;; TODO(M3): this hardcodes Counter as the only supported ADT.
      ;; Generalising to Cell/Map/Set/MerkleTree/List requires walking the
      ;; Ledger-Constructor body and dispatching on each field's ADT type.
      (define (emit-initial-state ledger-field* ctor-arg*)
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
        ;; J2 (constructor body emission) later overrides these defaults
        ;; with whatever the source constructor assigns.
        (out "        let sv = new_array(vec![\n")
        (let ([all-bindings
               (apply append
                 (map (lambda (lf)
                        (nanopass-case (Ltypescript Program-Element) lf
                          [(public-ledger-declaration ,pl-array ,lconstructor)
                           (pl-array->public-bindings pl-array)]
                          [else '()]))
                      ledger-field*))])
          (for-each
            (lambda (pb)
              (let ([read-type (tadt-read-op-type (binding-type pb))])
                (out (format "            new_cell(~a),\n"
                             (default-value-rust read-type)))))
            all-bindings))
        (out "        ]);\n")
        (out "        let state = ChargedState::new(sv);\n")
        (out "        let qctx = QueryContext::new(state, ContractAddress::default());\n")
        (out "        Ok(ConstructorResult {\n")
        (out "            current_contract_state: qctx.state,\n")
        (out "            current_private_state: ctx.initial_private_state,\n")
        (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
        (out "        })\n")
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

      ;; stmt-flatten: collapse nested `seq`s and trailing-`(tuple)` unit
      ;; statements into a flat list of leaf Statements. The unit
      ;; `(statement-expression (tuple src))` at the end of a `seq` is
      ;; pure (returns ()), so dropping it preserves semantics for our
      ;; void-returning circuits. Any other shape is left alone — callers
      ;; treat unexpected leaves as a non-match and fall back.
      (define (stmt-flatten stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(seq ,src ,stmt* ... ,stmt^)
           (let ([all (append stmt* (list stmt^))])
             (apply append (map stmt-flatten all)))]
          [(statement-expression ,expr)
           ;; Drop a bare unit `(tuple src)` — common terminal of a `seq`
           ;; for void-returning circuits.
           (nanopass-case (Ltypescript Expression) expr
             [(tuple ,src ,tuple-arg* ...)
              (if (null? tuple-arg*) '() (list stmt))]
             [else (list stmt)])]
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
        (let ([e (expr-strip-cast expr)])
          (nanopass-case (Ltypescript Expression) e
            [(var-ref ,src ,var-name)
             (cond
               [(assq var-name binds) =>
                (lambda (p) (expr-resolve (cdr p) binds))]
               [else #f])]
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

      ;; expr->vm-value: turn a circuit argument Expression into a value
      ;; that the VM code can consume. I3a only needs literal integers
      ;; (counter's `round.increment(1)` passes the constant `1`); the
      ;; vm-code wraps these in `(rt-value->int amount)`, producing
      ;; `(VMvalue->int <int>)` after expansion, which we unwrap in
      ;; vminstr->builder-call. For anything we don't recognise, return
      ;; #f so the caller can bail out.
      (define (expr->vm-value expr)
        (nanopass-case (Ltypescript Expression) expr
          [(quote ,src ,datum)
           (if (and (integer? datum) (exact? datum)) datum #f)]
          [else #f]))

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

      ;; vminstr->builder-call: render a single vminstr as one line of the
      ;; OpProgramVerify builder chain (already indented for inclusion
      ;; inside the `let ops = ...` block). Recognises the ops needed by
      ;; counter — `idx`, `addi`, `ins`. Anything else returns #f so the
      ;; caller can bail out to the `unimplemented!()` fallback rather
      ;; than emit syntactically-valid but semantically-wrong Rust.
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
                  (let ([n (vm-immediate->int (cdr imm-pair))])
                    (and n (format "            .addi(~a)\n" n)))]))]
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
      (define (emit-impure-circuit cdefn)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
           (out (format "    pub fn ~a(\n" (camel->snake (id-sym function-name))))
           (out "        &self,\n")
           (out "        ctx: CircuitContext<PS>")
           (emit-circuit-args arg*)
           (out (format ",\n    ) -> Result<CircuitResults<PS, ~a>, CompactError> {\n"
                        (type-rust type)))
           (let ([emitted?
                  (and (unit-type? type)
                       (let ([call (stmt->single-public-ledger-call stmt)])
                         (and call
                              (emit-public-ledger-call-body
                                src
                                (cadr call)        ; adt-op
                                (car call)         ; path-elt*
                                (caddr call)))))]) ; expr*
             (unless emitted?
               (out (format "        unimplemented!(\"M3-I3: circuit body emission for ~a\")\n"
                            (id-sym function-name)))))
           (out "    }\n\n")]))

      ;; emit-pure-circuit: emit a pure circuit as a free function inside
      ;; `mod pure_circuits`. No ctx — just the declared args and a direct
      ;; return type. Body is an `unimplemented!()` placeholder; M3-I3 fills
      ;; this in.
      (define (emit-pure-circuit cdefn)
        (nanopass-case (Ltypescript Program-Element) cdefn
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
           (out (format "    pub fn ~a(" (camel->snake (id-sym function-name))))
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
           (out (format "        unimplemented!(\"M3-I3: pure circuit body emission for ~a\")\n"
                        (id-sym function-name)))
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
          [(talias ,src ,nominal? ,type-name ,type) (default-value-rust type)]
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
              (let* ([name (binding-field-name pb)]
                     [path* (binding-path-indices pb)]
                     [read-type (tadt-read-op-type (binding-type pb))]
                     [rust-ret (type-rust read-type)]
                     [decoder (or (decoder-for-type read-type)
                                  (format "/* TODO M3-K2.1: decoder for ~a */ compact_runtime::std_lib::decode_u64"
                                          rust-ret))])
                (out (format "    pub fn ~a(&self) -> Result<~a, CompactError> {\n" name rust-ret))
                (out "        let qctx = QueryContext::new(self.state.clone(), ContractAddress::default());\n")
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
                (out "    }\n")))
            exported-bindings))
        (out "}\n\n"))

      ;; emit-pure-circuits: emits the `pure_circuits` module containing one
      ;; free function per pure circuit declaration. Contracts with no pure
      ;; circuits (e.g. counter.compact) get an empty module.
      (define (emit-pure-circuits pure-circuit*)
        (out "pub mod pure_circuits {\n")
        (for-each emit-pure-circuit pure-circuit*)
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
            port))))
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,tdescs ,pelt* ...)
       (header)
       (emit-type-decls (program-export-tdefns pelt*))
       (emit-witnesses (program-witnesses pelt*))
       (emit-contract-struct)
       (emit-initial-state (program-ledger-fields pelt*)
                           (program-constructor-args pelt*))
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
                   [else (loop (cdr c*) acc)]))])
         (for-each
           (lambda (c)
             (unless (id-pure? (circuit-function-name c))
               (emit-impure-circuit c)))
           circuit*)
         (close-contract-struct)
         (emit-ledger-view (program-ledger-fields pelt*))
         (emit-pure-circuits pure-circuit*))
       (emit-cargo-toml)
       ir]))

  (define-passes rust-passes
    (print-rust          Ltypescript)))
