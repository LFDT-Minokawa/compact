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
          (field)
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
      ;; for witness-like callables and natives.
      (define callable-ht (make-eq-hashtable))

      ;; The `anative` alignment atom is a "pseudo-alignment" that the ledger does no know about.
      ;; We translate each occurrence into a sequence of real ledger alignment atoms.  This
      ;; translation mirrors the alignment defined in `runtime/src/compact-types.ts`.
      ;;
      ;; TODO (kmillikin): there is duplicated, but lower-level, handling of these types for the
      ;; Impact `push` and `popeq` instructions.  Try to find a way to share this code.
      (define (circuit-alignment-for src alignment* triv* instr*)
        (let loop ([alignment* alignment*] [triv* triv*] [instr* instr*]
                   [new-alignment* '()] [new-triv* '()])
          (if (null? alignment*)
              (begin
                (assert (null? triv*))
                (values (reverse new-alignment*) (reverse new-triv*) instr*))
              (let ([atom (car alignment*)])
                (nanopass-case (Lflattened Alignment) atom
                  [(anative ,opaque-type) (guard (string=? opaque-type "JubjubScalar"))
                   ;; This doesn't have its own descriptor in `runtime/src/compact-types.ts.  It's
                   ;; just a native field but it needs a ZKIR conversion instruction.
                   (let ([fld (make-temp-id src 'fld)])
                     (loop (cdr alignment*) (cdr triv*)
                       (with-output-language (Lzkir Instruction)
                         (cons `(encode (,fld) ,(car triv*)) instr*))
                       (with-output-language (Lflattened Alignment)
                         (cons `(afield) new-alignment*))
                       (cons fld new-triv*)))]
                  [(anative ,opaque-type) (guard (or (string=? opaque-type "Secp256k1Base")
                                                     (string=? opaque-type "Secp256k1Scalar")))
                   (let* ([fld0 (make-temp-id src 'fld)] [fld1 (make-temp-id src 'fld)])
                     (loop (cdr alignment*) (cdr triv*)
                       (with-output-language (Lzkir Instruction)
                         (cons `(encode (,fld0 ,fld1) ,(car triv*)) instr*))
                       (with-output-language (Lflattened Alignment)
                         ;; Reversed:
                         (cons* `(abytes 8) `(abytes 24) new-alignment*))
                       (cons* fld1 fld0 new-triv*)))]
                  [(anative ,opaque-type) (guard (string=? opaque-type "JubjubPoint"))
                   (let* ([pt0 (make-temp-id src 'pt)] [pt1 (make-temp-id src 'pt)])
                     (loop (cdr alignment*) (cdr triv*)
                       (with-output-language (Lzkir Instruction)
                         (cons `(encode (,pt0 ,pt1) ,(car triv*)) instr*))
                       (with-output-language (Lflattened Alignment)
                         (cons* `(afield) `(afield) new-alignment*))
                       (cons* pt1 pt0 new-triv*)))]
                  [(anative ,opaque-type) (guard (string=? opaque-type "Secp256k1Point"))
                   (let ([fld* (maplr (lambda (ignore) (make-temp-id src 'fld)) (make-list 5))])
                     (loop (cdr alignment*) (cdr triv*)
                       (with-output-language (Lzkir Instruction)
                         (cons `(encode (,fld* ...) ,(car triv*)) instr*))
                       (with-output-language (Lflattened Alignment)
                         ;; Reversed:
                         (cons* `(afield) `(abytes 8) `(abytes 24) `(abytes 8) `(abytes 24)
                           new-alignment*))
                       (append (reverse fld*) new-triv*)))]
                  [(abytes ,nat)
                   (let ([n (ceiling (/ nat (field-bytes)))])
                     (loop (cdr alignment*) (list-tail triv* n) instr*
                       (cons atom new-alignment*)
                       (append (reverse (list-head triv* n)) new-triv*)))]
                  [else (loop (cdr alignment*) (cdr triv*) instr*
                          (cons atom new-alignment*)
                          (cons (car triv*) new-triv*))])))))

      (define (make-private-input test var-name primitive-type)
        ;; The ZKIR v2 backend has this special case for literal true guards.
        (with-output-language (Lzkir Instruction)
          (if (eq? test 1)
              `(private_input ,(type->string primitive-type) ,var-name)
              `(private_input ,(type->string primitive-type) ,var-name ,test))))

      (define (make-public-input test var-name type-string)
        (with-output-language (Lzkir Instruction)
          (if (eq? test 1)
              `(public_input ,type-string ,var-name)
              `(public_input ,type-string ,var-name ,test))))

      (define (make-witness alignment* primitive-type*)
        (lambda (var-name* src test triv* instr*)
          (fold-left
            (lambda (instr* var-name primitive-type)
              ;; NB: the public inputs are 0 if a conditionally executed witness
              ;; call is not executed, and at present emit-constraints-for is always
              ;; okay with zero
                (emit-constraints-for var-name primitive-type
                  (cons (make-private-input test var-name primitive-type) instr*)))
              instr* var-name* primitive-type*)))

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
              [(constructJubjubPoint)
               (cons `(from_coordinates ,(car var-name*) ,(car triv*) ,(cadr triv*)) instr*)]
              [(degradeToTransient)
               (cons `(copy ,(car var-name*) ,(cadr triv*)) instr*)]
              [(ecAdd)
               (assert (= (length var-name*) 1))
               (cons `(add ,(car var-name*) ,(car triv*) ,(cadr triv*)) instr*)]
              [(ecNeg)
               (assert (= (length var-name*) 1))
               (let ([tmp-x (make-temp-id src 'x)]
                     [tmp-y (make-temp-id src 'y)]
                     [tmp-neg-x (make-temp-id src 'neg)])
                 (cons*
                   `(from_coordinates ,(car var-name*) ,tmp-neg-x ,tmp-y)
                   `(neg ,tmp-neg-x ,tmp-x)
                   `(into_coordinates ,tmp-x ,tmp-y ,(car triv*))
                   instr*))]
              [(ecMul)
               (assert (= (length var-name*) 1))
               (cons `(ec_mul ,(car var-name*) ,(car triv*) ,(cadr triv*)) instr*)]
              [(ecMulGenerator)
               (assert (= (length var-name*) 1))
               (cons `(ec_mul_generator ,(car var-name*) ,(car triv*)) instr*)]
              [(hashToCurve)
               (assert (= (length var-name*) 1))
               (cons `(hash_to_curve ,(car var-name*) ,triv* ...) instr*)]
              [(inv)
               (assert (= (length var-name*) 1))
               (cons `(inv ,(car var-name*) ,(car triv*)) instr*)]
              [(jubjubPointX)
               (assert (= (length var-name*) 1))
               (let ([y (make-temp-id src 'ignore)])
                 (cons `(into_coordinates ,(car var-name*) ,y ,(car triv*)) instr*))]
              [(jubjubPointY)
               (assert (= (length var-name*) 1))
               (let ([x (make-temp-id src 'ignore)])
                 (cons `(into_coordinates ,x ,(car var-name*) ,(car triv*)) instr*))]
              [(keccak256)
               (assert (= (length var-name*) 2))
               (let ([alignment* (arg->alignment arg* 0)]
                     [bytes (make-temp-id src 'bytes)])
                 (let-values ([(alignment* triv* instr*)
                               (circuit-alignment-for src alignment* triv* instr*)])
                   (cons*
                     `(bytes32_into_low_high ,(cadr var-name*) ,(car var-name*) ,bytes)
                     `(keccak256 ,bytes (,alignment* ...) ,triv* ...)
                     instr*)))]
              [(mul)
               (assert (= (length var-name*) 1))
               (cons `(mul, (car var-name*) ,(car triv*) ,(cadr triv*)) instr*)]
              [(neg)
               (assert (= (length var-name*) 1))
               (cons `(neg ,(car var-name*) ,(car triv*)) instr*)]
              [(persistentCommit)
               (assert (= (length var-name*) 2))
               ;; The two source arguments are swapped for the persistent_hash gate.  We assume
               ;; that the second argument is `(tbytes 32)` so it consumes two variables and we
               ;; know its alignment is `(abytes 32)`.
               (let ([var* (syntax-case triv* ()
                             [(a ... b c) #'(b c a ...)])]
                     [alignment* (append (arg->alignment arg* 1) (arg->alignment arg* 0))]
                     [bytes (make-temp-id src 'bytes)])
                 (let-values ([(alignment* triv* instr*)
                               (circuit-alignment-for src alignment* triv* instr*)])
                   (cons*
                     `(bytes32_into_low_high ,(cadr var-name*) ,(car var-name*) ,bytes)
                     `(persistent_hash ,bytes (,alignment* ...) ,var* ...)
                     instr*)))]
              [(persistentHash)
               (assert (= (length var-name*) 2))
               (let ([alignment* (arg->alignment arg* 0)]
                     [bytes (make-temp-id src 'bytes)])
                 (let-values ([(alignment* triv* instr*)
                               (circuit-alignment-for src alignment* triv* instr*)])
                   (cons*
                     `(bytes32_into_low_high ,(cadr var-name*) ,(car var-name*) ,bytes)
                     `(persistent_hash ,bytes (,alignment* ...) ,triv* ...)
                     instr*)))]
              [(secp256k1PointX)
               (assert (= (length var-name*) 1))
               (let ([y (make-temp-id src 'ignore)])
                 (cons `(into_coordinates ,(car var-name*) ,y ,(car triv*)) instr*))]
              [(secp256k1PointY)
               (assert (= (length var-name*) 1))
               (let ([x (make-temp-id src 'ignore)])
                 (cons `(into_coordinates ,x ,(car var-name*) ,(car triv*)) instr*))]
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
                    ,(make-temp-id src 'tmp) ,(cadr var-name*) ,(car triv*) ,248)
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
           (hashtable-set! callable-ht function-name (make-witness alignment* primitive-type*))]
          [(native ,src ,function-name ,native-entry (,arg* ...) (ty (,alignment* ...)
                                                                     (,primitive-type* ...)))
           (assert (not (hashtable-contains? callable-ht function-name)))
           (hashtable-set! callable-ht function-name
             (if (eq? (native-entry-class native-entry) 'witness)
                 (make-witness alignment* primitive-type*)
                 (make-native (id-sym function-name) arg*)))]
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
            (let* ([bytes (make-temp-id default-src 'bytes)]
                   [hash0 (make-temp-id default-src 'hash)]
                   [hash1 (make-temp-id default-src 'hash)])
              (zkir-instr*
                (cons*
                  `(bytes32_into_low_high ,hash1 ,hash0 ,bytes)
                  `(persistent_hash ,bytes (,alignment* ...) ,var* ...)
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
              [(VMstate-value-cell val)
               ;; Special handling of ZKIR native types.
               (if (and (zkir-val? val)
                        (= 1 (length (zkir-val-primitive-type* val))))
                   (with-output-language (Lzkir Instruction)
                     (nanopass-case (Lflattened Primitive-Type)
                                    (car (zkir-val-primitive-type* val))
                       [(topaque ,opaque-type) (guard (string=? opaque-type "JubjubPoint"))
                        (let* ([pt0 (make-temp-id default-src 'pt)]
                               [pt1 (make-temp-id default-src 'pt)])
                          (zkir-instr*
                            (cons `(encode (,pt0 ,pt1) ,(car (zkir-val-input* val)))
                              (zkir-instr*)))
                          (cons* pt1 pt0 -2 -2 2 1 code*))]
                       [(topaque ,opaque-type) (guard (string=? opaque-type "Secp256k1Point"))
                        (let* (;; This is the alignment of Secp256k1Point, see
                               ;; CompactTypeSecp256k1Point in runtime/src/compact-types.ts.
                               [alignment* '(24 8 24 8 -2)]
                               [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                       alignment*)])
                          (zkir-instr*
                            (cons `(encode (,fld* ...) ,(car (zkir-val-input* val)))
                              (zkir-instr*)))
                          (append (reverse fld*) (reverse alignment*) '(5 1) code*))]
                       [(tfield (field-scalar (curve-jubjub)))
                        (let ([fld (make-temp-id default-src 'fld)])
                          (zkir-instr*
                            (cons `(encode (,fld) ,(car (zkir-val-input* val)))
                              (zkir-instr*)))
                          (cons* fld -2 1 1 code*))]
                       [(tfield (field-base (curve-secp256k1)))
                        (let* (;; This is the alignment of Secp256k1Base, see
                               ;; CompactTypeSecp256k1Base in runtime/src/compact-types.ts.
                               [alignment* '(24 8)]
                               [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                       alignment*)])
                          (zkir-instr*
                            (cons `(encode (,fld* ...) ,(car (zkir-val-input* val)))
                              (zkir-instr*)))
                          (append (reverse fld*) (reverse alignment*) '(2 1) code*))]
                       [(tfield (field-scalar (curve-secp256k1)))
                        (let* ([alignment* '(24 8)]
                               [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                       alignment*)])
                          (zkir-instr*
                            (cons `(encode (,fld* ...) ,(car (zkir-val-input* val)))
                              (zkir-instr*)))
                          (append (reverse fld*) (reverse alignment*) '(2 1) code*))]
                       [else (assemble-operand-acc (cons 1 code*) val)]))
                   (assemble-operand-acc (cons 1 code*) val))]
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
        (fields primitive-type* alignment* input*))

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
          [(anative ,opaque-type)
           ;; These are handled specially because (1) they assemble into a sequence of alignment
           ;; atoms and (2) they need ZKIR instructions to be emitted.
           (assert cannot-happen)]))

      ;; Map an impact instruction to a list of ZKIR Impact operands.
      (define (assemble1 impact-instr test-val primitive-type* alignment* var-name*)
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

            ;; log/emit --> 0x09
            [("log") (list #x09)]

            ;; root --> 0x0a
            [("root") (list #x0a)]

            ;; pop --> 0x0b
            [("pop") (list #x0b)]

            ;; popeq  --> 0x0c result
            ;; popeqc --> 0x0d result
            [("popeq")
             (let-values
                 ([(alignment var-name*)
                   (with-output-language (Lzkir Instruction)
                     ;; Special handling of ZKIR native types.
                     (if (= 1 (length primitive-type*))
                         (nanopass-case (Lflattened Primitive-Type) (car primitive-type*)
                           [(topaque ,opaque-type) (guard (string=? opaque-type "JubjubPoint"))
                            (let* ([pt0 (make-temp-id default-src 'pt)]
                                   [pt1 (make-temp-id default-src 'pt)])
                              (zkir-instr*
                                (cons*
                                  `(encode (,pt0 ,pt1) ,(car var-name*))
                                  (make-public-input test-val (car var-name*) "Point<Jubjub>")
                                  (zkir-instr*)))
                              (values (list -2 -2) (list pt0 pt1)))]
                           [(topaque ,opaque-type) (guard (string=? opaque-type "Secp256k1Point"))
                            (let* (;; This is the alignment of Secp256k1Point, see
                                   ;; CompactTypeSecp256k1Point in runtime/src/compact-types.ts.
                                   [alignment* '(24 8 24 8 -2)]
                                   [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                           alignment*)])
                              (zkir-instr*
                                (cons*
                                  `(encode (,fld* ...) ,(car var-name*))
                                  (make-public-input test-val (car var-name*) "Point<Secp256k1>")
                                  (zkir-instr*)))
                              (values alignment* fld*))]
                           [(tfield (field-scalar (curve-jubjub)))
                            (let ([fld (make-temp-id default-src 'fld)])
                              (zkir-instr*
                                (cons*
                                  `(encode (,fld) ,(car var-name*))
                                  (make-public-input test-val (car var-name*) "Scalar<Jubjub>")
                                  (zkir-instr*)))
                              (values (list -2) (list fld)))]
                           [(tfield (field-base (curve-secp256k1)))
                            (let* (;; This is the alignment of Secp256k1Base, see
                                   ;; CompactTypeSecp256k1Base in runtime/src/compact-types.ts.
                                   [alignment* '(24 8)]
                                   [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                           alignment*)])
                              (zkir-instr*
                                (cons*
                                  `(encode (,fld* ...) ,(car var-name*))
                                  (make-public-input test-val (car var-name*) "Base<Secp256k1>")
                                  (zkir-instr*)))
                              (values alignment* fld*))]
                           [(tfield (field-scalar (curve-secp256k1)))
                            (let* ([alignment* '(24 8)]
                                   [fld* (maplr (lambda (ignore) (make-temp-id default-src 'fld))
                                           alignment*)])
                              (zkir-instr*
                                (cons*
                                  `(encode (,fld* ...) ,(car var-name*))
                                  (make-public-input test-val (car var-name*) "Scalar<Secp256k1>")
                                  (zkir-instr*)))
                              (values alignment* fld*))]
                           [else
                             (for-each
                               (lambda (var-name)
                                 (zkir-instr*
                                   (cons
                                     (make-public-input test-val var-name "Scalar<BLS12-381>")
                                     (zkir-instr*))))
                               var-name*)
                             (values (map assemble-alignment-atom alignment*) var-name*)])
                         (begin
                           (for-each
                             (lambda (var-name)
                               (zkir-instr*
                                 (cons
                                   (make-public-input test-val var-name "Scalar<BLS12-381>")
                                   (zkir-instr*))))
                             var-name*)
                           (values (map assemble-alignment-atom alignment*) var-name*))))])
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

      (define (assemble test-val primitive-type* alignment* var-name* src path env vm-code instr*)
        (parameterize ([zkir-instr* instr*])
          (let* ([code (expand-vm-code src path #f env (vm-code-code vm-code))]
                 [op** (map (lambda (c)
                              (assemble1 c test-val primitive-type* alignment* var-name*))
                         code)])
            (with-output-language (Lzkir Instruction)
              (fold-left
                (lambda (acc op*)
                  (if (null? op*)
                      acc
                      (cons `(impact ,test-val ,op* ...) acc)))
                (zkir-instr*)
                op**)))))

      ;; ==== Per-circuit state ====
      (define default-src)

      ;; Accumulate a list of instructions to constrain an output index given an expected primitive
      ;; type.
      (define (emit-constraints-for var-name type instr*)
        (nanopass-case (Lflattened Primitive-Type) type
          [(topaque ,opaque-type) instr*]
          [(tfield ,ftype) instr*]
          [(tunsigned ,nat)
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

      ;; Turn an Lflattened argument list into a list of names, a parallel list of types, and
      ;; conversion instructions.
      (define (unzip-arguments arg*)
        (if (null? arg*)
            (values '() '())
            (let-values ([(name* type*) (unzip-arguments (cdr arg*))])
              (nanopass-case (Lflattened Argument) (car arg*)
                [(argument (,var-name* ...) (ty (,alignment* ...) (,primitive-type* ...)))
                 (values (append var-name* name*) (append primitive-type* type*))]))))

      (define (field-type->string ftype)
        (nanopass-case (Lflattened Field-Type) ftype
          [(field-native) "Scalar<BLS12-381>"]
          [(field-scalar (curve-jubjub)) "Scalar<Jubjub>"]
          [(field-base (curve-secp256k1)) "Base<Secp256k1>"]
          [(field-scalar (curve-secp256k1)) "Scalar<Secp256k1>"]))

      (define (type->string primitive-type)
        (nanopass-case (Lflattened Primitive-Type) primitive-type
          [(tfield ,ftype) (field-type->string ftype)]
          [(tunsigned ,nat) "Scalar<BLS12-381>"]
          [(topaque ,opaque-type)
           (case opaque-type
             [("JubjubPoint") "Point<Jubjub>"]
             [("Secp256k1Point") "Point<Secp256k1>"]
             [else "Scalar<BLS12-381>"])]
          [else (assert cannot-happen)])))

    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       ;; The mapping from input language circuit names to exported names is one to many, the same
       ;; circuit can be exported under different names.  Build a hashtable from circuit name to
       ;; exported names.
       (for-each (lambda (export-name name)
                   (hashtable-set! export-ht name
                     (cons export-name (hashtable-ref export-ht name '()))))
         export-name* name*)

       ;; Process witness and native declarations in a separate pass over the program elements
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
      [(circuit ,src ,function-name (,arg* ...) (ty (,alignment* ...) (,primitive-type* ...))
         ,stmt* ... (,triv* ...))
       ;; - Replace the internal name with the exported ones
       ;; - Insert type constraints for inputs
       ;; - Translate the statements in the body
       ;; - Emit an (output ...) terminator with the result trivs as operands.
       (fluid-let ([default-src src])
         (let-values ([(var-name* arg-type*) (unzip-arguments arg*)])
           (let* ([constraint*
                    (fold-left (lambda (constraint* var-name type)
                                 (emit-constraints-for var-name type constraint*))
                      '() var-name* arg-type*)]
                  [instr*
                    (fold-left (lambda (instr* stmt) (Statement stmt instr*))
                      constraint* stmt*)]
                  [body
                    (if (null? triv*)
                        instr*
                        (cons
                          (with-output-language (Lzkir Instruction)
                            `(output ,triv* ...))
                          instr*))])
             `(circuit ,src (,(hashtable-ref export-ht function-name '()) ...)
                ((,var-name* ,(map type->string arg-type*)) ...)
                (,(map type->string primitive-type*) ...)
                ,(reverse body) ...))))])

    (Statement : Statement (ir instr*) -> * (instr*)
      [(= ,test (,var-name* ...) (call ,src ,function-name ,triv* ...))
       (let ([code-generator (hashtable-ref callable-ht function-name #f)])
         (assert code-generator)
         (code-generator var-name* src test triv* instr*))]
      [(= ,test (,var-name* ...) (contract-call ,src ,elt-name ((,recv* ...) ,primitive-type) ,triv* ...))
       (nanopass-case (Lflattened Primitive-Type) primitive-type
         [(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
            (cond
              [(null? elt-name*)
               (internal-errorf 'reduce-to-zkir
                 "contract-call references unknown circuit ~s on contract ~s"
                 elt-name contract-name)]
              [(eq? (car elt-name*) elt-name)
               (let ([callee-arg-type* (car type**)])
                 (let ([callee-input-primitive-type*
                        (apply append
                          (map (lambda (arg-ty)
                                 (nanopass-case (Lflattened Type) arg-ty
                                   [(ty (,alignment* ...) (,primitive-type* ...))
                                    primitive-type*]))
                               callee-arg-type*))])
                   (unless (fx= (length callee-input-primitive-type*) (length triv*))
                     (internal-errorf 'reduce-to-zkir
                       "contract-call argument arity mismatch for ~s.~s: ~s expected, ~s actual"
                       contract-name elt-name
                       (length callee-input-primitive-type*) (length triv*)))
                   (nanopass-case (Lflattened Type) (car type*)
                     [(ty (,alignment* ...) (,primitive-type* ...))
                      (unless (fx= (length primitive-type*) (length var-name*))
                        (internal-errorf 'reduce-to-zkir
                          "contract-call result arity mismatch for ~s.~s: ~s expected, ~s var-names"
                          contract-name elt-name
                          (length primitive-type*) (length var-name*)))
                      ;; The `desugar-contract-calls` circuit pass has already rewritten this
                      ;; cross-contract call into an extended contract-call whose result
                      ;; vector carries cc-rand / ep-mod / ep-div as extra witnessed values,
                      ;; plus an explicit transientCommit `call` and a kernel.claimContractCall
                      ;; `public-ledger`. So all that remains here is to witness the
                      ;; (extended) result vector — the transient hash and the claim are
                      ;; lowered by the generic call / public-ledger handlers.
                      ((make-witness alignment* primitive-type*) var-name* src test triv* instr*)])))]
              [else (loop (cdr elt-name*) (cdr type**) (cdr type*))]))]
         [else
          (internal-errorf 'reduce-to-zkir
            "contract-call primitive-type is not a tcontract")])]
      [(= ,test () (emit ,src ,event-version ,event-tag ,len ,triv* ... ,vm-code))
       (let* ([payload-primitive-type*
                (map (lambda (_)
                       (with-output-language (Lflattened Primitive-Type)
                         `(tfield (field-native))))
                     triv*)]
              [payload-alignment*
                (with-output-language (Lflattened Alignment)
                  (list `(abytes ,len)))]
              [env (list (cons 'emit-version event-version)
                         (cons 'emit-tag     event-tag)
                         (cons 'emit-payload (make-zkir-val payload-primitive-type* payload-alignment* triv*)))])
         (assemble test '() '() '() src '() env vm-code instr*))]
      [(= ,test (,var-name) (default ,opaque-type))
       (with-output-language (Lzkir Instruction)
         (case opaque-type
           [("JubjubPoint") (cons `(from_coordinates ,var-name 0 1) instr*)]
           [("Secp256k1Point")
            (let* ([tmp0 (make-temp-id default-src 'tmp)]
                   [tmp1 (make-temp-id default-src 'tmp)])
              (cons*
                `(ec_mul_generator ,var-name ,tmp1)
                `(from_bytes32 "Scalar<Secp256k1>" ,tmp1 ,tmp0)
                `(into_bytes32 ,tmp0 0)
                instr*))]
           [else (assert cannot-happen)]))]
      [(= ,test (,var-name0 ,var-name1) (field->bytes ,src ,len ,ftype ,triv))
       ;; TODO(kmillikin): this needs to respect test because `constrain_bits` can fail.
       ;; NB: missing-guard-workarounds now implements a workaround that ensures
       ;; field->bytes receives a large enough length that it won't produce
       ;; constrain_bits when the test might be false
       (with-output-language (Lzkir Instruction)
         (define (handle-secp256k1-field)
           (let ([tmp (make-temp-id src 'tmp)])
             (cons*
               `(bytes32_into_low_high ,var-name1 ,var-name0 ,tmp)
               `(into_bytes32 ,tmp ,triv)
               instr*)))
         (nanopass-case (Lflattened Field-Type) ftype
           [(field-base (curve-secp256k1)) (handle-secp256k1-field)]
           [(field-scalar (curve-secp256k1)) (handle-secp256k1-field)]
           [(field-native)
            (if (<= len (field-bytes))
                (cons*
                  `(constrain_bits ,var-name1 ,(* len 8))
                  `(copy ,var-name1 ,triv)
                  instr*)
                (cons `(div_mod_power_of_two ,var-name0 ,var-name1 ,triv ,(* (field-bytes) 8))
                  instr*))]))]
      [(= ,test (,var-name0 ,var-name1) (div-mod-power-of-two ,triv ,bits))
       (with-output-language (Lzkir Instruction)
         (cons
           `(div_mod_power_of_two ,var-name0 ,var-name1 ,triv ,bits)
           instr*))]
      [(= ,test (,var-name* ...) (bytes->vector ,triv))
       (assert (not (null? var-name*)))
       (with-output-language (Lzkir Instruction)
         (let loop ([var-name* var-name*] [var triv] [instr* instr*])
           (if (null? (cdr var-name*))
               (cons `(copy ,(car var-name*) ,var) instr*)
               (let ([quo (make-temp-id default-src 'quo)])
                 (loop (cdr var-name*) quo
                   (cons `(div_mod_power_of_two ,quo ,(car var-name*) ,var ,8) instr*))))))]
      [(= ,test (,var-name* ...) (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...)
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
                               (cons (cons (car formal*)
                                       (make-zkir-val primitive-type* alignment* var*))
                                 env)))])))])
            (assemble test primitive-type* alignment* var-name* src (map Path-Element path-elt*)
              env
              vm-code
              instr*))])]
      [(= ,test ,var-name ,single)
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
      [(< ,bits ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (cons `(less_than ,var-name ,triv0 ,triv1 ,bits) instr*))]
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
      [(bytes->field ,src ,ftype ,len ,triv0 ,triv1)
       (with-output-language (Lzkir Instruction)
         (define (handle-secp256k1-field)
           (let ([tmp (make-temp-id src 'tmp)])
             (cons*
               `(from_bytes32 ,(field-type->string ftype) ,var-name ,tmp)
               `(bytes32_from_low_high ,tmp ,triv1 ,triv0)
               instr*)))
         (nanopass-case (Lflattened Field-Type) ftype
           [(field-base (curve-secp256k1)) (handle-secp256k1-field)]
           [(field-scalar (curve-secp256k1)) (handle-secp256k1-field)]
           [(field-native)
            ;; TODO(kmillikin): This should respect test and be conditional in the ZKIR output.
            ;; NB: missing-guard-workarounds now implements a workaround that ensures
            ;; bytes->field receives inputs that can't cause reconstitute_field
            ;; to fail when test turns out to be false
            (with-output-language (Lzkir Instruction)
              ;; flatten-datatype takes care of this case.
              (assert (> len (field-bytes)))
              (cons `(reconstitute_field ,var-name ,triv0 ,triv1 ,(* 8 (field-bytes))) instr*))]))]
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
                   ; TODO: use of reconstitute_field should be conditioned on test
                   ; NB: missing-guard-workarounds now implements a workaround that ensures
                   ; vector->bytes gets valid inputs when test turns out to be false
                   (cons `(reconstitute_field ,result ,div ,current ,8) instr*)))))]
      [(cast-to-field ,ftype ,primitive-type ,triv)
       ;; The types are distinct, which means that the source for a Scalar<Jubjub> target must be
       ;; Scalar<BLS12-381> (Compact `Field` or `Uint` types) and the source for a Scalar<BLS12-381>
       ;; target must be Scalar<Jubjub> (`Uint` sources are `safe-cast`s).
       (with-output-language (Lzkir Instruction)
         (cons (nanopass-case (Lflattened Field-Type) ftype
                 [(field-native) `(encode (,var-name) ,triv)]
                 [(field-scalar (curve-jubjub)) `(jubjub_scalar_from_native ,var-name ,triv)])
           instr*))]
      [(cast-from-field ,src ,safe ,nat ,ftype ,triv)
       ;; TODO(kmillikin): This needs to be conditional on test.
       ;; NB: missing-guard-workarounds now implements a workaround that ensures
       ;; cast-from-field's safe flag is #t whenever the test might be false.
       (let ([instr* (cons (with-output-language (Lzkir Instruction)
                             (nanopass-case (Lflattened Field-Type) ftype
                               [(field-native)
                                ;; TODO(kmillikin): The `copy` here is unnecessary.  Remove it.
                                `(copy ,var-name ,triv)]
                               [(field-scalar (curve-jubjub))
                                `(encode (,var-name) ,triv)]))
                       instr*)])
         (if safe
             instr*
             (emit-constraints-for var-name
               (with-output-language (Lflattened Primitive-Type) `(tunsigned ,nat))
               instr*)))]
      [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,triv)
       ;; TODO(kmillikin): This needs to be conditional on test.
       ;; NB: missing-guard-workarounds now implements a workaround that ensures
       ;; downcast-unsigned's safe flag is #t whenever the test might be false.
       (with-output-language (Lzkir Instruction)
         ;; TODO(kmillikin): The `copy` here is unnecessary.  Remove it.
         (cons `(copy ,var-name ,triv)
           (if safe
               instr*
               (emit-constraints-for triv
                 (with-output-language (Lflattened Primitive-Type) `(tunsigned ,nat1))
                 instr*))))]
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
          (make-zkir-val primitive-type* alignment* triv*)])])
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
      [(circuit ,src (,name* ...) ((,var-name* ,zkir-type*) ...) (,zkir-type0* ...) ,instr* ...)
       (define (print-circuit op)
         (print-json-compact op
           (with-var-table
             (let* ([inputs (list->vector (maplr (lambda (var-name zkir-type)
                                                   `((name . ,(var->string var-name))
                                                     (type . ,zkir-type)))
                                            var-name* zkir-type*))]
                    [instructions (list->vector (maplr Instruction instr*))]
                    [outputs (list->vector zkir-type0*)])
               `((version . ((major . 3) (minor . 0)))
                 (do_communications_commitment . #t)
                 (inputs . ,inputs)
                 (outputs . ,outputs)
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
      [(bytes32_from_low_high ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "bytes32_from_low_high") (output . ,outp) (inputs . ,(vector inp0 inp1)))]
      [(bytes32_into_low_high ,outp0 ,outp1 ,[* inp])
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "bytes32_into_low_high") (outputs . ,(vector outp0 outp1)) (bytes . ,inp)))]
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
      [(div_mod_power_of_two ,[* outp0] ,[* outp1] ,[* inp] ,imm)
       `((op . "div_mod_power_of_two") (outputs . ,(vector outp0 outp1)) (val . ,inp)
         (bits . ,imm))]
      [(ec_mul ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "ec_mul") (output . ,outp) (a . ,inp0) (scalar . ,inp1))]
      [(ec_mul_generator ,[* outp] ,[* inp])
       `((op . "ec_mul_generator") (output . ,outp) (scalar . ,inp))]
      [(encode (,outp* ...) ,[* inp])
       (let ([outp* (maplr Output outp*)])
         `((op . "encode") (outputs . ,(list->vector outp*)) (input . ,inp)))]
      [(from_bytes32 ,zkir-type ,[* outp] ,[* inp])
       `((op . "from_bytes32") (type . ,zkir-type) (output . ,outp) (bytes . ,inp))]
      [(from_coordinates ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "from_coordinates") (output . ,outp) (inputs . ,(vector inp0 inp1)))]
      [(hash_to_curve ,[* outp] ,[* inp*] ...)
       `((op . "hash_to_curve") (output . ,outp) (inputs . ,(list->vector inp*)))]
      [(impact ,[* inp] ,[* inp*] ...)
       `((op . "impact") (guard . ,inp) (inputs . ,(list->vector inp*)))]
      [(into_bytes32 ,[* outp] ,[* inp])
       `((op . "into_bytes32") (output . ,outp) (input . ,inp))]
      [(into_coordinates ,outp0 ,outp1 ,[* inp])
       (let* ([outp0 (Output outp0)] [outp1 (Output outp1)])
         `((op . "into_coordinates") (outputs . ,(vector outp0 outp1)) (point . ,inp)))]
      [(inv ,[* outp] ,[* inp])
       `((op . "inv") (output . ,outp) (a . ,inp))]
      [(jubjub_scalar_from_native ,[* outp] ,[* inp])
       `((op . "jubjub_scalar_from_native") (output . ,outp) (native . ,inp))]
      [(keccak256 ,[* outp] (,alignment* ...) ,[* inp*] ...)
       `((op . "keccak256") (output . ,outp)
         (alignment . ,(alignment->vector alignment*)) (inputs . ,(list->vector inp*)))]
      [(less_than ,[* outp] ,[* inp0] ,[* inp1] ,imm)
       `((op . "less_than") (output . ,outp) (a . ,inp0) (b . ,inp1) (bits . ,imm))]
      [(mul ,[* outp] ,[* inp0] ,[* inp1])
       `((op . "mul") (output . ,outp) (a . ,inp0) (b . ,inp1))]
      [(neg ,[* outp] ,[* inp])
       `((op . "neg") (output . ,outp) (a . ,inp))]
      ;; TODO(kmillikin): we don't actually use this instruction, we use (cond_select t 0 1).  But
      ;; we should use this one instead.
      [(not ,[* outp] ,[* inp])
       `((op . "not") (output . ,outp) (a . ,inp))]
      [(output ,[* inp*] ...)
       `((op . "output") (vals . ,(list->vector inp*)))]
      [(persistent_hash ,[* outp] (,alignment* ...) ,[* inp*] ...)
       `((op . "persistent_hash") (output . ,outp)
         (alignment . ,(alignment->vector alignment*)) (inputs . ,(list->vector inp*)))]
      [(private_input ,zkir-type ,[* outp])
       ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
       ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "private_input") (type . ,zkir-type) (output . ,outp) (guard . ,(void)))]
      [(private_input ,zkir-type ,[* outp] ,[* inp])
       `((op . "private_input") (type . ,zkir-type) (output . ,outp) (guard . ,inp))]
      [(public_input ,zkir-type ,[* outp])
       ;; Kind of warty: rather than a literal true guard or making it truly optional by leaving it
       ;; out of the JSON representation, ZKIR wants to put a JSON null value there.
       `((op . "public_input") (type . ,zkir-type) (output . ,outp) (guard . ,(void)))]
      [(public_input ,zkir-type ,[* outp] ,[* inp])
       `((op . "public_input") (type . ,zkir-type) (output . ,outp) (guard . ,inp))]
      [(reconstitute_field ,[* outp] ,[* inp0] ,[* inp1] ,imm)
       `((op . "reconstitute_field") (output . ,outp) (divisor . ,inp0) (modulus . ,inp1)
         (bits . ,imm))]
      [(reverse_bytes ,[* outp] ,[* inp])
       `((op . "reverse_bytes") (output . ,outp) (bytes . ,inp))]
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
