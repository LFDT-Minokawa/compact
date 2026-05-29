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

      ;; current-qctx-ref: Rust expression string referring to the
      ;; QueryContext that ledger-read sub-expressions should read from.
      ;; In circuit bodies this is `&ctx.current_query_context`; in the
      ;; constructor body it is `&qctx` (the local QueryContext we built
      ;; from the K1 seed). emit-body-or-fallback parameterizes this
      ;; before walking the body.
      (define current-qctx-ref
        (make-parameter "&ctx.current_query_context"))

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
           ;; Nominal aliases emit the alias name (the user expects to see
           ;; `MyId` in signatures, not the expanded underlying form);
           ;; transparent aliases expand. Compact's `type X = ...` is a
           ;; transparent alias by default; `nominal type X = ...` is the
           ;; nominal form. F2 of M3.
           (if nominal? (symbol->string type-name) (type-rust type))]
          [(topaque ,src ,opaque-type)
           ;; Compact's opaque types (e.g. `Opaque<"string">`) lower to
           ;; the named string handle. Rust mirrors via a `String` or
           ;; runtime-defined newtype. For now emit `String` for the
           ;; canonical "string" opaque; other opaque types stay flagged.
           (cond
             [(equal? opaque-type "string") "String"]
             [else (format "/* TODO M3-F4: topaque ~a */" opaque-type)])]
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
           ;; External contract types appear when a contract calls into
           ;; another. The Compact reference for one contract from another
           ;; lowers to a `ContractAddress` at runtime (32-byte hash). Mirror
           ;; the TS path: emit `ContractAddress`. F4 partial; refinements
           ;; (typed handles per external-contract-name) can come later.
           "ContractAddress"]
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

      ;; L2 — native bindings.
      ;;
      ;; Each `(native src function-name native-entry (arg* ...) type)`
      ;; Program-Element carries a `native-entry` record (see langs.ss).
      ;; The record now has two binding fields:
      ;;   - `native-entry-function`      — the TS-side string
      ;;     (e.g. "__compactRuntime.persistentHash")
      ;;   - `native-entry-rust-function` — the Rust-side string
      ;;     (e.g. "compact_runtime::persistent_hash"), or #f if not yet
      ;;     mapped in midnight-natives.ss.
      ;;
      ;; `native-call-site-rust` extracts a usable Rust call-target from
      ;; a native Program-Element (or from any function-name id record
      ;; resolved to its native-entry by callers). When the binding hasn't
      ;; been mapped yet, returns a TODO-tagged placeholder so the
      ;; generated code makes the gap obvious. Used by I3b/J2 when
      ;; emitting call sites for native circuits.
      (define (native-pelt? pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(native ,src ,function-name ,native-entry (,arg* ...) ,type) #t]
          [else #f]))

      (define (native-pelt-entry pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(native ,src ,function-name ,native-entry (,arg* ...) ,type) native-entry]))

      (define (native-pelt-function-name pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(native ,src ,function-name ,native-entry (,arg* ...) ,type) function-name]))

      ;; build-native-id-ht: eq-hashtable from each native's function-name id
      ;; to its native-entry. Lets call-site emission look up the Rust binding
      ;; by the call's function-name id (which references the same id record
      ;; that appears in the native declaration).
      (define (build-native-id-ht pelt*)
        (let ([ht (make-eq-hashtable)])
          (for-each
            (lambda (pelt)
              (when (native-pelt? pelt)
                (eq-hashtable-set! ht
                  (native-pelt-function-name pelt)
                  (native-pelt-entry pelt))))
            pelt*)
          ht))

      (define (native-call-site-rust ne)
        (or (native-entry-rust-function ne)
            (format "/* TODO M3-L2: no Rust binding for ~a */ ~a"
                    (native-entry-function ne)
                    "unimplemented!()")))

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

      ;; ldecl-constructor-stmt: from a Program-Element of shape
      ;; (public-ledger-declaration pl-array lconstructor), extract the
      ;; constructor's body Statement. Returns #f if none.
      (define (ldecl-constructor-stmt ldecl)
        (nanopass-case (Ltypescript Program-Element) ldecl
          [(public-ledger-declaration ,pl-array ,lconstructor)
           (nanopass-case (Ltypescript Ledger-Constructor) lconstructor
             [(constructor ,src (,arg* ...) ,stmt) stmt])]
          [else #f]))

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
             (let ([n (enum-ref->u8 e)])
               (if n (format "~au8" n)
                   "/* TODO M3-J2: unresolved enum-ref */ 0u8"))]
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
             (format "(~a == ~a)"
                     (ctor-expr-rust expr1 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
                     (ctor-expr-rust expr2 local-binds
                                     native-id-ht witness-id-ht circuit-id-ht))]
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             ;; I3b/3: ledger read in expression position. Goes through
             ;; emit-ledger-read-expr which uses current-qctx-ref to pick
             ;; the right QueryContext source.
             (emit-ledger-read-expr path-elt* adt-op)]
            [else
             ;; quote/tuple/etc. fall through to the existing expr-rust.
             (expr-rust e native-id-ht)])))

      ;; stdlib-circuit-rust-path: if `function-name` is a Compact stdlib
      ;; circuit we map to a runtime-side function (currently `some` and
      ;; `none`, both in `compact_runtime::std_lib`), return the qualified
      ;; Rust path with the explicit generic `::<T>` ascription so Rust's
      ;; type inference doesn't need extra hints. Returns #f for
      ;; non-stdlib callees.
      ;;
      ;; `cdefn` is the circuit pelt looked up via circuit-id-ht (or #f).
      ;; We use its return type (`Maybe<T>`) to extract T.
      (define (stdlib-circuit-rust-path function-name cdefn)
        (let ([sym (id-sym function-name)])
          (cond
            [(or (eq? sym 'some) (eq? sym 'none))
             (let ([ret-type (and cdefn (circuit-return-type cdefn))])
               (let ([t (and ret-type (maybe-value-type ret-type))])
                 (format "compact_runtime::std_lib::~a~a"
                         sym
                         (if t
                             (format "::<~a>" (type-rust t))
                             ""))))]
            [else #f])))

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
             ;; they return (PS, T). The constructor walker emits them as
             ;; `let` bindings above; this branch should be unreachable.
             "/* TODO M3-J2: witness inline */ unimplemented!()"]
            [stdlib
             ;; I3b/4: stdlib circuits (`some`, `none`) live in
             ;; compact_runtime::std_lib. Render with the runtime path.
             (let ([args
                    (map (lambda (e)
                           (ctor-expr-rust e local-binds
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
                           (ctor-expr-rust e local-binds
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
               (and (or ne w (and c (id-pure? function-name)))
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
            [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
             ;; I3b/3: ledger read in expression position. Supported when
             ;; op-class is `read`, the path is a single index, and the
             ;; result type has a decoder.
             (ledger-read-supported? path-elt* adt-op)]
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
                 (let ([classified
                        (classify-const-rhs (cdr b) witness-id-ht circuit-id-ht)])
                   (and (or (memq (car classified) '(witness pure-circuit))
                            ;; I3b/3: also accept plain const RHS shapes
                            ;; (e.g. `const tmp = default<Bytes<32>>;`)
                            ;; whose expression is something expr-rust
                            ;; can render. emit-body-or-fallback's else
                            ;; branch already handles these.
                            (expr-supported? (cdr b) native-id-ht
                                             witness-id-ht circuit-id-ht))
                        (loop (cdr stmts)))))]
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
              [(stmt->assert (car stmts)) =>
               (lambda (a)
                 (let* ([expr (car a)]
                        [msg (cdr a)]
                        [cond-str
                         (assert-cond-rust expr local-binds
                                           native-id-ht witness-id-ht circuit-id-ht)]
                        [line
                         (format "        compact_assert!(~a, ~s);\n"
                                 cond-str msg)])
                   (loop (cdr stmts)
                         local-binds
                         witness-emitted?
                         (cons line pre-lines)
                         writes)))]
              [(const-binding (car stmts)) =>
               (lambda (b)
                 (let* ([var-name (car b)]
                        [rhs (cdr b)]
                        [rust-name (symbol->string (camel->snake (id-sym var-name)))]
                        [classified
                         (classify-const-rhs rhs witness-id-ht circuit-id-ht)])
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
                                     (ctor-expr-rust e local-binds
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
                             [arg-strs
                              (map (lambda (e)
                                     (ctor-expr-rust e local-binds
                                                     native-id-ht witness-id-ht circuit-id-ht))
                                   pargs)]
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
                     [else
                      ;; Unknown rhs shape — try a generic ctor-expr-rust
                      ;; render and emit a plain `let`.
                      (let ([rendered
                             (ctor-expr-rust rhs local-binds
                                             native-id-ht witness-id-ht circuit-id-ht)])
                        (loop (cdr stmts)
                              (cons (cons var-name rust-name) local-binds)
                              witness-emitted?
                              (cons (format "        let ~a = ~a;\n" rust-name rendered)
                                    pre-lines)
                              writes))])))]
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
      ;;   (list 'witness rust-name args)        for witness calls
      ;;   (list 'pure-circuit rust-name args)   for pure circuit calls
      ;;   (list 'unknown)                       otherwise
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
                   [rust-val (ctor-expr-rust val-expr local-binds
                                             native-id-ht witness-id-ht circuit-id-ht)])
              ;; Cell.write vm-code for a single-element path is exactly:
              ;;   push false (state-value 'cell (align idx 1))
              ;;   push true  (state-value 'cell <value>)
              ;;   ins false 1
              ;; (The leading idx and trailing ins are suppressed when the
              ;; path before the last element is empty, which it is here.)
              (out (format "            .push(false, new_cell(~au8))\n" idx))
              (out (format "            .push(true, new_cell(~a))\n" rust-val))
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
        ;; J2: emit the constructor body if we have one and its shape
        ;; matches. Fall back to the K1-only return otherwise (counter has
        ;; no constructor body, so it lands here naturally).
        (let* ([stmt (and (pair? ledger-field*)
                          (ldecl-constructor-stmt (car ledger-field*)))]
               [native-id-ht (build-native-id-ht all-pelt*)]
               [witness-id-ht (build-witness-id-ht all-pelt*)]
               [circuit-id-ht (build-circuit-id-ht all-pelt*)]
               [emitted?
                (and stmt
                     (emit-ctor-body-or-fallback stmt
                                                 native-id-ht witness-id-ht circuit-id-ht))])
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

      ;; rendered-has-todo?: returns #t if the rendered Rust string contains
      ;; a TODO marker (`/* TODO`) or an `unimplemented!(` call. Used by
      ;; emit-if-expression-body to bail out (fall back to the method-level
      ;; `unimplemented!()`) if any sub-render produced an incomplete result.
      (define (rendered-has-todo? s)
        (or (and (string? s)
                 (or (substring? s "/* TODO")
                     (substring? s "unimplemented!(")))))

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
           (out (format "    pub fn ~a(\n" (camel->snake (id-sym function-name))))
           (out "        &self,\n")
           (out "        ctx: CircuitContext<PS>")
           (emit-circuit-args arg*)
           (out (format ",\n    ) -> Result<CircuitResults<PS, ~a>, CompactError> {\n"
                        (type-rust type)))
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
                                                       native-id-ht witness-id-ht circuit-id-ht)))))])
             (unless emitted?
               (out (format "        unimplemented!(\"M3-I3: circuit body emission for ~a\")\n"
                            (id-sym function-name)))))
           (out "    }\n\n")]))

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
          [(quote ,src ,datum)
           (cond
             [(bytevector? datum) (bytevector->rust-array-literal datum)]
             [(boolean? datum) (if datum "true" "false")]
             [(and (integer? datum) (exact? datum)) (format "~a" datum)]
             [else (format "/* TODO M3-I3b: quote variant */ unimplemented!()")])]
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
          [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
           ;; I3b/3: ledger read in expression position (e.g. inside an
           ;; `(==)` or as the RHS of a const-binding). Emits an inline
           ;; gather query against (current-qctx-ref) and decodes the
           ;; resulting AlignedValue using the same decoder table the
           ;; Ledger view uses.
           (emit-ledger-read-expr path-elt* adt-op)]
          [else
           (format "/* TODO M3-I3b: unhandled Expression variant */ unimplemented!()")]))

      ;; emit-ledger-read-expr: render a `(public-ledger ... read)` IR
      ;; node as a Rust block expression that runs a gather query and
      ;; decodes the result. Used by expr-rust when the read appears in
      ;; expression position (clear()'s `apk == authority`, in_state's
      ;; inlined `state == s`).
      ;;
      ;; The qctx source comes from the (current-qctx-ref) dynamic
      ;; parameter so circuit-body emissions read from
      ;; `&ctx.current_query_context` while constructor-body emissions
      ;; would read from `&qctx`.
      (define (emit-ledger-read-expr path-elt* adt-op)
        (nanopass-case (Ltypescript ADT-Op) adt-op
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
           (cond
             [(not (eq? op-class 'read))
              "/* TODO M3-I3b: non-read public-ledger in expr */ unimplemented!()"]
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
                   "/* TODO M3-I3b: ledger read with non-index path */ unimplemented!()"]
                  [(not decoder)
                   "/* TODO M3-I3b: ledger read decoder */ unimplemented!()"]
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
                       "        }"))]))])]))

      ;; tuple-arg-rust: emit a Rust expression for a Tuple-Argument
      ;; (`single` or `spread`). I3b/1 only needs `single`; `spread` emits a
      ;; TODO placeholder.
      (define (tuple-arg-rust ta native-id-ht)
        (nanopass-case (Ltypescript Tuple-Argument) ta
          [(single ,src ,expr) (expr-rust expr native-id-ht)]
          [(spread ,src ,nat ,expr)
           (format "/* TODO M3-I3b: tuple spread */ unimplemented!()")]))

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
             ;; persistent_hash needs a flat `&[u8]`. Compact's argument is a
             ;; Vector<N, T> which the IR represents as a `(tuple ...)` of T
             ;; values. For the tiny.compact public_key shape both elements
             ;; are `[u8; 32]` and we can build a flat byte slice via
             ;; `[a, b].concat()`. The trailing `.0` unwraps HashOutput into
             ;; `[u8; 32]`.
             ;; TODO(M3-I3): generalise to other `persistentHash<T>` shapes
             ;; once we have a FieldRepr-faithful Rust path.
             (cond
               [(fx= (length expr*) 1)
                (format "compact_runtime::persistent_hash(&~a.concat()).0"
                        (expr-rust (car expr*) native-id-ht))]
               [else
                "/* TODO M3-I3b: persistentHash arity */ unimplemented!()"])]
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
             ;; A user-defined circuit call. We don't yet resolve these to
             ;; their Rust paths — leave a TODO so the next wedge can pick
             ;; it up.
             (format "/* TODO M3-I3b: call to ~a (non-native) */ unimplemented!()"
                     (id-sym function-name))])))

      ;; stmt-pure-body-rust: try to render the body of a pure circuit as a
      ;; single Rust expression (no trailing semicolon — used in tail
      ;; position). Accepts the narrow shape "a single statement-expression
      ;; whose expression is a `call`" (the shape produced for tiny.compact's
      ;; `public_key`). Returns the Rust expression string on success, #f to
      ;; signal the caller should fall back to `unimplemented!()`.
      (define (stmt-pure-body-rust stmt native-id-ht)
        (let ([stmts (stmt-flatten stmt)])
          (cond
            [(or (null? stmts) (not (null? (cdr stmts)))) #f]
            [else
             (nanopass-case (Ltypescript Statement) (car stmts)
               [(statement-expression ,expr)
                ;; We currently only emit bodies whose return expression is
                ;; itself a `call`. Other shapes (var-ref, tuple, …) are
                ;; valid Rust expressions but won't appear in tiny.compact's
                ;; pure circuits at this stage.
                (nanopass-case (Ltypescript Expression) expr
                  [(call ,src ,function-name ,expr* ...)
                   (expr-rust expr native-id-ht)]
                  [else #f])]
               [else #f])])))

      ;; emit-pure-circuit: emit a pure circuit as a free function inside
      ;; `mod pure_circuits`. No ctx — just the declared args and a direct
      ;; return type. For the narrow tiny.compact-style shape (a single
      ;; expression in statement position) we render the expression
      ;; directly; everything else keeps an `unimplemented!()` placeholder.
      (define (emit-pure-circuit cdefn native-id-ht)
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
           (let ([body (stmt-pure-body-rust stmt native-id-ht)])
             (cond
               [body (out (format "        ~a\n" body))]
               [else
                (out (format "        unimplemented!(\"M3-I3: pure circuit body emission for ~a\")\n"
                             (id-sym function-name)))]))
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
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           ;; Enums are FieldRepr'd as a u8 discriminant on chain. The
           ;; in_state inlining (and any other tenum ledger read in
           ;; expression position) decodes to u8 — the discriminant
           ;; comparison stays a u8-vs-u8 check, matching the way
           ;; enum-ref->u8 emits literals.
           "compact_runtime::std_lib::decode_u8"]
          [(tbytes ,src ,len)
           (format "compact_runtime::std_lib::decode_bytes::<~a>" len)]
          [(talias ,src ,nominal? ,type-name ,type) (decoder-for-type type)]
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
      (define (emit-pure-circuits pure-circuit* native-id-ht)
        (out "pub mod pure_circuits {\n")
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
            port))))
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,tdescs ,pelt* ...)
       (header)
       (emit-type-decls (program-export-tdefns pelt*))
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
             (unless (id-pure? (circuit-function-name c))
               (emit-impure-circuit c native-id-ht witness-id-ht circuit-id-ht)))
           circuit*)
         (close-contract-struct)
         (emit-ledger-view (program-ledger-fields pelt*))
         (emit-pure-circuits pure-circuit* native-id-ht))
       (emit-cargo-toml)
       ir]))

  (define-passes rust-passes
    (print-rust          Ltypescript)))
