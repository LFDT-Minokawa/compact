;;; This file is part of Compact.
;;; Copyright (C) 2025 Midnight Foundation
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

#!chezscheme

(library (zkir-v3-passes)
  (export zkir-v3-passes)
  (import (except (chezscheme) errorf)
    (utils)
    (datatype)
    (nanopass)
    (langs)
    (pass-helpers)
    (natives)
    (ledger)
    (vm)
    (json))

  (define-pass reduce-to-zkir : Lflattened (ir) -> Lzkir ()
    (definitions
      ;; ==== Per-program state ====
      ;; Mapping IR circuit names to their export name(s).
      (define export-ht (make-eq-hashtable))

      (define (exported-circuit? pelt)
        (nanopass-case (Lflattened Program-Element) pelt
          [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
           (hashtable-contains? export-ht function-name)]
          [else #f]))

      ;; Handling calls (to witnesses and natives) in the IR.  There is a table of code generators
      ;; for witness-like callables and external natives.
      (define callable-ht (make-eq-hashtable))

      (define (make-witness primitive-type*)
        (lambda (var-name* test triv* instr*)
          (with-output-language (Lzkir Instruction)
            ;; TODO(kmillikin): this might insert an unused load_imm.  If so, elimitate it.
            (let-values ([(test-var instr*) (Triv test instr*)])
              (let* ([instr* (fold-left
                               (lambda (instr* triv)
                                 (let-values ([(_ instr*) (Triv triv instr*)])
                                   instr*))
                               instr* triv*)])
                (fold-left
                  (lambda (instr* var-name primitive-type)
                    (let* ([var (allocate-var var-name)]
                           ;; The ZKIR v2 backend has this special case for literal true guards.
                           [instr* (cons (if (eq? test 1)
                                             `(private_input)
                                             `(private_input ,test-var))
                                     instr*)])
                      (emit-constraints-for var primitive-type instr*)))
                  instr* var-name* primitive-type*))))))

      (define (make-native name arg*)
        ;; Get the list of alignment atoms for a 0-based arg index.
        (define (arg->alignment arg* index)
          (nanopass-case (Lflattened Argument) (list-ref arg* index)
            [(argument (,var-name ...) (ty (,alignment* ...) (,primitive-type* ...)))
             alignment*]))
        (lambda (var-name* test triv* instr*)
          (with-output-language (Lzkir Instruction)
            ;; TODO(kmillikin): this might insert an unused load_imm.  If so, elimitate it.
            (let*-values ([(test-var instr*) (Triv test instr*)]
                          [(input-var* instr*)
                           (let loop ([triv* triv*] [instr* instr*] [var* '()])
                             (if (null? triv*)
                                 (values (reverse var*) instr*)
                                 (let-values ([(var instr*) (Triv (car triv*) instr*)])
                                   (loop (cdr triv*) instr* (cons var var*)))))])
              ;; Generally assume that the arity is correct here.
              (case name
                [(degradeToTransient)
                 (bind (car var-name*) (cadr input-var*))
                 instr*]
                [(ecAdd)
                 (for-each allocate-var var-name*)
                 (cons (apply (lambda (ax ay bx by) `(ec_add ,ax ,ay ,bx ,by)) input-var*)
                   instr*)]
                [(ecMul)
                 (for-each allocate-var var-name*)
                 (cons (apply (lambda (ax ay scalar) `(ec_mul ,ax ,ay ,scalar)) input-var*)
                   instr*)]
                [(ecMulGenerator)
                 (for-each allocate-var var-name*)
                 (cons `(ec_mul_generator ,(car input-var*)) instr*)]
                [(hashToCurve)
                 (for-each allocate-var var-name*)
                 (cons `(hash_to_curve ,input-var* ...) instr*)]
                [(persistentCommit)
                 (for-each allocate-var var-name*)
                 ;; The two source arguments are swapped for the persistent_hash gate.  We assume
                 ;; that the second argument is `(tbytes 32)` so it consumes two variables and we
                 ;; know its alignment is `(abytes 32)`.
                 (let ([var* (syntax-case input-var* ()
                               [(a ... b c) #'(b c a ...)])]
                       [alignment* (append (arg->alignment arg* 1) (arg->alignment arg* 0))])
                   (cons `(persistent_hash (,alignment* ...) ,var* ...) instr*))]
                [(persistentHash)
                 (for-each allocate-var var-name*)
                 (let ([alignment* (arg->alignment arg* 0)])
                   (cons `(persistent_hash (,alignment* ...) ,input-var* ...) instr*))]
                [(transientCommit)
                 (allocate-var (car var-name*))
                 ;; The last input needs to be moved first.
                 (let ([var* (syntax-case input-var* ()
                               [(a ... b) #'(b a ...)])])
                   (cons `(transient_hash ,var* ...) instr*))]
                [(transientHash)
                 (allocate-var (car var-name*))
                 (cons `(transient_hash ,input-var* ...) instr*)]
                [else
                  (fprintf (current-error-port) "unknown native: ~s\n" name)
                  (assert not-implemented)])))))

      (define (declare-callable pelt)
        (nanopass-case (Lflattened Program-Element) pelt
          [(witness ,src ,function-name (,arg* ...) (ty (,alignment* ...)
                                                      (,primitive-type* ...)))
           (assert (not (hashtable-contains? callable-ht function-name))) 
           (hashtable-set! callable-ht function-name (make-witness primitive-type*))]
          [(external ,src ,function-name ,native-entry (,arg* ...) (ty (,alignment* ...)
                                                                     (,primitive-type* ...)))
           (assert (not (hashtable-contains? callable-ht function-name)))
           (hashtable-set! callable-ht function-name
             (if (eq? (native-entry-class native-entry) 'witness)
                 (make-witness primitive-type*)
                 (make-native (native-entry-name native-entry) arg*)))]
          [else (void)]))

      ;; ==== Impact Assembler ====
      (define (assert-byte n)
        (assert (and (fixnum? n) (fx<= 0 n #xff))))

      (define (assert-nibble n)
        (assert (and (fixnum? n) (fx<= 0 n #xf))))

      ;; Impact opcodes are one byte, sometimes with an operand encoded in the low nibble.  It's
      ;; convenient to combine high and low nibbles.
      (define (combine hi lo)
        (assert-nibble hi)
        (assert-nibble lo)
        (fxlogor (fxsll hi 4) lo))

      ;; The ZKIR encoding of an Impact instruction consists of a sequence of "codes", where each
      ;; code can be either a literal byte value or an Lzkir variable (instruction output).
      (define-datatype Impact-code
        [Ie-imm n]
        [Ie-var n])

      ;; Encode a VM operand, collecting codes in reverse.
      (define (assemble-operand-acc code* rand)
        (define (public-adt type)
          (nanopass-case (Lflattened Type) type
            [(ty (,alignment ...) (,primitive-type))
             (guard (Lflattened-Public-Ledger-ADT? primitive-type))
             primitive-type]
            [else #f]))
        ;; Operands can be one of:
        ;;   - zkir-val, typed Lzkir outputs consisting of a list of
        ;;     alignment atoms and a list of instruction outputs
        ;;   - integer literals
        ;;   - VMop, whose datatype definition is in vm.ss
        (cond
          [(zkir-val? rand)
           (let ([code* (fold-left (lambda (code* a)
                                     (cons (assemble-alignment-atom a) code*))
                          (cons (Ie-imm (length (zkir-val-alignment* rand))) code*)
                          (zkir-val-alignment* rand))])
             (fold-left (lambda (code* var) (cons (Ie-var var) code*))
               code* (zkir-val-var* rand)))]
          [(not (VMop? rand)) (cons (Ie-imm rand) code*)]
          [else
            (VMop-case rand
              [(VMstack) (cons (Ie-imm -1) code*)]
              [(VMalign value bytes)
               (assert-byte bytes)
               ;; Encoding is length=1 bytes value (in reverse).
               (assemble-operand-acc (cons* (Ie-imm bytes) (Ie-imm 1) code*) value)]
              [(VMvalue->int x)
               (let ([var* (zkir-val-var* x)])
                 (assert (and (list? var*) (= 1 (length var*))))
                 (cons (Ie-var (car var*)) code*))]
              [(VMstate-value-null) (cons (Ie-imm 0) code*)]
              [(VMstate-value-cell val) (assemble-operand-acc (cons (Ie-imm 1) code*) val)]
              [(VMstate-value-ADT val type)
               (let ([adt (public-adt type)])
                 (if (not adt)
                     (assemble-operand-acc (cons (Ie-imm 1) code*) val)
                     (nanopass-case (Lflattened Public-Ledger-ADT) adt
                       [(,src ,adt-name ((,adt-formal* ,adt-arg*) ...) ,vm-expr (,adt-op* ...))
                        (assemble-operand-acc code*
                          (expand-vm-expr src
                            (map cons adt-formal* adt-arg*)
                            (vm-expr-expr vm-expr)))])))]
              [(VMstate-value-map key* val*)
               (fold-left assemble-operand-acc
                 (fold-left assemble-operand-acc
                   (cons (Ie-imm (combine (length key*) 2)) code*)
                   key*)
                 val*)]
              [(VMstate-value-merkle-tree nat key* val*)
               (fold-left assemble-operand-acc
                 (fold-left assemble-operand-acc
                   ;; Tag with length(key*) << 8 | combine(nat, 4)
                   (cons (Ie-imm (fxlogor (fxsll (length key*) 8) (combine nat 4))) code*)
                   key*)
                 val*)]
              [(VMstate-value-array val*)
               (fold-left assemble-operand-acc
                 (cons (Ie-imm (combine (length val*) 3)) code*)
                 val*)]
              [else
                (fprintf (current-error-port) "rand: ~s\n" rand)
                (assert not-implemented)])]))

      (define (assemble-operand rand)
        (reverse (assemble-operand-acc '() rand)))

      ;; The ZKIR representation of a Minokawa value.  It consists of a sequence of Lflattened
      ;; alignment atoms and a parallel sequence of Lzkir variables (instruction outputs).
      (define-record-type zkir-val
        (nongenerative)
        (fields alignment* var*))

      ;; Encode a path.
      (define (assemble-path path)
        (reverse (fold-left assemble-operand-acc '() path)))

      ;; Map an Impact VM alignment to a ZKIR operand (which might be negative).
      (define (assemble-alignment-atom atom)
        (Ie-imm (nanopass-case (Lflattened Alignment) atom
                  [(abytes ,nat) nat]
                  [(acompress) -1]
                  [(afield) -2]
                  [(aadt) -3]
                  [(acontract) -4])))

      ;; Map an impact instruction to a list of ZKIR Impact operands.
      (define (assemble1 impact-instr var-name* alignment*)
        (define (suppress? rand)
          (and (VMop? rand)
               (VMop-case rand [(VMsuppress) #t] [else #f])))
        ;; The arguments are an association list with string keys.
        (let ([rands (vminstr-arg* impact-instr)])
          (case (vminstr-op impact-instr)
            ;; lt --> 0x01
            [("lt") (list (Ie-imm #x01))]

            ;; eq --> 0x02
            [("eq") (list (Ie-imm #x02))]

            ;; type --> 0x03
            [("type") (list (Ie-imm #x03))]

            ;; size --> 0x04
            [("size") (list (Ie-imm #x04))]

            ;; neg --> 0x08
            [("neg") (list (Ie-imm #x08))]

            ;; root --> 0x0a
            [("root") (list (Ie-imm #x0a))]

            ;; popeq  --> 0x0c result
            ;; popeqc --> 0x0d result
            ;; This instruction occurs at most once in a program, so it's OK to allocate indexes for
            ;; the variable names.
            [("popeq")
             (let* ([output-vars (maplr (lambda (vn) (Ie-var (allocate-var vn))) var-name*)]
                    [alignment (map assemble-alignment-atom alignment*)])
               (cons*
                 (Ie-imm (if (cdr (assoc "cached" rands)) #xd #xc))
                 (Ie-imm (length alignment))
                 (append alignment output-vars)))]

            ;; addi --> 0x0e state
            [("addi")
             (cons (Ie-imm #xe) (assemble-operand (cdr (assoc "immediate" rands))))]

            ;; subi --> 0x0f state
            [("subi")
             (cons (Ie-imm #xf) (assemble-operand (cdr (assoc "immediate" rands))))]

            ;; push  --> 0x10 state
            ;; pushs --> 0x11 state
            [("push")
             (let ([code* (assemble-operand (cdr (assoc "value" rands)))])
               (cons (Ie-imm (if (cdr (assoc "storage" rands)) #x11 #x10)) code*))]

            ;; branch --> 0x12 u21
            [("branch")
             (let ([n (cdr (assoc "skip" rands))])
               ;; TODO(kmillikin): Is this guaranteed to be in range?
               (assert (<= (integer-length n) 21))
               (list (Ie-imm #x12) (Ie-imm n)))]

            ;; add --> 0x14
            [("add") (list (Ie-imm #x14))]

            ;; member --> 0x18
            [("member") (list (Ie-imm #x18))]

            ;; rem  --> 0x19
            ;; remc --> 0x1a
            [("rem") (list (Ie-imm (if (cdr (assoc "cached" rands)) #x1a #x19)))]

            ;; dup n --> 0x3n
            [("dup") (list (Ie-imm (combine #x3 (cdr (assoc "n" rands)))))]

            ;; swap n --> 0x4n
            [("swap") (list (Ie-imm (combine #x4 (cdr (assoc "n" rands)))))]

            ;; idx path   --> 0x5n [path], where n is length(path)-1
            ;; idxc path  --> 0x6n [path]
            ;; idxp path  --> 0x7n [path]
            ;; idxpc path --> 0x8n [path]
            [("idx")
             (let ([hi (if (cdr (assoc "pushPath" rands))
                           (if (cdr (assoc "cached" rands)) #x8 #x7)
                           (if (cdr (assoc "cached" rands)) #x6 #x5))]
                   [path (cdr (assoc "path" rands))])
               (if (suppress? path)
                   '()
                   (begin
                     (assert (not (null? path)))
                     (cons (Ie-imm (combine hi (1- (length path)))) (assemble-path path)))))]

            ;; ins n  --> 0x9n
            ;; insc n --> 0xan
            [("ins")
             (let ([hi (if (cdr (assoc "cached" rands)) #xa #x9)]
                   [n (cdr (assoc "n" rands))])
               (if (suppress? n)
                   '()
                   (list (Ie-imm (combine hi n)))))]

            [else
              (fprintf (current-error-port) "Instruction ~s\n" impact-instr)
              (assert not-implemented)])))

      ;; We patch up popeq and popeqc instructions.
      (define (popeq? code*)
        (and (pair? code*)
             (Impact-code-case (car code*)
               [(Ie-imm n) (<= #xc n #xd)]
               [else #f])))

      (define (assemble test-var alignment* var-name* src path env vm-code instr*)
        (let ([code (expand-vm-code src path #f env (vm-code-code vm-code))])
          (with-output-language (Lzkir Instruction)
            (fold-left
              (lambda (instr* impact-instr)
                (let ([code* (assemble1 impact-instr var-name* alignment*)])
                  ;; A "suppress" operand was an instruction to skip the instruction, empty code.
                  (if (null? code*)
                      instr*
                      ;; There is at most one popeq.  It needs public_input instructions for each
                      ;; result, they're emitted here before any load_imm to match the ZKIR v2
                      ;; implementation.
                      (let ([instr* (if (not (popeq? code*))
                                        instr*
                                        (fold-left
                                          (lambda (instr* var-name)
                                            (cons
                                              ;; A weird case duplicated from ZKIR v2.
                                              (if (eq? test-var (hashtable-ref immediate-ht 1 #f))
                                                  `(public_input)
                                                  `(public_input ,test-var))
                                              instr*))
                                          instr* var-name*))])
                        ;; The ZKIR v2 implementation emits all the load_imm before any
                        ;; declare_pub_input.  That's not necessary but we maintain that behavior
                        ;; for now to avoid rebasing all our tests.
                        (let-values ([(vars instr*)
                                      (let loop ([code* code*] [vars '()] [instr* instr*])
                                        (if (null? code*)
                                            (values (reverse vars) instr*)
                                            (Impact-code-case (car code*)
                                              [(Ie-imm n)
                                               (let-values ([(var instr*) (emit-immediate n instr*)])
                                                 (loop (cdr code*) (cons var vars) instr*))]
                                              [(Ie-var n) (loop (cdr code*) (cons n vars) instr*)])))])
                          (let ([instr* (fold-left (lambda (instr* var)
                                                     (cons `(declare_pub_input ,var) instr*))
                                          instr* vars)])
                            (cons `(pi_skip ,test-var ,(length vars)) instr*)))))))
              instr* code))))

      ;; ==== Per-circuit state ====
      (define next-index)
      (define environment-ht)
      (define immediate-ht)

      ;; Reset the per-circuit state.
      (define (reset-state!)
        (set! next-index 0)
        (set! environment-ht (make-eq-hashtable))
        (set! immediate-ht (make-eq-hashtable)))

      ;; Allocate and return the next available output index.
      (define (allocate-index)
        (let ([index next-index])
          (set! next-index (1+ index))
          index))

      ;; Allocate an output index for a variable name, returning the index.
      (define (allocate-var name)
        ;; Names in Lflattened should be unique.
        (assert (not (hashtable-contains? environment-ht name)))
        (let ([index (allocate-index)])
          (hashtable-set! environment-ht name index)
          index))

      ;; Bind an existing output index to a variable name.
      (define (bind name index)
        (assert (and (not (hashtable-contains? environment-ht name))
                     (< index next-index)))
        (hashtable-set! environment-ht name index))

      ;; Lookup a variable's index.
      (define (lookup name)
        (assert (hashtable-contains? environment-ht name))
        (hashtable-ref environment-ht name #f))

      ;; Return the index of a load_imm for a field constant, reusing an existing one if possible.
      ;; Accumulates instructions.
      (define (emit-immediate nat instr*)
        (let ([existing (hashtable-ref immediate-ht nat #f)])
          (if existing
              (values existing instr*)
              (with-output-language (Lzkir Instruction)
                (let ([index (allocate-index)])
                  (hashtable-set! immediate-ht nat index)
                  (values index (cons `(load_imm ,nat) instr*)))))))

      ;; Accumulate a list of instructions to constrain an output index given an expected primitive
      ;; type.
      (define (emit-constraints-for index type instr*)
        (nanopass-case (Lflattened Primitive-Type) type
          [(topaque ,opaque-type) instr*]
          [(tfield) instr*]
          [(tfield ,nat)
           (with-output-language (Lzkir Instruction)
             (cond
               [(zero? nat)
                (let-values ([(zero instr*) (emit-immediate 0 instr*)])
                  (cons `(constrain_eq ,index ,zero) instr*))]
               [(= 1 nat)
                (cons `(constrain_to_boolean ,index) instr*)]
               ;; nat is one less than a power of 2.
               [(zero? (bitwise-and nat (1+ nat)))
                (cons `(constrain_bits ,index ,(integer-length nat)) instr*)]
               [else
                   ;; Compute the bits required to represent nat.  Plonk requires this to be a
                   ;; multiple of two, so instead of ⌈log_2(nat + 1)⌉, we compute k = ⌈log_4(nat +
                   ;; 1)⌉: the smallest exponent for which nat + 1 <= 4^k, and therefore nat <
                   ;; 2^(2k) with 2k being guaranteed to be even.  Note that we need need nat + 1,
                   ;; at nat itself is a valid assignment, and the final check is a less-than check.
                 (let ([bits (* 2 (quotient (+ (integer-length (+ 1 nat)) 1) 2))])
                   (let*-values ([(bound instr*) (emit-immediate (1+ nat) instr*)]
                                 [(var instr*) (values (allocate-index)
                                                 (cons `(less_than ,index ,bound ,bits) instr*))])
                     (cons `(assert ,var) instr*)))]))]
          [else (assert cannot-happen)]))

      ;; Turn an Lflattened argument list into a list of names and a parallel list of types.
      (define unzip-arguments
        (lambda (arg*)
          (if (null? arg*)
              (values '() '())
              (let-values ([(name* type*) (unzip-arguments (cdr arg*))])
                (nanopass-case (Lflattened Argument) (car arg*)
                  [(argument (,var-name* ...) (ty (,alignment* ...) (,primitive-type* ...)))
                   (values (append var-name* name*) (append primitive-type* type*))])))))
      )

    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       ;; The mapping from input language circuit names to exported names is one to many, the same
       ;; circuit can be exported under different names.  Build a hashtable from circuit name to
       ;; exported names.
       (for-each (lambda (export-name name)
                   (hashtable-set! export-ht name
                     (cons export-name (hashtable-ref export-ht name '()))))
         export-name* name*)

       ;; Process witness and external declarations in a separate pass over the program elements
       ;; because we don't assume that they precede their uses (that's not enforced by the syntax).
       (for-each declare-callable pelt*)
       
       ;; TODO(kmillikin): this will compile exported pure circuits.  If there is no difference in
       ;; error behavior, we could consider skipping them here or even eliminating them earlier.
       `(program ,src
          ,(fold-right
             (lambda (pelt cdefn*)
               (if (exported-circuit? pelt)
                   (cons (Circuit-Definition pelt) cdefn*)
                   cdefn*))
               '() pelt*) ...)])

    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
       ;; - Replace the internal name with the exported ones
       ;; - Replace inputs with their count
       ;; - Insert type constraints for inputs
       ;; - Translate the statements in the body
       ;; - Add instructions for the outputs
       (reset-state!)
       (let-values ([(name* type*) (unzip-arguments arg*)])
         ;; Allocate the first N indexes for the input names before emitting any instructions.
         (for-each allocate-var name*)
         (let* ([constraint*
                  (fold-left (lambda (constraint* name type)
                               (emit-constraints-for (lookup name) type constraint*))
                    '() name* type*)]
                [instr*
                  (fold-left (lambda (instr* stmt) (Statement stmt instr*))
                    constraint* stmt*)]
                [body
                  (fold-left (lambda (body triv)
                               (with-output-language (Lzkir Instruction)
                                 (let-values ([(var instr*) (Triv triv body)])
                                   (cons `(output ,var) instr*))) )
                    instr* triv*)])
           `(circuit ,src (,(hashtable-ref export-ht function-name '()) ...) ,(length name*)
              ,(reverse body) ...)))])

    (Statement : Statement (ir instr*) -> * (instr*)
      [(= (,var-name* ...) (call ,src ,test ,function-name ,triv* ...))
       (let ([code-generator (hashtable-ref callable-ht function-name #f)])
         (assert code-generator)
         (code-generator var-name* test triv* instr*))]
      [(= (,var-name0 ,var-name1) (field->bytes ,src ,test ,len ,triv))
       ;; TODO(kmillikin): this needs to respect test because `constrain_bits` can fail.
       (with-output-language (Lzkir Instruction)
         (if (<= len (field-bytes))
             (let*-values ([(var0 instr*) (emit-immediate 0 instr*)]
                           [(var1 instr*) (Triv triv instr*)])
               ;; Hacky manual update of the environment for the outputs, they are existing values
               ;; and not fresh instruction outputs.
               (hashtable-set! environment-ht var-name0 var0)
               (hashtable-set! environment-ht var-name1 var1)
               (cons `(constrain_bits ,var1 ,(* len 8)) instr*))
             (let-values ([(var instr*) (Triv triv instr*)])
               (allocate-var var-name0)
               (allocate-var var-name1)
               (cons `(div_mod_power_of_two ,var ,(* (field-bytes) 8)) instr*))))]
      [(= (,var-name* ...) (public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...)
                             ,src^ ,adt-op ,triv* ...))
       (nanopass-case (Lflattened ADT-Op) adt-op
         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...)
            (,type* ...) (ty (,alignment* ...) (,primitive-type* ...)) ,vm-code)
          (let*-values
              ([(test-var instr*) (Triv test instr*)]
               [(path instr*)
                (let loop ([path-elt* path-elt*] [path '()] [instr* instr*])
                  (if (null? path-elt*)
                      (values (reverse path) instr*)
                      (let-values ([(operand instr*) (Path-Element (car path-elt*) instr*)])
                        (loop (cdr path-elt*) (cons operand path) instr*))))]
               ;; Expansion of the Impact code needs an environment mapping the formals to their
               ;; values.  The arguments triv* are flat but they need to be nested according to the
               ;; structure of type*.
               [(env instr*)
                ;; Walk in lockstep down type* and formal*, peeling off triv*s.
                (let outer ([type* type*] [formal* ledger-op-formal*] [triv* triv*]
                            ;; Start with an environment that has the ADT formals.
                            [env (map cons adt-formal* adt-arg*)]
                            [instr* instr*])
                  (if (null? type*)
                      (begin
                        (assert (and (null? formal*) (null? triv*)))
                        (values env instr*))
                      (nanopass-case (Lflattened Type) (car type*)
                        ;; primitive-type* tells us how many triv*s to peel off.
                        [(ty (,alignment* ...) (,primitive-type* ...))
                         (let-values
                             ([(var* triv* instr*)
                               (let inner ([pt* primitive-type*] [triv* triv*] [var* '()]
                                           [instr* instr*])
                                 (if (null? pt*)
                                     (values (reverse var*) triv* instr*)
                                     (let-values ([(var instr*) (Triv (car triv*) instr*)])
                                       (inner (cdr pt*) (cdr triv*) (cons var var*)
                                         instr*))))])
                           ;; Pair the alignment* atoms with the triv*s, bind to the formal,
                           ;; and loop.
                           (outer (cdr type*) (cdr formal*) triv*
                             (cons (cons (car formal*) (make-zkir-val alignment* var*))
                               env)
                             instr*))])))])
            (assemble test-var alignment* var-name* src path env vm-code instr*))])]
      [(= ,var-name ,single)
       (Single single var-name instr*)]
      [(assert ,src ,test ,mesg)
       (with-output-language (Lzkir Instruction)
         (let-values ([(var instr*) (Triv test instr*)])
           (cons `(assert ,var) instr*)))]
      [else (assert cannot-happen)])

    (Single : Single (ir var-name instr*) -> * (instr*)
      [(+ ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)])
           (allocate-var var-name)
           (cons `(add ,var0 ,var1) instr*)))]
      [(- ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)]
                       [(var2 instr*) (values (allocate-index) (cons `(neg ,var1) instr*))])
           (allocate-var var-name)
           (cons `(add ,var0 ,var2) instr*)))]
      [(* ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)])
           (allocate-var var-name)
           (cons `(mul ,var0 ,var1) instr*)))]
      [(< ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)])
           (allocate-var var-name)
           (cons `(less_than ,var0 ,var1 ,mbits) instr*)))]
      [(== ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)])
           (allocate-var var-name)
           (cons `(test_eq ,var0 ,var1) instr*)))]
      [(select ,triv0 ,triv1 ,triv2)
       (with-output-language (Lzkir Instruction)
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)]
                       [(var2 instr*) (Triv triv2 instr*)])
           (allocate-var var-name)
           (cons `(select ,var0 ,var1 ,var2) instr*)))]
      [(bytes->field ,src ,test ,len ,triv0 ,triv1)
       ;; TODO(kmillikin): This should respect test and be conditional in the ZKIR output.
       (with-output-language (Lzkir Instruction)
         ;; flatten-datatype takes care of this case.
         (assert (> len (field-bytes)))
         (let*-values ([(var0 instr*) (Triv triv0 instr*)]
                       [(var1 instr*) (Triv triv1 instr*)])
           (allocate-var var-name)
           (cons `(reconstitute_field ,var0 ,var1 ,(* 8 (field-bytes))) instr*)))]
      [(downcast-unsigned ,src ,test ,nat ,triv)
       ;; TODO(kmillikin): This needs to be conditional on test.
       (with-output-language (Lzkir Instruction)
         (let-values ([(var instr*) (Triv triv instr*)])
           (let ([instr* (emit-constraints-for var
                           (with-output-language (Lflattened Primitive-Type) `(tfield ,nat))
                           instr*)])
             ;; TODO(kmillikin): The `copy` here is unnecessary.  Remove it.
             (allocate-var var-name)
             (cons `(copy ,var) instr*))))]
      [else (assert cannot-happen)])

    ;; Path elements are either literals or Lflattened typed sequences of triv values.  Represent
    ;; the latter by the pair of the sequence of alignments and the sequence of ZKIR outputs.
    (Path-Element : Path-Element (ir instr*) -> * (operand instr*)
      [,path-index (values (VMalign path-index 1) instr*)]  ; <-- length in bytes is 1
      [(,src ,type ,triv* ...)
       (let-values ([(var* instr*)
                     (let loop ([triv* triv*] [var* '()] [instr* instr*])
                       (if (null? triv*)
                           (values (reverse var*) instr*)
                           (let-values ([(var instr*) (Triv (car triv*) instr*)])
                             (loop (cdr triv*) (cons var var*) instr*))))])
         (nanopass-case (Lflattened Type) type
           [(ty (,alignment* ...) (,primitive-type* ...))
            (values (make-zkir-val alignment* var*) instr*)]))])

    (Triv : Triv (ir instr*) -> * (nat instr*)
      [,var-name (values (lookup var-name) instr*)]
      [,nat (emit-immediate nat instr*)])
    )

  (define-pass print-zkir-v3 : Lzkir (ir) -> Lzkir ()
    (definitions
      (define (alignment-atom->alist atom)
        (nanopass-case (Lflattened Alignment) atom
          [(acompress) `((tag . "atom") (value . ((tag . "compress"))))]
          [(abytes ,nat) `((tag . "atom") (value . ((length . ,nat) (tag . "bytes"))))]
          [(afield) `((tag . "atom") (value . ((tag . "field"))))]
          ;; Alignment for ADT and contract types can't appear?
          [else (assert cannot-happen)]))
      (define (alignment->vector alignment*)
        (list->vector (map alignment-atom->alist alignment*)))
      ;; Field representations (which *can* be negative) are represented with a leading sign and
      ;; then hexadecimal byte values in little endian order.
      (define (field-rep->string fr)
        (call-with-string-output-port
          (lambda (sp)
            (let ([fr (if (< fr 0)
                          (begin (put-char sp #\-) (- fr))
                          fr)])
              (let loop ([fr fr])
                (if (< fr 256)
                    (fprintf sp "~2,'0x" fr)
                    (begin (fprintf sp "~2,'0x" (remainder fr 256))
                           (loop (quotient fr 256)))))))))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ,[] ...) ir])
    (Circuit-Definition : Circuit-Definition (ir) -> * ()
      [(circuit ,src (,name* ...) ,arg-count ,instr* ...)
       (define (print-circuit op)
         (print-json-compact op
           `((version . ((major . 3) (minor . 0)))
             (do_communications_commitment . ,(not (no-communications-commitment)))
             (num_inputs . ,arg-count)
             (instructions . ,(list->vector (map Instruction instr*))))))
       (let ([output-port*
               (fold-left (lambda (output-port* name)
                            (let ([target (assq name (target-ports))])
                              (if target
                                  (cons (cdr target) output-port*)
                                  output-port*)))
                 '() name*)])
         ;; Exported pure circuits are in the IR but don't have any corresponding target ports.
         (when (not (null? output-port*))
           (if (null? (cdr output-port*))
               ;; Directly print it to the port.
               (print-circuit (car output-port*))

               ;; Stringify it first.
               (let ([str (call-with-string-output-port print-circuit)])
                 (for-each (lambda (op) (put-string op str)) output-port*)))))])
    (Instruction : Instruction (ir) -> * (json)
      [(add ,var0 ,var1)
       `((op . "add") (a . ,var0) (b . ,var1))]
      [(assert ,var)
       `((op . "assert") (cond . ,var))]
      [(constrain_bits ,var ,imm)
       `((op . "constrain_bits") (var . ,var) (bits . ,imm))]
      [(constrain_eq ,var0 ,var1)
       `((op . "constrain_eq") (a . ,var0) (b . ,var1))]
      [(constrain_to_boolean ,var)
       `((op . "constrain_to_boolean") (var . ,var))]
      [(copy ,var)
       `((op . "copy") (var . ,var))]
      [(declare_pub_input ,var)
       `((op . "declare_pub_input") (var . ,var))]
      [(div_mod_power_of_two ,var ,imm)
       `((op . "div_mod_power_of_two") (var . ,var) (bits . ,imm))]
      [(ec_add ,var0 ,var1 ,var2 ,var3)
       `((op . "ec_add") (a_x . ,var0) (a_y . ,var1) (b_x . ,var2) (b_y . ,var3))]
      [(ec_mul ,var0 ,var1 ,var2)
       `((op . "ec_mul") (a_x . ,var0) (a_y . ,var1) (scalar . ,var2))]
      [(ec_mul_generator ,var)
       `((op . "ec_mul_generator") (scalar . ,var))]
      [(hash_to_curve ,var* ...)
       `((op . "hash_to_curve") (inputs . ,(list->vector var*)))]
      [(less_than ,var0 ,var1 ,imm)
       `((op . "less_than") (a . ,var0) (b . ,var1) (bits . ,imm))]
      [(load_imm ,fr)
       `((op . "load_imm") (imm . ,(field-rep->string fr)))]
      [(mul ,var0 ,var1)
       `((op . "mul") (a . ,var0) (b . ,var1))]
      [(neg ,var)
       `((op . "neg") (a . ,var))]
      [(output ,var)
       `((op . "output") (var . ,var))]
      [(persistent_hash (,alignment* ...) ,var* ...)
       `((op . "persistent_hash")
         (alignment . ,(alignment->vector alignment*))
         (inputs . ,(list->vector var*)))]
      [(pi_skip ,var ,imm)
       `((op . "pi_skip") (guard . ,var) (count . ,imm))]
      [(private_input)
       ;; Kind of warty: rather than a literal true (load_imm `1`) guard or making it truly optional
       ;; by leaving it out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "private_input") (guard . ,(void)))]
      [(private_input ,var)
       `((op . "private_input") (guard . ,var))]
      [(public_input)
       ;; Kind of warty: rather than a literal true (load_imm `1`) guard or making it truly optional
       ;; by leaving it out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "public_input") (guard . ,(void)))]
      [(public_input ,var)
       `((op . "public_input") (guard . ,var))]
      [(reconstitute_field ,var0 ,var1 ,imm)
       `((op . "reconstitute_field") (divisor . ,var0) (modulus . ,var1) (bits . ,imm))]
      [(select ,var0 ,var1 ,var2)
       `((op . "cond_select") (bit . ,var0) (a . ,var1) (b . ,var2))]
      [(test_eq ,var0 ,var1)
       `((op . "test_eq") (a . ,var0) (b . ,var1))]
      [(transient_hash ,var* ...)
       `((op . "transient_hash") (inputs . ,(list->vector var*)))]))

  (define-passes zkir-v3-passes
    (reduce-to-zkir Lzkir)
    (print-zkir-v3  Lzkir))
  )
