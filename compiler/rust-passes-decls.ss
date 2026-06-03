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
                    ;; H1/Bucket-4: derive Default so user enums work as
                    ;; defaultable fields of generated structs (which derive
                    ;; Default themselves). The first variant is the default.
                    (out "#[derive(Clone, Copy, Debug, PartialEq, Eq, Default)]\n")
                    (out "#[repr(u8)]\n")
                    (out (format "pub enum ~a {\n" enum-name))
                    (let loop ([variants (cons elt-name elt-name*)] [i 0])
                      (unless (null? variants)
                        (when (= i 0)
                          (out "    #[default]\n"))
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
                      [(let ([entry (lookup-stdlib-struct struct-name)])
                         (and entry (cadr entry)))
                       ;; Stdlib struct (Maybe / MerkleTreePath /
                       ;; MerkleTreePathEntry) is provided by
                       ;; compact-runtime — skip per-contract emission.
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
