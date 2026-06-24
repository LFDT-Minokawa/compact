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
           ;; has the needed impls upstream. "JubjubPoint" maps to the
           ;; upstream alias (orphan-safe repr helpers live in
           ;; compact_runtime::jubjub_point_*). Other opaque tags stay flagged.
           (cond
             [(equal? opaque-type "string") "compact_runtime::std_lib::OpaqueString"]
             [(equal? opaque-type "Uint8Array") "Vec<u8>"]
             [(equal? opaque-type "JubjubPoint") "JubjubPoint"]
             [else (format "/* TODO M3-F4: topaque ~a */" opaque-type)])]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           ;; Stdlib structs (Maybe<T>, MerkleTreePath<#n, T>,
           ;; MerkleTreePathEntry) resolve to runtime-provided Rust types
           ;; via stdlib-struct-mappings. Other named structs lower to
           ;; their bare name; their definitions are emitted by
           ;; emit-type-decls (H5 / future tasks).
           (let ([entry (lookup-stdlib-struct struct-name)])
             (if entry
                 ((car entry) elt-name* type*)
                 (symbol->string struct-name)))]
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

      ;; R5a: Recognise the `JubjubPoint` opaque type. Lowered through
      ;; Ltypescript as `tstruct 'JubjubPoint` with no body fields.
      ;; Upstream `EmbeddedGroupAffine` (= JubjubPoint) has an `Aligned`
      ;; impl but no `FieldRepr` / `FromFieldRepr` / `BinaryHashRepr`,
      ;; and Rust's orphan rules forbid us from supplying them
      ;; downstream. Codegen routes JubjubPoint-typed struct fields
      ;; through compact_runtime::jubjub_point_* free functions.
      (define (problematic-jubjub-point? type)
        (nanopass-case (Ltypescript Type) type
          [(topaque ,src ,opaque-type)
           (equal? opaque-type "JubjubPoint")]
          [(talias ,src ,nominal? ,type-name ,type)
           (problematic-jubjub-point? type)]
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
          [(problematic-jubjub-point? type)
           ;; R5a: orphan-safe const from compact_runtime.
           "compact_runtime::JUBJUB_POINT_FIELD_SIZE"]
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
            [(problematic-jubjub-point? type)
             ;; R5a: orphan-safe parse via compact_runtime helper.
             (out (format "        let ~a = compact_runtime::jubjub_point_from_field_repr(&r[_offset.._offset + ~a])?;\n"
                          name size-expr))
             (out (format "        _offset += ~a;\n" size-expr))]
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
          [(problematic-jubjub-point? type)
           ;; R5a: orphan-safe field_size.
           (format "compact_runtime::jubjub_point_field_size(&self.~a)" field-name)]
          [else
           (format "self.~a.field_size()" field-name)]))

      ;; field-repr-emit: write the per-field `self.x.field_repr(writer)`
      ;; or equivalent loop for `[T; N]` of user types.
      (define (emit-field-repr-call field-name type)
        (cond
          [(problematic-vector? type)
           (out (format "        for _e in self.~a.iter() { _e.field_repr(writer); }\n"
                        field-name))]
          [(problematic-jubjub-point? type)
           ;; R5a: orphan-safe field_repr.
           (out (format "        compact_runtime::jubjub_point_field_repr(&self.~a, writer);\n"
                        field-name))]
          [else
           (out (format "        self.~a.field_repr(writer);\n" field-name))]))
