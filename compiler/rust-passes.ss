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

      ;; rust-keyword?: returns #t when the symbol matches a Rust reserved
      ;; keyword (strict + reserved). Enum variant names like
      ;; `final` (election.compact's PublicState.final) collide otherwise.
      ;; Callers escape such names with the `r#` raw-identifier prefix.
      (define rust-keyword?
        (let ([kws '(as async await break const continue crate do dyn
                     else enum extern false final fn for if impl in
                     let loop macro match mod move mut override priv
                     pub ref return self Self static struct super trait
                     true try type typeof unsafe unsized use virtual
                     where while yield abstract become box)])
          (lambda (sym) (and (memq sym kws) #t))))

      ;; rust-variant-name: render an enum variant name, escaping Rust
      ;; keywords via the raw-identifier `r#` prefix.
      (define (rust-variant-name sym)
        (if (rust-keyword? sym)
            (string-append "r#" (symbol->string sym))
            (symbol->string sym)))

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
           ;; Compact's opaque types lower to runtime-defined Rust types.
           ;; "string" uses an OpaqueString newtype (compact_runtime::std_lib)
           ;; that carries the Aligned/FieldRepr impls bare String can't have
           ;; under orphan rules. "Uint8Array" maps to Vec<u8> since Vec<u8>
           ;; has the needed impls upstream. Other opaque tags stay flagged.
           (cond
             [(equal? opaque-type "string") "compact_runtime::std_lib::OpaqueString"]
             [(equal? opaque-type "Uint8Array") "Vec<u8>"]
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

      ;; -----------------------------------------------------------------
      ;; M3.5 helpers: per-field codegen for Aligned / FieldRepr /
      ;; FromFieldRepr impls of user structs.
      ;;
      ;; Rust's orphan rules forbid us from impl'ing those upstream traits
      ;; on foreign types like `[u8; N]` (N != 32), `Vec<u8>`, or
      ;; `[UserType; N]`. To sidestep that, when a struct field has one of
      ;; these "problematic" types we emit:
      ;;   - the FIELD_SIZE / Aligned::concat / field_size() / field_repr()
      ;;     pieces inline (computing what `<T as Trait>::method` would
      ;;     have returned), and
      ;;   - a call to a free `compact_runtime::*_from_field_repr`
      ;;     helper for the parse side.
      ;; -----------------------------------------------------------------

      ;; Recognise tbytes with a non-32 length.
      (define (problematic-bytes? type)
        (nanopass-case (Ltypescript Type) type
          [(tbytes ,src ,len) (not (= len 32))]
          [else #f]))

      ;; Recognise tvector whose element is itself a user struct / enum.
      ;; (Upstream provides no `[T; N]` impls for non-u8 T.)
      (define (problematic-vector? type)
        (nanopass-case (Ltypescript Type) type
          [(tvector ,src ,len ,type)
           (nanopass-case (Ltypescript Type) type
             [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
              (not (eq? struct-name 'Maybe))]
             [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #t]
             [else #f])]
          [else #f]))

      ;; Recognise Opaque<"Uint8Array"> which lowers to Vec<u8>.
      (define (problematic-vec-u8? type)
        (nanopass-case (Ltypescript Type) type
          [(topaque ,src ,opaque-type) (equal? opaque-type "Uint8Array")]
          [else #f]))

      ;; field-size-const-expr: compile-time expression for
      ;; `<T as FromFieldRepr>::FIELD_SIZE`. For problematic types,
      ;; substitute a runtime helper / literal.
      (define (field-size-const-expr type)
        (cond
          [(problematic-bytes? type)
           (nanopass-case (Ltypescript Type) type
             [(tbytes ,src ,len)
              (format "compact_runtime::bytes_field_size(~a)" len)])]
          [(problematic-vec-u8? type)
           ;; Vec<u8> has no fixed FIELD_SIZE; codegen treats this as 0
           ;; (the surrounding ADT carries the byte count).
           "0"]
          [(problematic-vector? type)
           (nanopass-case (Ltypescript Type) type
             [(tvector ,src ,len ,type)
              (format "<~a as FromFieldRepr>::FIELD_SIZE * ~a"
                      (type-rust type) len)])]
          [else
           (format "<~a as FromFieldRepr>::FIELD_SIZE" (type-rust type))]))

      ;; field-from-repr-expr: parse one field from the slice
      ;; `r[_offset.._offset + size]` and bind to `name`. For
      ;; problematic types, call into runtime helpers.
      (define (emit-field-from-repr name type)
        (let ([size-expr (field-size-const-expr type)])
          (cond
            [(problematic-bytes? type)
             (nanopass-case (Ltypescript Type) type
               [(tbytes ,src ,len)
                (out (format "        let ~a = compact_runtime::bytes_from_field_repr::<~a>(&r[_offset.._offset + ~a])?;\n"
                             name len size-expr))
                (out (format "        _offset += ~a;\n" size-expr))])]
            [(problematic-vec-u8? type)
             (out (format "        let ~a = compact_runtime::vec_u8_from_field_repr(&r[_offset.._offset])?;\n"
                          name))]
            [(problematic-vector? type)
             (nanopass-case (Ltypescript Type) type
               [(tvector ,src ,len ,type)
                (out (format "        let ~a = compact_runtime::array_from_field_repr::<~a, ~a>(&r[_offset.._offset + ~a], <~a as FromFieldRepr>::FIELD_SIZE)?;\n"
                             name (type-rust type) len size-expr (type-rust type)))
                (out (format "        _offset += ~a;\n" size-expr))])]
            [else
             (let ([rust-ty (type-rust type)])
               (out (format "        let ~a = <~a as FromFieldRepr>::from_field_repr(&r[_offset.._offset + <~a as FromFieldRepr>::FIELD_SIZE])?;\n"
                            name rust-ty rust-ty))
               (out (format "        _offset += <~a as FromFieldRepr>::FIELD_SIZE;\n" rust-ty)))])))

      ;; alignment-expr: emit a `&Alignment` reference for use inside
      ;; `Alignment::concat([...])`. For `[T; N]` of user types,
      ;; Alignment::concat needs N references which we cannot easily
      ;; produce inline — synthesise a small helper expression that
      ;; builds a temporary Vec<&Alignment>.
      ;;
      ;; Since `Alignment::concat` takes `IntoIterator<Item = &Alignment>`,
      ;; we can build an expression that does the work inline.
      (define (emit-alignment-piece type first?)
        (cond
          [(problematic-vector? type)
           (nanopass-case (Ltypescript Type) type
             [(tvector ,src ,len ,type)
              ;; Emit a Box-leaked vector of N copies of T's alignment.
              ;; Simpler: just emit N comma-separated &T::alignment() calls.
              (let loop ([i 0])
                (when (< i len)
                  (out (format "~a&<~a as Aligned>::alignment()"
                               (if (and first? (= i 0)) "" ", ")
                               (type-rust type)))
                  (loop (+ i 1))))])]
          [else
           (out (format "~a&<~a as Aligned>::alignment()"
                        (if first? "" ", ")
                        (type-rust type)))]))

      ;; field-size-instance-expr: runtime field.field_size() expression
      ;; for use in the per-instance field_size() summation.
      (define (field-size-instance-expr field-name type)
        (cond
          [(problematic-vector? type)
           ;; iter().map(|e| e.field_size()).sum() avoids requiring
           ;; FieldRepr to be impl'd on [T; N].
           (format "self.~a.iter().map(|e| e.field_size()).sum::<usize>()" field-name)]
          [else
           (format "self.~a.field_size()" field-name)]))

      ;; field-repr-emit: write the per-field `self.x.field_repr(writer)`
      ;; or equivalent loop for `[T; N]` of user types.
      (define (emit-field-repr-call field-name type)
        (cond
          [(problematic-vector? type)
           (out (format "        for _e in self.~a.iter() { _e.field_repr(writer); }\n"
                        field-name))]
          [else
           (out (format "        self.~a.field_repr(writer);\n" field-name))]))

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

      ;; circuit-pelt-src: extract the src record from a Circuit-Definition
      ;; Program-Element. Used by program-circuits to distinguish
      ;; user-defined circuits from stdlib specialisations
      ;; (e.g. `some<Field>`, `none<Field>`) via `stdlib-src?`.
      (define (circuit-pelt-src pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt) src]))

      ;; Collect user-defined circuit definitions from a list of program
      ;; elements. Includes both exported circuits (which become the public
      ;; Contract impl surface / `pub fn`s in `mod pure_circuits`) and
      ;; non-exported user circuits (internal helpers like
      ;; tiny.compact's `in_state` or zerocash's
      ;; `commitment_from_coin_info`). Stdlib specialisations like
      ;; `some<Field>` / `none<Field>` are excluded — they live in the
      ;; runtime as fixed Rust functions and the call-site dispatcher
      ;; rewrites references to `compact_runtime::std_lib::some` etc.
      (define (program-circuits pelt*)
        (let loop ([pelt* pelt*] [acc '()])
          (cond
            [(null? pelt*) (reverse acc)]
            [(and (circuit? (car pelt*))
                  (or (id-exported? (circuit-function-name (car pelt*)))
                      (not (stdlib-src? (circuit-pelt-src (car pelt*))))))
             (loop (cdr pelt*) (cons (car pelt*) acc))]
            [else (loop (cdr pelt*) acc)])))

      ;; circuit-function-name: extract the function-name id record from a
      ;; Circuit-Definition Program-Element. Used to query (id-pure?) at the
      ;; dispatch site without re-pattern-matching.
      (define (circuit-function-name pelt)
        (nanopass-case (Ltypescript Program-Element) pelt
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt) function-name]))

      ;; collect-pure-circuit-tdefns: scan non-exported user pure circuit
      ;; sigs and synthesise Ltypescript export-typedef pelts for any
      ;; tstruct/tenum types referenced there but not already in
      ;; `existing-tdefns`. Used by the Rust path to close the E2 walker
      ;; gap for circuits whose sigs introduce user types that no
      ;; publicly-reachable surface mentions (e.g. zerocash's
      ;; `derive_nullifier(...): nullifier`).
      ;;
      ;; We run this in rust-passes (not analysis-passes) because
      ;; purity-inference runs AFTER the analysis-passes Program pass,
      ;; so `id-pure?` is only reliable here on the Ltypescript IR.
      ;; Stdlib pure circuits (`some`, `none`, merkle-tree helpers) are
      ;; excluded via `stdlib-src?` — their referenced types are
      ;; runtime-provided and must not be per-contract re-emitted.
      (define (collect-pure-circuit-tdefns pelt* existing-tdefns)
        (let ([seen-names (make-hashtable symbol-hash eq?)]
              [out-tdefns '()])
          (define (push-type! src^ name type)
            (unless (hashtable-ref seen-names name #f)
              (hashtable-set! seen-names name #t)
              (set! out-tdefns
                (cons
                  (with-output-language (Ltypescript Program-Element)
                    `(export-typedef ,src^ ,name () ,type))
                  out-tdefns))
              ;; Recurse into the new type's fields (for tstruct).
              (nanopass-case (Ltypescript Type) type
                [(tstruct ,src^^ ,struct-name^ (,elt-name^* ,type^*) ...)
                 (for-each scan-type type^*)]
                [else (void)])))
          (define (scan-type type)
            (nanopass-case (Ltypescript Type) type
              [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
               (push-type! src^ struct-name type)
               (for-each scan-type type*)]
              [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
               (push-type! src^ enum-name type)]
              [(tvector ,src^ ,len ,type^) (scan-type type^)]
              [(ttuple ,src^ ,type* ...) (for-each scan-type type*)]
              [else (void)]))
          (define (scan-arg arg)
            (nanopass-case (Ltypescript Argument) arg
              [(,var-name ,type) (scan-type type)]))
          ;; Seed the seen set with names already in existing-tdefns so
          ;; we don't synthesise duplicates.
          (for-each
            (lambda (etd)
              (nanopass-case (Ltypescript Program-Element) etd
                [(export-typedef ,src ,type-name (,tvar-name* ...) ,type)
                 (nanopass-case (Ltypescript Type) type
                   [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
                    (hashtable-set! seen-names struct-name #t)]
                   [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
                    (hashtable-set! seen-names enum-name #t)]
                   [else (void)])
                 (hashtable-set! seen-names type-name #t)]
                [else (void)]))
            existing-tdefns)
          ;; Walk every circuit pelt. Gate on (id-pure? AND not stdlib).
          ;; Exported pure circuits already feed E2's walker; this is a
          ;; safety net so the same logic catches non-exported ones too.
          (for-each
            (lambda (pelt)
              (nanopass-case (Ltypescript Program-Element) pelt
                [(circuit ,src^ ,function-name (,arg* ...) ,type ,stmt)
                 (when (and (id-pure? function-name)
                            (not (stdlib-src? src^)))
                   (for-each scan-arg arg*)
                   (scan-type type))]
                [else (void)]))
            pelt*)
          (reverse out-tdefns)))

      ;; emit-type-decls: emit one Rust type declaration per exported
      ;; user type. For `tenum`, emit a `#[repr(u8)] pub enum` with
      ;; explicit discriminants (H1-H4). For `tstruct`, emit a
      ;; `pub struct` with `Aligned` / `FieldRepr` / `FromFieldRepr`
      ;; impls (H5-H7); `Maybe<T>` is runtime-provided and skipped;
      ;; generic structs emit a TODO. `talias` emits a TODO placeholder
      ;; for later M3 tasks; anything else also emits a TODO so unknown
      ;; variants stay visible.
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
                        (out (format "    ~a = ~a,\n"
                                     (rust-variant-name (car variants))
                                     i))
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
                        (out (format "            ~a => Some(Self::~a),\n"
                                     i
                                     (rust-variant-name (car variants))))
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
                       ;; redefinition.
                       (void)]
                      [(not (null? tvar-name*))
                       ;; H5: generic structs not yet handled. Emit a TODO so
                       ;; non-zero `tvar-name*` is visible to downstream
                       ;; tasks. Monomorphic structs fall through to real
                       ;; emission below.
                       (out (format "// TODO M3-H5: generic struct ~a<~{~a~^, ~}>\n"
                                    struct-name tvar-name*))]
                      [else
                       ;; H5: derive + struct decl. Conservative: skip Copy
                       ;; (user may add manually); always derive Default so
                       ;; ledger init can `Pair::default()` if needed.
                       (out "#[derive(Clone, Debug, PartialEq, Eq, Default)]\n")
                       (out (format "pub struct ~a {\n" struct-name))
                       (for-each
                         (lambda (name type)
                           (out (format "    pub ~a: ~a,\n" name (type-rust type))))
                         elt-name* type*)
                       (out "}\n")
                       ;; H6: Aligned impl — concat of field alignments.
                       (out (format "impl Aligned for ~a {\n" struct-name))
                       (out "    fn alignment() -> Alignment {\n")
                       (out "        Alignment::concat([")
                       (let loop ([types type*] [first? #t])
                         (cond
                           [(null? types) (void)]
                           [else
                            (emit-alignment-piece (car types) first?)
                            (loop (cdr types) #f)]))
                       (out "])\n")
                       (out "    }\n")
                       (out "}\n")
                       ;; H7a: FieldRepr impl — delegate to each field.
                       (out (format "impl FieldRepr for ~a {\n" struct-name))
                       (out "    fn field_repr<W: MemWrite<Fr>>(&self, writer: &mut W) {\n")
                       (for-each
                         (lambda (name type)
                           (emit-field-repr-call name type))
                         elt-name* type*)
                       (out "    }\n")
                       (out "    fn field_size(&self) -> usize {\n        ")
                       (cond
                         [(null? elt-name*) (out "0")]
                         [else
                          (let loop ([names elt-name*] [types type*] [first? #t])
                            (cond
                              [(null? names) (void)]
                              [else
                               (out (format "~a~a"
                                            (if first? "" " + ")
                                            (field-size-instance-expr (car names) (car types))))
                               (loop (cdr names) (cdr types) #f)]))])
                       (out "\n    }\n")
                       (out "}\n")
                       ;; H7b: FromFieldRepr impl — parse each field by offset.
                       ;; Uses fully-qualified `<T as FromFieldRepr>::FIELD_SIZE`
                       ;; to avoid associated-const resolution ambiguity.
                       (out (format "impl FromFieldRepr for ~a {\n" struct-name))
                       (out "    const FIELD_SIZE: usize = ")
                       (cond
                         [(null? type*) (out "0")]
                         [else
                          (let loop ([types type*] [first? #t])
                            (cond
                              [(null? types) (void)]
                              [else
                               (out (format "~a~a"
                                            (if first? "" " + ")
                                            (field-size-const-expr (car types))))
                               (loop (cdr types) #f)]))])
                       (out ";\n")
                       (out "    fn from_field_repr(r: &[Fr]) -> Option<Self> {\n")
                       (out "        if r.len() < Self::FIELD_SIZE { return None; }\n")
                       (out "        let mut _offset = 0usize;\n")
                       (for-each
                         (lambda (name type)
                           (emit-field-from-repr name type))
                         elt-name* type*)
                       ;; Silence unused-assignment warning on the final
                       ;; _offset += that no field reads.
                       (out "        let _ = _offset;\n")
                       (out (format "        Some(~a {" struct-name))
                       (let loop ([names elt-name*] [first? #t])
                         (cond
                           [(null? names) (void)]
                           [else
                            (out (format "~a ~a"
                                         (if first? "" ",")
                                         (car names)))
                            (loop (cdr names) #f)]))
                       (out " })\n")
                       (out "    }\n")
                       (out "}\n")
                       ;; M3.5-E4.4 Blocker 3: From<S> for Value so callers
                       ;; can pass a user-struct value where an AlignedValue
                       ;; is needed (e.g. leaf_hash's arg in HMT.insert).
                       ;; The upstream blanket
                       ;;   impl<T: DynAligned, Value: From<T>> From<T>
                       ;;     for AlignedValue
                       ;; turns `Value: From<S>` into `AlignedValue: From<S>`
                       ;; automatically. Each field's `.into()` produces a
                       ;; Value (primitives + Maybe<T> + recursively user
                       ;; structs that go through this same impl), which we
                       ;; concat in field order — matching FieldRepr.
                       (out (format "impl From<~a> for compact_runtime::Value {\n"
                                    struct-name))
                       (out (format "    fn from(s: ~a) -> compact_runtime::Value {\n"
                                    struct-name))
                       (cond
                         [(null? elt-name*)
                          (out "        compact_runtime::Value::concat(core::iter::empty::<&compact_runtime::Value>())\n")]
                         [else
                          ;; Build a Vec<Value> field-by-field, then concat.
                          ;; Use explicit `Value::from(...)` per field rather
                          ;; than `.into()` to avoid trait-resolution
                          ;; ambiguity — some primitive field types
                          ;; (e.g. [u8; 32]) have multiple `From<[u8; 32]>`
                          ;; impls in transitive deps. Naming the target
                          ;; type pins inference.
                          ;;
                          ;; For `[T; N]` where T is a user struct, upstream
                          ;; has no `From<[T; N]> for Value`, so we expand
                          ;; the array element-by-element into the Vec.
                          (out "        let mut _v: Vec<compact_runtime::Value> = Vec::new();\n")
                          (for-each
                            (lambda (name type)
                              (cond
                                [(problematic-vector? type)
                                 (out (format "        for _e in s.~a.iter() { _v.push(compact_runtime::Value::from(_e.clone())); }\n"
                                              name))]
                                [else
                                 (out (format "        _v.push(compact_runtime::Value::from(s.~a));\n"
                                              name))]))
                            elt-name* type*)
                          (out "        compact_runtime::Value::concat(_v.iter())\n")])
                       (out "    }\n")
                       (out "}\n")
                       (out "\n")])]
                   [(talias ,src ,nominal? ,type-name ,type)
                    ;; F6 follow-up: emit `pub type X = Y;` for nominal
                    ;; aliases (`new type X = Y;`). Transparent aliases
                    ;; (`type X = Y;`) expand at use sites via type-rust,
                    ;; so we don't need a top-level decl for them.
                    (when nominal?
                      (out (format "pub type ~a = ~a;\n\n"
                                   type-name (type-rust type))))]
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
               (string-append rendered ".clone()")]
              [else rendered]))))

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
               ;; Pure-circuit calls must target an EXPORTED circuit
               ;; (the only ones that land in the `pure_circuits` mod).
               ;; Non-exported helpers exist in the IR but aren't
               ;; emitted, so a `pure_circuits::<name>(...)` reference
               ;; would fail to compile. Reject here so the body walker
               ;; falls back to `unimplemented!()` cleanly.
               (and (or ne
                        w
                        (and c
                             (id-pure? function-name)
                             (id-exported? function-name)))
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
                      (let ([rendered
                             (ctor-expr-rust rhs local-binds
                                             native-id-ht witness-id-ht circuit-id-ht)])
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
                                     (ctor-expr-rust e local-binds
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
                  [else
                   (let ([read-type (tadt-read-op-type t)])
                     (out (format "            ~a(~a),\n"
                                  (if (type-is-tvector? read-type)
                                      "new_cell_array"
                                      "new_cell")
                                  (default-value-rust read-type))))])))
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
                    (and rendered (make-vm-rust-expr rendered)))))]))

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

      ;; vm-value->rust-state-value: render a state-value form (the kind
      ;; that appears as the `value` arg of a `push` vm-instruction) as
      ;; a Rust expression of type `StateValue<DefaultDB>`. Returns #f if
      ;; the form isn't one we yet know how to translate.
      (define (vm-value->rust-state-value val)
        (cond
          [(VMop? val)
           (VMop-case val
             [(VMstate-value-null) "StateValue::Null"]
             [(VMstate-value-cell inner)
              (let ([rust-inner (vm-cell-elem->rust inner)])
                (and rust-inner (format "new_cell(~a)" rust-inner)))]
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
              (format "/* TODO M3-E6: enum-ref of non-tenum type */ unimplemented!()")])]
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
           ;; we have a dedicated decoder. Other element types (Bytes<M>,
           ;; user structs, nested vectors) need their own helpers — leave
           ;; them flagged so the gap is visible.
           (nanopass-case (Ltypescript Type) type
             [(tfield ,src)
              (format "compact_runtime::std_lib::decode_vector_fr::<~a>" len)]
             [else #f])]
          [(talias ,src ,nominal? ,type-name ,type) (decoder-for-type type)]
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
            port))))
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
