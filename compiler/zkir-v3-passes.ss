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
          (config-params)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers)
          (natives)
          (ledger)
          (vm)
          (json))

  ;; Field representations (which *can* be negative) are represented with an optional leading minus
  ;; sign and then hexadecimal byte values in little endian order.
  (define (zkir-field-rep->string fr)
    (call-with-string-output-port
      (lambda (sp)
        (let ([fr (if (< fr 0)
                      (begin (put-string sp "-0x") (- fr))
                      (begin (put-string sp "0x") fr))])
          (let loop ([fr fr])
            (if (< fr 256)
                (fprintf sp "~(~2,'0x~)" fr)
                (let-values ([(q r) (div-and-mod fr 256)])
                  (fprintf sp "~(~2,'0x~)" r)
                  (loop q))))))))

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
        (lambda (var-name* src test triv* instr*)
          (with-output-language (Lzkir Instruction)
            (fold-left
              (lambda (instr* var-name primitive-type)
                ;; The ZKIR v2 backend has this special case for literal true guards.
                (emit-constraints-for var-name primitive-type
                  (cons (if (eq? test 1)
                            `(private_input ,var-name)
                            `(private_input ,var-name ,test))
                    instr*)))
              instr* var-name* primitive-type*))))

      (define (make-native name arg*)
        ;; Get the list of alignment atoms for a 0-based arg index.
        (define (arg->alignment arg* index)
          (nanopass-case (Lflattened Argument) (list-ref arg* index)
            [(argument (,var-name ...) (ty (,alignment* ...) (,primitive-type* ...)))
             alignment*]))
        (lambda (var-name* src test triv* instr*)
          (with-output-language (Lzkir Instruction)
            ;; Generally assume that the arity is correct here.
            (case name
              [(degradeToTransient)
               (cons `(copy ,(car var-name*) ,(cadr triv*)) instr*)]
              [(ecAdd)
               (assert (= (length var-name*) 2))
               (cons (apply (lambda (ax ay bx by)
                              `(ec_add ,(car var-name*) ,(cadr var-name*) ,ax ,ay ,bx ,by))
                       triv*)
                 instr*)]
              [(ecMul)
               (assert (= (length var-name*) 2))
               (cons (apply (lambda (ax ay scalar)
                              `(ec_mul ,(car var-name*) ,(cadr var-name*) ,ax ,ay ,scalar))
                       triv*)
                 instr*)]
              [(ecMulGenerator)
               (assert (= (length var-name*) 2))
               (cons `(ec_mul_generator ,(car var-name*) ,(cadr var-name*) ,(car triv*))
                 instr*)]
              [(hashToCurve)
               (assert (= (length var-name*) 2))
               (cons `(hash_to_curve ,(car var-name*) ,(cadr var-name*) ,triv* ...) instr*)]
              [(persistentCommit)
               (assert (= (length var-name*) 2))
               ;; The two source arguments are swapped for the persistent_hash gate.  We assume
               ;; that the second argument is `(tbytes 32)` so it consumes two variables and we
               ;; know its alignment is `(abytes 32)`.
               (let ([var* (syntax-case triv* ()
                             [(a ... b c) #'(b c a ...)])]
                     [alignment* (append (arg->alignment arg* 1) (arg->alignment arg* 0))])
                 (cons `(persistent_hash ,(car var-name*) ,(cadr var-name*)
                          (,alignment* ...) ,var* ...)
                   instr*))]
              [(persistentHash)
               (assert (= (length var-name*) 2))
               (let ([alignment* (arg->alignment arg* 0)])
                 (cons `(persistent_hash ,(car var-name*) ,(cadr var-name*)
                          (,alignment* ...) ,triv* ...)
                   instr*))]
              [(transientCommit)
               (assert (= (length var-name*) 1))
               ;; The last input needs to be moved first.
               (let ([var* (syntax-case triv* ()
                             [(a ... b) #'(b a ...)])])
                 (cons `(transient_hash ,(car var-name*) ,var* ...) instr*))]
              [(transientHash)
               (assert (= (length var-name*) 1))
               (cons `(transient_hash ,(car var-name*) ,triv* ...) instr*)]
              [(upgradeFromTransient)
               (assert (= (length var-name*) 2))
               (cons*
                 `(div_mod_power_of_two
                    ,(cadr var-name*) ,(make-temp-id src 'tmp) ,(car triv*) ,248)
                 `(copy ,(car var-name*) ,0)
                 instr*)]
              [else
                (fprintf (current-error-port) "unknown native: ~s\n" name)
                (assert not-implemented)]))))

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

      (define zkir-instr* (make-parameter '()))

      ;; Encode a VM operand, collecting codes in reverse.
      (define (assemble-operand-acc code* rand)
        ;; Encode a string in a field, return the immediate and the length of the UTF-8 encoding
        (define (domain-separator str)
          (let* ([bytes (string->utf8 str)]
                 [length (bytevector-length bytes)]
                 [field
                   ;; "Little-endian" encoding of the byte array into a field, assumed to fit.
                   (begin
                     (assert (<= length (field-bytes)))
                     (let loop ([i (1- length)] [acc 0])
                       (if (< i 0)
                           acc
                           (loop (1- i) (+ (* acc 256) (bytevector-u8-ref bytes i))))))])
            (values field length)))
        ;; Emit a ZKIR persistent_hash gate and accumulate the result operand encoding.
        (define (persistent-hash alignment* var* code*)
          (with-output-language (Lzkir Instruction)
            (let ([hash0 (make-temp-id default-src 'hash)]
                  [hash1 (make-temp-id default-src 'hash)])
              (zkir-instr*
                (cons `(persistent_hash ,hash0 ,hash1 (,alignment* ...) ,var* ...)
                  (zkir-instr*)))
              ;; Note that the operand encoding (1 32 hash0 hash1) is reversed.
              (cons* hash1 hash0 32 1 code*))))
        ;; The number of zeros and alignment for the default value of an Lflattened type.
        (define (default-for type)
          (nanopass-case (Lflattened Type) type
            [(ty (,alignment* ...) (,primitive-type* ...))
             (let ([count (fold-left
                            (lambda (count atom)
                              (nanopass-case (Lflattened Alignment) atom
                                [(abytes ,nat) (+ count (ceiling (/ nat (field-bytes))))]
                                [else (1+ count)]))
                            0 alignment*)])
               (values count alignment*))]))

        ;; Operands can be one of:
        ;;   - zkir-val, typed Lzkir outputs consisting of a list of
        ;;     alignment atoms and a list of instruction outputs
        ;;   - integer literals
        ;;   - VMop, whose datatype definition is in vm.ss
        (cond
          [(zkir-val? rand)
           (let ([code* (fold-left (lambda (code* a)
                                     (cons (assemble-alignment-atom a) code*))
                          (cons (length (zkir-val-alignment* rand)) code*)
                          (zkir-val-alignment* rand))])
             (fold-left (lambda (code* var) (cons var code*))
               code* (zkir-val-input* rand)))]
          [(not (VMop? rand)) (cons rand code*)]
          [else
            (VMop-case rand
              [(VMstack) (cons -1 code*)]
              [(VM+ x0 x1)
               (let ([op0 (assemble-operand x0)] [op1 (assemble-operand x1)])
                 ;; Expects a pair of singleton immediates.
                 (assert (and (null? (cdr op0)) (null? (cdr op1))))
                 (assert (and (zkir-field-rep? (car op0)) (zkir-field-rep? (car op1))))
                 (cons (+ (car op0) (car op1)) code*))]
              [(VMalign value bytes)
               (assert-byte bytes)
               ;; Encoding is length=1 bytes value (in reverse).
               (assemble-operand-acc (cons* bytes 1 code*) value)]
              [(VMaligned-concat x*)
               (let ([op* (maplr assemble-operand x*)])
                 ;; Each element of op* consists of the length, and then a tail that needs to be
                 ;; split into alignment* and var*.
                 (let outer ([op* op*] [count 0] [alignment* '()] [var* '()])
                   (if (null? op*)
                       ;; Encoding in code* is in reversed order.
                       (append (reverse var*) alignment* (cons count code*))
                       (let ([len (caar op*)])
                         (assert (zkir-field-rep? len))
                         (let inner ([i len] [tail (cdar op*)] [alignment* alignment*])
                           (if (zero? i)
                               (outer (cdr op*) (+ count len) alignment* (append var* tail))
                               (inner (1- i) (cdr tail) (cons (car tail) alignment*))))))))]
              [(VMnull type)
               (let-values ([(count alignment*) (default-for type)])
                 ;; Encoding in code* is in reversed order.
                 (append (make-list count 0)
                   (map assemble-alignment-atom (reverse alignment*))
                   (cons (length alignment*) code*)))]
              [(VMmax-sizeof type)
               ;; There's room to tighten this in the future, we just need to be careful to keep it
               ;; in sync with the Rust version.
               ;; This code is a version of the ZKIR v2 implementation, simplified by standard
               ;; call-by-value reasoning.
               (nanopass-case (Lflattened Type) type
                 [(ty (,alignment* ...) (,primitive-type* ...))
                  (cons (if (null? alignment*)
                            2
                            (fold-left
                              (lambda (sum atom)
                                (+ sum
                                  (nanopass-case (Lflattened Alignment) atom
                                    [(abytes ,nat)
                                     (if (zero? nat)
                                         3
                                         (+ 2 nat (ceiling (/ (integer-length nat) 8))))]
                                    [else 34])))
                              (1+ (ceiling (/ (integer-length (length alignment*)) 8)))
                              alignment*))
                    code*)])]
              [(VMvalue->int x)
               (let ([var* (zkir-val-input* x)])
                 (assert (and (list? var*) (= 1 (length var*))))
                 (cons (car var*) code*))]
              [(VMcoin-commit coin recipient)
               ;; A coin-commit operand is like a call to `coinCommitment` in the standard library.
               ;; It's implemented by generating the same ZKIR code that would be generated.
               (assert (and (zkir-val? coin) (zkir-val? recipient)))
               (with-output-language (Lzkir Instruction)
                 (let ([rvar* (zkir-val-input* recipient)]
                       [data0 (make-temp-id default-src 'data)]
                       [data1 (make-temp-id default-src 'data)])
                   (zkir-instr*
                     (cons*
                       `(cond_select ,data1 ,(car rvar*)
                          ,(list-ref rvar* 2)
                          ,(list-ref rvar* 4))
                       `(cond_select ,data0 ,(car rvar*)
                          ,(list-ref rvar* 1)
                          ,(list-ref rvar* 3))
                       (zkir-instr*)))
                   (let-values ([(sep-val sep-length) (domain-separator "midnight:zswap-cc[v1]")])
                     (persistent-hash
                       (with-output-language (Lflattened Alignment)
                         (list `(abytes ,sep-length) `(abytes ,32) `(abytes ,32) `(abytes ,16)
                           `(abytes ,1) `(abytes ,32)))
                       (append (cons sep-val (zkir-val-input* coin)) (list (car rvar*) data0 data1))
                       code*))))]
              [(VMleaf-hash val)
               (let*-values
                   ([(val* alignment*)
                     ;; The operand is either a ZKIR instruction ouput or the default value of a
                     ;; type.
                     (cond
                       [(zkir-val? val)
                        (values (zkir-val-input* val) (zkir-val-alignment* val))]
                       [(VMop? val)
                        (VMop-case val
                          [(VMnull type)
                           (let-values ([(count alignment*) (default-for type)])
                             (values (make-list count 0) alignment*))]
                          [else (assert cannot-happen)])]
                       [else (assert cannot-happen)])])
                 (let-values ([(sep-val sep-length) (domain-separator "mdn:lh")])
                   (persistent-hash
                     (with-output-language (Lflattened Alignment)
                       (cons `(abytes ,sep-length) alignment*))
                     (cons sep-val val*)
                     code*)))]
              [(VMstate-value-null) (cons 0 code*)]
              [(VMstate-value-cell val) (assemble-operand-acc (cons 1 code*) val)]
              [(VMstate-value-ADT val type)
               (or (nanopass-case (Lflattened Type) type
                     [(ty (,alignment* ...) ((tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))))
                      (assemble-operand-acc code*
                        (expand-vm-expr src
                          (map cons adt-formal* adt-arg*)
                          (vm-expr-expr vm-expr)))]
                     [else #f])
                   (assemble-operand-acc (cons 1 code*) val))]
              [(VMstate-value-map key* val*)
               (fold-left assemble-operand-acc
                 (fold-left assemble-operand-acc
                   (cons (combine (length key*) 2) code*)
                   key*)
                 val*)]
              [(VMstate-value-merkle-tree nat key* val*)
               (fold-left assemble-operand-acc
                 (fold-left assemble-operand-acc
                   ;; Tag with length(key*) << 8 | combine(nat, 4)
                   (cons (fxlogor (fxsll (length key*) 8) (combine nat 4)) code*)
                   key*)
                 val*)]
              [(VMstate-value-array val*)
               (fold-left assemble-operand-acc
                 (cons (combine (length val*) 3) code*)
                 val*)]
              [else
                (fprintf (current-error-port) "rand: ~s\n" rand)
                (assert not-implemented)])]))

      (define (assemble-operand rand)
        (reverse (assemble-operand-acc '() rand)))

      ;; The ZKIR representation of a Minokawa value.  It consists of a sequence of Lflattened
      ;; alignment atoms and a parallel sequence of Lzkir input operands (variables or immediates).
      (define-record-type zkir-val
        (nongenerative)
        (fields alignment* input*))

      ;; Encode a path.
      (define (assemble-path path)
        (reverse (fold-left assemble-operand-acc '() path)))

      ;; Map an Impact VM alignment to a ZKIR operand (which might be negative).
      (define (assemble-alignment-atom atom)
        (nanopass-case (Lflattened Alignment) atom
          [(abytes ,nat) nat]
          [(acompress) -1]
          [(afield) -2]
          [(aadt) -3]
          [(acontract) -4]))

      ;; Map an impact instruction to a list of ZKIR Impact operands.
      (define (assemble1 impact-instr var-name* alignment*)
        (define (suppress? rand)
          (and (VMop? rand)
               (VMop-case rand [(VMsuppress) #t] [else #f])))
        ;; The arguments are an association list with string keys.
        (let ([rands (vminstr-arg* impact-instr)])
          (case (vminstr-op impact-instr)
            ;; lt --> 0x01
            [("lt") (list #x01)]

            ;; eq --> 0x02
            [("eq") (list #x02)]

            ;; type --> 0x03
            [("type") (list #x03)]

            ;; size --> 0x04
            [("size") (list #x04)]

            ;; neg --> 0x08
            [("neg") (list #x08)]

            ;; root --> 0x0a
            [("root") (list #x0a)]

            ;; pop --> 0x0b
            [("pop") (list #x0b)]

            ;; popeq  --> 0x0c result
            ;; popeqc --> 0x0d result
            ;; This instruction occurs at most once in a program, so it's OK to allocate indexes for
            ;; the variable names.
            [("popeq")
             (let ([alignment (map assemble-alignment-atom alignment*)])
               (cons*
                 (if (cdr (assoc "cached" rands)) #xd #xc)
                 (length alignment)
                 (append alignment var-name*)))]

            ;; addi --> 0x0e state
            [("addi")
             (cons #xe (assemble-operand (cdr (assoc "immediate" rands))))]

            ;; subi --> 0x0f state
            [("subi")
             (cons #xf (assemble-operand (cdr (assoc "immediate" rands))))]

            ;; push  --> 0x10 state
            ;; pushs --> 0x11 state
            [("push")
             (let ([code* (assemble-operand (cdr (assoc "value" rands)))])
               (cons (if (cdr (assoc "storage" rands)) #x11 #x10) code*))]

            ;; branch --> 0x12 u21
            [("branch")
             ;; TODO(kmillikin): Is skip guaranteed to be in range?
             (cons #x12 (assemble-operand (cdr (assoc "skip" rands))))]

            ;; jmp --> 0x13 u21
            [("jmp")
             ;; TODO(kmillikin): Is skip guaranteed to be in range?
             (cons #x13 (assemble-operand (cdr (assoc "skip" rands))))]

            ;; add --> 0x14
            [("add") (list #x14)]

            ;; concat  --> 0x16 u21
            ;; concatc --> 0x17 u21
            [("concat")
             ;; TODO(kmillikin): Is n guaranteed to be in range?
             (cons (if (cdr (assoc "cached" rands)) #x17 #x16)
               (assemble-operand (cdr (assoc "n" rands))))]

            ;; member --> 0x18
            [("member") (list #x18)]

            ;; rem  --> 0x19
            ;; remc --> 0x1a
            [("rem") (list (if (cdr (assoc "cached" rands)) #x1a #x19))]

            ;; dup n --> 0x3n
            [("dup") (list (combine #x3 (cdr (assoc "n" rands))))]

            ;; swap n --> 0x4n
            [("swap") (list (combine #x4 (cdr (assoc "n" rands))))]

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
                     (cons (combine hi (1- (length path))) (assemble-path path)))))]

            ;; ins n  --> 0x9n
            ;; insc n --> 0xan
            [("ins")
             (let ([hi (if (cdr (assoc "cached" rands)) #xa #x9)]
                   [n (cdr (assoc "n" rands))])
               (if (suppress? n)
                   '()
                   (list (combine hi n))))]

            [else
              (fprintf (current-error-port) "unimplemented: ~s\n" impact-instr)
              (assert not-implemented)])))

      ;; We patch up popeq and popeqc instructions.
      (define (popeq? code*)
        (and (pair? code*)
             (zkir-field-rep? (car code*))
             (<= #xc (car code*) #xd)))

      (define (assemble test-val alignment* var-name* src path env vm-code instr*)
        (parameterize ([zkir-instr* instr*])
          (let* ([code (expand-vm-code src path #f env (vm-code-code vm-code))]
                 [op** (map (lambda (c) (assemble1 c var-name* alignment*)) code)])
            (with-output-language (Lzkir Instruction)
              (cons `(impact ,test-val ,(apply append op**) ...)
                (fold-left (lambda (instr* op*)
                             (if (not (popeq? op*))
                                 instr*
                                 (fold-left
                                   (lambda (instr* var-name)
                                     (cons
                                       ;; A weird case duplicated from ZKIR v2.
                                       (if (eq? test-val 1)
                                           `(public_input ,var-name)
                                           `(public_input ,var-name ,test-val))
                                       instr*))
                                   instr* var-name*)))
                  (zkir-instr*) op**))))))

      ;; ==== Per-circuit state ====
      (define default-src)

      ;; Accumulate a list of instructions to constrain an output index given an expected primitive
      ;; type.
      (define (emit-constraints-for var-name type instr*)
        (nanopass-case (Lflattened Primitive-Type) type
          [(topaque ,opaque-type) instr*]
          [(tfield) instr*]
          [(tfield ,nat)
           (with-output-language (Lzkir Instruction)
             (cond
               [(zero? nat)
                (cons `(constrain_eq ,var-name ,0) instr*)]
               [(= 1 nat)
                (cons `(constrain_to_boolean ,var-name) instr*)]
               ;; nat is one less than a power of 2.
               [(zero? (bitwise-and nat (1+ nat)))
                (cons `(constrain_bits ,var-name ,(integer-length nat)) instr*)]
               [else
                 ;; Compute the bits required to represent nat.  Plonk requires this to be a
                 ;; multiple of two, so instead of ⌈log_2(nat + 1)⌉, we compute k = ⌈log_4(nat +
                 ;; 1)⌉: the smallest exponent for which nat + 1 <= 4^k, and therefore nat <
                 ;; 2^(2k) with 2k being guaranteed to be even.  Note that we need need nat + 1,
                 ;; at nat itself is a valid assignment, and the final check is a less-than check.
                 (let ([bits (* 2 (quotient (+ (integer-length (+ 1 nat)) 1) 2))]
                       [tmp (make-temp-id default-src 'tmp)])
                   (cons*
                     `(assert ,tmp)
                     `(less_than ,tmp ,var-name ,(1+ nat) ,bits)
                     instr*))]))]
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
       ;; - Insert type constraints for inputs
       ;; - Translate the statements in the body
       ;; - Add instructions for the outputs
       (fluid-let ([default-src src])
         (let-values ([(var-name* type*) (unzip-arguments arg*)])
           (let* ([constraint*
                    (fold-left (lambda (constraint* var-name type)
                                 (emit-constraints-for var-name type constraint*))
                      '() var-name* type*)]
                  [instr*
                    (fold-left (lambda (instr* stmt) (Statement stmt instr*))
                      constraint* stmt*)]
                  [body
                    (fold-left (lambda (body triv)
                                 (with-output-language (Lzkir Instruction)
                                   (cons `(output ,triv) body)) )
                      instr* triv*)])
             `(circuit ,src (,(hashtable-ref export-ht function-name '()) ...) (,var-name* ...)
                ,(reverse body) ...))))])

    (Statement : Statement (ir instr*) -> * (instr*)
      [(= (,var-name* ...) (call ,src ,test ,function-name ,triv* ...))
       (let ([code-generator (hashtable-ref callable-ht function-name #f)])
         (assert code-generator)
         (code-generator var-name* src test triv* instr*))]
      [(= (,var-name* ...) (contract-call ,src ,test ,elt-name (,triv ,primitive-type) ,triv* ...))
       (source-errorf src "cross-contract calls are not yet supported")]
      [(= (,var-name0 ,var-name1) (field->bytes ,src ,test ,len ,triv))
       ;; TODO(kmillikin): this needs to respect test because `constrain_bits` can fail.
       (with-output-language (Lzkir Instruction)
         (if (<= len (field-bytes))
             (cons*
               `(constrain_bits ,var-name1 ,(* len 8))
               `(copy ,var-name1 ,triv)
               instr*)
             (cons `(div_mod_power_of_two ,var-name0 ,var-name1 ,triv ,(* (field-bytes) 8))
               instr*)))]
      [(= (,var-name* ...) (bytes->vector ,triv))
       (assert (not (null? var-name*)))
       (with-output-language (Lzkir Instruction)
         (let loop ([var-name* var-name*] [var triv] [instr* instr*])
           (if (null? (cdr var-name*))
               (cons `(copy ,(car var-name*) ,var) instr*)
               (let ([quo (make-temp-id default-src 'quo)])
                 (loop (cdr var-name*) quo
                   (cons `(div_mod_power_of_two ,quo ,(car var-name*) ,var ,8) instr*))))))]
      [(= (,var-name* ...) (public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...)
                             ,src^ ,adt-op ,triv* ...))
       (nanopass-case (Lflattened ADT-Op) adt-op
         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...)
            (,type* ...) (ty (,alignment* ...) (,primitive-type* ...)) ,vm-code)
          (let (;; Expansion of the Impact code needs an environment mapping the formals to their
                ;; values.  The arguments triv* are flat but they need to be nested according to the
                ;; structure of type*.
                [env
                  ;; Walk in lockstep down type* and formal*, peeling off triv*s.
                  (let outer ([type* type*] [formal* ledger-op-formal*] [triv* triv*]
                              ;; Start with an environment that has the ADT formals.
                              [env (map cons adt-formal* adt-arg*)])
                    (if (null? type*)
                        (begin
                          (assert (and (null? formal*) (null? triv*)))
                          env)
                        (nanopass-case (Lflattened Type) (car type*)
                          ;; primitive-type* tells us how many triv*s to peel off.
                          [(ty (,alignment* ...) (,primitive-type* ...))
                           (let-values
                               ([(var* triv*)
                                 (let inner ([pt* primitive-type*] [triv* triv*] [var* '()])
                                   (if (null? pt*)
                                       (values (reverse var*) triv*)
                                       (inner (cdr pt*) (cdr triv*) (cons (car triv*) var*))))])
                             ;; Pair the alignment* atoms with the triv*s, bind to the formal,
                             ;; and loop.
                             (outer (cdr type*) (cdr formal*) triv*
                               (cons (cons (car formal*) (make-zkir-val alignment* var*))
                                 env)))])))])
            (assemble test alignment* var-name* src (map Path-Element path-elt*) env vm-code
              instr*))])]
      [(= ,var-name ,single)
       (Single single var-name instr*)]
      [(assert ,src ,test ,mesg)
       (with-output-language (Lzkir Instruction)
         (cons `(assert ,test) instr*))]
      [else
        (fprintf (current-error-port) "unimplemented: ~s\n" ir)
        (assert cannot-happen)])

    (Single : Single (ir var-name instr*) -> * (instr*)
      [(+ ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (cons `(add ,var-name ,triv0 ,triv1) instr*))]
      [(- ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (let ([neg (make-temp-id default-src 'neg)])
           (cons*
             `(add ,var-name ,triv0 ,neg)
             `(neg ,neg ,triv1)
             instr*)))]
      [(* ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (cons `(mul ,var-name ,triv0 ,triv1) instr*))]
      [(< ,mbits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (cons `(less_than ,var-name ,triv0 ,triv1 ,mbits) instr*))]
      [(== ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (cons `(test_eq ,var-name ,triv0 ,triv1) instr*))]
      [(select ,triv0 ,triv1 ,triv2)
       (with-output-language (Lzkir Instruction)
         (cons `(cond_select ,var-name ,triv0 ,triv1 ,triv2) instr*))]
      [(bytes-ref ,triv ,nat)
       (with-output-language (Lzkir Instruction)
         (let ([quo (make-temp-id default-src 'quo)]
               [ig0 (make-temp-id default-src 'ignore)]
               [ig1 (make-temp-id default-src 'ignore)])
           (cons*
             `(div_mod_power_of_two ,ig1 ,var-name ,quo ,8)
             `(div_mod_power_of_two ,quo ,ig0 ,triv ,(* nat 8))
             instr*)))]
      [(bytes->field ,src ,test ,len ,triv0 ,triv1)
       ;; TODO(kmillikin): This should respect test and be conditional in the ZKIR output.
       (with-output-language (Lzkir Instruction)
         ;; flatten-datatype takes care of this case.
         (assert (> len (field-bytes)))
         (cons `(reconstitute_field ,var-name ,triv0 ,triv1 ,(* 8 (field-bytes))) instr*))]
      [(vector->bytes ,triv ,triv* ...)
       (with-output-language (Lzkir Instruction)
         (if (null? triv*)
             (cons `(copy ,var-name ,triv) instr*)
             (let recur ([result var-name] [current triv] [triv+ triv*] [instr* instr*])
               (let-values ([(div instr*)
                             (if (null? (cdr triv+))
                                 (values (car triv+) instr*)
                                 (let ([div (make-temp-id default-src 'div)])
                                   (values div (recur div (car triv+) (cdr triv+) instr*))))])
                   (cons `(reconstitute_field ,result ,div ,current ,8) instr*)))))]
      [(downcast-unsigned ,src ,test ,nat ,triv)
       ;; TODO(kmillikin): This needs to be conditional on test.
       (with-output-language (Lzkir Instruction)
         ;; TODO(kmillikin): The `copy` here is unnecessary.  Remove it.
         (cons `(copy ,var-name ,triv)
           (emit-constraints-for triv
             (with-output-language (Lflattened Primitive-Type) `(tfield ,nat))
             instr*)))]
      [else
        (fprintf (current-error-port) "unimplemented: ~s\n" ir)
        (assert cannot-happen)])

    ;; Path elements are either literals or Lflattened typed sequences of triv values.  Represent
    ;; the latter by the pair of the sequence of alignments and the sequence of ZKIR outputs.
    (Path-Element : Path-Element (ir) -> * (operand)
      [,path-index (VMalign path-index 1)]  ; <-- length in bytes is 1
      [(,src ,type ,triv* ...)
       (nanopass-case (Lflattened Type) type
         [(ty (,alignment* ...) (,primitive-type* ...))
          (make-zkir-val alignment* triv*)])])
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
      (module (with-var-table var->string)
        (define ht)
        (define counter)
        (define-syntax with-var-table
          (syntax-rules ()
            [(_ b1 b2 ...)
             (fluid-let ([ht (make-eq-hashtable)] [counter 0])
               b1 b2 ...)]))
        (define (var->string var)
          (let ([a (eq-hashtable-cell ht var #f)])
            (or (cdr a)
                (let ([str (format "%~s.~d" (id-sym var) counter)])
                  (set! counter (fx+ counter 1))
                  (set-cdr! a str)
                  str)))))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ,cdefn* ...)
       (for-each Circuit-Definition cdefn*)
       ir])
    (Circuit-Definition : Circuit-Definition (ir) -> * ()
      [(circuit ,src (,name* ...) (,var-name* ...) ,instr* ...)
       (define (print-circuit op)
         (print-json-compact op
           (with-var-table
             (let* ([inputs (list->vector (maplr var->string var-name*))]
                    [instructions (list->vector (maplr Instruction instr*))])
               `((version . ((major . 3) (minor . 0)))
                 (do_communications_commitment . ,(not (no-communications-commitment)))
                 (inputs . ,inputs)
                 (instructions . ,instructions))))))
       (let ([output-port*
               (fold-left (lambda (output-port* name)
                            (let ([target (assq name (target-ports))])
                              (if target
                                  (cons (cdr target) output-port*)
                                  output-port*)))
                 '() name*)])
         ;; Exported pure circuits are in the IR but don't have any corresponding target ports.
         (unless (null? output-port*)
           (if (null? (cdr output-port*))
               ;; Directly print it to the port.
               (print-circuit (car output-port*))

               ;; Stringify it first.
               (let ([str (call-with-string-output-port print-circuit)])
                 (for-each (lambda (op) (put-string op str)) output-port*)))))])
    (Instruction : Instruction (ir) -> * (json)
      [(add ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "add") (output . ,outp) (a . ,inp0) (b . ,inp1))]
      [(assert ,[* inp])
       `((op . "assert") (cond . ,inp))]
      [(cond_select ,[* outp] ,[* inp0] ,[* inp1] ,[* inp2])
       `((op . "cond_select") (output . ,outp) (bit . ,inp0) (a . ,inp1) (b . ,inp2))]
      [(constrain_bits ,[* inp] ,imm)
       `((op . "constrain_bits") (val . ,inp) (bits . ,imm))]
      [(constrain_eq ,[* inp0] ,[* inp1])
       `((op . "constrain_eq") (a . ,inp0) (b . ,inp1))]
      [(constrain_to_boolean ,[* inp])
       `((op . "constrain_to_boolean") (val . ,inp))]
      [(copy ,[* outp] ,[* inp])
       `((op . "copy") (output . ,outp) (val . ,inp))]
      [(div_mod_power_of_two ,outp0 ,outp1 ,[* inp] ,imm)
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "div_mod_power_of_two") (outputs . ,(vector outp0 outp1)) (val . ,inp)
           (bits . ,imm)))]
      [(ec_add ,outp0 ,outp1 ,[* inp0] ,[* inp1] ,[* inp2] ,[* inp3])
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "ec_add") (outputs . ,(vector outp0 outp1)) (a_x . ,inp0) (a_y . ,inp1)
           (b_x . ,inp2) (b_y . ,inp3)))]
      [(ec_mul ,outp0 ,outp1 ,[* inp0] ,[* inp1] ,[* inp2])
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "ec_mul") (outputs . ,(vector outp0 outp1)) (a_x . ,inp0) (a_y . ,inp1)
           (scalar . ,inp2)))]
      [(ec_mul_generator ,outp0 ,outp1 ,[* inp])
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "ec_mul_generator") (outputs . ,(vector outp0 outp1)) (scalar . ,inp)))]
      [(hash_to_curve ,outp0 ,outp1 ,[* inp*] ...)
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "hash_to_curve") (outputs . ,(vector outp0 outp1))
           (inputs . ,(list->vector inp*))))]
      [(less_than ,[* outp] ,[* inp0] ,[* inp1] ,imm)
       `((op . "less_than") (output . ,outp) (a . ,inp0) (b . ,inp1) (bits . ,imm))]
      [(mul ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "mul") (output . ,outp) (a . ,inp0) (b . ,inp1))]
      [(neg ,[* outp] ,[* inp])
       `((op . "neg") (output . ,outp) (a . ,inp))]
      [(output ,[* inp])
       `((op . "output") (val . ,inp))]
      [(persistent_hash ,outp0 ,outp1 (,alignment* ...) ,[* inp*] ...)
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "persistent_hash") (outputs . ,(vector outp0 outp1))
           (alignment . ,(alignment->vector alignment*)) (inputs . ,(list->vector inp*))))]
      [(private_input ,[* outp])
       ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
       ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "private_input") (output . ,outp) (guard . ,(void)))]
      [(private_input ,[* outp] ,[* inp])
       `((op . "private_input") (output . ,outp) (guard . ,inp))]
      [(public_input ,[* outp])
       ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
       ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "public_input") (output . ,outp) (guard . ,(void)))]
      [(public_input ,[* outp] ,[* inp])
       `((op . "public_input") (output . ,outp) (guard . ,inp))]
      [(impact ,[* inp] ,[* inp*] ...)
       `((op . "impact") (guard . ,inp) (inputs . ,(list->vector inp*)))]
      [(reconstitute_field ,[* outp] ,[* inp0] ,[* inp1] ,imm)
       `((op . "reconstitute_field") (output . ,outp) (divisor . ,inp0) (modulus . ,inp1)
         (bits . ,imm))]
      [(test_eq ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "test_eq") (output . ,outp) (a . ,inp0) (b . ,inp1))]
      [(transient_hash ,[* outp] ,[* inp*] ...)
       `((op . "transient_hash") (output . ,outp) (inputs . ,(list->vector inp*)))])
    (Input : Input (ir) -> * (json)
      (,fr (zkir-field-rep->string fr))
      (,var-name (var->string var-name)))
    (Output : Output (ir) -> * (json)
      (,var-name (var->string var-name))))

  (define-passes zkir-v3-passes
    (reduce-to-zkir Lzkir)
    (print-zkir-v3  Lzkir))
  )
