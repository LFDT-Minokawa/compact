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

      (define (out s)
        (display-string s (get-target-port 'contract.rs)))

      ;; rust-feature-error: raises a compactc error tagged with the
      ;; `--rust:` prefix when the codegen hits an unsupported Compact
      ;; construct. Use this in place of emitting `unimplemented!()`
      ;; Rust into the output — contracts that would otherwise compile
      ;; but panic at runtime now fail at compile time with a clear
      ;; message.
      ;;
      ;; Prefer this over external-errorf when you have a source object
      ;; (most IR nodes carry `,src`); falls back to external-errorf
      ;; when src is #f.
      ;;
      ;; The `tag` argument is a short stable identifier (e.g.
      ;; 'struct-literal-mismatch, 'enum-ref-non-tenum, 'witness-inline)
      ;; — useful for users grepping the codegen to see what they hit
      ;; and for future cross-references in docs.
      (define (rust-feature-error src tag msg . args)
        (let ([prefixed (format "compactc --rust: unsupported Compact construct (~a): ~a"
                                tag (apply format msg args))])
          (if src
              (source-errorf src "~a" prefixed)
              (external-errorf "~a" prefixed))))

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

      ;; current-impure-call-binds: A15 sibling of current-witness-call-binds
      ;; for non-pure user-circuit calls hoisted out of an assert/condition.
      ;; did.compact's `assert(!verificationMethodExists(id), ...)` shape is
      ;; the canonical case. Each entry is `(list function-name arg-expr*
      ;; rust-name)` mirroring the witness binds. Consulted by
      ;; ctor-call-rust's else branch BEFORE falling to call-rust (which
      ;; would error with "non-native-call"): on hit, the call renders as
      ;; `<rust-name>.result.clone()` referring to the hoisted
      ;; `let <rust-name> = self.<X>(ctx, args)?;` binding.
      (define current-impure-call-binds
        (make-parameter '()))

      ;; current-var-substitution: alist of (var-name . rust-rendered-string),
      ;; threaded dynamically by ctor-expr-rust so that downstream callees
      ;; reachable only through `expr-rust` (e.g. emit-ledger-read-expr →
      ;; expr->vm-value → expr-rust) can still resolve var-ref substitutions
      ;; that came from inline-circuit-call's formal-binds. Without this,
      ;; rendering `verificationMethodExists(disclosedMethodId)` inlined into
      ;; an assert leaks the inner formal `id` into the final Rust because
      ;; expr-rust's var-ref clause has no access to ctor-expr-rust's
      ;; explicit local-binds parameter. Default `'()` matches "no
      ;; substitution active" — expr-rust falls back to its plain snake-case
      ;; rendering. Bug-1 (post-A19 inventory).
      (define current-var-substitution
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

      ;; current-ledger-field-types: eqv-hashtable mapping a ledger
      ;; field's path-index (a non-negative integer) → its declared
      ;; binding Type (the tadt wrapper, e.g.
      ;; `(tadt Cell ([0 (tvector 3 (tunsigned ...))]) ...)`). Initialised
      ;; by `emit-initial-state` before walking the constructor body so
      ;; `emit-body-writes` can choose `new_cell_array(...)` vs
      ;; `new_cell(...)` based on the destination field's tvector-ness
      ;; (Iter 7). Defaults to #f when not parameterized — callers fall
      ;; back to the plain `new_cell(...)` shape, matching pre-Iter 7
      ;; behaviour.
      (define current-ledger-field-types
        (make-parameter #f))

      ;; current-arith-suffix: Rust unsigned-type suffix ("u8" / "u16" /
      ;; "u32" / "u64" / "u128") that wrapping_add / wrapping_sub /
      ;; wrapping_mul operands should carry on their integer-literal
      ;; receivers. Set by expr-rust's downcast-unsigned clause before
      ;; recursing into the wrapped arithmetic so Rust resolves the
      ;; inherent method on a concrete type rather than rejecting the
      ;; call as "ambiguous numeric type". `#f` outside arithmetic
      ;; contexts.
      ;;
      ;; Iter 7 follow-up: introduced to support non-identity lambdas
      ;; in `map()` (e.g. `(x * 2) as Uint<64>` lowering).
      (define current-arith-suffix
        (make-parameter #f))

      ;; integer-literal-rendering?: returns #t when `s` is a string of
      ;; one or more decimal digits (with no suffix, no operator chars,
      ;; no parens). Used by arith-operand-rust to decide whether
      ;; appending a `u<width>` type suffix is safe — variable refs and
      ;; method-call expressions would be corrupted by suffix
      ;; concatenation, but a bare literal token can carry the suffix
      ;; directly (`1` + `u64` = `1u64`).
      (define (integer-literal-rendering? s)
        (and (string? s)
             (fx> (string-length s) 0)
             (let loop ([i 0])
               (cond
                 [(fx= i (string-length s)) #t]
                 [else
                  (let ([c (string-ref s i)])
                    (and (char>=? c #\0) (char<=? c #\9)
                         (loop (fx+ i 1))))]))))

      ;; build-ledger-field-type-ht: given the program's ledger-field*
      ;; Program-Element list, build an eqv-hashtable mapping each
      ;; binding's path-index (number) to its binding Type. Mirrors
      ;; `pl-array->public-bindings` + `binding-path-indices` /
      ;; `binding-type`, but those live in rust-passes-emit.ss; this
      ;; helper sits next to its parameter so the include order doesn't
      ;; matter.
      (define (build-ledger-field-type-ht public-bindings)
        (let ([ht (make-eqv-hashtable)])
          (for-each
            (lambda (pb)
              (nanopass-case (Ltypescript Public-Ledger-Binding) pb
                [(,src ,ledger-field-name (,path-index* ...) ,type)
                 (when (and (pair? path-index*) (number? (car path-index*)))
                   (hashtable-set! ht (car path-index*) type))]))
            public-bindings)
          ht))

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

      ;; uint-byte-length: number of bytes the on-state alignment uses to
      ;; hold values up to `nat`. ceil(bit_length / 8). Mirrors the TS
      ;; emitter's `(byte-length nat)` helper used by
      ;; `CompactTypeUnsignedInteger(maxValue, length)`. This is the
      ;; `AlignmentAtom::Bytes { length: ... }` parameter on the wire and
      ;; can differ from the Rust integer width's byte count for bounded
      ;; ranges (e.g. `Uint<0..70000>` is u32 in Rust but 3 bytes on state).
      (define (uint-byte-length nat)
        (let loop ([n nat] [bits 0])
          (if (= n 0)
              (if (= bits 0) 1 (div (+ bits 7) 8))
              (loop (div n 2) (+ bits 1)))))

      ;; uint-byte-length-matches-rust-width?: true when the on-state
      ;; byte-length equals the Rust integer width's byte count, i.e. the
      ;; fixed-width `Uint<N>` cases where N ∈ {8,16,32,64,128}. False for
      ;; bounded ranges with non-power-of-two byte-lengths (e.g. 3, 5, 6,
      ;; 7, 9..15). When false, codegen must route through
      ;; `new_cell_bounded_uint(value, byte_len)` to get TS-parity.
      (define (uint-byte-length-matches-rust-width? nat)
        (let ([bl (uint-byte-length nat)])
          (or (= bl 1) (= bl 2) (= bl 4) (= bl 8) (= bl 16))))

      ;; -----------------------------------------------------------------
      ;; Stdlib lookup tables.
      ;;
      ;; Two alists drive every place the emitter must special-case a
      ;; runtime-provided struct or stdlib pure circuit:
      ;;
      ;;   stdlib-struct-mappings  : struct-name → (type-rust-fn skip-decl?)
      ;;     - type-rust-fn (lambda elt-name* type*) → Rust type string,
      ;;       called from type-rust's tstruct branch.
      ;;     - skip-decl? boolean; when #t, emit-type-decls's tstruct branch
      ;;       skips per-contract emission (runtime provides the type).
      ;;
      ;;   stdlib-circuit-mappings : compact-name → (rust-path-fn)
      ;;     - rust-path-fn (lambda cdefn) → Rust callee path string,
      ;;       called from stdlib-circuit-rust-path. cdefn is the looked-up
      ;;       circuit pelt (or #f); the lambda may inspect its return type
      ;;       for turbofish ascription.
      ;;
      ;; Adding a new stdlib mapping is a single table-entry edit instead
      ;; of touching 3-5 scattered cond clauses.
      ;; -----------------------------------------------------------------

      (define stdlib-struct-mappings
        `((Maybe
            ,(lambda (elt-name* type*)
               (let loop ([names elt-name*] [types type*])
                 (cond
                   [(null? names) "Maybe</* L1: no value field */>"]
                   [(eq? (car names) 'value) (format "Maybe<~a>" (type-rust (car types)))]
                   [else (loop (cdr names) (cdr types))])))
            #t)
          (MerkleTreePath
            ,(lambda (elt-name* type*)
               (let loop ([names elt-name*] [types type*])
                 (cond
                   [(null? names) "compact_runtime::MerklePath</* no leaf field */>"]
                   [(eq? (car names) 'leaf)
                    (format "compact_runtime::MerklePath<~a>" (type-rust (car types)))]
                   [else (loop (cdr names) (cdr types))])))
            #t)
          (MerkleTreePathEntry
            ,(lambda (elt-name* type*) "compact_runtime::MerklePathEntry")
            #t)))

      (define stdlib-circuit-mappings
        `((some
            ,(lambda (cdefn)
               (let ([t (and cdefn (maybe-value-type (circuit-return-type cdefn)))])
                 (format "compact_runtime::std_lib::some~a"
                         (if t (format "::<~a>" (type-rust t)) "")))))
          (none
            ,(lambda (cdefn)
               (let ([t (and cdefn (maybe-value-type (circuit-return-type cdefn)))])
                 (format "compact_runtime::std_lib::none~a"
                         (if t (format "::<~a>" (type-rust t)) "")))))
          (merkleTreePathRoot
            ,(lambda (cdefn) "compact_runtime::std_lib::merkle_tree_path_root"))
          (merkleTreePathRootNoLeafHash
            ,(lambda (cdefn) "compact_runtime::std_lib::merkle_tree_path_root_no_leaf_hash"))))

      ;; lookup-stdlib-struct: return (type-rust-fn skip-decl?) list for a
      ;; struct-name, or #f if not a stdlib struct.
      (define (lookup-stdlib-struct struct-name)
        (let ([entry (assq struct-name stdlib-struct-mappings)])
          (and entry (cdr entry))))

      ;; lookup-stdlib-circuit: return (rust-path-fn) list for a Compact
      ;; stdlib circuit symbol, or #f if not a stdlib circuit.
      (define (lookup-stdlib-circuit sym)
        (let ([entry (assq sym stdlib-circuit-mappings)])
          (and entry (cdr entry))))

