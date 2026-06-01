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

