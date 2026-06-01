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

      ;; current-witness-call-binds: alist of (witness-call-expr-node .
      ;; rust-name). Populated when the body walker hoists witness calls
      ;; out of an assert/condition expression to top-level `let`-bindings
      ;; (election.add_voter's `!path_of(pk).is_some` shape). Consulted by
      ;; ctor-call-rust before the "witness inline" TODO branch — when the
      ;; current call expression matches (by eq?-identity), we emit the
      ;; bound name instead of a TODO. Keys use eq? identity, so the same
      ;; IR node reference must flow from hoist to render.
      (define current-witness-call-binds
        (make-parameter '()))

      ;; current-enum-ref-typed?: when #t, ctor-expr-rust renders an
      ;; `enum-ref` as `EnumName::r#variant` instead of the integer
      ;; discriminant. Used inside an `==` comparison whose other operand
      ;; renders as a typed enum value (e.g. a witness call returning a
      ;; tenum). The default #f preserves the existing integer rendering
      ;; against u8-decoded ledger reads — that path covers tiny.compact's
      ;; `state == STATE.unset` and election.commit/reveal's
      ;; `state.read() == PublicState.commit` where the ledger decoder
      ;; produces u8.
      (define current-enum-ref-typed?
        (make-parameter #f))

      ;; current-formal-arg-types: eq-hashtable mapping a var-name id-sym
      ;; → its declared Compact Type. Initialised from a circuit's formal
      ;; args by emit-impure-circuit / emit-pure-circuit before walking
      ;; the body. The body walker additionally mutates this table as it
      ;; processes const-bindings (so a const-bound witness result whose
      ;; declared return type is a tenum can flow into `==` rendering).
      ;;
      ;; Used by `==` rendering (via operand-typed-enum?) to detect when
      ;; a var-ref operand resolves to a tenum-typed name, so an
      ;; `enum-ref` on the other side renders as `EnumName::variant`
      ;; rather than the integer discriminant.
      (define current-formal-arg-types
        (make-parameter #f))

      ;; build-formal-arg-type-ht: build an eq-hashtable seeded with a
      ;; circuit's (Argument*) list, mapping id-sym → Type. Always returns
      ;; a fresh table (even when arg* is empty) so the body walker has a
      ;; mutable home for const-binding types it discovers later.
      (define (build-formal-arg-type-ht arg*)
        (let ([ht (make-eq-hashtable)])
          (for-each
            (lambda (a)
              (nanopass-case (Ltypescript Argument) a
                [(,var-name ,type)
                 (eq-hashtable-set! ht (id-sym var-name) type)]))
            arg*)
          ht))

      ;; record-const-binding-type!: if rhs is a direct call into a
      ;; witness or pure circuit whose declared return type we know, add
      ;; `var-name → type` to current-formal-arg-types. Called from the
      ;; body walker on each const-binding so subsequent `==` rendering
      ;; can detect tenum-typed locals (e.g. election.vote$reveal's
      ;; `const vote = private$vote();` where private$vote returns
      ;; PermissibleVotes).
      (define (record-const-binding-type! var-name rhs
                                          witness-id-ht circuit-id-ht)
        (let ([ht (current-formal-arg-types)])
          (when ht
            (let ([t (infer-rhs-type rhs witness-id-ht circuit-id-ht)])
              (when t
                (eq-hashtable-set! ht (id-sym var-name) t))))))

      ;; infer-rhs-type: best-effort declared type of a const-binding RHS.
      ;; Currently recognises direct witness calls (the only shape we care
      ;; about for tenum detection); pure-circuit calls are handled too
      ;; for completeness. Strips talias / casts. Returns #f when the
      ;; shape isn't a recognised call.
      (define (infer-rhs-type rhs witness-id-ht circuit-id-ht)
        (let ([e (expr-strip-cast rhs)])
          (nanopass-case (Ltypescript Expression) e
            [(call ,src ,function-name ,expr* ...)
             (let ([w (eq-hashtable-ref witness-id-ht function-name #f)]
                   [c (eq-hashtable-ref circuit-id-ht function-name #f)])
               (cond
                 [w
                  (nanopass-case (Ltypescript Program-Element) w
                    [(witness ,src ,function-name (,arg* ...) ,type) type]
                    [else #f])]
                 [c (circuit-return-type c)]
                 [else #f]))]
            ;; `const tmp = default<T>;` — type is carried directly on
            ;; the node, so record it so arg-rust-clone-if-var can skip
            ;; redundant clones on Copy default values.
            [(default ,src ,type) type]
            [else #f])))

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
           ;; emit Maybe<<that-type>>. Similarly MerkleTreePath<#n, T> /
           ;; MerkleTreePathEntry lower to compact_runtime::MerklePath<T> /
           ;; MerklePathEntry. Other named structs lower to their bare
           ;; name; their definitions are emitted by emit-type-decls
           ;; (H5 / future tasks).
           (cond
             [(eq? struct-name 'Maybe)
              (let loop ([names elt-name*] [types type*])
                (cond
                  [(null? names) "Maybe</* L1: no value field */>"]
                  [(eq? (car names) 'value) (format "Maybe<~a>" (type-rust (car types)))]
                  [else (loop (cdr names) (cdr types))]))]
             [(eq? struct-name 'MerkleTreePath)
              (let loop ([names elt-name*] [types type*])
                (cond
                  [(null? names) "compact_runtime::MerklePath</* no leaf field */>"]
                  [(eq? (car names) 'leaf)
                   (format "compact_runtime::MerklePath<~a>" (type-rust (car types)))]
                  [else (loop (cdr names) (cdr types))]))]
             [(eq? struct-name 'MerkleTreePathEntry)
              "compact_runtime::MerklePathEntry"]
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
                    (out "}\n")
                    ;; F2.2: From<EnumName> for Value — delegate via the u8
                    ;; discriminant. Lifts the enum into AlignedValue (via
                    ;; the upstream DynAligned blanket) so `new_cell(<enum>)`
                    ;; type-checks at ledger-write sites (e.g.
                    ;; election.advance's `state.write(successor(...))`).
                    (out (format "impl From<~a> for compact_runtime::Value {\n" enum-name))
                    (out (format "    fn from(v: ~a) -> compact_runtime::Value {\n" enum-name))
                    (out "        compact_runtime::Value::from(v as u8)\n")
                    (out "    }\n")
                    (out "}\n")
                    ;; M3.5: BinaryHashRepr for the enum — delegate via the
                    ;; u8 discriminant. Lets enum values flow through stdlib
                    ;; wrappers whose generic params require BinaryHashRepr
                    ;; (e.g. merkle_tree_path_root::<T>(path) when T is or
                    ;; contains a user enum, transitively).
                    (out (format "impl compact_runtime::BinaryHashRepr for ~a {\n" enum-name))
                    (out "    fn binary_repr<W: MemWrite<u8>>(&self, writer: &mut W) {\n")
                    (out "        (*self as u8).binary_repr(writer);\n")
                    (out "    }\n")
                    (out "    fn binary_len(&self) -> usize { 1 }\n")
                    (out "}\n")]
                   [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                    (cond
                      [(eq? struct-name 'Maybe)
                       ;; L1: Maybe<T> is provided by compact-runtime as a
                       ;; canonical generic struct — skip per-contract
                       ;; redefinition.
                       (void)]
                      [(eq? struct-name 'MerkleTreePath)
                       ;; MerkleTreePath<#n, T> lowers to upstream
                       ;; compact_runtime::MerklePath<T> — skip per-contract
                       ;; emission.
                       (void)]
                      [(eq? struct-name 'MerkleTreePathEntry)
                       ;; MerkleTreePathEntry lowers to upstream
                       ;; compact_runtime::MerklePathEntry — skip per-contract
                       ;; emission.
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
                       ;; M3.5: BinaryHashRepr for the struct — delegate
                       ;; field-by-field (same shape as FieldRepr / FromFieldRepr).
                       ;; Required by stdlib wrappers like
                       ;; merkle_tree_path_root::<T>(path) where T: BinaryHashRepr
                       ;; (e.g. zerocash.spend's `commitments.path_root::<commitment>(path)`).
                       (out (format "impl compact_runtime::BinaryHashRepr for ~a {\n"
                                    struct-name))
                       (out "    fn binary_repr<W: MemWrite<u8>>(&self, writer: &mut W) {\n")
                       (cond
                         [(null? elt-name*)
                          (out "        let _ = writer;\n")]
                         [else
                          (for-each
                            (lambda (name)
                              (out (format "        self.~a.binary_repr(writer);\n"
                                           name)))
                            elt-name*)])
                       (out "    }\n")
                       (out "    fn binary_len(&self) -> usize {\n        ")
                       (cond
                         [(null? elt-name*) (out "0")]
                         [else
                          (let loop ([names elt-name*] [first? #t])
                            (cond
                              [(null? names) (void)]
                              [else
                               (out (format "~aself.~a.binary_len()"
                                            (if first? "" " + ")
                                            (car names)))
                               (loop (cdr names) #f)]))])
                       (out "\n    }\n")
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
               type expr* local-binds
               native-id-ht witness-id-ht circuit-id-ht)]
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
            [(eq? sym 'merkleTreePathRoot)
             ;; `merkleTreePathRoot<#n, T>(path) -> MerkleTreeDigest`. Rust
             ;; wrapper takes `MerklePath<T>` and infers T from the arg, so
             ;; no turbofish needed.
             "compact_runtime::std_lib::merkle_tree_path_root"]
            [(eq? sym 'merkleTreePathRootNoLeafHash)
             ;; `merkleTreePathRootNoLeafHash<#n>(path) -> MerkleTreeDigest`.
             ;; Leaf is always `Bytes<32>`; wrapper has no generics.
             "compact_runtime::std_lib::merkle_tree_path_root_no_leaf_hash"]
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
                "/* TODO M3-J2: witness inline */ unimplemented!()"])]
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

      ;; stmt->if-then-else: detect a `(if cond then-stmt else-stmt)`
      ;; statement and return (list cond then-stmt else-stmt). Used by
      ;; E6.2's impure if-mid-body walker extension.
      (define (stmt->if-then-else stmt)
        (nanopass-case (Ltypescript Statement) stmt
          [(if ,src ,expr0 ,stmt1 ,stmt2) (list expr0 stmt1 stmt2)]
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
                   (and (fx= (length path-elt*) 1)
                        (nanopass-case (Ltypescript Path-Element) (car path-elt*)
                          [,path-index #t]
                          [else #f])
                        (for-all (lambda (e)
                                   (expr-supported?
                                     e native-id-ht witness-id-ht circuit-id-ht))
                                 expr*)
                        (loop (cdr stmts)))))]
              [(stmt->if-then-else (car stmts)) =>
               (lambda (parts)
                 (let* ([cond-expr (car parts)]
                        [then-call (branch->single-pl-call (cadr parts))]
                        [else-call (branch->single-pl-call (caddr parts))])
                   (and then-call else-call
                        (expr-supported? cond-expr native-id-ht witness-id-ht circuit-id-ht)
                        (let ([then-path (caddr then-call)]
                              [then-exprs (cadddr then-call)]
                              [else-path (caddr else-call)]
                              [else-exprs (cadddr else-call)])
                          (and (fx= (length then-path) 1)
                               (fx= (length else-path) 1)
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        then-exprs)
                               (for-all (lambda (e)
                                          (expr-supported?
                                            e native-id-ht witness-id-ht circuit-id-ht))
                                        else-exprs)
                               (loop (cdr stmts)))))))]
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
                     ;; Seed current-formal-arg-types with the
                     ;; constructor's args so var-ref-known-copy? can
                     ;; suppress redundant `.clone()` on primitive ctor
                     ;; parameters (`v: Field` in tiny.compact, etc.).
                     ;; The body walker mutates the same hashtable as it
                     ;; classifies const-bindings, so witness/pure-circuit
                     ;; results get their declared types recorded too.
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
      (define (render-struct-literal type expr* local-binds
                                     native-id-ht witness-id-ht circuit-id-ht)
        (let* ([st (struct-of-type type)]
               [struct-name (and st (car st))]
               [elt-name* (and st (cadr st))])
          (cond
            [(not st)
             "/* TODO M3-F2.2: struct-literal of non-tstruct type */ unimplemented!()"]
            [(not (fx= (length expr*) (length elt-name*)))
             "/* TODO M3-F2.2: struct-literal field-count mismatch */ unimplemented!()"]
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
               (out (format "        unimplemented!(\"M3-I3: circuit body emission for ~a\")\n"
                            (id-sym function-name)))))
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
              (format "/* TODO M3-E6: enum-ref of non-tenum type */ unimplemented!()")])]
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
                "/* TODO M3-F2.2: struct-literal mismatch */ unimplemented!()"]
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
           (format "/* TODO M3-I3b: unhandled Expression variant */ unimplemented!()")]))

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
                       "/* TODO M3-F1.2/2: ADT read-with-arg lowering */ unimplemented!()")]
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
           (parameterize ([current-formal-arg-types (build-formal-arg-type-ht arg*)])
             (let ([body (stmt-pure-body-rust stmt native-id-ht)])
               (cond
                 [body (out (format "        ~a\n" body))]
                 [else
                  (out (format "        unimplemented!(\"M3-I3: pure circuit body emission for ~a\")\n"
                               (id-sym function-name)))])))
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
