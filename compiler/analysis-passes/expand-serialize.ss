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

(define-pass expand-serialize : Lnodisclose (ir) -> Lnoserialize ()
  (definitions
    (define (format-field-type ftype)
      (nanopass-case (Lnoserialize Field-Type) ftype
        [(field-native) "Field"]
        [(field-scalar (curve-jubjub)) "JubjubScalar"]
        [(field-base (curve-secp256k1)) "Secp256k1Base"]
        [(field-scalar (curve-secp256k1)) "Secp256k1Scalar"]))
    (define (format-type type)
      (nanopass-case (Lnoserialize Type) type
        [(tboolean ,src) "Boolean"]
        [(tfield ,src ,ftype) (format-field-type ftype)]
        [(tunsigned ,src ,nat)
         (or (and (> nat 0)
                  (let ([bits (integer-length nat)])
                    (and (= (expt 2 bits) (+ nat 1))
                         (format "Uint<~d>" bits))))
             (format "Uint<0..~d>" (+ nat 1)))]
        [(topaque ,src ,opaque-type) (format "Opaque<~s>" opaque-type)]
        [(tunknown) "Unknown"]
        [(tvector ,src ,len ,type) (format "Vector<~s, ~a>" len (format-type type))]
        [(tbytes ,src ,len) (format "Bytes<~s>" len)]
        [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
         (format "contract ~a<~{~a~^, ~}>" contract-name
           (map (lambda (elt-name pure-dcl type* type)
                  (if pure-dcl
                      (format "pure ~a(~{~a~^, ~}): ~a" elt-name
                              (map format-type type*) (format-type type))
                      (format "~a(~{~a~^, ~}): ~a" elt-name
                              (map format-type type*) (format-type type))))
                elt-name* pure-dcl* type** type*))]
        [(ttuple ,src ,type* ...)
         (format "[~{~a~^, ~}]" (map format-type type*))]
        [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
         (format "struct ~a<~{~a~^, ~}>" struct-name
           (map (lambda (elt-name type)
                  (format "~a: ~a" elt-name (format-type type)))
                elt-name* type*))]
        [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
         (format "Enum<~a, ~s~{, ~s~}>" enum-name elt-name elt-name*)]
        [(talias ,src ,nominal? ,type-name ,type)
         (if nominal?
             (format "~a" type-name)
             (format-type type))]
        [else (internal-errorf 'format-type "unrecognized type ~a" type)]))

    (define (field-length-in-bytes ftype)
      (nanopass-case (Lnoserialize Field-Type) ftype
        [(field-native) (1+ (field-bytes))]
        [(field-scalar (curve-jubjub)) (1+ (field-bytes))]
        [(field-base (curve-secp256k1)) 32]
        [(field-scalar (curve-secp256k1)) 32]))

    (define (native-field-type)
      (with-output-language (Lnoserialize Field-Type) `(field-native)))

    ;; expr has type `type` and the result has type `Bytes<len>`.  It is a static
    ;; error if the serialized form of `type` occupies more than `len` bytes.  If
    ;; it occupies less than `len` bytes, 0 bytes are added at the end to bring the
    ;; length up to `len` bytes.
    (define (build-serialize src type expr len?)
      (define (bytes-or-tuple-arg as-bytes? nbytes expr)
        (if as-bytes?
            expr
            (with-output-language (Lnoserialize Tuple-Argument)
              `(spread ,src ,nbytes
                 (bytes->vector ,src ,nbytes ,expr)))))
      (define (make-tuple-ref src expr kindex)
        (with-output-language (Lnoserialize Expression)
          `(tuple-ref ,src ,expr ,kindex)))
      (define (make-elt-ref src expr elt-name i)
        (with-output-language (Lnoserialize Expression)
          `(elt-ref ,src ,expr ,elt-name ,i)))
      (define (maybe-bind src multiple? rx* rt* re* type expr k)
        (if (and multiple?
                 (nanopass-case (Lnoserialize Expression) expr
                   [(quote ,src ,datum) #f]
                   [(var-ref ,src ,var-name) #f]
                   [else #t]))
            (let* ([x (make-temp-id src 't)])
              (k (cons x rx*) (cons type rt*) (cons expr re*)
                 (with-output-language (Lnoserialize Expression)
                   `(var-ref ,src ,x))))
            (k rx* rt* re* expr)))
      (define (maybe-add-let* x* t* e* expr)
        (if (null? x*)
            expr
            (with-output-language (Lnoserialize Expression)
              `(let* ,src ([(,x* ,t*) ,e*] ...) ,expr))))
      (define (go type expr rx* rt* re* n rta* k)
        (define (do-unsigned nat expr)
          (cond
            [(eqv? nat 0) (k rx* rt* re* n rta*)]
            [(<= nat 255)
             (k rx* rt* re* (+ n 1)
                (cons
                  (lambda (as-bytes?)
                    (if as-bytes?
                        (let ([ftype (native-field-type)])
                          (with-output-language (Lnoserialize Expression)
                            `(field->bytes ,src 1 ,ftype
                               (safe-cast ,src (tfield ,src ,ftype) (tunsigned ,src ,nat) ,expr))))
                        (with-output-language (Lnoserialize Tuple-Argument)
                          `(single ,src
                             ,(if (eqv? nat 255)
                                  expr
                                  `(safe-cast ,src (tunsigned ,src 255) (tunsigned ,src ,nat) ,expr))))))
                  rta*))]
            [else
             (let ([nbytes (quotient (+ (integer-length nat) 7) 8)]
                   [ftype (native-field-type)])
               (k rx* rt* re* (+ n nbytes)
                  (cons
                    (lambda (as-bytes?)
                      (bytes-or-tuple-arg as-bytes? nbytes
                        (with-output-language (Lnoserialize Expression)
                          `(field->bytes ,src ,nbytes ,ftype
                             (safe-cast ,src (tfield ,src ,ftype) (tunsigned ,src ,nat) ,expr)))))
                    rta*)))]))
        (nanopass-case (Lnoserialize Type) type
          [(tboolean ,src^)
           (k rx* rt* re* (+ n 1)
              (cons
                (lambda (as-bytes?)
                  (if as-bytes?
                      (with-output-language (Lnoserialize Expression)
                        `(if ,src ,expr
                             (quote ,src #vu8(1))
                             (quote ,src #vu8(0))))
                      (with-output-language (Lnoserialize Tuple-Argument)
                        `(single ,src
                           (if ,src ,expr
                               (safe-cast ,src (tunsigned ,src 255) (tunsigned ,src 1) (quote ,src 1))
                               (safe-cast ,src (tunsigned ,src 255) (tunsigned ,src 0) (quote ,src 0)))))))
                rta*))]
          [(tfield ,src^ ,ftype)
           (let ([len (field-length-in-bytes ftype)])
             (k rx* rt* re* (+ n len)
               (cons
                 (lambda (as-bytes?)
                   (bytes-or-tuple-arg as-bytes? len
                     (with-output-language (Lnoserialize Expression)
                       `(field->bytes ,src ,len ,ftype ,expr))))
                 rta*)))]
          [(tunsigned ,src^ ,nat)
           (do-unsigned nat expr)]
          [(tbytes ,src^ ,len)
           (k rx* rt* re* (+ n len)
              (cons
                (lambda (as-bytes?)
                  (bytes-or-tuple-arg as-bytes? len expr))
                rta*))]
          [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
           (let ([nat (length elt-name*)])
             (do-unsigned nat
               (with-output-language (Lnoserialize Expression)
                 `(cast-from-enum ,src (tunsigned ,src ,nat) ,type ,expr))))]
          [(tvector ,src^ ,len ,type^)
           (maybe-bind src (fx> len 1) rx* rt* re* type expr
             (lambda (rx* rt* re* expr)
               (let f ([len len] [i 0] [rx* rx*] [rt* rt*] [re* re*] [n n] [rta* rta*])
                 (if (fx= len 0)
                     (k rx* rt* re* n rta*)
                     (go type^ (make-tuple-ref src expr i) rx* rt* re* n rta*
                         (lambda (rx* rt* re* n rta*)
                           (f (fx- len 1) (fx+ i 1) rx* rt* re* n rta*)))))))]
          [(ttuple ,src^ ,type* ...)
           (maybe-bind src (fx> (length type*) 1) rx* rt* re* type expr
             (lambda (rx* rt* re* expr)
               (let f ([type* type*] [i 0] [rx* rx*] [rt* rt*] [re* re*] [n n] [rta* rta*])
                 (if (null? type*)
                     (k rx* rt* re* n rta*)
                     (go (car type*) (make-tuple-ref src expr i) rx* rt* re* n rta*
                         (lambda (rx* rt* re* n rta*)
                           (f (cdr type*) (fx+ i 1) rx* rt* re* n rta*)))))))]
          [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
           (maybe-bind src (fx> (length type*) 1) rx* rt* re* type expr
             (lambda (rx* rt* re* expr)
               (let f ([type* type*] [elt-name* elt-name*] [i 0] [rx* rx*] [rt* rt*] [re* re*] [n n] [rta* rta*])
                 (if (null? type*)
                     (k rx* rt* re* n rta*)
                     (go (car type*) (make-elt-ref src expr (car elt-name*) i) rx* rt* re* n rta*
                         (lambda (rx* rt* re* n rta*)
                           (f (cdr type*) (cdr elt-name*) (fx+ i 1) rx* rt* re* n rta*)))))))]
          [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (source-errorf src "type ~a (contract) is not serializable" (format-type type))]
          [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (source-errorf src "type ~a (ADT) is not serializable" (format-type type))]
          [(topaque ,src^ ,opaque-type)
           (source-errorf src "type ~a (opaque) is not serializable" (format-type type))]
          [else (internal-errorf 'build-serialize "unhandled type ~s" type)]))
        (go type expr '() '() '() 0 '()
            (lambda (rx* rt* re* n rta*)
              (when (and len? (> n len?))
                (source-errorf src "actual serialized size ~d exceeds specified length ~d for type ~a"
                               n len? (format-type type)))
              (let ([len (or len? n)])
                (values
                  len
                  (maybe-add-let* (reverse rx*) (reverse rt*) (reverse re*)
                    (with-output-language (Lnoserialize Expression)
                      (if (and (fx<= (length rta*) 1) (= n len))
                          (if (null? rta*)
                              `(quote ,src #vu8())
                              ((car rta*) #t))
                          `(vector->bytes ,src ,len
                             (vector ,src
                               ,(reverse
                                  (let ([rta* (map (lambda (rta) (rta #f)) rta*)])
                                    (if (= n len)
                                        rta*
                                        (let ([pad (- len n)])
                                          (cons
                                            `(spread ,src ,pad
                                               (bytes->vector ,src ,pad
                                                 (quote ,src ,(make-bytevector pad 0))))
                                            rta*)))))
                               ...))))))))))

    ;; expr has type `Bytes<len>`, and the result has type `type`.  It is a static
    ;; error if the serialized form of `type` occupies more than `len` bytes.
    ;; If the serialized form occupies less than `len` bytes, the remaining bytes
    ;; are ignored but should be zero.
    (define (build-deserialize src type expr len)
      (let ([bytes-type (with-output-language (Lnoserialize Type)
                          `(tbytes ,src ,len))])
        (define (maybe-add-let expr k)
          (nanopass-case (Lnoserialize Expression) expr
            [(quote ,src ,datum) (k expr)]
            [(var-ref ,src ,var-name) (k expr)]
            [else (let ([t (make-temp-id src 't)])
                    (with-output-language (Lnoserialize Expression)
                      `(let* ,src ([(,t ,bytes-type) ,expr])
                         ,(k `(var-ref ,src ,t)))))]))
        (maybe-add-let expr
          (lambda (expr)
            (define (go type i)
              (with-output-language (Lnoserialize Expression)
                (define (do-unsigned nat k)
                  (cond
                    [(eqv? nat 0) (values i (k `(quote ,src 0)))]
                    [else
                     (let ([nbytes (quotient (+ (integer-length nat) 7) 8)])
                       (values
                         (+ i nbytes)
                         (k `(cast-from-bytes ,src (tunsigned ,src ,nat) ,nbytes
                               (bytes-slice ,src ,bytes-type ,expr (quote ,src ,i) ,nbytes)))))]))
                (nanopass-case (Lnoserialize Type) type
                  [(tboolean ,src^)
                   (values
                     (+ i 1)
                     `(== ,src
                          (tunsigned ,src 255)
                          (bytes-ref ,src ,bytes-type ,expr (quote ,src ,i))
                          (safe-cast ,src (tunsigned ,src 255) (tunsigned ,src 1) (quote ,src 1))))]
                  [(tfield ,src^ ,ftype)
                   (let ([len (field-length-in-bytes ftype)])
                     (values
                       (+ i len)
                       `(cast-from-bytes ,src (tfield ,src ,ftype) ,len
                          (bytes-slice ,src ,bytes-type ,expr (quote ,src ,i) ,len))))]
                  [(tunsigned ,src^ ,nat)
                   (do-unsigned nat values)]
                  [(tbytes ,src^ ,len)
                   (values
                     (+ i len)
                     (if (eqv? len 0)
                         `(quote ,src #vu8())
                         `(bytes-slice ,src ,bytes-type ,expr (quote ,src ,i) ,len)))]
                  [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
                   (let ([nat (length elt-name*)])
                     (do-unsigned nat
                       (lambda (expr)
                         `(cast-to-enum ,src ,type (tunsigned ,src ,nat) ,expr))))]
                  [(tvector ,src^ ,len ,type^)
                   (let loop ([len len] [i i] [rexpr* '()])
                     (if (fx= len 0)
                         (values
                           i
                           `(vector ,src
                              ,(fold-left
                                 (lambda (expr* expr)
                                   (cons `(single ,src ,expr) expr*))
                                 '()
                                 rexpr*)
                              ...))
                         (let-values ([(i expr) (go type^ i)])
                           (loop (fx- len 1) i (cons expr rexpr*)))))]
                  [(ttuple ,src^ ,type* ...)
                   (let loop ([type* type*] [i i] [rexpr* '()])
                     (if (null? type*)
                         (values
                           i
                           `(tuple ,src
                              ,(fold-left
                                 (lambda (expr* expr)
                                   (cons `(single ,src ,expr) expr*))
                                 '()
                                 rexpr*)
                              ...))
                         (let-values ([(i expr) (go (car type*) i)])
                           (loop (cdr type*) i (cons expr rexpr*)))))]
                  [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
                   (let loop ([type* type*] [i i] [rexpr* '()])
                     (if (null? type*)
                         (values i `(new ,src ,type ,(reverse rexpr*) ...))
                         (let-values ([(i expr) (go (car type*) i)])
                           (loop (cdr type*) i (cons expr rexpr*)))))]
                  [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                   (source-errorf src "type ~a (contract) is not deserializable" (format-type type))]
                  [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                   (source-errorf src "type ~a (ADT) is not deserializable" (format-type type))]
                  [(topaque ,src^ ,opaque-type)
                   (source-errorf src "type ~a (opaque) is not deserializable" (format-type type))]
                  [else (internal-errorf 'build-deserialize "unhandled type ~s" type)])))
            (let-values ([(i expr) (go type 0)])
              (unless (<= i len)
                (source-errorf src "actual serialized size ~d exceeds specified length ~d for type ~a"
                               i len (format-type type)))
              expr)))))
    )
  (Expression : Expression (ir) -> Expression ()
    [(emit ,src ,[type] ,[expr])
     (let-values ([(n expr) (build-serialize src type expr #f)])
       `(emit ,src ,type ,n ,expr))]
    [(serialize ,src ,len ,[type] ,[expr])
     (let-values ([(n expr) (build-serialize src type expr len)])
       expr)]
    [(deserialize ,src ,len ,[type] ,[expr])
     (build-deserialize src type expr len)]))
