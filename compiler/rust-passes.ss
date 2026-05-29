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
           (format "/* TODO M3-F2: tstruct ~a */" struct-name)]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           (format "/* TODO M3-F3: tenum ~a */" enum-name)]
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

      ;; emit-initial-state: emits the `initial_state` constructor method
      ;; inside the open Contract impl block. For counter.compact this
      ;; seeds the single Counter ledger field to 0.
      ;;
      ;; TODO(M3): this hardcodes Counter as the only supported ADT.
      ;; Generalising to Cell/Map/Set/MerkleTree/List requires walking the
      ;; Ledger-Constructor body and dispatching on each field's ADT type.
      (define (emit-initial-state ledger-field*)
        (out "    pub fn initial_state(\n")
        (out "        &self,\n")
        (out "        ctx: ConstructorContext<PS>,\n")
        (out "    ) -> Result<ConstructorResult<PS>, CompactError> {\n")
        ;; For each ledger field, build its initial StateValue. For M2 this
        ;; is hardcoded to Cell(0u64) (Counter's initial value).
        (out "        let sv = new_array(vec![\n")
        (for-each
          (lambda (lf)
            (out "            new_cell(0u64),\n"))
          ledger-field*)
        (out "        ]);\n")
        (out "        let state = ChargedState::new(sv);\n")
        (out "        let qctx = QueryContext::new(state, ContractAddress::default());\n")
        (out "        Ok(ConstructorResult {\n")
        (out "            current_contract_state: qctx.state,\n")
        (out "            current_private_state: ctx.initial_private_state,\n")
        (out "            current_zswap_local_state: ctx.empty_zswap_local_state,\n")
        (out "        })\n")
        (out "    }\n\n"))

      ;; emit-increment-circuit: emits the `increment` circuit method
      ;; inside the open Contract impl block. Hard-coded for
      ;; counter.compact's single `increment()` circuit calling
      ;; Counter.increment(1). The Op sequence (Idx + Addi + Ins) comes
      ;; from compiler/midnight-ledger.ss:602-606. M3 will generalise to
      ;; arbitrary circuit bodies via a proper IR walk.
      (define (emit-increment-circuit)
        (out "    pub fn increment(\n")
        (out "        &self,\n")
        (out "        ctx: CircuitContext<PS>,\n")
        (out "    ) -> Result<CircuitResults<PS, ()>, CompactError> {\n")
        (out "        let ops = OpProgramVerify::<DefaultDB>::new()\n")
        (out "            .idx_at_index(0u8, true)\n")
        (out "            .addi(1)\n")
        (out "            .ins(true, 1)\n")
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
        (out "    }\n\n"))

      ;; emit-ledger-view: emits the module-level `ledger()` factory and the
      ;; `Ledger<'a, D>` view struct with one accessor method per ledger
      ;; field. For counter.compact this is a single `round()` method that
      ;; reads the Counter value via a dup+idx+popeq Op program. The popeq
      ;; uses ResultModeGather so the read value is captured as a
      ;; GatherEvent::Read(AlignedValue) event (ResultModeVerify would
      ;; require the value to be known up-front, which is the opposite of
      ;; what we want here).
      ;;
      ;; TODO(M3): hardcodes a single Counter field. Generalising requires
      ;; walking the Ledger-Constructor body and emitting one accessor per
      ;; field with the right decode path + type.
      (define (emit-ledger-view ledger-field*)
        (out "pub struct Ledger<'a, D: DB = DefaultDB> {\n")
        (out "    state: &'a ChargedState<D>,\n")
        (out "}\n\n")
        (out "pub fn ledger<D: DB>(state: &ChargedState<D>) -> Ledger<'_, D> {\n")
        (out "    Ledger { state }\n")
        (out "}\n\n")
        (out "impl<'a, D: DB> Ledger<'a, D> {\n")
        ;; Each ledger field → one method. Counter currently only.
        (for-each
          (lambda (lf)
            (out "    pub fn round(&self) -> Result<u64, CompactError> {\n")
            (out "        let qctx = QueryContext::new(self.state.clone(), ContractAddress::default());\n")
            (out "        let ops = OpProgramGather::<D>::new()\n")
            (out "            .dup(0)\n")
            (out "            .idx_at_index(0u8, false)\n")
            (out "            .popeq(true)\n")
            (out "            .build();\n")
            (out "        let results = query_for_read(&qctx, &ops, None, &initial_cost_model())\n")
            (out "            .map_err(|e| CompactError::AssertionFailed(format!(\"ledger query failed: {:?}\", e)))?;\n")
            (out "        let av = match results.events.last() {\n")
            (out "            Some(compact_runtime::onchain_vm::result_mode::GatherEvent::Read(av)) => av,\n")
            (out "            _ => return Err(CompactError::AssertionFailed(\"ledger: expected Read event\".into())),\n")
            (out "        };\n")
            (out "        compact_runtime::std_lib::decode_u64(av)\n")
            (out "    }\n"))
          ledger-field*)
        (out "}\n\n"))

      ;; emit-pure-circuits: emits the `pure_circuits` module. counter.compact
      ;; has no pure circuits, so the module is emitted empty. M3 fills it in
      ;; for contracts that declare pure circuits.
      (define (emit-pure-circuits pure-circuit*)
        (out "pub mod pure_circuits {\n")
        ;; M3: emit one `pub fn` per pure circuit.
        (for-each (lambda (c) (out "    // TODO(M3): emit pure circuit\n")) pure-circuit*)
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
       (emit-witnesses (program-witnesses pelt*))
       (emit-contract-struct)
       (emit-initial-state (program-ledger-fields pelt*))
       ;; M2: hardcode the increment circuit for counter.compact.
       ;; M3 replaces this with a real IR walk over circuit declarations.
       (emit-increment-circuit)
       (close-contract-struct)
       (emit-ledger-view (program-ledger-fields pelt*))
       ;; counter.compact has no pure circuits — emit an empty module.
       (emit-pure-circuits '())
       (emit-cargo-toml)
       ir]))

  (define-passes rust-passes
    (print-rust          Ltypescript)))
