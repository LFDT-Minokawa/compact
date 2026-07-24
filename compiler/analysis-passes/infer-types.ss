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

(define-pass infer-types : Lexpanded (ir) -> Ltypes ()
  (definitions
    (define contract-type-ht)
    (define standard-event-ht)
    (define-syntax T
      (syntax-rules ()
        [(T ty clause ...)
         (nanopass-case (Ltypes Type) ty clause ... [else #f])]))
    (define-datatype Idtype
      ; ordinary expression types
      (Idtype-Base type)
      ; circuits, witnesses, and statements
      (Idtype-Function kind is-native arg-name* arg-type* return-type)
      )
    (module (set-idtype! unset-idtype! get-idtype)
      (define ht (make-eq-hashtable))
      (define (set-idtype! id idtype)
        (hashtable-set! ht id idtype))
      (define (unset-idtype! id)
        (hashtable-delete! ht id))
      (define (get-idtype src id)
        (or (hashtable-ref ht id #f)
            (internal-errorf 'get-idtype! "type of identifier ~s at ~a has not been set"
              (id-sym id)
              (format-source-object src))))
      )
    (define (arg->name arg)
      (nanopass-case (Ltypes Argument) arg
        [(,var-name ,type) var-name]))
    (define (arg->type arg)
      (nanopass-case (Ltypes Argument) arg
        [(,var-name ,type) type]))
    (define (format-field-type ftype)
      (nanopass-case (Ltypes Field-Type) ftype
        [(field-native) "Field"]
        [(field-scalar (curve-jubjub)) "JubjubScalar"]
        [(field-base (curve-secp256k1)) "Secp256k1Base"]
        [(field-scalar (curve-secp256k1)) "Secp256k1Scalar"]))
    (define (format-adt-arg adt-arg)
      (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg
        [,nat (format "~d" nat)]
        [,type (format-type type)]))
    (define (format-public-adt adt-name adt-arg*)
      (if (eq? adt-name '__compact_Cell)
          (begin
            (assert (= (length adt-arg*) 1))
            (format-adt-arg (car adt-arg*)))
          (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))))
    (define (format-type type)
      (nanopass-case (Ltypes Type) type
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
        [(tundeclared) "Undeclared"]
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
        [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
         (format-public-adt adt-name adt-arg*)]
        [else (internal-errorf 'format-type "unrecognized type ~a" type)]))
    (define (de-alias type nominal-too?)
      (nanopass-case (Ltypes Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (guard (or nominal-too? (not nominal?)))
         (de-alias type nominal-too?)]
        [else type]))
    (module (sametype? subtype?)
      (define (same-adt-arg? adt-arg1 adt-arg2)
        (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg1
          [,nat1
           (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg2
             [,nat2 (= nat1 nat2)]
             ; with current restrictions, this case won't get past ledger meta-type checks
             [else #f])]
          [,type1
           (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg2
             [,type2 (sametype? type1 type2)]
             ; with current restrictions, this case won't get past ledger meta-type checks
             [else #f])]))
      (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
        (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                  (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                           (and (eq? elt-name1 elt-name2)
                                (eq? pure-dcl1 pure-dcl2)
                                (fx= (length type1*) (length type2*))
                                (andmap sametype? type1* type2*)
                                (sametype? type1 type2)))
                         elt-name1* pure-dcl1* type1** type1*))
                elt-name2* pure-dcl2* type2** type2*))
      (define (same-curve-type? ctype1 ctype2)
        (nanopass-case (Ltypes Curve-Type) ctype1
          [(curve-jubjub)
           (nanopass-case (Ltypes Curve-Type) ctype2
             [(curve-jubjub) #t]
             [else #f])]
          [(curve-secp256k1)
           (nanopass-case (Ltypes Curve-Type) ctype2
             [(curve-secp256k1) #t]
             [else #f])]))
      (define (same-field-type? ftype1 ftype2)
        (nanopass-case (Ltypes Field-Type) ftype1
          [(field-native)
           (nanopass-case (Ltypes Field-Type) ftype2
             [(field-native) #t]
             [else #f])]
          [(field-base ,ctype1)
           (nanopass-case (Ltypes Field-Type) ftype2
             [(field-base ,ctype2) (same-curve-type? ctype1 ctype2)]
             [else #f])]
          [(field-scalar ,ctype1)
           (nanopass-case (Ltypes Field-Type) ftype2
             [(field-scalar ,ctype2) (same-curve-type? ctype1 ctype2)]
             [else #f])]))
      (define (sametype? type1 type2)
        (let ([type1 (de-alias type1 #f)] [type2 (de-alias type2 #f)])
          (or (eq? type1 type2)
              (T type1
                 [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
                 [(tfield ,src1 ,ftype1)
                  (T type2 [(tfield ,src2 ,ftype2) (same-field-type? ftype1 ftype2)])]
                 [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])]
                 [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
                 [(topaque ,src1 ,opaque-type1)
                  (T type2
                     [(topaque ,src2 ,opaque-type2)
                      (string=? opaque-type1 opaque-type2)])]
                 [(tvector ,src1 ,len1 ,type1)
                  (T type2
                     [(tvector ,src2 ,len2 ,type2)
                      (and (= len1 len2)
                           (sametype? type1 type2))]
                     [(ttuple ,src2 ,type2* ...)
                      (and (= len1 (length type2*))
                           (andmap (lambda (type2) (sametype? type1 type2)) type2*))])]
                 [(ttuple ,src1 ,type1* ...)
                  (T type2
                     [(tvector ,src2 ,len2 ,type2)
                      (and (= (length type1*) len2)
                           (andmap (lambda (type1) (sametype? type1 type2)) type1*))]
                     [(ttuple ,src2 ,type2* ...)
                      (and (= (length type1*) (length type2*))
                           (andmap sametype? type1* type2*))])]
                 [(tunknown) (T type2 [(tunknown) #t])]
                 [(tundeclared) (T type2 [(tundeclared) #t])]
                 [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                  (T type2
                     [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                      (and (eq? contract-name1 contract-name2)
                           (fx= (length elt-name1*) (length elt-name2*))
                           (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
                 [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                  (T type2
                     [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                      ; include struct-name and elt-name tests for nominal typing; remove
                      ; for structural typing.
                      (and (eq? struct-name1 struct-name2)
                           (fx= (length elt-name1*) (length elt-name2*))
                           (andmap eq? elt-name1* elt-name2*)
                           (andmap sametype? type1* type2*))])]
                 [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
                  (T type2
                     [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                      (and (eq? enum-name1 enum-name2)
                           (eq? elt-name1 elt-name2)
                           (fx= (length elt-name1*) (length elt-name2*))
                           (andmap eq? elt-name1* elt-name2*))])]
                 [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                  (assert nominal1?)
                  (T type2
                     [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                      (assert nominal2?)
                      (and (eq? type-name1 type-name2)
                           (sametype? type1 type2))])]
                 [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
                  (T type2
                     [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                      (and (eq? adt-name1 adt-name2)
                           (fx= (length adt-arg1*) (length adt-arg2*))
                           (andmap same-adt-arg? adt-arg1* adt-arg2*))])]))))
      (define (subtype? type1 type2)
        (let ([type1 (de-alias type1 #f)] [type2 (de-alias type2 #f)])
          (or (eq? type1 type2)
              (T type1
                 [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
                 [(tfield ,src1 ,ftype1)
                  (T type2 [(tfield ,src2 ,ftype2) (same-field-type? ftype1 ftype2)])]
                 [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (<= nat1 nat2)])]
                 [(tbytes ,src1 ,len1) (T type2 [(tbytes ,src2 ,len2) (= len1 len2)])]
                 [(topaque ,src1 ,opaque-type1)
                  (T type2
                     [(topaque ,src2 ,opaque-type2)
                      (string=? opaque-type1 opaque-type2)])]
                 [(tvector ,src1 ,len1 ,type1)
                  (T type2
                     [(tvector ,src2 ,len2 ,type2)
                      (and (= len1 len2)
                           (subtype? type1 type2))]
                     [(ttuple ,src2 ,type2* ...)
                      (and (= len1 (length type2*))
                           (andmap (lambda (type2) (subtype? type1 type2)) type2*))])]
                 [(ttuple ,src1 ,type1* ...)
                  (T type2
                     [(tvector ,src2 ,len2 ,type2)
                      (and (= (length type1*) len2)
                           (andmap (lambda (type1) (subtype? type1 type2)) type1*))]
                     [(ttuple ,src2 ,type2* ...)
                      (and (= (length type1*) (length type2*))
                           (andmap subtype? type1* type2*))])]
                 [(tunknown) #t] ; tunknown values originate from empty-vector constants.
                 [(tundeclared) (T type2 [(tundeclared) #t])]
                 [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                  (T type2
                     [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                      (and (eq? contract-name1 contract-name2)
                           (fx>= (length elt-name1*) (length elt-name2*))
                           (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
                 [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                  (T type2
                     [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                      ; include struct-name and elt-name tests for nominal typing; remove
                      ; and change sametype? to subtype? for structural typing.
                      (and (eq? struct-name1 struct-name2)
                           (fx= (length elt-name1*) (length elt-name2*))
                           (andmap eq? elt-name1* elt-name2*)
                           (andmap sametype? type1* type2*))])]
                 [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
                  (T type2
                     [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                      (and (eq? enum-name1 enum-name2)
                           (eq? elt-name1 elt-name2)
                           (fx= (length elt-name1*) (length elt-name2*))
                           (andmap eq? elt-name1* elt-name2*))])]
                 [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                  (assert nominal1?)
                  (T type2
                     [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                      (assert nominal2?)
                      (and (eq? type-name1 type-name2)
                           (sametype? type1 type2))])]
                 [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr (,adt-op1* ...) (,adt-rt-op1* ...))
                  (T type2
                     [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr (,adt-op2* ...) (,adt-rt-op2* ...))
                      (and (eq? adt-name1 adt-name2)
                           (fx= (length adt-arg1*) (length adt-arg2*))
                           (andmap same-adt-arg? adt-arg1* adt-arg2*))])])
              (T type2
                 [(tundeclared) #t])))))
    (define (public-adt? type)
      (nanopass-case (Ltypes Type) (de-alias type #t)
        [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
        [else #f]))
    (define (verify-non-adt-type! src type fmt . arg*)
      (when (public-adt? type)
        (source-errorf src
                        "expected ~a type to be an ordinary Compact type but received ADT type ~a"
                        (apply format fmt arg*)
                        (format-type type))))
    (define-syntax Non-ADT-Type
      (syntax-rules ()
        [(_ ?type ?src ?fmt ?arg ...)
         (let ([type (Type ?type)])
           (verify-non-adt-type! ?src type ?fmt ?arg ...)
           type)]))
    (define (type-contains? type base-predicate)
      (let recur ([type type])
        (nanopass-case (Ltypes Type) type
          [(tvector ,src ,len ,type) (recur type)]
          [(ttuple ,src ,type* ...) (ormap recur type*)]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) (ormap recur type*)]
          [(talias ,src ,nominal ,type-name ,type) (recur type)]
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (ormap (lambda (adt-arg)
                    (nanopass-case (Ltypes Public-Ledger-ADT-Arg) adt-arg
                      [,nat #f]
                      [,type (recur type)]))
             adt-arg*)]
          [else (base-predicate type)])))
    (define (declared? type)
      (nanopass-case (Ltypes Type) type
        [(tundeclared) #f]
        [else #t]))
    (define current-whose-body #f)
    (define current-return-type #f)
    (define (do-circuit-body src whose-body arg* return-type expr)
      (let ([id* (map arg->name arg*)] [type* (map arg->type arg*)])
        (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* type*)
        (let-values ([(expr actual-type) (fluid-let ([current-whose-body whose-body]
                                                     [current-return-type return-type])
                                           (Care expr))])
          (unless (subtype? actual-type return-type)
            (source-errorf src "mismatch between actual return type ~a and declared return type ~a of ~a"
              (format-type actual-type)
              (format-type return-type)
              whose-body))
          (for-each unset-idtype! id*)
          (if (declared? return-type)
              (values (maybe-safecast src return-type actual-type expr) return-type)
              (values expr actual-type)))))
    (define maybe-safecast
      (case-lambda
        [(src) (lambda (declared-type actual-type expr)
                 (maybe-safecast src declared-type actual-type expr))]
        [(src declared-type actual-type expr)
         (if (sametype? declared-type actual-type)
             expr
             (with-output-language (Ltypes Expression)
               `(safe-cast ,src ,declared-type ,actual-type ,expr)))]))
    (define (contains-js-opaque? type)
      (type-contains? type
        (lambda (type)
          (T type
            [(topaque ,src ,opaque-type) (or (string=? opaque-type "string") (string=? opaque-type "Uint8Array"))]))))
    (define (contains-secp256k1? type)
      (type-contains? type
        (lambda (type)
          (T type
            [(tfield ,src (field-base (curve-secp256k1))) #t]
            [(tfield ,src (field-scalar (curve-secp256k1))) #t]
            [(topaque ,src ,opaque-type) (string=? opaque-type "Secp256k1Point")]))))
    (define (do-call src fold? fun actual-type* build-call)
      (define compatible-args?
        (let ([nactual (length actual-type*)])
          (lambda (arg-type*)
            (and (= (length arg-type*) nactual)
                 (andmap subtype? actual-type* arg-type*)))))
      (nanopass-case (Lexpanded Function) fun
        [(fref ,src^ ,symbolic-function-name ((,function-name** ...) ...)
               (,generic-value* ...)
               ((,src* ,generic-kind** ...) ...))
         (define-record-type blob (nongenerative) (fields name is-native arg-type* return-type))
         (define (blob<? blob1 blob2)
           (source-object<?
             (id-src (blob-name blob1))
             (id-src (blob-name blob2))))
         (define (opaque-hashing-error? symbolic-name blob)
           (and (blob-is-native blob)
                (memq symbolic-name '(persistentHash persistentCommit keccak256))
                (> (length (blob-arg-type* blob)) 0)
                (contains-js-opaque? (car (blob-arg-type* blob)))))
         (let outer ([function-name** function-name**] [arg-incompatible-blob** '()] [fold-incompatible-blob** '()])
           (if (null? function-name**)
               (let ()
                 (define (functions-are ls)
                   (let ([n (length ls)])
                     (if (fx= n 1) "one function is" (format "~r functions are" n))))
                 (source-errorf src "no compatible function named ~a is in scope at this call~@[~a~]~@[~a~]~@[~a~]"
                   symbolic-function-name
                   (let ([generic-failure* (let-values ([(src* generic-kind**)
                                                         (let ([x* (sort (lambda (x y) (source-object<? (car x) (car y)))
                                                                         (map cons src* generic-kind**))])
                                                           (values (map car x*) (map cdr x*)))])
                                             (map (lambda (src generic-kind*)
                                                    (format "declared generics for function at ~a:\n        <~{~s~^, ~}>"
                                                      (format-source-object src)
                                                      generic-kind*))
                                                  src*
                                                  generic-kind**))])
                     (and (not (null? generic-kind**))
                          (format "\n    \
                                   ~a incompatible with the supplied generic values\n      \
                                   supplied generic values:\n        <~{~a~^, ~}>\
                                   ~{\n      ~a~}"
                            (functions-are generic-failure*)
                            (map (lambda (generic-value)
                                   (nanopass-case (Lexpanded Generic-Value) generic-value
                                     [,type (format "type ~a" (format-type (Type type)))]
                                     [,nat (format "size ~d" nat)]))
                                 generic-value*)
                            generic-failure*)))
                   (let ([arg-incompatible* (map (lambda (blob)
                                                   (format "declared argument types for function at ~a:\n        (~{~a~^, ~})"
                                                     (format-source-object (id-src (blob-name blob)))
                                                     (map format-type (blob-arg-type* blob))))
                                                 (sort blob<? (apply append arg-incompatible-blob**)))])
                     (and (not (null? arg-incompatible*))
                          (format "\n    \
                                   ~a incompatible with the supplied argument types\n      \
                                   supplied argument types:\n        (~{~a~^, ~})\
                                   ~{\n      ~a~}"
                            (functions-are arg-incompatible*)
                            (map format-type actual-type*)
                            arg-incompatible*)))
                   (let ([fold-incompatible* (map (lambda (blob)
                                                    (format "declared first-argument and return types for function at ~a:\n        ~a\n        ~a"
                                                      (format-source-object (id-src (blob-name blob)))
                                                      (format-type (car (blob-arg-type* blob)))
                                                      (format-type (blob-return-type blob))))
                                                  (sort blob<? (apply append fold-incompatible-blob**)))])
                     (and (not (null? fold-incompatible*))
                          (format "\n    \
                                   ~a incompatible because fold requires the return type and the first argument type to be the same\
                                   ~{\n      ~a~}"
                            (functions-are fold-incompatible*)
                            fold-incompatible*)))))
               (let ([function-name* (car function-name**)]
                     [function-name** (cdr function-name**)])
                 (let ([blob* (map (lambda (function-name)
                                     (Idtype-case (get-idtype src function-name)
                                       [(Idtype-Function kind is-native arg-name* arg-type* return-type)
                                        (make-blob function-name is-native arg-type* return-type)]
                                       [else (assert cannot-happen)]))
                                   function-name*)])
                   (let*-values ([(arg-compatible-blob* arg-incompatible-blob*)
                                  (partition (lambda (x) (compatible-args? (blob-arg-type* x))) blob*)]
                                 [(compatible-blob* fold-incompatible-blob*)
                                  (if fold?
                                      (partition (lambda (x) (sametype? (blob-return-type x) (car (blob-arg-type* x)))) arg-compatible-blob*)
                                      (values arg-compatible-blob* '()))])
                     (cond
                       [(null? compatible-blob*)
                        (outer function-name**
                               (cons arg-incompatible-blob* arg-incompatible-blob**)
                               (cons fold-incompatible-blob* fold-incompatible-blob**))]
                       [(null? (cdr compatible-blob*))
                        (let ([blob (car compatible-blob*)])
                          (when (opaque-hashing-error? symbolic-function-name blob)
                            (source-errorf src
                              "~a cannot be applied to a first argument containing opaque JavaScript values, received ~a"
                              symbolic-function-name
                              (format-type (car (blob-arg-type* blob)))))
                          (build-call
                            (blob-arg-type* blob)
                            (blob-return-type blob)
                            (with-output-language (Ltypes Function)
                              `(fref ,src^ ,(blob-name blob)))))]
                       [else
                        (source-errorf src
                                       "call site ambiguity (multiple compatible functions) in call to ~a\n    \
                                       supplied argument types:\n      \
                                       (~{~a~^, ~})\n    \
                                       compatible functions:\
                                       ~{\n      ~a~}"
                          symbolic-function-name
                          (map format-type actual-type*)
                          (map format-source-object
                               (sort source-object<?
                                     (map (lambda (blob) (id-src (blob-name blob)))
                                          compatible-blob*))))]))))))]
        [(circuit ,src^ (,[Argument : arg*] ...) ,[Return-Type : type src^ "anonymous circuit" -> type] ,expr)
         ; Inferring the first-argument and return types for fold is a bit
         ; tricky, since the return type becomes the first argument type for
         ; the second and subsequent fold iterations.  We handle inference
         ; as follows.
         ;
         ; When both types are declared:
         ;   We complain as usual if the declared types are not the same type,
         ;   and we complain as usual if either the inferred first-argument type
         ;   or the inferred body type is not a subtype of the declared
         ;   return and first-argument type.
         ;
         ; When the first argument type is declared but not the return type:
         ;   We infer the type of the body as usual based on the declared
         ;   first-argument type.  If the inferred body type is not the same as
         ;   the declared first-argument type, we complain.  Otherwise, we
         ;   use the first-argument type as the return type.
         ;
         ;   An alternative when the inferred body type is a proper subtype
         ;   of the declared first-argument type is is to use the declared
         ;   first-argument type as the return type and upcast the body's
         ;   return value accordingly.  This situation is unusual, however,
         ;   and probably involves an explicit downcast in the body, so doing
         ;   so might be surprising.
         ;
         ; When the return type is declared but not the first-argument type:
         ;   If the inferred first-argument type is not a subtype of the
         ;   declared return type, we complain.  Otherwise we use the declared
         ;   return type for the first-argument type, infer the body type based
         ;   on this, and complain as usual if the inferred body type is not a
         ;   subtype of the declared return type.
         ;
         ; When neither the first-argument type nor the return type is declared:
         ;   We use the inferred type of the first argument as the first-argument
         ;   type and infer the body type based on this.  We complain if the
         ;   inferred body type is not the same the inferred first-argument type.
         ;   Otherwise we also use the inferred first-argument type as the return
         ;   type.
         ;
         ;   An alternative when the inferred body type is a proper supertype
         ;   of the inferred first-argument type is to use the inferred body
         ;   type as the first-argument type and infer the body type again.
         ;   Unfortunately, this might result in a still greater inferred body
         ;   type.  In this case, there might not be a fixpoint or it might be
         ;   prohibitively expensive to find.  And even processing the body
         ;   twice can lead to quadratic compile time if folds are nested.
         (define (replace-undeclared type type^)
           (if (declared? type)
               type
               type^))
         (define (fold-error first-arg-type first-arg-type-declared? return-type return-type-declared?)
           (source-errorf src
                          "fold requires the return type and first-argument type to be the same\n    \
                           ~:[[inferred] ~;~]first-argument type: ~a,\n    \
                           ~:[[inferred] ~;~]return type: ~a"
             first-arg-type-declared?
             (format-type first-arg-type)
             return-type-declared?
             (format-type return-type)))
         (let ([arg-type* (map arg->type arg*)])
           (unless (compatible-args? arg-type*)
             (source-errorf src
                            "incompatible arguments in call to anonymous circuit\n    \
                            supplied argument types:\n      \
                            (~{~a~^, ~})\n    \
                            declared circuit type:\n      \
                            (~{~a~^, ~})"
                            (map format-type actual-type*)
                            (map format-type arg-type*)))
           (let* ([known-arg-type*
                    (if (and fold?
                             (declared? type)
                             (not (declared? (car arg-type*))))
                        (begin
                          (unless (subtype? (car actual-type*) type)
                            (fold-error (car actual-type*) #f type #t))
                          (cons type (map replace-undeclared (cdr arg-type*) (cdr actual-type*))))
                        (map replace-undeclared arg-type* actual-type*))]
                  [arg* (map (lambda (var-name known-arg-type)
                               (with-output-language (Ltypes Argument)
                                 `(,var-name ,known-arg-type)))
                             (map arg->name arg*)
                             known-arg-type*)])
             (let-values ([(expr known-type) (do-circuit-body src^ "anonymous circuit" arg* type expr)])
               (when fold?
                 (unless (sametype? known-type (car known-arg-type*))
                   (fold-error
                     (car known-arg-type*)
                     (eq? (car known-arg-type*) (car arg-type*))
                     known-type
                     (eq? known-type type))))
               (build-call
                 known-arg-type*
                 known-type
                 (with-output-language (Ltypes Function)
                   `(circuit ,src (,arg* ...) ,known-type ,expr))))))]))
    (define (max-type type*)
      (let loop ([type* type*] [max-type (with-output-language (Ltypes Type) `(tunknown))])
        (if (null? type*)
            max-type
            (let ([type (car type*)] [type* (cdr type*)])
              (cond
                [(subtype? type max-type) (loop type* max-type)]
                [(subtype? max-type type) (loop type* type)]
                [else #f])))))
    (define (vector-element-type src what type)
      (nanopass-case (Ltypes Type) (de-alias type #t)
        [(ttuple ,src^ ,type^* ...)
         (values
           (length type^*)
           (or (max-type type^*)
               (source-errorf src "~a should be a vector but has a tuple type ~a that cannot be converted to a vector because its element types are unrelated"
                              what
                              (format-type type))))]
        [(tbytes ,src^ ,len) (values len (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
        [(tvector ,src^ ,len ,type) (values len type)]
        [else (source-errorf src "~a should be a vector, tuple, or Bytes but has type ~a"
                             what
                             (format-type type))]))
    (define (vector-element-types src who type+ argno)
      (let loop ([type+ type+] [n #f] [argno argno] [rtype* '()])
        (let ([type (car type+)] [type* (cdr type+)])
          (let-values ([(nat type) (vector-element-type src (format "~a ~:r argument" who argno) type)])
            (unless (or (not n) (= nat n))
              (source-errorf src "mismatch in ~s-argument vector lengths" who))
            (let ([rtype* (cons type rtype*)])
              (if (null? type*)
                  (values nat (reverse rtype*))
                  (loop type* nat (fx+ argno 1) rtype*)))))))
    (define (maybe-bind src result-type expr k)
      (nanopass-case (Ltypes Expression) expr
        [(quote ,src ,datum) (k expr)]
        [(var-ref ,src ,var-name) (k expr)]
        [else (let ([t (make-temp-id src 't)])
                (with-output-language (Ltypes Expression)
                  `(let* ,src ([(,t ,result-type) ,expr])
                     ,(k `(var-ref ,src ,t)))))]))
    (define (arithmetic-binop src op expr1 expr2 k)
      (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
        (define (condense type l/r)
          (nanopass-case (Ltypes Type) type
            [(talias ,src ,nominal? ,type-name ,type)
             (let-values ([(type-name* unaliased-type) (condense type l/r)])
               (values
                 (if nominal? (cons type-name type-name*) type-name*)
                 unaliased-type))]
            [(tfield ,src (field-native)) (values '() type)]
            [(tfield ,src (field-scalar (curve-secp256k1))) (values '() type)]
            [(tunsigned ,src ,nat) (values '() type)]
            [else (source-errorf src "~a is an invalid ~a operand type for binary arithmetic operator ~a"
                    (format-type type) l/r op)]))
        (define (make-native-field-op)
          (let ([result-type (with-output-language (Ltypes Type) `(tfield ,src (field-native)))])
            (values
              (k #f
                (maybe-safecast src result-type type1 expr1)
                (maybe-safecast src result-type type2 expr2))
              result-type)))
        (define (invalid-combination)
          (source-errorf src "incompatible combination of types ~a and ~a for binary arithmetic operator ~a"
            (format-type type1)
            (format-type type2)
            op))
        (let-values ([(type-name1* unaliased-type1) (condense type1 "left")]
                     [(type-name2* unaliased-type2) (condense type2 "right")])
          (let-values
              ([(result-expr result-type)
                (nanopass-case (Ltypes Type) unaliased-type1
                  [(tfield ,src1 (field-native))
                   (nanopass-case (Ltypes Type) unaliased-type2
                     [(tfield ,src2 (field-native))
                      (make-native-field-op)]
                     [(tunsigned ,src2 ,nat)
                      (make-native-field-op)]
                     [else (invalid-combination)])]
                  [(tfield ,src1 (field-scalar (curve-secp256k1)))
                   (guard (eq? op '*))
                   (nanopass-case (Ltypes Type) unaliased-type2
                     [(tfield ,src2 (field-scalar (curve-secp256k1)))
                      (values (k #f expr1 expr2) unaliased-type1)]
                     [else (invalid-combination)])]
                  [(tunsigned ,src1 ,nat1)
                   (nanopass-case (Ltypes Type) unaliased-type2
                     [(tfield ,src2 (field-native))
                      (make-native-field-op)]
                     [(tunsigned ,src2 ,nat2)
                      (let ([result-nat (case op
                                          [+ (+ nat1 nat2)]
                                          [* (* nat1 nat2)]
                                          [- nat1]
                                          [else (assert cannot-happen)])])
                        (unless (<= result-nat (max-unsigned))
                          (source-errorf src "resulting value might exceed largest representable Uint value (for Field semantics, cast either operand to Field)"))
                        (let ([mbits (max 1 (integer-length result-nat))])
                          (assert (<= mbits (unsigned-bits)))
                          (let ([result-type (with-output-language (Ltypes Type) `(tunsigned ,src ,result-nat))])
                            (define (maybe-cast nat^ type^ expr)
                              (if (= nat^ result-nat)
                                  expr
                                  (with-output-language (Ltypes Expression)
                                    `(safe-cast ,src ,result-type ,type^ ,expr))))
                            (values
                              (with-output-language (Ltypes Expression)
                                (if (eq? op '-)
                                    (maybe-bind src type1 expr1
                                      (lambda (expr1)
                                        (maybe-bind src type2 expr2
                                          (lambda (expr2)
                                            `(seq ,src
                                               (assert ,src
                                                 ,(let-values ([(type nat) (if (< nat1 nat2) (values type2 nat2) (values type1 nat1))])
                                                    (let ([mbits (fxmax 1 (integer-length nat))])
                                                      (with-output-language (Ltypes Expression)
                                                        `(>= ,src ,mbits ,(maybe-safecast src type type1 expr1) ,(maybe-safecast src type type2 expr2)))))
                                                 "result of subtraction would be negative")
                                               ,(k mbits
                                                  (maybe-cast nat1 type1 expr1)
                                                  (maybe-cast nat2 type2 expr2)))))))
                                    (k mbits
                                      (maybe-cast nat1 type1 expr1)
                                      (maybe-cast nat2 type2 expr2))))
                              result-type))))]
                     [else (invalid-combination)])]
                  [else (invalid-combination)])])
            (if (and (null? type-name1*) (null? type-name2*))
                (values result-expr result-type)
                (begin
                  ; this is, in effect, (sametype? type1 type2)
                  (unless (and (equal? type-name1* type-name2*)
                               (sametype? unaliased-type1 unaliased-type2))
                    (invalid-combination))
                  (values
                    (with-output-language (Ltypes Expression)
                      (nanopass-case (Ltypes Type) unaliased-type1
                        [(tunsigned ,src1 ,nat1)
                         (if (eq? op '-)
                             result-expr
                             (let ([result-nat (nanopass-case (Ltypes Type) result-type
                                                 [(tunsigned ,src ,nat) nat]
                                                 [else (assert cannot-happen)])])
                               `(downcast-unsigned ,src ,result-nat ,nat1 ,result-expr)))]
                        [else `(safe-cast ,src ,type1 ,result-type ,result-expr)]))
                    type1)))))))
    (define (relational-operator src expr1 expr2 k)
      (values
        (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
          (or (let f ([type1 type1] [type2 type2])
                (T (de-alias type1 #f)
                   [(tunsigned ,src1 ,nat1)
                    (T (de-alias type2 #f)
                       [(tunsigned ,src2 ,nat2)
                        (let-values ([(type nat) (if (< nat1 nat2) (values type2 nat2) (values type1 nat1))])
                          (let ([bits (fxmax 1 (integer-length nat))])
                            ; maybe-bind forces the evaluation of expr1 before expr2.
                            ; this prevents the downstream transformations from changing the evaluation order.
                            (maybe-bind src type1 expr1
                              (lambda (expr1)
                                (k bits (maybe-safecast src type type1 expr1) (maybe-safecast src type type2 expr2))))))])]
                   [(talias ,src1 ,nominal1? ,type-name1 ,type1)
                    (T (de-alias type2 #f)
                       [(talias ,src2 ,nominal2? ,type-name2 ,type2)
                        (and (eq? type-name1 type-name2)
                             (f type1 type2))])]))
              (source-errorf src "incompatible combination of types ~a and ~a for relational operator"
                             (format-type type1)
                             (format-type type2))))
        (with-output-language (Ltypes Type) `(tboolean ,src))))
    (define (equality-operator src expr1 expr2 k)
      (let*-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
        (verify-non-adt-type! src type1 "equality-operator left operand")
        (verify-non-adt-type! src type2 "equality-operator right operand")
        (let ([type (cond
                      [(subtype? type1 type2) type2]
                      [(subtype? type2 type1) type1]
                      [else #f])])
          (unless type
            (source-errorf src "incompatible types ~a and ~a for equality operator"
                           (format-type type1)
                           (format-type type2)))
          (values
            (k type (maybe-safecast src type type1 expr1) (maybe-safecast src type type2 expr2))
            (with-output-language (Ltypes Type) `(tboolean ,src))))))
    (define (find-adt-op src elt-name sugar? adt-name adt-op* type* expr expr* fail)
      (let ([elt-name (cond
                        [(hashtable-ref ledger-op-aliases elt-name #f) =>
                         (lambda (new-elt-name)
                           (record-alias! src elt-name new-elt-name)
                           new-elt-name)]
                        [else elt-name])])
        (let loop ([adt-op* adt-op*])
          (if (null? adt-op*)
              (fail)
              (nanopass-case (Ltypes ADT-Op) (car adt-op*)
                [(,ledger-op ,op-class ((,var-name* ,type^* ,discloses?*) ...) ,type ,vm-code)
                 (if (eq? ledger-op elt-name)
                     (let ([ndeclared (length type^*)] [nactual (length type*)])
                       (unless (fx= nactual ndeclared)
                         (source-errorf src "~a ~a requires ~a argument~:*~p but received ~a"
                           adt-name ledger-op ndeclared nactual))
                       (when (and (memq adt-name '(MerkleTree HistoricMerkleTree))
                                  (memq ledger-op '(insert insertIndex))
                                  (> nactual 0)
                                  (contains-js-opaque? (car type*)))
                         (source-errorf src
                           "~a ~a cannot be applied to a first argument containing opaque JavaScript values, received ~a"
                           adt-name ledger-op (format-type (car type*))))
                       (for-each
                         (lambda (declared-type actual-type i)
                           (unless (subtype? actual-type declared-type)
                             (if sugar?
                                 (source-errorf src "expected right-hand side of ~a to have type ~a but received ~a"
                                                sugar?
                                                (format-type declared-type)
                                                (format-type actual-type))
                                 (source-errorf src "expected ~:r argument of ~s to have type ~a but received ~a"
                                                (fx1+ i)
                                                ledger-op
                                                (format-type declared-type)
                                                (format-type actual-type)))))
                         type^* type* (iota ndeclared))
                       (values
                         (let ([expr* (map (maybe-safecast src) type^* type* expr*)])
                           (with-output-language (Ltypes Expression)
                             `(ledger-call ,src ,elt-name ,sugar? ,expr ,expr* ...)))
                         type))
                     (loop (cdr adt-op*)))])))))
    (define (adt-op-error! src elt-name sugar? adt-name adt-rt-op* adt-arg*)
      (for-each
        (lambda (adt-rt-op)
          (nanopass-case (Ltypes ADT-Runtime-Op) adt-rt-op
            [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
             (when (eq? ledger-op elt-name)
               (source-errorf src "~s ~s is a runtime-only method, but was invoked in-circuit"
                              adt-name ledger-op))]))
        adt-rt-op*)
      (source-errorf src "operation ~a undefined for ledger field type ~a"
                     (or sugar? elt-name)
                     (format-public-adt adt-name adt-arg*)))
    (define (find-adt-op! src elt-name sugar? adt-name adt-op* adt-rt-op* type* expr expr* adt-arg*)
      (find-adt-op src elt-name sugar? adt-name adt-op* type* expr expr*
        (lambda ()
          (adt-op-error! src elt-name sugar? adt-name adt-rt-op* adt-arg*))))
    (define (find-contract-circuit src src^ contract-name elt-name elt-name* declared-type** return-type* actual-type actual-type* expr expr*)
      (let loop ([elt-name* elt-name*] [declared-type** declared-type**] [return-type* return-type*])
        (if (null? elt-name*)
            (source-errorf src^ "contract ~s has no circuit declaration named ~s"
                           contract-name
                           elt-name)
          (if (eq? (car elt-name*) elt-name)
              (let ([declared-type* (car declared-type**)])
                (let ([ndeclared (length declared-type*)] [nactual (length actual-type*)])
                  (unless (fx= nactual ndeclared)
                    (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                   contract-name elt-name ndeclared nactual)))
                (for-each
                  (lambda (declared-type actual-type i)
                    (unless (subtype? actual-type declared-type)
                      (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                     (fx1+ i)
                                     contract-name
                                     elt-name
                                     (format-type declared-type)
                                     (format-type actual-type))))
                  declared-type* actual-type* (enumerate declared-type*))
                (values
                  (let ([expr* (map (maybe-safecast src) declared-type* actual-type* expr*)])
                    (with-output-language (Ltypes Expression)
                      `(contract-call ,src ,elt-name (,expr ,actual-type) ,expr* ...)))
                  (car return-type*)))
              (loop (cdr elt-name*) (cdr declared-type**) (cdr return-type*))))))
    (define (contract-implements! pelt* export-name* name*)
      (let ([export-name->name (make-hashtable symbol-hash eq?)]
            [name->type.type* (make-eq-hashtable)])
        (for-each
          (lambda (export-name name)
            (hashtable-set! export-name->name export-name name))
          export-name* name*)
        (for-each
          (lambda (pelt)
            (nanopass-case (Ltypes Program-Element) pelt
              [(circuit ,src ,function-name ((,var-name* ,type*) ...) ,type ,expr)
               (guard (id-exported? function-name))
               (hashtable-set! name->type.type* function-name (cons type type*))]
              [else (void)]))
          pelt*)
        (lambda (cidecl)
          (nanopass-case (Lexpanded Contract-Implements-Declaration) cidecl
            [(contract-implements ,src ,[Type : type])
             (nanopass-case (Ltypes Type) type
               [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl?* (,type** ...) ,type*) ...)
                (for-each
                  (lambda (elt-name pure-dcl? type* type)
                    (let* ([name (hashtable-ref export-name->name elt-name #f)]
                           [type.type* (or (and name (hashtable-ref name->type.type* name #f))
                                           (source-errorf src "contract implements failure:\n  this contract does not export a circuit named ~s" elt-name))])
                      (when pure-dcl?
                        (unless (id-pure? name)
                          (source-errorf src "contract implements failure:\n  this contract exports a circuit named ~s, but\n  it is not declared pure" elt-name)))
                      (let ([type^ (car type.type*)] [type^* (cdr type.type*)])
                        (let ([n (length type*)] [n^ (length type^*)])
                          (unless (= n^ n)
                            (source-errorf src "contract implements failure:\n  this contract exports a circuit named ~s, but\n  it takes ~d arguments rather than ~d"
                                           elt-name
                                           n^
                                           n)))
                        (for-each
                          (lambda (type type^ i)
                            (unless (sametype? type^ type)
                              (source-errorf src "contract implements failure:\n  this contract exports a circuit named ~s, but\n  the type of its ~:r argument is ~a rather than ~a"
                                             elt-name
                                             (fx+ i 1)
                                             (format-type type^)
                                             (format-type type))))
                          type*
                          type^*
                          (enumerate type*))
                        (unless (sametype? type^ type)
                          (source-errorf src "contract implements failure:\n  this contract exports a circuit named ~s, but\n  its return type is ~a rather than ~a"
                                         elt-name
                                         (format-type type^)
                                         (format-type type))))))
                  elt-name*
                  pure-dcl?*
                  type**
                  type*)]
               [else (source-errorf src "non-contract type ~a in contract implements form"
                                    (format-type type))])]))))
    (define (serializable? type)
      (nanopass-case (Ltypes Type) (de-alias type #t)
        [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #f]
        [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...) #f]
        [(topaque ,src^ ,opaque-type) #f]
        [else #t]))
    (define (validate-event-type! src type)
      (let ([type (de-alias type #t)])
        (nanopass-case (Ltypes Type) type
          [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
           (let ([declared (hashtable-ref standard-event-ht struct-name #f)])
             (unless (and declared (sametype? type declared))
               (source-errorf src "~a is not a declared event type" (format-type type))))]
          [else
           (source-errorf src "expected structure type (representation of an event), received ~a"
                          (format-type type))])))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ((,struct-name* ,[type*]) ...) (,unused-pelt* ...) (,ecdecl* ...) (,cidecl* ...) ,pelt* ...)
     (define (contract-name ct)
       (nanopass-case (Ltypes Contract-Type) ct
         [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          contract-name]))
     (define (make-contract-type-hashtable)
       (make-hashtable
         (lambda (ct) (symbol-hash (contract-name ct)))
         sametype?))
     (for-each Set-Program-Element-Type! unused-pelt*)
     (for-each Set-Program-Element-Type! pelt*)
     (for-each External-Contract-Declaration! ecdecl*)
     (fluid-let ([standard-event-ht
                  (let ([ht (make-hashtable symbol-hash eq?)])
                    (for-each (lambda (n t) (hashtable-set! ht n t)) struct-name* type*)
                    ht)])
       (fluid-let ([contract-type-ht (make-contract-type-hashtable)])
         (maplr Program-Element unused-pelt*))
       (fluid-let ([contract-type-ht (make-contract-type-hashtable)])
         (let* ([pelt* (maplr Program-Element pelt*)]
                [contract-type*
                 (sort
                   (lambda (ct1 ct2)
                     (string<?
                       (symbol->string (contract-name ct1))
                       (symbol->string (contract-name ct2))))
                   (vector->list (hashtable-keys contract-type-ht)))])
           (for-each (contract-implements! pelt* export-name* name*) cidecl*)
           `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,pelt* ...))))])
  (Set-Program-Element-Type! : Program-Element (ir) -> * (void)
    (definitions
      (define (build-function kind is-native name arg* type)
        (let ([var-name* (map arg->name arg*)] [type* (map arg->type arg*)])
          (set-idtype! name (Idtype-Function kind is-native var-name* type* type)))))
    [(circuit ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "circuit" -> type] ,expr)
     (build-function 'circuit #f function-name arg* type)]
    [(native ,src ,function-name ,native-entry (,[arg*] ...) ,[Return-Type : type src "circuit" -> type])
     (build-function (native-entry-class native-entry) #t function-name arg* type)]
    [(witness ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "witness" -> type])
     (when (and (not (feature-zkir-v3)) (contains-secp256k1? type))
       (source-errorf src "secp256k1 is not supported in ZKIR v2: try recompiling with the flag `--feature-zkir-v3`"))
     (build-function 'witness #f function-name arg* type)]
    [(public-ledger-declaration ,src ,ledger-field-name ,[type])
     (unless (public-adt? type)
       (source-errorf src "expected ADT-type for ledger declaration after expand-modules-and-types, received ~a"
                          (format-type type)))
     (when (and (not (feature-zkir-v3)) (contains-secp256k1? type))
       (source-errorf src "secp256k1 is not supported in ZKIR v2: try recompiling with the flag `--feature-zkir-v3`"))
     (set-idtype! ledger-field-name (Idtype-Base type))]
    [else (void)])
  (External-Contract-Declaration! : External-Contract-Declaration (ir) -> * (void)
    [(external-contract ,src ,contract-name ,ecdecl-circuit* ...)
     (for-each External-Contract-Circuit! ecdecl-circuit*)])
  (External-Contract-Circuit! : External-Contract-Circuit (ir) -> * (void)
    [(,src ,pure-dcl ,elt-name (,[arg*] ...) ,type)
     (Non-ADT-Type type src "circuit ~a return" elt-name)])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,[arg*] ...) ,expr)
     (let-values ([(expr return-type) (do-circuit-body src "ledger constructor" arg* (with-output-language (Ltypes Type) `(ttuple ,src)) expr)])
       `(constructor ,src (,arg* ...) ,expr))])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "circuit" -> type] ,expr)
     (when (and (not (feature-zkir-v3))
                (or (contains-secp256k1? type)
                    (ormap (lambda (arg) (contains-secp256k1? (arg->type arg))) arg*)))
       (source-errorf src "secp256k1 is not supported in ZKIR v2: try recompiling with the flag `--feature-zkir-v3`"))
     (let-values ([(expr return-type) (do-circuit-body src (format "circuit ~a" (id-sym function-name)) arg* type expr)])
       `(circuit ,src ,function-name (,arg* ...) ,return-type ,expr))])
  (Native-Declaration : Native-Declaration (ir) -> Native-Declaration ()
    [(native ,src ,function-name ,native-entry (,[arg*] ...) ,[Return-Type : type src "circuit" -> type])
     `(native ,src ,function-name ,native-entry (,arg* ...) ,type)])
  (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
    [(witness ,src ,function-name (,[arg*] ...) ,[Return-Type : type src "witness" -> type])
     `(witness ,src ,function-name (,arg* ...) ,type)])
  (Export-Type-Definition :  Export-Type-Definition (ir) -> Export-Type-Definition ()
    [(export-typedef ,src ,type-name (,tvar-name* ...) ,[type])
     (if (public-adt? type)
         (source-errorf src "cannot export alias for ADT types from the top level")
         `(export-typedef ,src ,type-name (,tvar-name* ...) ,type))])
  (ADT-Op : ADT-Op (ir) -> ADT-Op ())
  (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
  (Argument : Argument (ir) -> Argument ()
    [(,var-name ,type)
     (let ([type (Non-ADT-Type type (id-src var-name) "argument '~a'" (id-sym var-name))])
       `(,var-name ,type))])
  (Return-Type : Type (ir src what) -> Type ()
    [else (Non-ADT-Type ir src "~a return" what)])
  (Generic-Value : Generic-Value (ir) -> Public-Ledger-ADT-Arg ())
  (Type : Type (ir) -> Type ()
    [(tboolean ,src) `(tboolean ,src)]
    [(tfield ,src ,[ftype]) `(tfield ,src ,ftype)]
    [(tunsigned ,src ,nat) `(tunsigned ,src ,nat)]
    [(topaque ,src ,opaque-type) `(topaque ,src ,opaque-type)]
    [(tundeclared) `(tundeclared)]
    [(tvector ,src ,len ,type)
     (let ([type (Non-ADT-Type type src "vector element")])
       `(tvector ,src ,len ,type))]
    [(tbytes ,src ,len)
     `(tbytes ,src ,len)]
    [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
     (let ([type** (map (lambda (type* elt-name)
                          (map (lambda (type i)
                                 (Non-ADT-Type type src "circuit '~a' argument ~d" elt-name (fx+ i 1)))
                               type*
                               (enumerate type*)))
                        type**
                        elt-name*)]
           [type* (map (lambda (type elt-name) (Non-ADT-Type type src "circuit '~a' return" elt-name))
                       type*
                       elt-name*)])
       `(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...))]
    [(ttuple ,src ,type* ...)
     (let ([type* (map (lambda (type i)
                         (Non-ADT-Type type src "tuple element ~d" (fx+ i 1)))
                       type*
                       (enumerate type*))])
       `(ttuple ,src ,type* ...))]
    [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
     (let ([type* (map (lambda (type elt-name)
                         (Non-ADT-Type type src "struct field '~a'" elt-name))
                       type*
                       elt-name*)])
       `(tstruct ,src ,struct-name (,elt-name* ,type*) ...))]
    [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
     `(tenum ,src ,enum-name ,elt-name ,elt-name* ...)]
    [(talias ,src ,nominal? ,type-name ,[type])
     `(talias ,src ,nominal? ,type-name ,type)]
    [(tadt ,src ,adt-name ([,adt-formal* ,generic-value*] ...) ,vm-expr (,[adt-op*] ...) (,[adt-rt-op*] ...))
     (when (or (eq? adt-name 'MerkleTree) (eq? adt-name 'HistoricMerkleTree))
       (let ([depth (car generic-value*)])
         (unless (<= (min-merkle-tree-depth) depth (max-merkle-tree-depth))
           (source-errorf src "~a depth ~d does not fall in ~d <= depth <= ~d"
                          adt-name
                          depth
                          (min-merkle-tree-depth)
                          (max-merkle-tree-depth)))))
     `(tadt ,src ,adt-name ([,adt-formal* ,(map Generic-Value generic-value*)] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))])
  (CareNot : Expression (ir) -> Expression ()
    [(if ,src ,[Care : expr0 type0] ,expr1 ,expr2)
     (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type0)))
     (let ([expr1 (CareNot expr1)] [expr2 (CareNot expr2)])
       `(if ,src ,expr0 ,expr1 ,expr2))]
    [(seq ,src ,expr* ... ,expr)
     (let* ([expr* (maplr CareNot expr*)] [expr (CareNot expr)])
       `(seq ,src ,expr* ... ,expr))]
    [(let* ,src ([(,var-name* ,[type*]) ,expr*] ...) ,expr)
     (let ([declared-type* type*])
       (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
         (let ([declared-type* (maplr (lambda (var-name declared-type actual-type)
                                        (unless (subtype? actual-type declared-type)
                                          (source-errorf src "mismatch between actual type ~a and declared type ~a of const binding"
                                                         (format-type actual-type)
                                                         (format-type declared-type)))
                                        (let ([type (if (declared? declared-type)
                                                        declared-type
                                                        actual-type)])
                                          (set-idtype! var-name (Idtype-Base type))
                                          type))
                                      var-name*
                                      declared-type*
                                      actual-type*)])
           (let ([expr (CareNot expr)])
             (for-each unset-idtype! var-name*)
             `(let* ,src ([(,var-name* ,declared-type*)
                           ,(map (maybe-safecast src) declared-type* actual-type* expr*)]
                          ...)
                ,expr)))))]
    [else (let-values ([(expr type) (Care ir)]) expr)])
  (elt-call-lhs : Expression (ir src op adt-type-only?) -> Expression (type)
    (definitions
      (define (elt-call-oops src type)
        (source-errorf src (if adt-type-only?
                               "expected left-hand side of ~a to have an ADT type, received ~a"
                               "expected left-hand side of ~a to have an ADT or contract type, received ~a")
                       op
                       (format-type type)))
      (define (check-result-type src expr type)
        (nanopass-case (Ltypes Type) (de-alias type #t)
          [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (source-errorf src "expected a ledger field name at base of ledger access")]
          [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
           (guard (not adt-type-only?))
           (values expr type)]
          [else (elt-call-oops src type)])))
    [(var-ref ,src ,var-name)
     (Idtype-case (get-idtype src var-name)
       [(Idtype-Base type) (check-result-type src `(var-ref ,src ,var-name) type)]
       [(Idtype-Function kind is-native arg-name* arg-type* return-type)
        ; can't happen if expand-modules-and-types is doing its job
        (source-errorf src "invalid context for reference to ~s name ~s"
                       kind
                       (id-sym var-name))])]
    [(ledger-ref ,src ,ledger-field-name)
     (values
       `(ledger-ref ,src ,ledger-field-name)
       (Idtype-case (get-idtype src ledger-field-name)
         [(Idtype-Base type) type]
         [(Idtype-Function kind is-native arg-name* arg-type* return-type)
          ; can't happen if expand-modules-and-types is doing its job
          (source-errorf src "invalid context for reference to ~s name ~s"
                         kind
                         (id-sym ledger-field-name))]))]
    [(elt-call ,src ,[elt-call-lhs : expr src "." #f -> expr type] ,elt-name ,[Care : expr* type*] ...)
     (let ([actual-type type] [actual-type* type*])
       (define (handle-contract expr actual-type err)
         (let ([root-type (de-alias actual-type #t)])
           (nanopass-case (Ltypes Type) root-type
             [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
              (guard (not adt-type-only?))
              (hashtable-set! contract-type-ht root-type #t)
              (find-contract-circuit src src^ contract-name elt-name elt-name* type** type* actual-type actual-type* expr expr*)]
             [else (err)])))
       (nanopass-case (Ltypes Type) (de-alias actual-type #t)
         [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
          (find-adt-op src elt-name #f adt-name adt-op* actual-type* expr expr*
            (lambda ()
              (let-values ([(expr actual-type) (find-adt-op src 'read #f adt-name adt-op* '() expr '()
                                                 (lambda () (adt-op-error! src elt-name #f adt-name adt-rt-op* adt-arg*)))])
                (handle-contract expr actual-type (lambda () (adt-op-error! src elt-name #f adt-name adt-rt-op* adt-arg*))))))]
         [else (handle-contract expr actual-type (lambda () (elt-call-oops src actual-type)))]))]
    [else (let-values ([(expr type) (Care ir)])
            (check-result-type src expr type))])
  (Care : Expression (ir) -> Expression (type)
    (definitions
      (define (desugar-ledger-read src expr type)
        (nanopass-case (Ltypes Type) (de-alias type #t)
          [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
           (find-adt-op src 'read #f adt-name adt-op* '() expr '()
             (lambda ()
               (source-errorf src "incomplete chain of ledger indirects: final result must be a regular type, but received ADT type ~a"
                              (format-type type))))]
          [else (values expr type)]))
      )
    [(quote ,src ,datum)
     (values
       `(quote ,src ,datum)
       (with-output-language (Ltypes Type)
         (cond
           [(boolean? datum) `(tboolean ,src)]
           [(field? datum)
            (if (<= datum (max-unsigned))
                `(tunsigned ,src ,datum)
                (source-errorf src "constant ~d is larger than the largest representable Uint; use\
                               \n    ~:*~d as Field\
                               \n  to treat as a value of type Field"
                               datum))]
           [(bytevector? datum)
            ; no need to check len? for the generated tbytes.  this is already caught in
            ; the parser
            `(tbytes ,src ,(bytevector-length datum))]
           [else (assert cannot-happen)])))]
    [(var-ref ,src ,var-name)
     (values
       `(var-ref ,src ,var-name)
       (Idtype-case (get-idtype src var-name)
         [(Idtype-Base type) type]
         [(Idtype-Function kind is-native arg-name* arg-type* return-type)
          ; can't happen if expand-modules-and-types is doing its job
          (source-errorf src "invalid context for reference to ~s name ~s"
                         kind
                         (id-sym var-name))]))]
    [(ledger-ref ,src ,ledger-field-name)
     (desugar-ledger-read src
       `(ledger-ref ,src ,ledger-field-name)
       (Idtype-case (get-idtype src ledger-field-name)
         [(Idtype-Base type) type]
         [(Idtype-Function kind is-native arg-name* arg-type* return-type)
          ; can't happen if expand-modules-and-types is doing its job
          (source-errorf src "invalid context for reference to ~s name ~s"
                         kind
                         (id-sym ledger-field-name))]))]
    [(default ,src ,[type])
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
        (guard (eq? adt-name 'Kernel))
        (source-errorf src "default is not defined for ADT type Kernel")]
       [else (values `(default ,src ,type) type)])]
    [(if ,src ,[Care : expr0 type0] ,expr1 ,expr2)
     (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type0)))
     (let-values ([(expr1 type1) (Care expr1)] [(expr2 type2) (Care expr2)])
       (let ([type (cond
                     [(subtype? type1 type2) type2]
                     [(subtype? type2 type1) type1]
                     [else (source-errorf src "mismatch between type ~a and type ~a of condition branches"
                                          (format-type type1)
                                          (format-type type2))])])
         (values
           `(if ,src
                ,expr0
                ,(maybe-safecast src type type1 expr1)
                ,(maybe-safecast src type type2 expr2))
           type)))]
    [(elt-ref ,src ,[Care : expr type] ,elt-name)
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
        (let ([elt-name (cond
                          [(and (stdlib-src? src1)
                                (assp (lambda (x) (and (eq? (car x) struct-name) (eq? (cdr x) elt-name)))
                                      stdlib-struct-field-aliases)) =>
                           (lambda (a)
                             (let ([new-elt-name (cdr a)])
                               (record-alias! src elt-name new-elt-name)
                               new-elt-name))]
                          [else elt-name])])
          (let loop ([elt-name* elt-name*] [type* type*] [i 0])
            (if (null? elt-name*)
                (source-errorf src "structure ~s has no field named ~s"
                               struct-name
                               elt-name)
                (if (eq? (car elt-name*) elt-name)
                    (values
                      `(elt-ref ,src ,expr ,elt-name ,i)
                      (car type*))
                    (loop (cdr elt-name*) (cdr type*) (fx+ i 1))))))]
       [else (source-errorf src "expected structure type, received ~a"
                            (format-type type))])]
    [(elt-call ,src ,expr ,elt-name ,expr* ...)
     (let-values ([(expr type) (elt-call-lhs ir src "." #f)])
       (desugar-ledger-read src expr type))]
    [(emit ,src ,[Care : expr type])
     (validate-event-type! src type)
     (values
       `(emit ,src ,type ,expr)
       (with-output-language (Ltypes Type) `(ttuple ,src)))]
    [(serialize ,src ,len ,[type] ,[Care : expr type^])
     (unless (serializable? type)
       (source-errorf src "~a is not a serializable type" (format-type type)))
     (unless (subtype? type^ type)
       (source-errorf src "mismatch between actual type ~a and parameterized type ~a in call to serialize"
                      (format-type type^)
                      (format-type type)))
     (values
       `(serialize ,src ,len ,type ,(maybe-safecast src type type^ expr))
       (with-output-language (Ltypes Type) `(tbytes ,src ,len)))]
    [(deserialize ,src ,len ,[type] ,[Care : expr type^])
     (unless (serializable? type)
       (source-errorf src "~a is not a serializable type" (format-type type)))
     (let ([expected-type (with-output-language (Ltypes Type) `(tbytes ,src ,len))])
       (unless (sametype? type^ expected-type)
         (source-errorf src "expected deserialize argument to have type ~a, received ~a"
                        (format-type expected-type)
                        (format-type type^))))
     (values
       `(deserialize ,src ,len ,type ,expr)
       type)]
    [(= ,src ,[elt-call-lhs : expr1 src "=" #t -> expr1 type1] ,[Care : expr2 type2])
     (nanopass-case (Ltypes Type) (de-alias type1 #t)
       [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
        (find-adt-op! src 'write "=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
       [else (source-errorf src "expected left-hand side of = to have an ADT type, received ~a"
                            (format-type type1))])]
    [(+= ,src ,[elt-call-lhs : expr1 src "+=" #t -> expr1 type1] ,[Care : expr2 type2])
     (nanopass-case (Ltypes Type) (de-alias type1 #t)
       [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
        (find-adt-op! src 'increment "+=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
       [else (source-errorf src "expected left-hand side of += to have an ADT type, received ~a"
                            (format-type type1))])]
    [(-= ,src ,[elt-call-lhs : expr1 src "-=" #t -> expr1 type1] ,[Care : expr2 type2])
     (nanopass-case (Ltypes Type) (de-alias type1 #t)
       [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
        (find-adt-op! src 'decrement "-=" adt-name adt-op* adt-rt-op* (list type2) expr1 (list expr2) adt-arg*)]
       [else (source-errorf src "expected left-hand side of -= to have an ADT type, received ~a"
                            (format-type type1))])]
    [(enum-ref ,src ,[type] ,elt-name^)
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
        (unless (or (eq? elt-name^ elt-name) (memq elt-name^ elt-name*))
          (source-errorf src "enum ~s has no field named ~s"
                         enum-name
                         elt-name^))
        (values
          `(enum-ref ,src ,type ,elt-name^)
          type)]
       [else
        ; can't presently happen: we never construct an enum-ref unless we have an enum type
        (source-errorf src "expected enum type, received ~a"
                       (format-type type))])]
    [(tuple ,src ,[Tuple-Argument : tuple-arg* -> expr* type* kind* nat* elt-type**] ...)
     (define (unrelated-elt-types elt-type+)
       (let ([type (car elt-type+)])
         (let loop ([type* (cdr elt-type+)])
           (let ([type^ (car type*)])
             (unless (or (subtype? type^ type) (subtype? type type^))
               (source-errorf src "tuple/vector construction expression with vector-typed spreads has unrelated element types ~a and ~a"
                              (format-type type) (format-type type^)))
             (loop (cdr type*))))))
     (if (memq 'vector-spread kind*)
         ; when a tuple expression contains a spread of a vector-typed value, the resulting value is a vector
         ; and must have a vector type, so the type of each non-spread element and the element type of each tuple or
         ; vector element must be liftable to a common element type. if we someday extend the tuple type to incorporate
         ; both single and spread elements, e.g., (ttuple (single Field) (spread 3 Boolean)), we can lift this
         ; restriction; though then it would also be incumbent upon us to add a source-level syntax for such types.
         ; one way to look at such types is as a compressed representation of a tuple type.  for example, the
         ; the tuple type above could also be written as (tuple Field Boolean Boolean Boolean).  compression is
         ; useful, if not critical, when spreading longer vectors: (ttuple (single Field) (spread 1000000 Boolean))
         ; would be rather large if uncompressed.
         (let ([elt-type (let ([elt-type* (apply append elt-type**)])
                           (or (max-type elt-type*) (unrelated-elt-types elt-type*)))])
           (define (make-vector-type len)
             (unless (len? len)
               (source-errorf src "the size of tuple/vector construction expression with vector-typed spread\n    ~d\n  exceeds the maximum vector size allowed\n    ~d"
                              len
                              (max-bytes/vector-length)))
             (with-output-language (Ltypes Type)
               `(tvector ,src ,len ,elt-type)))
           (values
             `(vector ,src ,(map (lambda (kind nat expr type)
                                   (if (eq? kind 'single)
                                       `(single ,src ,(maybe-safecast src elt-type type expr))
                                       `(spread ,src ,nat ,(maybe-safecast src (make-vector-type nat) type expr))))
                                 kind* nat* expr* type*)
                      ...)
             (make-vector-type (apply + nat*))))
         ; if a tuple contains only non-spread elements and spreads of tuple-typed values, the resulting value
         ; is a tuple and can have any mix of element types.
         (let* ([elt-type* (apply append elt-type**)]
                [len (length elt-type*)])
           (unless (len? len)
             (source-errorf src "the size of tuple/vector construction expression with tuple-typed spread\n    ~d\n  exceeds the maximum tuple size allowed\n    ~d"
                            len
                            (max-bytes/vector-length)))
           (values
             `(tuple ,src ,(map (lambda (kind nat expr)
                                  (if (eq? kind 'single)
                                      `(single ,src ,expr)
                                      `(spread ,src ,nat ,expr)))
                                kind* nat* expr*)
                     ...)
             (with-output-language (Ltypes Type)
               `(ttuple ,src ,elt-type* ...)))))]
    [(bytes ,src ,[Bytes-Argument : tuple-arg* nat*] ...)
     (let ([len-total (apply + nat*)])
       (unless (len? len-total)
         (source-errorf src "Bytes construction length\n    ~d exceeds the maximum bytes length allowed\n    ~d"
                        len-total
                        (max-bytes/vector-length)))
       (values
         `(vector->bytes ,src ,len-total
            (vector ,src ,tuple-arg* ...))
         (with-output-language (Ltypes Type)
           `(tbytes ,src ,len-total))))]
    [(tuple-ref ,src ,[Care : expr expr-type] ,[Care : index index-type])
     (nanopass-case (Ltypes Type) (de-alias index-type #t)
       [(tunsigned ,src^ ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (cond
       [(let f ([index index])
          (nanopass-case (Ltypes Expression) index
            [(quote ,src ,datum)
             (unless (kindex? datum)
               (source-errorf src "index ~d exceeds maximum allowed index ~d for a tuple or vector reference"
                              datum
                              (- (max-bytes/vector-length) 1)))
             datum]
            [(safe-cast ,src ,type ,type^ ,index) (f index)]
            [else #f])) =>
        (lambda (kindex)
          (define (bounds-check what len)
            (unless (< kindex len)
              (source-errorf src "index ~d is out-of-bounds for a ~a of length ~d"
                             kindex what len)))
          (nanopass-case (Ltypes Type) (de-alias expr-type #t)
            [(tbytes ,src ,len)
             (bounds-check "Bytes value" len)
             (values
               `(bytes-ref ,src ,expr-type ,expr (quote ,src ,kindex))
               (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
            [(ttuple ,src^ ,type* ...)
             (bounds-check "tuple" (length type*))
             (values
               `(tuple-ref ,src ,expr ,kindex)
               (list-ref type* kindex))]
            [(tvector ,src^ ,len^ ,type^)
             (bounds-check "vector" len^)
             (values
               `(tuple-ref ,src ,expr ,kindex)
               type^)]
            [else (source-errorf src "expected a tuple, Vector, or Bytes type, received ~a"
                                 (format-type expr-type))]))]
       [else
        (let ()
          (define (zero-check len)
            (unless (> len 0)
              (source-errorf src "expected a non-empty tuple, vector, or Bytes type, received ~a"
                             (format-type expr-type))))
          (nanopass-case (Ltypes Type) (de-alias expr-type #t)
            [(tbytes ,src^ ,len)
             (zero-check len)
             (values
               `(bytes-ref ,src ,expr-type ,expr ,index)
               (with-output-language (Ltypes Type) `(tunsigned ,src 255)))]
            [else
             (let-values ([(len^ elt-type) (vector-element-type src "tuple reference with a non-constant index" expr-type)])
               (zero-check len^)
               (let* ([vector-type (with-output-language (Ltypes Type) `(tvector ,src ,len^ ,elt-type))]
                      [expr (maybe-safecast src vector-type expr-type expr)])
                 (values
                   `(vector-ref ,src ,vector-type ,expr ,index)
                   elt-type)))]))])]
    [(tuple-slice ,src ,[Care : expr expr-type] ,[Care : index index-type] ,len)
     (nanopass-case (Ltypes Type) (de-alias index-type #t)
       [(tunsigned ,src^ ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (cond
       [(let f ([index index])
          (nanopass-case (Ltypes Expression) index
            [(quote ,src ,datum)
             (unless (kindex? datum)
               (source-errorf src "index ~d exceeds maximum index allowed ~d for a slice"
                              datum
                              (- (max-bytes/vector-length) 1)))
             datum]
            [(safe-cast ,src ,type ,type^ ,index) (f index)]
            [else #f])) =>
        (lambda (kindex)
          (define (bounds-check what input-len)
            (unless (<= (+ kindex len) input-len)
              (source-errorf src "slice index ~d plus length ~d is out-of-bounds for a ~a of length ~d"
                             kindex len what input-len)))
          (nanopass-case (Ltypes Type) (de-alias expr-type #t)
            [(tbytes ,src ,len^)
             (bounds-check "Bytes value" len^)
             (values
               `(bytes-slice ,src ,expr-type ,expr (quote ,src ,kindex) ,len)
               (with-output-language (Ltypes Type)
                 `(tbytes ,src ,len)))]
            [(ttuple ,src^ ,type* ...)
             (bounds-check "tuple" (length type*))
             (values
               `(tuple-slice ,src ,expr-type ,expr ,kindex ,len)
               (with-output-language (Ltypes Type)
                 `(ttuple ,src ,(list-head (list-tail type* kindex) len) ...)))]
            [(tvector ,src^ ,len^ ,type^)
             (bounds-check "vector" len^)
             (values
               `(tuple-slice ,src ,expr-type ,expr ,kindex ,len)
               (with-output-language (Ltypes Type)
                 `(tvector ,src ,len ,type^)))]
            [else (source-errorf src "expected first slice argument to be a tuple, Vector, or Bytes type, received ~a"
                                 (format-type expr-type))]))]
       [else
        (let ()
          (define (bounds-check input-len)
            (unless (<= len input-len)
              (source-errorf src "slice length ~d exceeds the length ~d of the input tuple, vector, or Bytes value" len input-len)))
          (nanopass-case (Ltypes Type) (de-alias expr-type #t)
            [(tbytes ,src^ ,len^)
             (bounds-check len^)
             (values
               `(bytes-slice ,src ,expr-type ,expr ,index ,len)
               (with-output-language (Ltypes Type) `(tbytes ,src ,len)))]
            [else
             (let-values ([(input-len elt-type) (vector-element-type src "tuple slice with a non-constant index" expr-type)])
               (bounds-check input-len)
               (let* ([vector-type (with-output-language (Ltypes Type)
                                     ; there is no need to check (len? len^) since since if the check is violated the construction of expr-type
                                     ; would have already caught it
                                     `(tvector ,src ,input-len ,elt-type))]
                      [expr (maybe-safecast src vector-type expr-type expr)])
                 (values
                   `(vector-slice ,src ,vector-type ,expr ,index ,len)
                   (with-output-language (Ltypes Type)
                     `(tvector ,src ,len ,elt-type)))))]))])]
    [(+ ,src ,expr1 ,expr2)
     (arithmetic-binop src '+ expr1 expr2
       (lambda (mbits expr1 expr2)
         `(+ ,src ,mbits ,expr1 ,expr2)))]
    [(- ,src ,expr1 ,expr2)
     (arithmetic-binop src '- expr1 expr2
       (lambda (mbits expr1 expr2)
         `(- ,src ,mbits ,expr1 ,expr2)))]
    [(* ,src ,expr1 ,expr2)
     (arithmetic-binop src '* expr1 expr2
       (lambda (mbits expr1 expr2)
         `(* ,src ,mbits ,expr1 ,expr2)))]
    [(< ,src ,expr1 ,expr2)
     (relational-operator src expr1 expr2
       (lambda (bits expr1 expr2)
         `(< ,src ,bits ,expr1 ,expr2)))]
    [(<= ,src ,expr1 ,expr2)
     (relational-operator src expr1 expr2
       (lambda (bits expr1 expr2)
         `(<= ,src ,bits ,expr1 ,expr2)))]
    [(> ,src ,expr1 ,expr2)
     (relational-operator src expr1 expr2
       (lambda (bits expr1 expr2)
         `(> ,src ,bits ,expr1 ,expr2)))]
    [(>= ,src ,expr1 ,expr2)
     (relational-operator src expr1 expr2
       (lambda (bits expr1 expr2)
         `(>= ,src ,bits ,expr1 ,expr2)))]
    [(== ,src ,expr1 ,expr2)
     (equality-operator src expr1 expr2
       (lambda (type expr1 expr2)
         `(== ,src ,type ,expr1 ,expr2)))]
    [(!= ,src ,expr1 ,expr2)
     (equality-operator src expr1 expr2
       (lambda (type expr1 expr2)
         `(!= ,src ,type ,expr1 ,expr2)))]
    [(for ,src ,var-name ,expr1 ,expr2)
     (let-values ([(expr1 type1) (Care expr1)])
       (let-values ([(len elt-type) (vector-element-type src "for 'of' expression" type1)])
         (set-idtype! var-name (Idtype-Base elt-type))
         (let ([expr2 (CareNot expr2)])
           (unset-idtype! var-name)
           (values
             `(fold ,src ,len
                ,(let ([t (make-temp-id src 't)])
                   `(circuit ,src ((,t (ttuple ,src))
                                   (,var-name ,elt-type))
                             (ttuple ,src)
                             (seq ,src ,expr2 (var-ref ,src ,t))))
                ((tuple ,src) (ttuple ,src))
                (,expr1 ,type1 ,elt-type))
             (with-output-language (Ltypes Type)
               `(ttuple ,src))))))]
    [(map ,src ,fun ,expr ,expr* ...)
     (let*-values ([(expr+ actual-type+) (maplr2 Care (cons expr expr*))]
                   [(len actual-elt-type+) (vector-element-types src 'map actual-type+ 2)])
       (do-call src #f fun actual-elt-type+
         (lambda (declared-type+ return-type fun)
           (values
             `(map ,src ,len ,fun
                ; each map-arg contains
                ; - an expression whose value should be a tuple, vector, or bytes
                ; - the value's type, which should be a tttuple with a tvector supertype, a tvector, or a tbytes
                ; - the type to which each element of the expression's value must be cast, i.e., the declared type of fun's corresponding parameter
                (,(car expr+) ,(car actual-type+) ,(car declared-type+))
                (,(cdr expr+) ,(cdr actual-type+) ,(cdr declared-type+))
                ...)
             (with-output-language (Ltypes Type)
               `(tvector ,src ,len ,return-type))))))]
    [(fold ,src ,fun ,expr0 ,expr ,expr* ...)
     (let*-values ([(expr0 actual-type0) (Care expr0)]
                   [(expr+ actual-type+) (maplr2 Care (cons expr expr*))]
                   [(len actual-elt-type+) (vector-element-types src 'fold actual-type+ 3)])
       (do-call src #t fun (cons actual-type0 actual-elt-type+)
         (lambda (declared-type+ return-type fun)
           (let ([declared-type0 (car declared-type+)] [declared-type+ (cdr declared-type+)])
             (let ([expr0 (maybe-safecast src declared-type0 actual-type0 expr0)])
               (values
                 `(fold ,src ,len ,fun
                    (,expr0 ,declared-type0)
                    ; see the note about map args above
                    (,(car expr+) ,(car actual-type+) ,(car declared-type+))
                    (,(cdr expr+) ,(cdr actual-type+) ,(cdr declared-type+))
                    ...)
                 return-type))))))]
    [(call ,src ,fun ,expr* ...)
     (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
       (do-call src #f fun actual-type*
         (lambda (declared-type* return-type fun)
           (values
             `(call ,src ,fun ,(map (maybe-safecast src) declared-type* actual-type* expr*) ...)
             return-type))))]
    [(new ,src ,[type] ,new-field* ...)
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
        (define-record-type field
          (nongenerative)
          (fields src (mutable expr) (mutable type))
          (protocol (lambda (n) (lambda (src expr) (n src expr #f)))))
        (define-record-type spread
          (nongenerative)
          (parent field)
          (fields)
          (protocol (lambda (n) (lambda (src expr) ((n src expr))))))
        (define-record-type positional
          (nongenerative)
          (parent field)
          (fields)
          (protocol (lambda (n) (lambda (src expr) ((n src expr))))))
        (define-record-type named
          (nongenerative)
          (parent field)
          (fields elt-name)
          (protocol (lambda (n) (lambda (src elt-name expr) ((n src expr) elt-name)))))
        (define (process-field! field)
          (let-values ([(expr type) (Care (field-expr field))])
            (field-expr-set! field expr)
            (field-type-set! field type)))
        (define (s0)
          (if (null? new-field*)
              (finish #f '() '())
              (nanopass-case (Lexpanded New-Field) (car new-field*)
                [(spread ,src^ ,expr) (snamed (cdr new-field*) (make-spread src^ expr) '() '())]
                [else (spositional new-field* '())])))
        (define (spositional new-field* rpositional*)
          (if (null? new-field*)
              (finish #f (reverse rpositional*) '())
              (nanopass-case (Lexpanded New-Field) (car new-field*)
                [(positional ,src^ ,expr) (spositional (cdr new-field*) (cons (make-positional src^ expr) rpositional*))]
                [else (snamed new-field* #f (reverse rpositional*) '())])))
        (define (snamed new-field* maybe-spread positional* rnamed*)
          (if (null? new-field*)
              (finish maybe-spread positional* (reverse rnamed*))
              (nanopass-case (Lexpanded New-Field) (car new-field*)
                [(named ,src^ ,elt-name ,expr)
                 (let ([elt-name (cond
                                   [(and (stdlib-src? src1)
                                         (assp (lambda (x) (and (eq? (car x) struct-name) (eq? (cdr x) elt-name)))
                                               stdlib-struct-field-aliases)) =>
                                    (lambda (a)
                                      (let ([new-elt-name (cdr a)])
                                        (record-alias! src^ elt-name new-elt-name)
                                        new-elt-name))]
                                   [else elt-name])])
                   (snamed (cdr new-field*) maybe-spread positional* (cons (make-named src^ elt-name expr) rnamed*)))]
                [(positional ,src^ ,expr) (source-errorf src^ "positional initializer found after spread or named initializer in struct creation syntax")]
                [(spread ,src^ ,expr) (source-errorf src^ "spread initializer found after positional or named initializers in struct creation syntax")])))
        (define (finish maybe-spread positional* named*)
          (let ([npositional (length positional*)])
            (let ([ndeclared (length elt-name*)])
              (when (fx> npositional ndeclared)
                (source-errorf src "more positional initializers (~d) supplied than the number of fields (~d) of ~a"
                               npositional
                               ndeclared
                               (format-type type))))
            (when maybe-spread (process-field! maybe-spread))
            (for-each process-field! positional*)
            (for-each process-field! named*)
            (when maybe-spread
              (unless (sametype? (field-type maybe-spread) type)
                (source-errorf (field-src maybe-spread)
                               "the type of the spread structure:\n    ~a\n  does match the declared type of the structure to be created:\n    ~a"
                               (format-type (field-type maybe-spread))
                               (format-type type))))
            (let ([ht (make-hashtable symbol-hash eq?)])
              ; NB: assuming field names are not duplicated, which should have already been caught
              (for-each
                (lambda (elt-name positional)
                  (hashtable-set! ht elt-name positional))
                (list-head elt-name* npositional)
                positional*)
              (for-each
                (lambda (named)
                  (let ([a (hashtable-cell ht (named-elt-name named) #f)])
                    (when (cdr a)
                      (let ([src (field-src named)] [src^ (field-src (cdr a))])
                        (if (positional? (cdr a))
                            (source-errorf src
                                           "value of field ~s is already specified positionally at ~a"
                                           (named-elt-name named)
                                           (format-source-object src^))
                            (source-errorf src
                                           "value of field ~s is already given at ~a"
                                           (named-elt-name named)
                                           (format-source-object src^)))))
                    (set-cdr! a named)))
                named*)
              (values
                ((lambda (k)
                   (if maybe-spread
                       (maybe-bind src (field-type maybe-spread) (field-expr maybe-spread) k)
                       (k #f)))
                 (lambda (maybe-spread-expr)
                   (let ([th* (maplr
                                 (lambda (elt-name declared-type i)
                                   (cond
                                     [(hashtable-ref ht elt-name #f) =>
                                      (lambda (field)
                                        (hashtable-delete! ht elt-name)
                                        ; delay type checks until structural checks are completed so the
                                        ; compiler complains about structural problems in preference to
                                        ; type errors
                                        (lambda ()
                                          (let ([actual-type (field-type field)])
                                            (unless (subtype? actual-type declared-type)
                                              (source-errorf src "mismatch between actual type ~a and declared type ~a for field ~s of ~a"
                                                             (format-type actual-type)
                                                             (format-type declared-type)
                                                             elt-name
                                                             (format-type type)))
                                            (maybe-safecast src declared-type actual-type (field-expr field)))))]
                                     [maybe-spread-expr
                                      (lambda () `(elt-ref ,src ,maybe-spread-expr ,elt-name ,i))]
                                     [else
                                      (source-errorf src "value for element ~s is missing in creation syntax for ~a"
                                                     elt-name
                                                     (format-type type))]))
                                 elt-name* type* (enumerate elt-name*))])
                     (for-each
                       (lambda (named)
                         (when (hashtable-contains? ht (named-elt-name named))
                           (source-errorf (field-src named)
                                          "value for unrecognized field named ~a appears in creation syntax for ~a"
                                          (named-elt-name named)
                                          (format-type type))))
                       named*)
                     ; force type checks now that structural checks are completed
                     (let ([expr* (maplr (lambda (th) (th)) th*)])
                       `(new ,src ,type ,expr* ...)))))
                type))))
        (s0)]
       [else (source-errorf src "expected structure type, received ~a"
                            (format-type type))])]
    [(seq ,src ,expr* ... ,expr)
     (let*-values ([(expr*) (maplr CareNot expr*)] [(expr type) (Care expr)])
       (values
         `(seq ,src ,expr* ... ,expr)
         type))]
    [(let* ,src ([(,var-name* ,[type*]) ,expr*] ...) ,expr)
     (let ([declared-type* type*])
       (let-values ([(expr* actual-type*) (maplr2 Care expr*)])
         (let ([declared-type* (maplr (lambda (var-name declared-type actual-type)
                                        (unless (subtype? actual-type declared-type)
                                          (source-errorf src "mismatch between actual type ~a and declared type ~a of const binding"
                                                         (format-type actual-type)
                                                         (format-type declared-type)))
                                        (let ([type (if (declared? declared-type)
                                                        declared-type
                                                        actual-type)])
                                          (set-idtype! var-name (Idtype-Base type))
                                          type))
                                      var-name*
                                      declared-type*
                                      actual-type*)])
           (let-values ([(expr body-type) (Care expr)])
             (for-each unset-idtype! var-name*)
             (values
               `(let* ,src ([(,var-name* ,declared-type*)
                             ,(map (maybe-safecast src) declared-type* actual-type* expr*)]
                            ...)
                  ,expr)
                body-type)))))]
    [(assert ,src ,[Care : expr type0] ,mesg)
     (unless (nanopass-case (Ltypes Type) (de-alias type0 #t)
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type0)))
     (values
       `(assert ,src ,expr ,mesg)
       (with-output-language (Ltypes Type) `(ttuple ,src)))]
    ;; TODO(kmillikin): make sure this case is covered by tests and works for JubjubScalar.
    [(cast ,src ,type (quote ,src^ ,datum))
     (guard
       ; NB: guards are run before automatic recursion, so type is an Lexpanded Type, not an Ltypes Type
       (let f ([type type])
         (nanopass-case (Lexpanded Type) type
           [(tfield ,src (field-native)) #t]
           [(talias ,src ,nominal? ,type-name ,type) (f type)]
           [else #f]))
       (field? datum)
       (> datum (max-unsigned)))
     (values
       `(quote ,src^ ,datum)
       (Type type))]
    [(cast ,src ,[type] ,[Care : expr type^])
     (define (handle-unaliased target-type source-type expr)
       (define (u8-subtype? type)
         (nanopass-case (Ltypes Type) (de-alias type #t)
           [(tunsigned ,src ,nat) (<= nat 255)]
           [else #f]))
       (define (u8-supertype? type)
         (nanopass-case (Ltypes Type) (de-alias type #t)
           [(tunsigned ,src ,nat) (>= nat 255)]
           [(tfield ,src ,ftype) #t]
           [else #f]))
       (or (and (subtype? source-type target-type)
                (maybe-safecast src target-type source-type expr))
           (T target-type
              [(tfield ,src1 ,ftype1)
               (T source-type
                  [(tfield ,src2 ,ftype2)
                   ;; We know that the field types are distinct because of `subtype?` above, and
                   ;; there is (currently) no field subtyping.
                   (nanopass-case (Ltypes Field-Type) ftype1
                     [(field-native)
                      (nanopass-case (Ltypes Field-Type) ftype2
                        [(field-scalar (curve-jubjub))
                         `(cast-to-field ,src ,ftype1 ,source-type ,expr)]
                        [else #f])]
                     [(field-scalar (curve-jubjub))
                      (nanopass-case (Ltypes Field-Type) ftype2
                        [(field-native)
                         `(cast-to-field ,src ,ftype1 ,source-type ,expr)]
                        [else #f])])]
                  [(tunsigned ,src2 ,nat)
                   (nanopass-case (Ltypes Field-Type) ftype1
                     [(field-native)
                      `(safe-cast ,src ,target-type ,source-type ,expr)]
                     [(field-scalar (curve-jubjub))
                      `(cast-to-field ,src ,ftype1 ,source-type ,expr)])]
                  [(tbytes ,src2 ,len2)
                   (guard (not (eqv? len2 0)))
                   (and (nanopass-case (Ltypes Field-Type) ftype1
                          [(field-native) #t]
                          [(field-base (curve-secp256k1)) (eqv? len2 32)]
                          [(field-scalar (curve-secp256k1)) (eqv? len2 32)]
                          [else #f])
                        `(cast-from-bytes ,src ,target-type ,len2 ,expr))]
                  [(tenum ,src2 ,enum-name ,elt-name ,elt-name* ...)
                   `(cast-from-enum ,src ,target-type ,source-type ,expr)]
                  [(tboolean ,src2)
                   `(if ,src ,expr
                        (safe-cast ,src ,target-type (tunsigned ,src 1) (quote ,src 1))
                        (safe-cast ,src ,target-type (tunsigned ,src 0) (quote ,src 0)))])]
              [(tbytes ,src1 ,len1)
               (T source-type
                  [(tfield ,src2 ,ftype)
                   (guard (not (= len1 0)))
                   (and (nanopass-case (Ltypes Field-Type) ftype
                          [(field-native) #t]
                          [(field-base (curve-secp256k1)) (eqv? len1 32)]
                          [(field-scalar (curve-secp256k1)) (eqv? len1 32)])
                        `(field->bytes ,src ,len1 ,ftype ,expr))]
                  [(tunsigned ,src2 ,nat2)
                   (guard (not (= len1 0)))
                   `(field->bytes ,src ,len1 (field-native)
                      (safe-cast ,src (tfield ,src2 (field-native)) ,source-type ,expr))]
                  [(ttuple ,src2 ,type* ...)
                   (guard
                     (= (length type*) len1)
                     (andmap u8-subtype? type*))
                   `(vector->bytes ,src ,len1 ,expr)]
                  [(tvector ,src2 ,len2 ,type2)
                   (guard (= len2 len1) (u8-subtype? type2))
                   `(vector->bytes ,src ,len1 ,expr)])]
              [(ttuple ,src1 ,type* ...)
               (T source-type
                  [(tbytes ,src2 ,len2)
                   (guard (= len2 (length type*)) (andmap u8-supertype? type*))
                   (maybe-safecast src target-type
                     (with-output-language (Ltypes Type)
                       `(tvector ,src ,len2 (tunsigned ,src 255)))
                     `(bytes->vector ,src ,len2 ,expr))])]
              [(tvector ,src1 ,len1 ,type)
               (T source-type
                  [(tbytes ,src2 ,len2)
                   (guard (= len2 len1) (u8-supertype? type))
                   (maybe-safecast src target-type
                     (with-output-language (Ltypes Type)
                       `(tvector ,src ,len2 (tunsigned ,src 255)))
                     `(bytes->vector ,src ,len1 ,expr))])]
              [(tunsigned ,src1 ,nat1)
               (T source-type
                  [(tfield ,src2 ,ftype)
                   `(cast-from-field ,src ,nat1 ,ftype ,expr)]
                  [(tunsigned ,src2 ,nat2)
                   (assert (> nat2 nat1))
                   `(downcast-unsigned ,src ,nat2 ,nat1 ,expr)]
                  [(tbytes ,src2 ,len2)
                   (guard (not (= len2 0)))
                   `(cast-from-bytes ,src ,target-type ,len2 ,expr)]
                  [(tenum ,src2 ,enum-name ,elt-name ,elt-name* ...)
                   `(cast-from-enum ,src ,target-type ,source-type ,expr)]
                  [(tboolean ,src2)
                   (if (= nat1 0)
                       `(if ,src ,expr
                            (downcast-unsigned ,src 1 ,nat1 (quote ,src 1))
                            (quote ,src 0))
                       `(if ,src ,expr
                            ,(if (eqv? nat1 1)
                                 `(quote ,src 1)
                                 `(safe-cast ,src ,target-type (tunsigned ,src 1) (quote ,src 1)))
                            (safe-cast ,src ,target-type (tunsigned ,src 0) (quote ,src 0))))])]
              [(tboolean ,src1)
               (T source-type
                  [(tfield ,src2 ,ftype)
                   `(if ,src
                        (== ,src ,source-type ,expr
                          (safe-cast ,src ,source-type (tunsigned ,src 0) (quote ,src 0)))
                        (quote ,src #f)
                        (quote ,src #t))]
                  [(tunsigned ,src2 ,nat2)
                   (if (eqv? nat2 0)
                       `(quote ,src #f)
                       `(if ,src
                            (== ,src ,source-type ,expr
                              (safe-cast ,src ,source-type (tunsigned ,src 0) (quote ,src 0)))
                            (quote ,src #f)
                            (quote ,src #t)))])]
              [(tenum ,src1 ,enum-name ,elt-name ,elt-name* ...)
               (guard (T source-type [(tfield ,src ,ftype) #t] [(tunsigned ,src ,nat) #t]))
               `(cast-to-enum ,src ,target-type ,source-type ,expr)])
           (source-errorf src "cannot cast from type ~a to type ~a"
                          (format-type source-type)
                          (format-type target-type))))
     (values
       (let ([unaliased-target-type (de-alias type #t)]
             [unaliased-source-type (de-alias type^ #t)])
         (let ([expr (maybe-safecast src unaliased-source-type type^ expr)])
           (maybe-safecast src type unaliased-target-type
             (handle-unaliased unaliased-target-type unaliased-source-type expr))))
       type)]
    [(disclose ,src ,[Care : expr type])
     (values
       `(disclose ,src ,expr)
       type)]
    [(return ,src)
     (assert current-return-type)
     (let ([type (with-output-language (Ltypes Type) `(ttuple ,src))])
       (unless (subtype? type current-return-type)
         (source-errorf src "~a is declared to return a value of type ~a, but its body can return without supplying a value"
                        current-whose-body
                        (format-type current-return-type)))
       (values
         `(return ,src (tuple ,src))
         type))]
    [(return ,src ,[Care : expr type])
     (assert current-return-type)
     (unless (subtype? type current-return-type)
       (source-errorf src "mismatch between actual return type ~a and declared return type ~a of ~a"
                      (format-type type)
                      (format-type current-return-type)
                      current-whose-body))
     (values
       `(return ,src ,expr)
       type)]
    [else (internal-errorf 'Care "unexpected ir ~s" ir)])
  (Tuple-Argument : Tuple-Argument (ir) -> Expression (type kind nat elt-type*)
    [(single ,src ,[Care : expr type])
     (verify-non-adt-type! src type "tuple element")
     (values expr type 'single 1 (list type))]
    [(spread ,src ,[Care : expr type])
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(ttuple ,src ,type* ...) (values expr type 'tuple-spread (length type*) type*)]
       [(tvector ,src ,len ,type^) (values expr type 'vector-spread len (list type^))]
       [(tbytes ,src ,len)
        (let ([expr `(bytes->vector ,src ,len ,expr)])
          (let* ([type^ (with-output-language (Ltypes Type) `(tunsigned ,src 255))]
                 [type (with-output-language (Ltypes Type) `(tvector ,src ,len , type^))])
            (values expr type 'vector-spread len (list type^))))]
       [else (source-errorf src "expected tuple/vector spread expression to have a tuple, Vector, or Bytes type but received ~a"
                            (format-type type))])])
  (Bytes-Argument : Tuple-Argument (ir) -> Tuple-Argument (nat)
    (definitions
      (define (u8-subtype? type)
        (nanopass-case (Ltypes Type) (de-alias type #t)
          [(tunsigned ,src ,nat) (<= nat 255)]
          [(tunknown) #t]
          [else #f])))
    [(single ,src ,[Care : expr type])
     (unless (u8-subtype? type)
       (source-errorf src "expected type of Bytes constructor argument to be a subtype of Uint<8> but received ~a"
                      (format-type type)))
     (values
       (let ([new-type (with-output-language (Ltypes Type)
                         `(tunsigned ,src 255))])
         `(single ,src ,(maybe-safecast src new-type type expr)))
       1)]
    [(spread ,src ,[Care : expr type])
     (nanopass-case (Ltypes Type) (de-alias type #t)
       [(tbytes ,src ,len)
        (values
          `(spread ,src ,len (bytes->vector ,src ,len ,expr))
          len)]
       [(ttuple ,src ,type* ...)
        (guard (andmap u8-subtype? type*))
        (let ([nat (length type*)])
          (values
            `(spread ,src ,nat
                     ,(let ([new-type (with-output-language (Ltypes Type)
                                        ; there is no need to check (len? nat) since construction of tuple
                                        ; would have already caught it
                                        `(tvector ,src ,nat (tunsigned ,src 255)))])
                        (maybe-safecast src new-type type expr)))
            nat))]
       [(tvector ,src ,len ,type^)
        (guard (u8-subtype? type^))
        (values
          `(spread ,src ,len
                   ,(let ([new-type (with-output-language (Ltypes Type)
                                      `(tvector ,src ,len (tunsigned ,src 255)))])
                      (maybe-safecast src new-type type expr)))
          len)]
       [else (source-errorf src "expected type of Bytes spread to be a Bytes value or a Tuple or Vector of Uint<8> subtypes but received ~a"
                            (format-type type))])])
  )
