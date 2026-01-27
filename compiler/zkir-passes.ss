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

(library (zkir-passes)
  (export zkir-passes)
  (import (except (chezscheme) errorf)
          (config-params)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers)
          (natives)
          (ledger)
          (vm))

  (define (print-zkir ir)
    (define (print-zkir prog entry-point)
      (define (extract-entry-point prog entry-point)
        (nanopass-case (Lflattened Program) prog
          [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
           (let ([entry-id (cond
                             [(assq entry-point (map cons export-name* name*)) => cdr]
                             [else (internal-errorf 'extrant-entry-point "unrecognized entry point ~s" entry-point)])])
             (let ([declarations (filter (lambda (pelt) (not (Lflattened-Circuit-Definition? pelt))) pelt*)]
                   [entry-points (filter (lambda (pelt)
                                           (nanopass-case (Lflattened Circuit-Definition) pelt
                                             [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
                                               (eq? function-name entry-id)]
                                             [else #f]))
                                         pelt*)])
               (cond
                 [(null? entry-points)
                  (internal-errorf 'extract-entry-point "~s is not an circuit entry point" entry-point)]
                 [(null? (cdr entry-points))
                  (with-output-language (Lflattened Program)
                    `(program ,src ((,export-name* ,name*) ...) ,(cons (car entry-points) declarations) ...))]
                 [else
                  (internal-errorf 'extract-entry-point "multiple entry points names ~s encountered!" entry-point)])))]))

      (define-pass print-zkir$ : Lflattened (ir) -> Lflattened ()
        (definitions
          (define ctr 0)
          (define varid-ht (make-eq-hashtable))
          (define calltype-ht (make-eq-hashtable))
          (define returntype-ht (make-eq-hashtable))
          (define literal-ht (make-eq-hashtable))
          (define print-gate
            (letrec ([seen-gate? #f]
                     [json (lambda (x)
                             (cond
                               [(string? x) (format "~s" x)]
                               [(fixnum? x) (format "~d" x)]
                               [(list? x) (format "[~{~a~^, ~}]" (map json x))]
                               [(hashtable? x)
                                (let-values ([(k* v*) (hashtable-entries x)])
                                  (let* ([kv* (map (lambda (k v) (cons k v)) (vector->list k*) (vector->list v*))]
                                         [kv*-sorted (sort (lambda (kv1 kv2)
                                                             (string<?
                                                               (symbol->string (car kv1))
                                                               (symbol->string (car kv2))))
                                                           kv*)])
                                    (format "{ ~{~a~^, ~} }"
                                            (map (lambda (kv)
                                                   (format "~a: ~a"
                                                           (json (car kv))
                                                           (json (cdr kv))))
                                                 kv*-sorted))))]
                               [(eq? x 'null) "null"]
                               [(symbol? x) (format "\"~a\"" x)]
                               [else (internal-errorf 'print-zkir "don't know how to output as json: ~s" x)]))])
              (lambda gs
                (for-each
                  (lambda (arg)
                    (unless (cadr arg)
                      (internal-errorf 'print-zkir "encountered unbound variable")))
                  (cdr gs))
                (printf "~:[~;,\n~]    { ~{~a~^, ~} }"
                        seen-gate?
                        (map (lambda (g) (if (pair? g)
                                             (format "\"~a\": ~a" (car g) (json (cadr g)))
                                             (format "\"op\": ~a" (json g))))
                             gs))
                (set! seen-gate? #t))))
          (define (is-std-file? file)
            (equal? (path-last file) "std"))
          (define (bind-var! var bind-to)
            (hashtable-set! varid-ht var bind-to))
          (define (new-var! var bound)
            (let ([index ctr])
              (bind-var! var index)
              (set! ctr (add1 ctr))
              (when bound
                (constrain-type bound index))
              index))

          ;; Returns the list of argument primitive types along with their indexes, with the
          ;; side effect of allocating those indexes.
          (define (allocate-args! args)
            (let-values ([(prim-type** index**)
                          (maplr2 (lambda (arg)
                                    (nanopass-case (Lflattened Argument) arg
                                      [(argument (,var-name* ...) ,type)
                                       (values
                                         (type->primitive-types type)
                                         (maplr (lambda (var-name) (new-var! var-name #f))
                                           var-name*))]))
                            args)])
              (values (apply append prim-type**) (apply append index**))))

          (define (type->primitive-types type)
            (nanopass-case (Lflattened Type) type
              [(ty (,alignment* ...) (,primitive-type* ...)) primitive-type*]))
          (define (alignment->json align)
            (define (mkhash assoc)
              (let ([ht (make-hashtable symbol-hash eq?)])
                (for-each (lambda (p) (hashtable-set! ht (car p) (cdr p))) assoc)
                ht))
            (define (alignment->json-atom align)
              (nanopass-case (Lflattened Alignment) align
                [(acompress) (mkhash `((tag . atom) (value . ,(mkhash `((tag . compress))))))]
                [(abytes ,nat) (mkhash `((tag . atom) (value . ,(mkhash `((tag . bytes) (length . ,nat))))))]
                [(afield) (mkhash `((tag . atom) (value . ,(mkhash `((tag . field))))))]
                [else (internal-errorf 'print-zkir "Attempted to extract alignment for ADT type ~s" align)]))
            (map alignment->json-atom align))
          (define (constrain-type type pos)
            (nanopass-case (Lflattened Primitive-Type) type
              [(tfield) (void)]
              [(tfield ,nat)
               (cond
                 [(= nat 0) (print-gate "constrain_eq" `[a ,pos] `[b ,(literal 0)])]
                 [(= nat 1) (print-gate "constrain_to_boolean" `[var ,pos])]
                 [(= (expt 2 (integer-length nat)) (+ nat 1))
                  ; NB: assuming constrain_bits works for arbitrary powers of two
                  (print-gate "constrain_bits" `[var ,pos] `[bits ,(integer-length nat)])]
                 [else
                   ;; Compute the bits required to represent nat.
                   ;; Plonk requires this to be a multiple of two, so instead of
                   ;; ⌈log_2(nat + 1)⌉, we compute k = ⌈log_4(nat + 1)⌉: the smallest
                   ;; exponent for which nat + 1 <= 4^k, and therefore nat < 2^(2k)
                   ;; with 2k being guaranteed to be even.
                   ;; Note that we need need nat + 1, at nat itself is a valid
                   ;; assignment, and the final check is a less-than check.
                   (let ([bits (* 2 (quotient (+ (integer-length (+ 1 nat)) 1) 2))])
                     (print-gate "less_than" `[a ,pos] `[b ,(literal (add1 nat))] `[bits ,bits])
                     (print-gate "assert" `[cond ,ctr])
                     (set! ctr (add1 ctr)))])]
              [(topaque ,opaque-type) (void)]
              [else (internal-errorf 'print-zkir "Unboundable type ~s" ir)]))
          (define std-circuits
            (let ([ht (make-hashtable symbol-hash eq?)])
              (define (register-handler! name handler)
                (unless (hashtable-contains? native-table name)
                  (internal-errorf 'print-zkir "undeclared native name ~s" name))
                (let ([a (hashtable-cell ht name #f)])
                  (when (cdr a) (internal-errorf 'print-zkir "duplicate circuit name ~s" name))
                  (set-cdr! a handler)))
              (register-handler! 'transientHash
                (lambda (align res* . xs)
                  (print-gate "transient_hash" `[inputs ,xs])
                  (new-var! (car res*) #f)))
              (register-handler! 'degradeToTransient
                (lambda (align res* a1 a2) (bind-var! (car res*) a2)))
              (register-handler! 'upgradeFromTransient
                (lambda (align res* a1)
                  (bind-var! (car res*) (literal 0))
                  (print-gate "div_mod_power_of_two" `[var ,a1] `[bits 248])
                  (set! ctr (add1 ctr))
                  (new-var! (cadr res*) #f)))
              (register-handler! 'ecAdd
                (lambda (align res* ax ay bx by)
                  (print-gate "ec_add" `[a_x ,ax] `[a_y ,ay] `[b_x ,bx] `[b_y ,by])
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'ecMul
                (lambda (align res* ax ay b)
                  (print-gate "ec_mul" `[a_x ,ax] `[a_y ,ay] `[scalar ,b])
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'ecMulGenerator
                (lambda (align res* b)
                  (print-gate "ec_mul_generator" `[scalar ,b])
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'hashToCurve
                (lambda (align res* . args*)
                  (print-gate "hash_to_curve" `[inputs ,args*])
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'transientCommit
                ;; First n-1 args are the object being committed.
                ;; Final arg is commitment nonce.
                ;; commit algorithm is: object.fold(nonce, poseidon_compress)
                (lambda (align res* . args*)
                  (print-gate "transient_hash" `[inputs ,(cons (car (list-tail args* (sub1 (length args*))))
                                                               (list-head args* (sub1 (length args*))))])
                  (new-var! (car res*) #f)))
              (register-handler! 'persistentCommit
                ;; First n-2 args are the object being committed.
                ;; Final 2 args are commitment nonce.
                ;; commit algorithm is: object.fold(nonce, poseidon_compress)
                (lambda (align res* . args*)
                  (print-gate "persistent_hash"
                              `[alignment ,(alignment->json
                                             (cons (with-output-language (Lflattened Alignment)
                                                     `(abytes 32))
                                                   (caar align)))]
                              `[inputs ,(append (list-tail args* (- (length args*) 2))
                                                (list-head args* (- (length args*) 2)))])
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'persistentHash
                (lambda (align res* . args*)
                  (print-gate "persistent_hash"
                              `[alignment ,(alignment->json (caar align))]
                              `[inputs ,args*])
                  ; FIXME: also cadr res*
                  ; FIXME: should check for expected number of res*
                  (new-var! (car res*) #f)
                  (new-var! (cadr res*) #f)))
              (register-handler! 'ownPublicKey
                (lambda (align res* . args*)
                  ; handled as a witness
                  (assert cannot-happen)))
              (register-handler! 'createZswapInput
                (lambda (align res* . args*)
                  ; handled as a witness
                  (assert cannot-happen)))
              (register-handler! 'createZswapOutput
                (lambda (align res* . args*)
                  ; handled as a witness
                  (assert cannot-happen)))
              ht))
          (define (literal n)
            (if (hashtable-contains? literal-ht n)
              (hashtable-ref literal-ht n #f)
              (begin
                (hashtable-set! literal-ht n ctr)
                (if (< n 0)
                    (print-gate "load_imm" `[imm ,(format "-~a" (le-bytes->hex (integer->le-bytes (- n))))])
                    (print-gate "load_imm" `[imm ,(format "~a" (le-bytes->hex (integer->le-bytes n)))]))
                (set! ctr (add1 ctr))
                (sub1 ctr))))
          (define (var-idx var)
            (or (hashtable-ref varid-ht var #f)
                (internal-errorf 'var-idx "var ~s is not bound" var)))
          (define (set-calltype! var type)
            (hashtable-set! calltype-ht var type))
          (define (calltype var)
            (hashtable-ref calltype-ht var #f))
          (define (le-bytes->hex bytes) (format "~{~2,'0x~}" bytes))
          (define (integer->le-bytes n)
            (if (< n 256)
                (list n)
                (cons (mod n 256) (integer->le-bytes (div n 256)))))
          (define (make-statement triv-or-var)
            (print-gate "declare_pub_input" `[var ,(if (id? triv-or-var)
                                                       (var-idx triv-or-var)
                                                       triv-or-var)]))
          (define (pl-array->public-bindings pl-array)
            (let f ([pl-array pl-array] [pb* '()])
              (nanopass-case (Lflattened Public-Ledger-Array) pl-array
                [(public-ledger-array ,pl-array-elt* ...)
                 (fold-right
                   (lambda (pl-array-elt pb*)
                     (nanopass-case (Lflattened Public-Ledger-Array-Element) pl-array-elt
                       [,pl-array (f pl-array pb*)]
                       [,public-binding (cons public-binding pb*)]))
                   pb*
                   pl-array-elt*)])))
          (define-record-type vmref
            (nongenerative)
            (fields type q))
          )
        (Program : Program (ir) -> Program ()
          [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
           (printf "{\n")
           (printf "  \"version\": { \"major\": 2, \"minor\": 0 },\n")
           (printf "  \"do_communications_commitment\": ~a,\n"
                   (if (no-communications-commitment) "false" "true"))
           (for-each Program-Element (filter (compose not Lflattened-Circuit-Definition?) pelt*))
           (for-each Program-Element (filter Lflattened-Circuit-Definition? pelt*))
           (printf "}\n")
           ir])
        (Program-Element : Program-Element (ir) -> * (void)
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
           ;; Allocating argument indexes and constraining arguments is done in
           ;; two steps due to the ordering of side effects (index allocation).
           (let-values ([(prim-type* index*) (allocate-args! arg*)])
             (printf "  \"num_inputs\": ~a,\n  \"instructions\": [\n" (length index*))
             (for-each constrain-type prim-type* index*)
             (for-each Statement stmt*)
             (for-each (lambda (triv) (print-gate "output" `[var ,(Triv triv)])) triv*)
             (printf "\n  ]\n"))]
          [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
           (if (eq? (native-entry-class native-entry) 'witness)
               (begin
                 (set-calltype! function-name '(witness . #f))
                 (hashtable-set! returntype-ht function-name (type->primitive-types type)))
               (set-calltype! function-name
                 (cons*
                   'builtin-circuit
                   (native-entry-name native-entry)
                   (list (map (lambda (arg)
                                (nanopass-case (Lflattened Argument) arg
                                  [(argument (,var-name ...) (ty (,alignment* ...) (,primitive-type* ...)))
                                   alignment*]))
                              arg*)
                         (nanopass-case (Lflattened Type) type
                           [(ty (,alignment* ...) (,primitive-type* ...)) alignment*])))))]
          [(witness ,src ,function-name (,arg* ...) ,type)
           (set-calltype! function-name '(witness . #f))
           (hashtable-set! returntype-ht function-name (type->primitive-types type))]
          [(kernel-declaration ,public-binding)
           (Public-Ledger-Binding public-binding)]
          [(public-ledger-declaration ,pl-array)
           (for-each Public-Ledger-Binding (pl-array->public-bindings pl-array))])
        (Public-Ledger-Binding : Public-Ledger-Binding (ir) -> * (void)
          [(,src ,ledger-field-name (,path-index* ...) ,primitive-type)
           (void)])
        (ADT-Op : ADT-Op (ir) -> * (op)
          [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
           (let ([type-length (lambda (type)
                                (nanopass-case (Lflattened Type) type
                                  [(ty (,alignment* ...) (,primitive-type* ...)) (length primitive-type*)]))])
             (list ledger-op (apply + (type-length type) (map type-length type*))))])
        (Statement : Statement (ir) -> * (void)
          [(= ,var-name ,single)
           (Single single)
           (new-var! var-name #f)]
          [(= (,var-name* ...) (call ,src ,[* test] ,function-name ,[* triv*] ...))
           (let ([pair (assert (calltype function-name))])
             (case (car pair)
               [(builtin-circuit)
                (cond
                  [(hashtable-ref std-circuits (cadr pair) #f) =>
                   (lambda (handler) (apply handler (cddr pair) var-name* triv*))]
                  [else (source-errorf src "unrecognized native circuit ~a" (cadr pair))])]
               [(witness)
                (for-each
                  (lambda (type var)
                    (if (equal? test (hashtable-ref literal-ht 1 #f))
                        (print-gate "private_input" '[guard null])
                        (print-gate "private_input" `[guard ,test]))
                    (new-var! var type))
                  (assert (hashtable-ref returntype-ht function-name #f))
                  var-name*)]
               [else (assert cannot-happen)]))]
          [(= (,var-name* ...) (contract-call ,src ,test ,elt-name (,triv ,primitive-type) ,triv* ...))
           (source-errorf src "cross-contract calls are not yet supported")]
          [(= (,var-name* ...) (bytes->vector ,[* triv]))
           (assert (not (null? var-name*)))
           (let loop ([var-name* var-name*] [triv triv])
             (let ([var-name (car var-name*)] [var-name* (cdr var-name*)])
               (if (null? var-name*)
                   (bind-var! var-name triv)
                   (begin
                     (print-gate "div_mod_power_of_two" `[var ,triv] `[bits 8])
                     (let ([q ctr])
                       (set! ctr (add1 ctr))
                       (new-var! var-name #f)
                       (loop var-name* q))))))]
          [(= (,var-name1 ,var-name2) (field->bytes ,src ,[* test] ,len ,[* triv]))
           ; FIXME: need to respect test: constrain_bits shouldn't happen if test is false
           (if (<= len (field-bytes))
               (begin
                 (bind-var! var-name1 (literal 0))
                 (bind-var! var-name2 triv)
                 (print-gate "constrain_bits" `[var ,triv] `[bits ,(* len 8)]))
               (begin
                 (print-gate "div_mod_power_of_two" `[var ,triv] `[bits ,(* (field-bytes) 8)])
                 (new-var! var-name1 #f)
                 (new-var! var-name2 #f)))]
          [(= (,var-name* ...) (public-ledger ,src ,[* test] ,ledger-field-name ,sugar? (,[* path-elt*] ...) ,src^ ,adt-op ,[* triv*] ...))
           (let ()
             (define (group type* triv*)
               (let f ([type* type*] [triv* triv*])
                 (if (null? type*)
                     (begin (assert (null? triv*)) '())
                     (let ([type (car type*)] [type* (cdr type*)])
                       (nanopass-case (Lflattened Type) type
                         [(ty (,alignment* ...) (,primitive-type* ...))
                          (let ([n (length primitive-type*)])
                            (assert (fx>= (length triv*) n))
                            (cons (list-head triv* n) (f type* (list-tail triv* n))))]
                         [else (assert cannot-happen)])))))
             (nanopass-case (Lflattened ADT-Op) adt-op
               [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
                (for-each
                  (lambda (ins)
                    (letrec* ([type->alignment (lambda (type)
                                                 (nanopass-case (Lflattened Type) type
                                                   [(ty (,alignment* ...) (,primitive-type* ...))
                                                    (map
                                                      (lambda (alignment)
                                                        (nanopass-case (Lflattened Alignment) alignment
                                                         [(acompress) -1]
                                                         [(abytes ,nat) nat]
                                                         [(afield) -2]
                                                         [(aadt) -3]
                                                         [(acontract) -4]))
                                                      alignment*)]))]
                              [null-for-alignment (lambda (alignment)
                                                    (apply append
                                                           (map (lambda (atom)
                                                                  (let ([n (if (< atom 0) 1 (ceiling (/ atom (field-bytes))))])
                                                                    (map (lambda (_) 0) (iota n))))
                                                                alignment)))]
                              [emit (lambda (ref) (make-statement
                                                    (cond
                                                      [(equal? test (hashtable-ref literal-ht 1 #f)) ref]
                                                      [(equal? ref (hashtable-ref literal-ht 1 #f)) test]
                                                      [else
                                                       (let ([ref (if (id? ref) (var-idx ref) ref)])
                                                         (print-gate "cond_select" `[bit ,test] `[a ,ref] `[b ,(literal 0)])
                                                         (set! ctr (add1 ctr))
                                                         (sub1 ctr))])))]
                              [vm-eval (lambda (vmop)
                                         (cond
                                          [(VMop? vmop)
                                           (VMop-case vmop
                                             [(VMsuppress) '()]
                                             [(VMstack) '(-1)]
                                             [(VMvoid) '()]
                                             [(VMstate-value-null) (list 0)]
                                             [(VMstate-value-cell val) (list* 1 (vm-eval val))]
                                             [(VMstate-value-ADT val type)
                                              ; wrap val in a cell, unless it is already an ADT
                                              (or (nanopass-case (Lflattened Type) type
                                                    [(ty (,alignment* ...) ((tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))))
                                                     (vm-eval
                                                       (expand-vm-expr
                                                         src
                                                         (map cons adt-formal* adt-arg*)
                                                         (vm-expr-expr vm-expr)))]
                                                    [else #f])
                                                  (list* 1 (vm-eval val)))]
                                             [(VMstate-value-map key* val*)
                                              (append (list (+ 2 (* (length key*) 16)))
                                                      (apply append (maplr vm-eval key*))
                                                      (apply append (maplr vm-eval val*)))]
                                             [(VMstate-value-array val*)
                                              (append (list (+ 3 (* (length val*) 16)))
                                                      (apply append (maplr vm-eval val*)))]
                                             [(VMstate-value-merkle-tree nat key* val*)
                                              (append (list (+ 4 (* nat 16) (* (length key*) 4096)))
                                                      (apply append (maplr vm-eval key*))
                                                      (apply append (maplr vm-eval val*)))]
                                             [(VMalign value bytes) (list* 1 bytes (vm-eval value))]
                                             [(VMaligned-concat x*)
                                              (let* ([x* (maplr vm-eval x*)]
                                                     [len* (map car x*)]
                                                     [alignment* (map (lambda (x len) (list-head (cdr x) len)) x* len*)]
                                                     [value* (map (lambda (x len) (list-tail (cdr x) len)) x* len*)])
                                                (append (list (apply + len*))
                                                        (apply append alignment*)
                                                        (apply append value*)))]
                                             [(VMvalue->int x)
                                              (let ([q (vmref-q x)])
                                                (unless (= 1 (length q))
                                                  (internal-errorf 'print-zkir (format "expected integer in VMvalue->int, got ~s" q)))
                                                `((ref . ,(car q))))]
                                             [(VMnull ty)
                                              (let* ([alignment (type->alignment ty)])
                                                (append (list (length alignment))
                                                        alignment
                                                        (null-for-alignment alignment)))]
                                             [(VMleaf-hash x)
                                              (let-values ([(value ty)
                                                            (cond
                                                              [(vmref? x) (values (map (lambda (q) (cons 'ref q)) (vmref-q x)) (vmref-type x))]
                                                              [(VMop? x)
                                                               (VMop-case x
                                                                 [(VMnull ty)
                                                                  (values (null-for-alignment (type->alignment ty)) ty)]
                                                                 [else (internal-errorf 'VMleaf-hash "expected vmref or VMnull, got ~s" x)])]
                                                              [else (internal-errorf 'VMleaf-hash "expected vmref or VMnull, got ~s" x)])])
                                                (let* ([alignment
                                                        (nanopass-case (Lflattened Type) ty
                                                          [(ty (,alignment* ...) (,primitive-type* ...))
                                                           alignment*])]
                                                       [value-refs (map (lambda (x) (if (pair? x) (cdr x) (literal x))) value)]
                                                       [domain-sep-string "mdn:lh"]
                                                       [domain-sep-bytes (bytevector->u8-list (string->utf8 domain-sep-string))]
                                                       [domain-sep-align (with-output-language (Lflattened Alignment)
                                                                                               `(abytes ,(length domain-sep-bytes)))]
                                                       [domain-sep-field (fold-right (lambda (byte acc) (+ byte (* 256 acc))) 0 domain-sep-bytes)]
                                                       [leaf1 (make-temp-id src 'leaf1)]
                                                       [leaf2 (make-temp-id src 'leaf2)])
                                                  (apply (hashtable-ref std-circuits 'persistentHash #f)
                                                         (list*
                                                           (list (list (cons domain-sep-align alignment)))
                                                           (list leaf1 leaf2)
                                                           (cons (literal domain-sep-field) value-refs)))
                                                  `(1 32 (ref . ,(var-idx leaf1)) (ref . ,(var-idx leaf2)))))]
                                             [(VMcoin-commit coin recipient)
                                              (let* ([coin (vmref-q coin)]
                                                     [recipient (vmref-q recipient)]
                                                     [abytes (lambda (n)
                                                               (with-output-language (Lflattened Alignment)
                                                                 `(abytes ,n)))]
                                                     [domain-sep-string "midnight:zswap-cc[v1]"]
                                                     [domain-sep-bytes (bytevector->u8-list (string->utf8 domain-sep-string))]
                                                     [domain-sep-field (fold-right (lambda (byte acc) (+ byte (* 256 acc))) 0 domain-sep-bytes)]
                                                     [data1 (make-temp-id src 'data1)]
                                                     [data2 (make-temp-id src 'data2)]
                                                     [hash1 (make-temp-id src 'hash1)]
                                                     [hash2 (make-temp-id src 'hash2)])
                                                (print-gate "cond_select" `[bit ,(car recipient)]
                                                                          `[a   ,(cadr recipient)]
                                                                          `[b   ,(cadddr recipient)])
                                                (new-var! data1 #f)
                                                (print-gate "cond_select" `[bit ,(car recipient)]
                                                                          `[a   ,(caddr recipient)]
                                                                          `[b   ,(car (cddddr recipient))])
                                                (new-var! data2 #f)
                                                (apply (hashtable-ref std-circuits 'persistentHash #f)
                                                       (list*
                                                         ;; alignment of `CoinPreimage` in std.compact
                                                         (list (list (list
                                                           (abytes (length domain-sep-bytes))
                                                           (abytes 32)
                                                           (abytes 32)
                                                           (abytes 16)
                                                           (abytes 1)
                                                           (abytes 32))))
                                                         (list hash1 hash2)
                                                         (append
                                                           (list (literal domain-sep-field))
                                                           coin
                                                           (list (car recipient))
                                                           (list (var-idx data1) (var-idx data2)))))
                                                `(1 32 (ref . ,(var-idx hash1)) (ref . ,(var-idx hash2))))]
                                             ;; There's room to tighten this in future, we just need to be careful to keep it
                                             ;; in-sync with the rust version.
                                             [(VMmax-sizeof ty)
                                              (let* ([alignment (type->alignment ty)]
                                                     [isize (lambda (n) (if (zero? n) 1 (ceiling (/ (integer-length n) 8))))]
                                                     [atom-len (lambda (atom) (if (< atom 0) 34 (+ 2 atom (isize atom))))]
                                                     [max-size (+ 1 (isize (length alignment)) (apply + (map atom-len alignment)))])
                                                (list max-size))]
                                             ;; Only handles literals x y
                                             [(VM+ x y)
                                              (let ([x (vm-eval x)]
                                                    [y (vm-eval y)])
                                                (unless (and (= (length x) 1)
                                                             (= (length y) 1)
                                                             (number? (car x))
                                                             (number? (car y)))
                                                  (internal-errorf 'print-zkir (format "VM+ in unexpected context: VM+ ~s ~s" x y)))
                                                (list (+ (car x) (car y))))]
                                             [else (internal-errorf 'print-zkir (format "unhandled vmop ~s" vmop))])]
                                          [(vmref? vmop)
                                           ;; // const foo = null[Set[Field]]();
                                           ;; ledger.bar.insert(/* foo */);
                                           (let ([q (vmref-q vmop)]
                                                 [alignment (type->alignment (vmref-type vmop))])
                                             (append (list (length alignment))
                                                     alignment
                                                     (maplr (lambda (q) (cons 'ref q)) q)))]
                                          [else (list vmop)]))]
                              [attr (lambda (name)
                                     (cdr (assoc (symbol->string name) (vminstr-arg* ins))))]
                              [eattr (lambda (name) (maplr (lambda (q) (if (pair? q) (cdr q) (literal q))) (vm-eval (attr name))))]
                              [emit-all (lambda (public-inputs)
                                          (unless (null? public-inputs)
                                            (for-each emit public-inputs)
                                            (print-gate "pi_skip"
                                                        `[guard ,test]
                                                        `[count ,(length public-inputs)])))])
                      ;; NOTE: This needs to be kept in sync with the FieldRepr
                      ;; implementation in midnight-onchain-runtime/src/ops.rs
                      (emit-all (case (vminstr-op ins)
                        ["noop" (map (lambda (_) (literal 0)) (iota (attr 'n)))]
                        ["lt" (list (literal 1))]
                        ["eq" (list (literal 2))]
                        ["type" (list (literal 3))]
                        ["size" (list (literal 4))]
                        ["new" (list (literal 5))]
                        ["and" (list (literal 6))]
                        ["or" (list (literal 7))]
                        ["neg" (list (literal 8))]
                        ["log" (list (literal 9))]
                        ["root" (list (literal 10))]
                        ["pop" (list (literal 11))]
                        ["popeq"
                         ;; Special case: We just create new variables and make
                         ;; them statements, without using the 'result value
                         ;; (because it isn't set). We first emit the alignment
                         (let ([alignment (type->alignment type)])
                           (append
                             (list (literal (if (attr 'cached) 13 12))
                                   (literal (length alignment)))
                             (maplr
                               (lambda (x) (if (pair? x) (cdr x) (literal x)))
                               alignment)
                             (maplr
                               (lambda (var)
                                 (if (equal? test (hashtable-ref literal-ht 1 #f))
                                     (print-gate "public_input" '[guard null])
                                     (print-gate "public_input" `[guard ,test]))
                                 (new-var! var #f)
                                 (var-idx var))
                               var-name*)))]
                        ["addi"
                         (list* (literal 14) (eattr 'immediate))]
                        ["subi"
                         (list* (literal 15) (eattr 'immediate))]
                        ["push"
                         (list* (literal (if (attr 'storage) 17 16))
                                (eattr 'value))]
                        ["branch"
                         (list* (literal 18) (eattr 'skip))]
                        ["jmp"
                         (list* (literal 19) (eattr 'skip))]
                        ["add" (list (literal 20))]
                        ["sub" (list (literal 21))]
                        ["concat"
                         (list* (literal (if (attr 'cached) 23 22))
                                (eattr 'n))]
                        ["member" (list (literal 24))]
                        ["rem" (list (literal (if (attr 'cached) 26 25)))]
                        ["dup" (list (literal (+ 48 (attr 'n))))]
                        ["swap" (list (literal (+ 64 (attr 'n))))]
                        ["idx"
                         (let* ([cached (attr 'cached)]
                                [push-path (attr 'pushPath)]
                                [raw-path (attr 'path)]
                                [path (if (and (VMop? raw-path) (VMop-case raw-path [(VMsuppress) #t] [else #f]))
                                          '()
                                          raw-path)]
                                [opcode-upper-nibble (cond
                                                      [(and (not cached) (not push-path)) 5]
                                                      [(and cached       (not push-path)) 6]
                                                      [(and (not cached) push-path)       7]
                                                      [(and cached       push-path)       8])])
                           (if (zero? (length path))
                               '()
                               (list* (literal (+ (* opcode-upper-nibble 16)
                                                  (sub1 (length path))))
                                      (maplr
                                        (lambda (elt)
                                          ;; The path element `elt` is either a literal or `(ref . n)` where n is the
                                          ;; index of a ZKIR instruction.
                                          (if (pair? elt) (cdr elt) (literal elt)))
                                        (apply append (maplr vm-eval path))))))]
                        ["ins" (if (VMop? (attr 'n))
                                   ; Means we have VMsuppress
                                   '()
                                   (list (literal (+ (if (attr 'cached) 160 144)
                                                     (attr 'n)))))]
                        ["ckpt" (list (literal 255))]
                        [else (internal-errorf 'print-zkir (format "unknown vm operation ~a" (vminstr-op ins)))]))))
                  (expand-vm-code src
                                  path-elt*
                                  #f
                                  (append (map cons adt-formal* adt-arg*)
                                          (map (lambda (ledger-op-formal type triv*)
                                                 (cons ledger-op-formal
                                                       (make-vmref type triv*)))
                                               ledger-op-formal*
                                               type*
                                               (group type* triv*)))
                                  (vm-code-code vm-code)))]))]
          [(assert ,src ,[* test] ,mesg)
           (print-gate "assert" `[cond ,test])]
          [else (internal-errorf 'print-zkir "unreachable")])
        (Path-Element : Path-Element (ir) -> * (str)
          [,path-index (VMalign path-index 1)]
          [(,src ,type ,[* triv*] ...) (make-vmref type triv*)])
        (Single : Single (ir) -> * (str)
          [,triv (print-gate "copy" `[var ,(Triv triv)])] ; not exercised when optimize-circuit is run
          ; TODO: is there any use to be made of mbits, which if not #f is the
          ; maximum number of bits occupied by the arguments and the result?
          [(+ ,mbits ,[* triv1] ,[* triv2])
           (print-gate "add" `[a ,triv1] `[b ,triv2])]
          [(- ,mbits ,[* triv1] ,[* triv2])
           (print-gate "neg" `[a ,triv2])
           (print-gate "add" `[a ,triv1] `[b ,ctr])
           (set! ctr (add1 ctr))]
          [(* ,mbits ,[* triv1] ,[* triv2])
           (print-gate "mul" `[a ,triv1] `[b ,triv2])]
          [(< ,mbits ,[* triv1] ,[* triv2])
           (print-gate "less_than" `[a ,triv1] `[b ,triv2] `[bits ,mbits])]
          [(== ,[* triv1] ,[* triv2])
           (print-gate "test_eq" `[a ,triv1] `[b ,triv2])]
          [(bytes-ref ,[* triv] ,nat)
           (print-gate "div_mod_power_of_two" `[var ,triv] `[bits ,(* nat 8)])
           (let ([q ctr])
             (set! ctr (+ ctr 2))
             ; FIXME: is there a better way to mask the higher bits?
             (print-gate "div_mod_power_of_two" `[var ,q] `[bits ,8])
             (set! ctr (add1 ctr)))]
          ; FIXME: zkir bytes->field needs to respect test
          [(bytes->field ,src ,[* test] ,len ,[* triv1] ,[* triv2])
           (if (<= len (field-bytes))
               ; flattened-datatype takes care of this case, so this line can't presently be reached
               (print-gate "copy" `[var ,triv2])
               (print-gate "reconstitute_field" `[divisor ,triv1] `[modulus ,triv2] `[bits ,(* 8 (field-bytes))]))]
          [(vector->bytes ,[* triv] ,[* triv*] ...)
           (if (null? triv*)
               (print-gate "copy" `[var ,triv])
               (let f ([triv triv] [triv+ triv*])
                 (let ([d (let ([triv (car triv+)] [triv* (cdr triv+)])
                            (if (null? triv*)
                                triv
                                (begin
                                  (f triv triv*)
                                  (let ([d ctr]) (set! ctr (add1 ctr)) d))))])
                   (print-gate "reconstitute_field" `[divisor ,d] `[modulus ,triv] `[bits 8]))))]
          ; FIXME: zkir downcast-unsigned needs to respect test
          [(downcast-unsigned ,src ,[* test] ,nat ,[* triv])
           (constrain-type (with-output-language (Lflattened Primitive-Type)
                                                 `(tfield ,nat))
                           triv)
           (print-gate "copy" `[var ,triv])]
          [(select ,[* triv0] ,[* triv1] ,[* triv2])
           (print-gate "cond_select" `[bit ,triv0] `[a ,triv1] `[b ,triv2])])
        (Triv : Triv (ir) -> * (str)
          [,var-name (var-idx var-name)]
          [,nat (literal nat)])
      )

      (define circuit (extract-entry-point prog entry-point))
      (print-zkir$ circuit))
    (for-each
      (lambda (a)
        (parameterize ([current-output-port (cdr a)])
          (print-zkir ir (car a))))
      (target-ports))
    ir)

  (define-passes zkir-passes
    (print-zkir                      Lflattened))
)
