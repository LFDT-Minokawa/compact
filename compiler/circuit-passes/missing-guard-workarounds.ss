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

#!chezscheme

(define-pass missing-guard-workarounds : Lflattened (ir) -> Lflattened ()
  ; This pass implements workarounds for the lack of conditionality of
  ; certain zkir operators.  The lack of conditionality burns in one of
  ; two ways: explicit checks like constrain_bits fail even when the
  ; conditional says not to execute it, and implicit operand checks, e.g.,
  ; by less_than, fail because an input value is undefined and might have
  ; any value due to the conditionality of the input value's computation.
  ; To avoid being overly paranoid, the pass records whether a variable
  ; definitely has a value and skips remediation for unknown values when
  ; a variable is defined.  It also implements various special cases to
  ; avoid generating the worst-case code unless necessary.
  ;
  ; Once zkir implements conditionality for the operators that can fail,
  ; this pass can simply be removed.
  (definitions
    (define-syntax with-temp-ids
      (syntax-rules ()
        [(_ src (t ...) b1 b2 ...)
         (let* ([t (make-temp-id src 't)] ...) b1 b2 ...)]))
    (module (def-ht defined! defined?)
      (define def-ht)
      (define (defined! var-name) (hashtable-set! def-ht var-name #t))
      (define (defined? triv)
        (or (not (id? triv))
            (hashtable-contains? def-ht triv))))
    (define (ensure-defined src test triv k)
      (if (defined? triv)
          (k triv)
          (with-output-language (Lflattened Statement)
            (with-temp-ids src (t)
              (cons `(= 1 ,t (select ,test ,triv 0))
                    (k t)))))))
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
     (fluid-let ([def-ht (make-eq-hashtable)])
       (for-each
         (lambda (arg)
           (nanopass-case (Lflattened Argument) arg
             [(argument (,var-name* ...) ,type) (for-each defined! var-name*)]))
         arg*)
       (let ([stmt* (apply append (maplr Statement stmt*))])
         `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))))])
  (Statement : Statement (ir) -> * (stmt*)
    [(= ,test ,var-name ,single)
     (when (eqv? test 1) (defined! var-name))
     (if (eqv? test 1)
         (list ir)
         (Single single test var-name))]
    [(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,triv))
     (if (or (eqv? test 1)
             (nanopass-case (Lflattened Field-Type) ftype
               [(field-native) (> len (field-bytes))]
               [(field-base (curve-secp256k1)) #t]
               [(field-scalar (curve-secp256k1)) #t]
               [else #f]))
         (list ir)
         (with-output-language (Lflattened Statement)
           (with-temp-ids (id-src var-name1) (q t1 t2)
             (list
               ; q represents everything that doesn't fit in len bytes and must be zero for the cast to succeed
               `(= 1 (,q ,var-name2) (div-mod-power-of-two ,triv ,(fx* len 8)))
               ; t1 = q == 0
               `(= 1 ,t1 (== ,q 0))
               ; t2 = !test || q == 0
               `(= 1 ,t2 (select ,test ,t1 1))
               `(assert ,src ,t2 ,(format "field value is too large to fit in ~d bytes" len))
               ; cast-from-field is used here with safe = #t to make check-types/Lflattened happy
               `(= 1 ,var-name1 (cast-from-field ,src #t 0
                                  ,(with-output-language (Lflattened Field-Type) `(field-native))
                                  ,q))))))]
    [(= ,test (,var-name* ...) ,multiple)
     (when (eqv? test 1) (for-each defined! var-name*))
     (list ir)]
    [(assert ,src ,test ,mesg) (list ir)])
  (Single : Single (ir test var-name) -> * (stmt*)
    [(< ,bits ,triv1 ,triv2)
     (with-output-language (Lflattened Statement)
       (ensure-defined (id-src var-name) test triv1
         (lambda (triv1)
           (ensure-defined (id-src var-name) test triv2
             (lambda (triv2)
               (list `(= 1 ,var-name (< ,bits ,triv1 ,triv2))))))))]
    [(bytes->field ,src ,ftype ,len ,triv1 ,triv2)
     (nanopass-case (Lflattened Field-Type) ftype
       [(field-base (curve-secp256k1)) (list `(= 1 ,var-name ,ir))]
       [(field-scalar (curve-secp256k1)) (list `(= 1 ,var-name ,ir))]
       [(field-native) (guard (<= len (field-bytes))) (list `(= 1 ,var-name ,ir))]
       [(field-native)
        (with-output-language (Lflattened Statement)
          ;; 256^k is one more than the largest value that fits in k bytes,
          ;; i.e., k base-256 digits, and is the same as 2^(8k).  So this use
          ;; of div-and-mod produces a remainder r representing the value of
          ;; the low-order (field-bytes) bytes of (max-field) and a quotient
          ;; q representing the value of the bits above that.  triv1 must be
          ;; less than or equal to q, and when triv1 = q, triv2 must be less
          ;; than or equal to r.
          (let-values ([(q r) (div-and-mod (max-field) (expt 256 (field-bytes)))])
            (ensure-defined (id-src var-name) test triv1
              (lambda (triv1)
                (ensure-defined (id-src var-name) test triv2
                  (lambda (triv2)
                    (with-temp-ids (id-src var-name) (t1 t2 t3 t4 t5 t6 t7)
                      (list
                        ;; t1 = triv1 < q
                        `(= 1 ,t1 (< ,(unsigned-bits) ,triv1 ,q))
                        ;; t2 = triv1 == q
                        `(= 1 ,t2 (== ,triv1 ,q))
                        ;; t3 = triv2 > r
                        `(= 1 ,t3 (< ,(unsigned-bits) ,r ,triv2))
                        ;; t4 = !(triv2 > r) && triv1 == 0
                        ;;    = triv1 == 0 && triv2 <= r
                        `(= 1 ,t4 (select ,t3 0 ,t2))
                        ;; t5 = triv1 < q || triv1 == 0 && triv2 <= r
                        `(= 1 ,t5 (select ,t1 1 ,t4))
                        ;; t6 = !test || triv1 < q || triv1 == 0 && triv2 <= r
                        `(= 1 ,t6 (select ,test ,t5 1))
                        `(assert ,src ,t6 "bytes value is too big to fit in a field")
                        ;; when bytes->field would fail, provide it something innocuous
                        `(= 1 ,t7 (select ,t5 ,triv1 0))
                        `(= 1 ,var-name (bytes->field ,src ,ftype ,len ,t7 ,triv2))))))))))]
       [else (assert cannot-happen)])]
    [(vector->bytes ,triv ,triv* ...)
     (with-output-language (Lflattened Statement)
       (let f ([triv* (cons triv triv*)] [rtriv* '()])
         (if (null? triv*)
             (let ([triv* (reverse rtriv*)])
               (list `(= 1 ,var-name (vector->bytes ,(car triv*) ,(cdr triv*) ...))))
             (ensure-defined (id-src var-name) test (car triv*)
               (lambda (triv) (f (cdr triv*) (cons triv rtriv*)))))))]
    [(cast-from-field ,src ,safe? ,nat ,ftype ,triv)
     (with-output-language (Lflattened Statement)
       (if safe?
           (list `(= 1 ,var-name ,ir))
           (let ([bits (fxmax 1 (integer-length nat))])
             ;; triv might have any field value
             (let ([bits (fxmax 1 (integer-length nat))])
               (with-temp-ids (id-src var-name) (q r t1)
                 (define (assert-and-cast test)
                   (list
                     `(assert ,src ,test ,(format "cast to Uint<0..~d> failed" nat))
                     ;; downcast-unsigned is used here with safe = #t to make check-types/Lflattened happy
                     `(= 1 ,var-name (downcast-unsigned ,src #t ,(expt 2 bits) ,nat ,r))))
                 (cons*
                   `(= 1 (,q ,r) (div-mod-power-of-two ,triv ,bits))
                   ;; q represents the high bits and must be zero for the cast to succeed
                   ;; t1 = q == 0
                   `(= 1 ,t1 (== ,q 0))
                   ;; r represents the low bits and must be <= nat for the cast to succeed
                   (if (= nat (- (expt 2 bits) 1))
                       ;; in this case, r cannot be > nat
                       (with-temp-ids (id-src var-name) (t2)
                         (cons
                           ;; t2 = !test || q == 0
                           `(= 1 ,t2 (select ,test ,t1 1))
                           (assert-and-cast t2)))
                       (with-temp-ids (id-src var-name) (t2 t3 t4)
                         (cons*
                           ;; t2 = r <= nat
                           `(= 1 ,t2 (< ,bits ,r ,(+ nat 1)))
                           ;; t3 = q == 0 && r <= nat
                           `(= 1 ,t3 (select ,t1 ,t2 0))
                           ;; t4 = !test || (q == 0 && r <= nat)
                           `(= 1 ,t4 (select ,test ,t3 1))
                           (assert-and-cast t4))))))))))]
    [(downcast-unsigned ,src ,safe? ,nat2 ,nat1 ,triv)
     (with-output-language (Lflattened Statement)
       (if safe?
           (list `(= 1 ,var-name ,ir))
           (if (= nat1 nat2)
               ;; it's probably always the case that nat1 < nat2, but handle this case anyway
               (list `(= 1 ,var-name ,triv))
               (ensure-defined (id-src var-name) test triv
                 (lambda (triv)
                   ;; triv is known to be < nat2
                   (with-temp-ids src (t1 t2)
                     (list
                       ;; t1 = triv <= nat1
                       `(= 1 ,t1 (< ,(fxmax 1 (integer-length nat2)) ,triv ,(+ nat1 1)))
                       ;; t2 = !test || triv <= nat1
                       `(= 1 ,t2 (select ,test ,t1 1))
                       `(assert ,src ,t2 ,(format "downcast to Uint<0..~d> failed" nat1))
                       ;; downcast-unsigned is used here with safe = #t to make check-types/Lflattened happy
                       `(= 1 ,var-name (downcast-unsigned ,src #t ,nat2 ,nat1 ,triv)))))))))]
    [else
     (with-output-language (Lflattened Statement)
       (list `(= 1 ,var-name ,ir)))]))
