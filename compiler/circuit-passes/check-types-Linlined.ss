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

(define-pass check-types/Linlined : Linlined (ir) -> Linlined ()
  (definitions
    (define-syntax T
      (syntax-rules ()
        [(T ty clause ...)
         (nanopass-case (Linlined Type) ty clause ... [else #f])]))
    (define (datum-type src x)
      (with-output-language (Linlined Type)
        (cond
          [(boolean? x) `(tboolean ,src)]
          ;; TODO(kmillikin): We probably have to change this.
          [(field? x) (if (<= x (max-unsigned))
                          `(tunsigned ,src ,x)
                          `(tfield ,src (field-native)))]
          [(bytevector? x) `(tbytes ,src ,(bytevector-length x))]
          [else (internal-errorf 'datum-type "unexpected datum ~s" x)])))
    (define-datatype Idtype
      ; ordinary expression types
      (Idtype-Base type)
      ; circuits, witnesses, and statements
      (Idtype-Function kind arg-name* arg-type* return-type)
      )
    (module (set-idtype! unset-idtype! get-idtype)
      (define ht (make-eq-hashtable))
      (define (set-idtype! id idtype)
        (hashtable-set! ht id idtype))
      (define (unset-idtype! id)
        (hashtable-delete! ht id))
      (define (get-idtype src id)
        (or (hashtable-ref ht id #f)
            (source-errorf src "encountered undefined identifier ~s"
              id)))
      )
    (define (arg->name arg)
      (nanopass-case (Linlined Argument) arg
        [(,var-name ,type) var-name]))
    (define (arg->type arg)
      (nanopass-case (Linlined Argument) arg
        [(,var-name ,type) type]))
    (define (format-field-type ftype)
      (nanopass-case (Linlined Field-Type) ftype
        [(field-native) "Field"]
        [(field-scalar (curve-jubjub)) "JubjubScalar"]
        [(field-base (curve-secp256k1)) "Secp256k1Base"]
        [(field-scalar (curve-secp256k1)) "Secp256k1Scalar"]))
    (define (format-type type)
      (define (format-adt-arg adt-arg)
        (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg
          [,nat (format "~d" nat)]
          [,type (format-type type)]))
      (nanopass-case (Linlined Type) type
        [(tboolean ,src) "Boolean"]
        [(tfield ,src ,ftype) (format-field-type ftype)]
        [(tunsigned ,src ,nat) (format "Uint<0..~d>" (+ nat 1))]
        [(topaque ,src ,opaque-type) (format "Opaque<~s>" opaque-type)]
        [(tunknown) "Unknown"]
        [(tvector ,src ,len ,type) (format "Vector<~s, ~a>" len (format-type type))]
        [(tbytes ,src ,len) (format "Bytes<~s>" len)]
        [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
         (format "contract ~a[~{~a~^, ~}]" contract-name
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
        [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
         (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))]))
      (define (same-curve-type? ctype1 ctype2)
        (nanopass-case (Linlined Curve-Type) ctype1
          [(curve-jubjub)
           (nanopass-case (Linlined Curve-Type) ctype2
             [(curve-jubjub) #t]
             [else #f])]
          [(curve-secp256k1)
           (nanopass-case (Linlined Curve-Type) ctype2
             [(curve-secp256k1) #t]
             [else #f])]))
      (define (same-field-type? ftype1 ftype2)
        (nanopass-case (Linlined Field-Type) ftype1
          [(field-native)
           (nanopass-case (Linlined Field-Type) ftype2
             [(field-native) #t]
             [else #f])]
          [(field-base ,ctype1)
           (nanopass-case (Linlined Field-Type) ftype2
             [(field-base ,ctype2) (same-curve-type? ctype1 ctype2)]
             [else #f])]
          [(field-scalar ,ctype1)
           (nanopass-case (Linlined Field-Type) ftype2
             [(field-scalar ,ctype2) (same-curve-type? ctype1 ctype2)]
             [else #f])]))
    (define (sametype? type1 type2)
      (define (same-adt-arg? adt-arg1 adt-arg2)
        (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg1
          [,nat1
           (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg2
             [,nat2 (= nat1 nat2)]
             [else #f])]
          [,type1
           (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg2
             [,type2 (sametype? type1 type2)]
             [else #f])]))
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
         [(tunknown) #t] ; tunknown originates from empty vectors
         [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
          (T type2
             [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
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
              (and (eq? contract-name1 contract-name2)
                   (fx= (length elt-name1*) (length elt-name2*))
                   (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
         [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
          (T type2
             [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
              ; include struct-name and elt-name tests for nominal typing; remove
              ; for structural typing.
              (and (eq? struct-name1 struct-name2)
                   (= (length elt-name1*) (length elt-name2*))
                   (andmap eq? elt-name1* elt-name2*)
                   (andmap sametype? type1* type2*))])]
          [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr1 (,adt-op1* ...))
           (T type2
              [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr2 (,adt-op2* ...))
               (and (eq? adt-name1 adt-name2)
                    (fx= (length adt-arg1*) (length adt-arg2*))
                    (andmap same-adt-arg? adt-arg1* adt-arg2*))])]))
    (define (type-error src what declared-type type)
      (source-errorf src "mismatch between actual type ~a and expected type ~a for ~a"
        (format-type type)
        (format-type declared-type)
        what))
    (define (arithmetic-binop src op mbits expr1 expr2)
      (let* ([type1 (Care expr1)] [type2 (Care expr2)])
        (unless (T type1
                  [(tfield ,src1 (field-native)) (T type2 [(tfield ,src2 (field-native)) #t])]
                  [(tfield ,src1 (field-scalar (curve-secp256k1)))
                   (guard (string=? op "*"))
                   (T type2 [(tfield ,src2 (field-scalar (curve-secp256k1))) #t])]
                  [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
          (source-errorf src "incompatible combination of types ~a and ~a for ~s"
            (format-type type1) (format-type type2) op))
        (unless (eqv? (T type1 [(tunsigned ,src ,nat) (fxmax 1 (integer-length nat))]) mbits)
          (source-errorf src "mismatched mbits ~s and type ~a for ~s"
                         mbits
                         (format-type type1)
                         op))
        type1))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
     (guard (c [else (internal-errorf 'check-types/Linlined
                                      "downstream type-check failure:\n~a"
                                      (with-output-to-string (lambda () (display-condition c))))])
       (for-each Set-Program-Element-Type! pelt*)
       (for-each Program-Element pelt*)
       ir)])
  (Set-Program-Element-Type! : Program-Element (ir) -> * (void)
    (definitions
      (define (build-function kind name arg* type)
        (let ([var-name* (map arg->name arg*)] [type* (map arg->type arg*)])
          (set-idtype! name (Idtype-Function kind var-name* type* type)))))
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (build-function 'circuit function-name arg* type)]
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (build-function 'circuit function-name arg* type)]
    [(witness ,src ,function-name (,arg* ...) ,type)
     (build-function 'witness function-name arg* type)]
    [(public-ledger-declaration ,pl-array ,lconstructor) (void)]
    [(kernel-declaration ,public-binding) (void)]
    )
  (Program-Element : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     (let ([id* (map arg->name arg*)] [type* (map arg->type arg*)])
       (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* type*)
       (let ([actual-type (Care expr)])
         (unless (sametype? actual-type type)
           (source-errorf src "mismatch between actual return type ~a and declared return type ~a"
             (format-type actual-type)
             (format-type type)))
         (for-each unset-idtype! id*)))]
    [else (void)])
  (CareNot : Expression (ir) -> * (void)
    [(if ,src ,[Care : expr0 -> * type0] ,expr1 ,expr2)
     (unless (nanopass-case (Linlined Type) type0
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type0)))
     (CareNot expr1)
     (CareNot expr2)]
    [(seq ,src ,expr* ... ,expr)
     (maplr CareNot expr*)
     (CareNot expr)]
    [(let* ,src ([,local* ,expr*] ...) ,expr)
     (let ([var-name* (map arg->name local*)] [declared-type* (map arg->type local*)])
       (for-each (lambda (var-name declared-type expr)
                   (let* ([actual-type (Care expr)]
                          [type (nanopass-case (Linlined Type) declared-type
                                  [(tunknown) actual-type]
                                  [else
                                   (unless (sametype? actual-type declared-type)
                                     (source-errorf src "mismatch between actual type ~a and declared type ~a of ~s"
                                                    (format-type actual-type)
                                                    (format-type declared-type)
                                                    var-name))
                                   declared-type])])
                     (set-idtype! var-name (Idtype-Base type))
                     type))
                 var-name*
                 declared-type*
                 expr*)
       (CareNot expr)
       (for-each unset-idtype! var-name*))]
    [else
     (Care ir)
     (void)])
  (Care : Expression (ir) -> * (type)
    [(quote ,src ,datum)
     (datum-type src datum)]
    [(var-ref ,src ,var-name)
     (Idtype-case (get-idtype src var-name)
       [(Idtype-Base type) type]
       [(Idtype-Function kind arg-name* arg-type* return-type)
        (source-errorf src "invalid context for reference to ~s name ~s"
                       kind
                       var-name)])]
    [(default ,src ,type) type]
    [(if ,src ,[Care : expr0 -> * type0] ,expr1 ,expr2)
     (unless (nanopass-case (Linlined Type) type0
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type0)))
     (let ([type1 (Care expr1)] [type2 (Care expr2)])
       (cond
         [(sametype? type1 type2) type1]
         [else (source-errorf src "mismatch between type ~a and type ~a of condition branches"
                              (format-type type1)
                              (format-type type2))]))]
    [(elt-ref ,src ,[Care : expr -> * type] ,elt-name)
     (nanopass-case (Linlined Type) type
       [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
        (let loop ([elt-name* elt-name*] [type* type*])
          (if (null? elt-name*)
              (source-errorf src "structure ~s has no field named ~s"
                             struct-name
                             elt-name)
              (if (eq? (car elt-name*) elt-name)
                  (car type*)
                  (loop (cdr elt-name*) (cdr type*)))))]
       [else (source-errorf src "expected structure type, received ~a"
                            (format-type type))])]
    [(emit ,src ,event-version ,event-tag ,len ,[Care : expr -> * type] ,vm-code)
     (nanopass-case (Linlined Type) type
       [(tbytes ,src^ ,len)
        (with-output-language (Linlined Type) `(ttuple ,src))]
       [else (source-errorf src "expected Bytes type, received ~a" (format-type type))])]
    [(tuple-ref ,src ,[Care : expr -> * expr-type] ,kindex)
     (define (bounds-check len)
       (unless (< kindex len)
         (source-errorf src "index ~s is out-of-bounds for tuple or vector of length ~s"
                        kindex len)))
     (nanopass-case (Linlined Type) expr-type
       [(ttuple ,src ,type* ...)
        (bounds-check (length type*))
        (list-ref type* kindex)]
       [(tvector ,src ,len ,type)
        (bounds-check len)
        type]
       [else (source-errorf src "expected vector type, received ~a"
                            (format-type expr-type))])]
    [(bytes-ref ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type])
     (nanopass-case (Linlined Type) index-type
       [(tunsigned ,src ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (unless (sametype? expr-type type)
       (source-errorf src "expected bytes-ref argument to have type ~a, received ~a"
                      type expr-type))
     (with-output-language (Linlined Type) `(tunsigned ,src 255))]
    [(vector-ref ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type])
     (nanopass-case (Linlined Type) index-type
       [(tunsigned ,src ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (unless (sametype? expr-type type)
       (source-errorf src "expected vector-ref argument to have type ~a, received ~a"
                      type expr-type))
     (nanopass-case (Linlined Type) expr-type
       [(tvector ,src^ ,len^ ,type^)
        (guard (> len^ 0))
        type^]
       [(ttuple ,src^ ,type^ ,type^* ...)
        (guard (andmap (lambda (type^^) (sametype? type^^ type^)) type^*))
        type^]
       [else (source-errorf src "expected vector-ref expr to have a non-empty vector type, received ~a"
                            (format-type expr-type))])]
    [(tuple-slice ,src ,[type] ,[Care : expr -> * expr-type] ,kindex ,len)
     (define (bounds-check input-len)
       (unless (<= (+ kindex len) input-len)
         (source-errorf src "index ~d plus length ~d is out-of-bounds for a tuple or vector of length ~d"
                        kindex len input-len)))
     (unless (sametype? expr-type type)
       (source-errorf src "expected slice argument to have type ~a, received ~a"
                      type expr-type))
     (with-output-language (Linlined Type)
       (nanopass-case (Linlined Type) expr-type
         [(ttuple ,src^ ,type* ...)
          (bounds-check (length type*))
          `(ttuple ,src ,(list-head (list-tail type* kindex) len) ...)]
         [(tvector ,src^ ,len^ ,type)
          (bounds-check len^)
          `(tvector ,src ,len ,type)]
         [else (source-errorf src "expected tuple or vector type, received ~a"
                              (format-type expr-type))]))]
    [(bytes-slice ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type] ,len)
     (nanopass-case (Linlined Type) index-type
       [(tunsigned ,src ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (unless (sametype? expr-type type)
       (source-errorf src "expected slice argument to have type ~a, received ~a"
                      type expr-type))
     (let ([input-len (nanopass-case (Linlined Type) expr-type
                        [(tbytes ,src^ ,len^) len^]
                        [else (source-errorf src "expected slice expr to have a Bytes type, received ~a"
                                             (format-type expr-type))])])
       (unless (<= len input-len)
         (source-errorf src "slice length ~d exceeds the length ~d of the input Bytes" len input-len))
       (with-output-language (Linlined Type)
         `(tbytes ,src ,len)))]
    [(vector-slice ,src ,type ,[Care : expr -> * expr-type] ,[Care : index -> * index-type] ,len)
     (nanopass-case (Linlined Type) index-type
       [(tunsigned ,src ,nat) nat]
       [else (source-errorf src "expected index to have an unsigned type, received ~a"
                            (format-type index-type))])
     (unless (sametype? expr-type type)
       (source-errorf src "expected slice argument to have type ~a, received ~a"
                      type expr-type))
     (let-values ([(input-len elt-type) (nanopass-case (Linlined Type) expr-type
                                          [(tvector ,src^ ,len^ ,type^) (values len^ type^)]
                                          [(ttuple ,src^) (values 0 (with-output-language (Linlined Type) `(tunknown)))]
                                          [(ttuple ,src^ ,type^ ,type^* ...)
                                           (guard (andmap (lambda (type^^) (sametype? type^^ type^)) type^*))
                                           (values (fx+ (length type^*) 1) type^)]
                                          [else (source-errorf src "expected slice expr to have a vector type, received ~a"
                                                               (format-type expr-type))])])
       (unless (<= len input-len)
         (source-errorf src "length ~d exceeds the length ~d of the input vector" len input-len))
       (with-output-language (Linlined Type)
         `(tvector ,src ,len ,elt-type)))]
    [(+ ,src ,mbits ,expr1 ,expr2)
     (arithmetic-binop src "+" mbits expr1 expr2)]
    [(- ,src ,mbits ,expr1 ,expr2)
     (arithmetic-binop src "-" mbits expr1 expr2)]
    [(* ,src ,mbits ,expr1 ,expr2)
     (arithmetic-binop src "*" mbits expr1 expr2)]
    [(< ,src ,bits ,expr1 ,expr2)
     (let* ([type1 (Care expr1)] [type2 (Care expr2)])
       (or (T type1
              [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
             ; the error message says "relational operator" here rather than "<" to avoid misleading
             ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
             (source-errorf src "incompatible combination of types ~a and ~a for relational operator"
                            (format-type type1)
                            (format-type type2)))
       (unless (eqv? (T type1 [(tunsigned ,src ,nat) (fxmax 1 (integer-length nat))]) bits)
         ; the error message says "relational operator" here rather than "<" to avoid misleading
         ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
         (source-errorf src "mismatched bits ~s and type ~a for relational operator"
                        bits
                        (format-type type1))))
     (with-output-language (Linlined Type) `(tboolean ,src))]
    [(== ,src ,type ,expr1 ,expr2)
     (let* ([type1 (Care expr1)] [type2 (Care expr2)])
       (unless (sametype? type1 type2)
         ; the error message say "equality operator" here rather than "==" to avoid misleading
         ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
         (source-errorf src "non-equivalent types ~a and ~a for equality operator"
                        (format-type type1)
                        (format-type type2)))
       (unless (sametype? type type1)
         ; the error message say "equality operator" here rather than "==" to avoid misleading
         ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
         (source-errorf src "mismatch between recorded type ~a and equality operand type ~a"
                        (format-type type)
                        (format-type type1))))
     (with-output-language (Linlined Type) `(tboolean ,src))]
    [(call ,src ,function-name ,expr* ...)
     (let ([actual-type* (maplr Care expr*)])
       (define compatible?
         (let ([nactual (length actual-type*)])
           (lambda (arg-type*)
             (and (= (length arg-type*) nactual)
                  (andmap sametype? actual-type* arg-type*)))))
       (Idtype-case (get-idtype src function-name)
         [(Idtype-Function kind arg-name* arg-type* return-type)
          (unless (compatible? arg-type*)
            (source-errorf src
                           "incompatible arguments in call to ~a;\n    \
                           supplied argument types:\n      \
                           ~a: (~{~a~^, ~});\n    \
                           declared argument types:\n      \
                           ~a: (~{~a~^, ~})"
              (symbol->string (id-sym function-name))
              (map format-type actual-type*)
                    (format-source-object (id-src function-name))
                    (map format-type arg-type*)))
          return-type]
         [else (source-errorf src "invalid context for reference to ~s (defined at ~a)"
                              function-name
                              (format-source-object (id-src function-name)))]))]
    [(new ,src ,type ,expr* ...)
     (let ([actual-type* (maplr Care expr*)])
       (nanopass-case (Linlined Type) type
         [(tstruct ,src1 ,struct-name (,elt-name* ,type*) ...)
          (let ([nactual (length actual-type*)] [ndeclared (length type*)])
            (unless (fx= nactual ndeclared)
              (source-errorf src "mismatch between actual number ~s and declared number ~s of field values for ~s"
                             nactual
                             ndeclared
                             struct-name)))
          (for-each
            (lambda (declared-type actual-type elt-name)
              (unless (sametype? actual-type declared-type)
                (source-errorf src "mismatch between actual type ~a and declared type ~a for field ~s of ~s"
                  (format-type actual-type)
                  (format-type declared-type)
                  elt-name
                  struct-name)))
            type*
            actual-type*
            elt-name*)]
         [else (source-errorf src "expected structure type, received ~a"
                              (format-type type))])
       type)]
    [(seq ,src ,expr* ... ,expr)
     (for-each CareNot expr*)
     (Care expr)]
    [(let* ,src ([,local* ,expr*] ...) ,expr)
     (let ([var-name* (map arg->name local*)] [declared-type* (map arg->type local*)])
       (for-each (lambda (var-name declared-type expr)
                   (let* ([actual-type (Care expr)]
                          [type (nanopass-case (Linlined Type) declared-type
                                  [(tunknown) actual-type]
                                  [else
                                   (unless (sametype? actual-type declared-type)
                                     (source-errorf src "mismatch between actual type ~a and declared type ~a of ~s"
                                                    (format-type actual-type)
                                                    (format-type declared-type)
                                                    var-name))
                                   declared-type])])
                     (set-idtype! var-name (Idtype-Base type))
                     type))
                 var-name*
                 declared-type*
                 expr*)
       (let ([type (Care expr)])
         (for-each unset-idtype! var-name*)
         type))]
    [(assert ,src ,[Care : expr -> * type] ,mesg)
     (unless (nanopass-case (Linlined Type) type
               [(tboolean ,src1) #t]
               [else #f])
       (source-errorf src "expected test to have type Boolean, received ~a"
                      (format-type type)))
     (with-output-language (Linlined Type) `(ttuple ,src))]
    [(tuple ,src ,tuple-arg* ...)
     (with-output-language (Linlined Type)
       `(ttuple ,src
          ,(fold-right
             (lambda (tuple-arg type*)
               (nanopass-case (Linlined Tuple-Argument) tuple-arg
                 [(single ,src ,expr) (cons (Care expr) type*)]
                 [(spread ,src ,nat ,expr)
                  (let ([type (Care expr)])
                    (nanopass-case (Linlined Type) type
                      [(ttuple ,src ,type^* ...) (append type^* type*)]
                      [else (source-errorf src "expected type of tuple spread to be a ttuple type but received ~a"
                                           (format-type type))]))]))
             '()
             tuple-arg*)
          ...))]
    [(vector ,src ,tuple-arg* ...)
     (with-output-language (Linlined Type)
       (let-values ([(nat* type**) (maplr2 (lambda (tuple-arg)
                                             (nanopass-case (Linlined Tuple-Argument) tuple-arg
                                               [(single ,src ,expr) (values 1 (list (Care expr)))]
                                               [(spread ,src ,nat ,expr)
                                                (let ([type (Care expr)])
                                                  (nanopass-case (Linlined Type) type
                                                    [(ttuple ,src ,type* ...) (values (length type*) type*)]
                                                    [(tvector ,src ,len ,type) (values len (list type))]
                                                    [else (source-errorf src "expected type of vector spread to be a ttuple or ttvector type but received ~a"
                                                                         (format-type type))]))]))
                                         tuple-arg*)])
         (let ([type* (apply append type**)])
           (let ([type (if (null? type*)
                           `(tunknown)
                           (let ([type (car type*)])
                             (for-each (lambda (type^)
                                         (unless (sametype? type^ type)
                                           (source-errorf src "different vector element types ~a and ~a"
                                                          (format-type type)
                                                          (format-type type^))))
                                       (cdr type*))
                             type))])
             `(tvector ,src ,(apply + nat*) ,type)))))]
    [(bytes->field ,src ,ftype ,len ,[Care : expr -> * type])
     (nanopass-case (Linlined Type) type
       [(tbytes ,src ,len^)
        (unless (= len^ len)
          (source-errorf src "mismatch between Bytes lengths ~s and ~s for bytes->field"
                         len
                         len^))]
       [else (source-errorf src "expected Bytes<~d>, got ~a for bytes->field"
                            len
                            (format-type type))])
     (with-output-language (Linlined Type)
       (nanopass-case (Linlined Field-Type) ftype
         [(field-native) `(tfield ,src ,ftype)]
         [(field-base (curve-secp256k1))
          (unless (eqv? len 32)
            (source-errorf src "expected Bytes<32>, got ~a for bytes->field"
              (format-type type)))
          `(tfield ,src ,ftype)]
         [(field-scalar (curve-secp256k1))
          (unless (eqv? len 32)
            (source-errorf src "expected Bytes<32>, got ~a for bytes->field"
              (format-type type)))
          `(tfield ,src ,ftype)]
         [else (source-errorf src "invalid target field type ~a for bytes->field"
                 (format-type `(tfield ,src ,ftype)))]))]
    [(field->bytes ,src ,len ,ftype ,[Care : expr -> * type])
     (unless (nanopass-case (Linlined Type) type
               [(tfield ,src^ ,ftype^)
                (and (same-field-type? ftype ftype^)
                     (nanopass-case (Linlined Field-Type) ftype
                       [(field-native) #t]
                       [(field-base (curve-secp256k1)) (eqv? len 32)]
                       [(field-scalar (curve-secp256k1)) (eqv? len 32)]
                       [else #f]))]
               [else #f])
       (source-errorf src "actual type ~a is an invalid argument to field->bytes for field ~a"
         (format-type type)
         (format-field-type ftype)))
     (when (= len 0) (source-errorf src "invalid cast from field to Bytes<0>"))
     (with-output-language (Linlined Type) `(tbytes ,src ,len))]
    [(bytes->vector ,src ,len ,[Care : expr -> * type])
     (nanopass-case (Linlined Type) type
       [(tbytes ,src ,len^)
        (unless (= len^ len)
          (source-errorf src "mismatch between Bytes lengths ~s and ~s for bytes->vector"
                         len
                         len^))])
     (with-output-language (Linlined Type) `(tvector ,src ,len (tunsigned ,src 255)))]
    [(vector->bytes ,src ,len ,[Care : expr -> * type])
     (define (u8-subtype? type)
       (nanopass-case (Linlined Type) type
         [(tunsigned ,src ,nat) (<= nat 255)]
         [else #f]))
     (define (unknown? type)
       (nanopass-case (Linlined Type) type
         [(tunknown) #t]
         [else #f]))
     (unless (nanopass-case (Linlined Type) type
               [(ttuple ,src1 ,type* ...) (and (= (length type*) len) (andmap u8-subtype? type*))]
               [(tvector ,src1 ,len1 ,type) (and (= len1 len) (or (u8-subtype? type) (unknown? type)))]
               [else #f])
       (source-errorf src "expected Vector<~d, Uint<8>> for vector->bytes call, received ~a"
                      len
                      (format-type type)))
     (with-output-language (Linlined Type) `(tbytes ,src ,len))]
    [(cast-to-field ,src ,ftype ,type ,[Care : expr -> * type^])
     (unless (sametype? type type^)
       (source-errorf src "expected ~a, got ~a for cast-to-field"
         (format-type type) (format-type type^)))
     (unless (nanopass-case (Linlined Type) type
               [(tfield ,src^ ,ftype^) #t]
               [(tunsigned ,src^ ,nat) #t]
               [else #f])
       ;; This is unexpected.
       (source-errorf src "expected a numeric type, got ~a for cast-to-field" (format-type type)))
     (with-output-language (Linlined Type) `(tfield ,src ,ftype))]
    [(cast-from-field ,src ,nat ,ftype ,[Care : expr -> * type])
     (with-output-language (Linlined Type)
       (unless (nanopass-case (Linlined Type) type
                 [(tfield ,src ,ftype^) (same-field-type? ftype ftype^)]
                 [else #f])
         (source-errorf src "expected ~a for cast-from-field call, received ~a"
           (format-type `(tfield ,src ,ftype))
           (format-type type)))
       `(tunsigned ,src ,nat))]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,[Care : expr -> * type])
     (assert (< nat1 nat2))
     (unless (nanopass-case (Linlined Type) type
               [(tunsigned ,src ,nat) #t]
               [else #f])
       (source-errorf src "expected an unsigned integer type, got ~a for downcast-unsigned"
         (format-type type)))
     (with-output-language (Linlined Type) `(tunsigned ,src ,nat1))]
    [(safe-cast ,src ,type ,type^ ,[Care : expr -> * type^^])
     (unless (sametype? type^^ type^)
       (source-errorf src "expected ~a, got ~a for upcast"
                      (format-type type^)
                      (format-type type^^)))
     type]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[Care : expr* -> * type^*] ...)
     (nanopass-case (Linlined ADT-Op) adt-op
       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
        (for-each
          (lambda (type type^ i)
            (unless (sametype? type^ type)
              (source-errorf src "expected ~:r argument of ~s to have type ~a but received ~a"
                             (fx1+ i)
                             ledger-op
                             (format-type type)
                             (format-type type^))))
          type* type^* (enumerate type*))
        type])]
    [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
     (nanopass-case (Linlined Type) type
       [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
        (let ([actual-type* (map Care expr*)])
          (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
            (if (null? elt-name*)
              (source-errorf src^ "contract ~s has no circuit declaration named ~s"
                             contract-name
                             elt-name)
              (if (eq? (car elt-name*) elt-name)
                (let ([declared-type* (car type**)])
                  (let ([ndeclared (length declared-type*)] [nactual (length actual-type*)])
                    (unless (fx= nactual ndeclared)
                      (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                     contract-name elt-name ndeclared nactual)))
                  (for-each
                    (lambda (declared-type actual-type i)
                      (unless (sametype? actual-type declared-type)
                        (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                       (fx1+ i)
                                       contract-name
                                       elt-name
                                       (format-type declared-type)
                                       (format-type actual-type))))
                    declared-type* actual-type* (enumerate declared-type*))
                  (car type*))
                (loop (cdr elt-name*) (cdr type**) (cdr type*))))))]
       [else (assert cannot-happen)])]
    [else (internal-errorf 'Care "unhandled form Expr-type ~s\n" ir)])
  )
