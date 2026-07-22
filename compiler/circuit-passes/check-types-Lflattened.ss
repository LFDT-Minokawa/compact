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

(define-pass check-types/Lflattened : Lflattened (ir) -> Lflattened ()
  (definitions
    (define program-src)
    (define-syntax T
      (syntax-rules ()
        [(T ty clause ...)
         (nanopass-case (Lflattened Primitive-Type) ty clause ... [else #f])]))
    (define-datatype Idtype
      ; ordinary expression types
      (Idtype-Base type)
      ; circuits, witnesses, and statements
      (Idtype-Function kind arg-name* arg-type* return-type*)
      )
    (module (id-ht set-idtype! get-idtype)
      (define id-ht (make-eq-hashtable))
      (define (set-idtype! id idtype)
        (hashtable-set! id-ht id idtype))
      (define (get-idtype id)
        (or (hashtable-ref id-ht id #f)
            (internal-errorf 'get-idtype "encountered undefined identifier ~s" id)))
      )
    (define (type->primitive-types type)
      (nanopass-case (Lflattened Type) type
        [(ty (,alignment* ...) (,primitive-type* ...)) primitive-type*]))
    (define (arg->names arg)
      (nanopass-case (Lflattened Argument) arg
        [(argument (,var-name* ...) ,type) var-name*]))
    (define (arg->types arg)
      (nanopass-case (Lflattened Argument) arg
        [(argument (,var-name* ...) ,type) (type->primitive-types type)]))
    (define (format-field-type ftype)
      (nanopass-case (Lflattened Field-Type) ftype
        [(field-native) "Field"]
        [(field-scalar (curve-jubjub)) "JubjubScalar"]
        [(field-base (curve-secp256k1)) "Secp256k1Base"]
        [(field-scalar (curve-secp256k1)) "Secp256k1Scalar"]))
    (define (format-primitive-type primitive-type)
      (define (format-type type)
        (format "(~{~a~^, ~})" (map format-primitive-type (type->primitive-types type))))
      (define (format-adt-arg adt-arg)
        (nanopass-case (Lflattened Public-Ledger-ADT-Arg) adt-arg
          [,nat (format "~d" nat)]
          [,type (format-type type)]))
      (nanopass-case (Lflattened Primitive-Type) primitive-type
        [(tfield ,ftype) (format-field-type ftype)]
        [(tunsigned ,nat) (format "Uint<0..~d>" (1+ nat))]
        [(topaque ,opaque-type) (format "Opaque<~s>" opaque-type)]
        [(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
         (format "contract ~a<~{~a~^, ~}>" contract-name
           (map (lambda (elt-name pure-dcl type* type)
                  (if pure-dcl
                      (format "pure ~a(~{~a~^, ~}): ~a" elt-name
                              (map format-type type*) (format-type type))
                      (format "~a(~{~a~^, ~}): ~a" elt-name
                              (map format-type type*) (format-type type))))
                elt-name* pure-dcl* type** type*))]
        [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
         (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))]
        [else (internal-errorf 'format-primitive-type "unexpected primitive type ~s" primitive-type)]))
    (define (subtype? type1 type2)
      (let ([primitive-type1* (type->primitive-types type1)]
            [primitive-type2* (type->primitive-types type2)])
        (and (fx= (length primitive-type1*) (length primitive-type2*))
             (andmap sub-primitive-type? primitive-type1* primitive-type2*))))
    (define (sub-primitive-type? primitive-type1 primitive-type2)
      (T primitive-type1
         [(tfield (field-native))
          (T primitive-type2
            [(tfield (field-native)) #t]
            [(tunsigned ,nat) (<= (max-field) nat)])]
         [(tfield (field-scalar (curve-jubjub)))
          (T primitive-type2
            [(tfield (field-native)) #t]
            [(tfield (field-scalar (curve-jubjub))) #t]
            [(tunsigned ,nat) (<= (max-jubjub-scalar) nat)])]
         [(tfield (field-base (curve-secp256k1)))
          (T primitive-type2 [(tfield (field-base (curve-secp256k1))) #t])]
         [(tfield (field-scalar (curve-secp256k1)))
          (T primitive-type2 [(tfield (field-scalar (curve-secp256k1))) #t])]
         [(tunsigned ,nat1)
          (T primitive-type2
            [(tfield (field-native)) (<= nat1 (max-field))]
            [(tfield (field-scalar (curve-jubjub))) (<= nat1 (max-jubjub-scalar))]
            [(tunsigned ,nat2) (<= nat1 nat2)]
            [(topaque ,opaque-type)
             ;; tfield value 0 of type (tfield 0) is produced by default<Opaque<"type">>
             (eqv? nat1 0)]
            ;; default<public-adt> is the only value of type public-adt and is represented by 0
            [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
             (eqv? nat1 0)])]
         [(topaque ,opaque-type1)
          (T primitive-type2
             [(topaque ,opaque-type2)
              (string=? opaque-type1 opaque-type2)])]
         [(tcontract ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
          (T primitive-type2
             [(tcontract ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
              (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
                (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                          (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                                   (and (eq? elt-name1 elt-name2)
                                        (eq? pure-dcl1 pure-dcl2)
                                        (fx= (length type1*) (length type2*))
                                        (andmap subtype? type1* type2*)
                                        (subtype? type1 type2)))
                                 elt-name1* pure-dcl1* type1** type1*))
                        elt-name2* pure-dcl2* type2** type2*))
              (and (eq? contract-name1 contract-name2)
                   (fx= (length elt-name1*) (length elt-name2*))
                   (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
         ; this should never presently happen, since no Triv has type public-adt
         [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr1 (,adt-op1* ...))
          (T primitive-type2
             [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr2 (,adt-op2* ...))
              #f])]))
    (define (type-error what declared-type type)
      (source-errorf program-src "mismatch between actual type ~a and expected type ~a for ~a"
        (format-primitive-type type)
        (format-primitive-type declared-type)
        what))
    (define (arithmetic-binop op mbits triv1 triv2)
      (let* ([primitive-type1 (Triv triv1)] [primitive-type2 (Triv triv2)])
        (unless (T primitive-type1
                  [(tfield (field-native))
                   (T primitive-type2
                     [(tfield (field-native)) (not mbits)]
                     [(tunsigned ,nat2) (not mbits)])]
                  [(tfield (field-scalar (curve-secp256k1)))
                   (guard (string=? op "*"))
                   (T primitive-type2
                     [(tfield (field-scalar (curve-secp256k1))) (not mbits)])]
                  [(tunsigned ,nat1)
                   (T primitive-type2
                     [(tfield (field-native)) (not mbits)]
                     [(tunsigned ,nat2)
                      (or (not mbits)
                          (let ([nat (if (string=? op "-") nat1 (max nat1 nat2))])
                            (<= (fxmax 1 (integer-length nat)) mbits)))])])
          (source-errorf program-src "mismatched mbits ~s and types ~a and ~a for ~s"
            mbits
            (format-primitive-type primitive-type1)
            (format-primitive-type primitive-type2)
            op))
        primitive-type1))
    (define (verify-test src test)
      (let ([type (Triv test)])
        (unless (nanopass-case (Lflattened Primitive-Type) type
                  [(tunsigned ,nat) (<= nat 1)]
                  [else #f])
          (source-errorf src
                         "expected test to have type Boolean, received ~a"
                         (format-primitive-type type)))))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
     (fluid-let ([program-src src])
       (guard (c [else (internal-errorf 'check-types/Lflattened
                                        "downstream type-check failure:\n~a"
                                        (with-output-to-string (lambda () (display-condition c))))])
         (for-each Set-Program-Element-Type! pelt*)
         (for-each Program-Element pelt*)
         ir))])
  (Set-Program-Element-Type! : Program-Element (ir) -> * (void)
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     (let ([var-name* (apply append (map arg->names arg*))]
           [arg-type* (apply append (map arg->types arg*))]
           [type* (type->primitive-types type)])
       (set-idtype! function-name (Idtype-Function 'circuit var-name* arg-type* type*)))]
    [(witness ,src ,function-name (,arg* ...) ,type)
     (let ([var-name* (apply append (map arg->names arg*))]
           [arg-type* (apply append (map arg->types arg*))]
           [type* (type->primitive-types type)])
       (set-idtype! function-name (Idtype-Function 'witness var-name* arg-type* type*)))]
    [else (void)])
  (Program-Element : Program-Element (ir) -> * (void)
    [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
     (fluid-let ([id-ht (hashtable-copy id-ht #t)])
       (let ([id* (apply append (map arg->names arg*))]
             [arg-type* (apply append (map arg->types arg*))]
             [type* (type->primitive-types type)])
         (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* arg-type*)
         (for-each Statement stmt*)
         (let ([actual-type* (map Triv triv*)])
           (unless (and (fx= (length actual-type*) (length type*))
                        (andmap sub-primitive-type? actual-type* type*))
             (source-errorf src "mismatch between actual return types ~a and declared return types ~a in ~a"
               (map format-primitive-type actual-type*)
               (map format-primitive-type type*)
               (symbol->string (id-sym function-name)))))))]
    [else (void)])
  (Statement : Statement (ir) -> * (void)
    [(= ,test ,var-name ,[Single : single -> * type])
     (verify-test program-src test)
     (set-idtype! var-name (Idtype-Base type))]
    [(= ,test (,var-name* ...) (call ,src ,function-name ,[* type*] ...))
     (verify-test src test)
     (let ([actual-type* type*])
       (define compatible?
         (let ([nactual (length actual-type*)])
           (lambda (arg-type*)
             (and (= (length arg-type*) nactual)
                  (andmap sub-primitive-type? actual-type* arg-type*)))))
       (Idtype-case (get-idtype function-name)
         [(Idtype-Function kind arg-name* arg-type* return-type*)
          (unless (compatible? arg-type*)
            (source-errorf src
                           "incompatible arguments in call to ~a;\n    \
                           supplied argument types:\n      \
                           (~{~a~^, ~});\n    \
                           declared argument types:\n      \
                           ~a: (~{~a~^, ~})"
              (symbol->string (id-sym function-name))
              (map format-primitive-type actual-type*)
              (format-source-object (id-src function-name))
              (map format-primitive-type arg-type*)))
          (for-each
            (lambda (var-name type)
              (set-idtype! var-name (Idtype-Base type)))
            var-name*
            return-type*)]
         [else (source-errorf src "invalid context for reference to ~s (defined at ~a)"
                              function-name
                              (format-source-object (id-src function-name)))]))]
    [(= ,test (,var-name* ...) (contract-call ,src ,elt-name ((,[* recv-type*] ...) ,primitive-type) ,[* type*] ...))
     (verify-test src test)
     (let ([actual-type* type*])
       (nanopass-case (Lflattened Primitive-Type) primitive-type
         [(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
            (if (null? elt-name*)
                (source-errorf src "contract ~s has no circuit declaration named ~s"
                               contract-name
                               elt-name)
                (if (eq? (car elt-name*) elt-name)
                    (let ([declared-type* (apply append (map type->primitive-types (car type**)))]
                          [return-type* (type->primitive-types (car type*))])
                      (let ([ndeclared (length declared-type*)] [nactual (length actual-type*)])
                        (unless (fx= nactual ndeclared)
                          (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                         contract-name elt-name ndeclared nactual)))
                      (for-each
                        (lambda (declared-type actual-type i)
                          (unless (sub-primitive-type? actual-type declared-type)
                            (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                           (fx1+ i)
                                           contract-name
                                           elt-name
                                           (format-primitive-type declared-type)
                                           (format-primitive-type actual-type))))
                        declared-type* actual-type* (enumerate declared-type*))
                      (for-each
                        (lambda (var-name type)
                          (set-idtype! var-name (Idtype-Base type)))
                        var-name*
                        return-type*))
                    (loop (cdr elt-name*) (cdr type**) (cdr type*)))))]
         [else (source-errorf src "expected primitive type tcontract for contract call, received ~a"
                              (format-primitive-type primitive-type))]))]
    [(= ,test (,var-name* ...) (default ,opaque-type))
     (verify-test program-src test)
     (with-output-language (Lflattened Primitive-Type)
       (case opaque-type
         [("JubjubPoint")
          (if (feature-zkir-v3)
              (begin
                (assert (= (length var-name*) 1))
                (set-idtype! (car var-name*) (Idtype-Base `(topaque "JubjubPoint"))))
              (begin
                (assert (= (length var-name*) 2))
                (set-idtype! (car var-name*) (Idtype-Base `(tfield (field-native))))
                (set-idtype! (cadr var-name*) (Idtype-Base `(tfield (field-native))))))]
         [("Secp256k1Point")
          (assert (feature-zkir-v3))
          (assert (= (length var-name*) 1))
          (set-idtype! (car var-name*) (Idtype-Base `(topaque "Secp256k1Point")))]
         [else (assert cannot-happen)]))]
    [(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,[* primitive-type]))
     (verify-test src test)
     (unless (nanopass-case (Lflattened Field-Type) ftype
               [(field-native)
                [T primitive-type [(tfield (field-native)) #t] [(tunsigned ,nat) #t]]]
               [(field-base (curve-secp256k1))
                (T primitive-type [(tfield (field-base (curve-secp256k1))) #t])]
               [(field-scalar (curve-secp256k1))
                (T primitive-type [(tfield (field-scalar (curve-secp256k1))) #t])])
       (type-error (format "argument to field->bytes at ~a" (format-source-object src))
         (with-output-language (Lflattened Primitive-Type) `(tfield ,ftype))
         primitive-type))
     (assert (not (= len 0)))
     (with-output-language (Lflattened Primitive-Type)
       (set-idtype! var-name1 (Idtype-Base `(tunsigned ,(max 0 (- (expt 2 (* (fxmin (fxmax 0 (fx- len (field-bytes))) (field-bytes)) 8)) 1)))))
       (set-idtype! var-name2 (Idtype-Base `(tunsigned ,(max 0 (- (expt 2 (* (fxmin len (field-bytes)) 8)) 1))))))]
    [(= ,test (,var-name1 ,var-name2) (div-mod-power-of-two ,[* primitive-type] ,bits))
     (verify-test program-src test)
     (unless (T primitive-type
               [(tfield (field-native)) #t]
               [(tunsigned ,nat) #t])
       (source-errorf program-src "expected Field or Uint for div-mod-power-of-two, received ~a"
         (format-primitive-type primitive-type)))
     (with-output-language (Lflattened Primitive-Type)
       (set-idtype! var-name1 (Idtype-Base `(tfield (field-native))))
       (set-idtype! var-name2 (Idtype-Base `(tunsigned ,bits))))]
    [(= ,test (,var-name* ...) (bytes->vector ,[* primitive-type]))
     (verify-test program-src test)
     (unless (T primitive-type
               [(tfield (field-native)) #t]
               [(tunsigned ,nat) #t])
       (source-errorf program-src "expected Field or Uint for bytes->vector, received ~a"
         (format-primitive-type primitive-type)))
     (with-output-language (Lflattened Primitive-Type)
       (for-each
         (lambda (var-name) (set-idtype! var-name (Idtype-Base `(tunsigned 8))))
         var-name*))]
    [(= ,test (,var-name* ...) (public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,adt-op ,[* type^*] ...))
     (verify-test src test)
     (nanopass-case (Lflattened ADT-Op) adt-op
       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
        (let ([arg-type* (apply append (map type->primitive-types type*))]
              [actual-type* type^*]
              [type* (type->primitive-types type)])
          (define compatible?
            (let ([nactual (length actual-type*)])
              (lambda (arg-type*)
                (and (= (length arg-type*) nactual)
                     (andmap sub-primitive-type? actual-type* arg-type*)))))
          (unless (compatible? arg-type*)
            (source-errorf src
                           "incompatible arguments for ledger.~a.~a;\n    \
                           supplied argument types:\n      \
                           (~{~a~^, ~});\n    \
                           declared argument types:\n      \
                           (~{~a~^, ~})"
                       (id-sym ledger-field-name)
                       ledger-op
                       (map format-primitive-type actual-type*)
                       (map format-primitive-type arg-type*)))
          (for-each
            (lambda (var-name type)
              (set-idtype! var-name (Idtype-Base type)))
            var-name*
            type*))])]
    [(= ,test (,var-name* ...) (emit ,src ,event-version ,event-tag ,len ,triv* ... ,vm-code))
     (verify-test src test)]
    [(assert ,src ,test ,mesg)
     (verify-test src test)]
    [else (internal-errorf 'Statement "unhandled form ~s" ir)])
  (Single : Single (ir) -> * (type)
    [,triv (Triv triv)]
    [(+ ,mbits ,triv1 ,triv2)
     (arithmetic-binop "+" mbits triv1 triv2)]
    [(- ,mbits ,triv1 ,triv2)
     (arithmetic-binop "-" mbits triv1 triv2)]
    [(* ,mbits ,triv1 ,triv2)
     (arithmetic-binop "*" mbits triv1 triv2)]
    [(< ,bits ,triv1 ,triv2)
     (let* ([primitive-type1 (Triv triv1)] [primitive-type2 (Triv triv2)])
       (let ([maybe-nat1 (T primitive-type1 [(tunsigned ,nat) nat])]
             [maybe-nat2 (T primitive-type2 [(tunsigned ,nat) nat])])
         (unless (and (number? maybe-nat1)
                      (number? maybe-nat2)
                      (<= (fxmax 1 (integer-length (max maybe-nat1 maybe-nat2))) bits))
           (source-errorf program-src "incompatible types ~a and ~a for relational operator"
              (format-primitive-type primitive-type1)
              (format-primitive-type primitive-type2)))
         (with-output-language (Lflattened Primitive-Type) `(tunsigned 1))))]
    [(== ,[* type1] ,[* type2])
     (unless (or (sub-primitive-type? type1 type2)
                 (sub-primitive-type? type2 type1))
      ; the error message say "equality operator" here rather than "==" to avoid misleading
      ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
      (source-errorf program-src "incompatible types ~a and ~a for equality operator"
               (format-primitive-type type1)
               (format-primitive-type type2)))
     (with-output-language (Lflattened Primitive-Type) `(tunsigned 1))]
    [(select ,[* type0] ,[* type1] ,[* type2])
     (unless (nanopass-case (Lflattened Primitive-Type) type0 [(tunsigned ,nat) (<= nat 1)] [else #f])
       (source-errorf program-src "expected select test to have type Boolean, received ~a"
               (format-primitive-type type0)))
     (cond
       [(sub-primitive-type? type1 type2) type2]
       [(sub-primitive-type? type2 type1) type1]
       [else (source-errorf program-src "mismatch between type ~a and type ~a of condition branches"
                     (format-primitive-type type1)
                     (format-primitive-type type2))])
     type1]
    [(bytes-ref ,[* primitive-type] ,nat)
     (unless (< nat (field-bytes))
       (source-errorf program-src "expected bytes-ref nat to be less than (field-bytes) but received ~d"
               nat))
     (unless (T primitive-type
               [(tfield (field-native)) #t]
               [(tunsigned ,nat) #t])
       (source-errorf program-src "expected Field or Uint for bytes-ref, recieved ~a"
         (format-primitive-type primitive-type)))
     (with-output-language (Lflattened Primitive-Type) `(tunsigned 255))]
    [(bytes->field ,src ,ftype ,len ,[* type1] ,[* type2])
     (nanopass-case (Lflattened Primitive-Type) type1
       [(tunsigned ,nat) #t]
       [else (source-errorf src "unexpected ~a of first argument to bytes->field"
                            (format-primitive-type type1))])
     (nanopass-case (Lflattened Primitive-Type) type2
       [(tunsigned ,nat) #t]
       [else (source-errorf src "unexpected ~a of second argument to bytes->field"
                            (format-primitive-type type2))])
     (with-output-language (Lflattened Primitive-Type) `(tfield ,ftype))]
    [(vector->bytes ,triv ,triv* ...)
     (let ([primitive-type* (map Triv (cons triv triv*))])
       (for-each (lambda (primitive-type)
                   (unless (T primitive-type [(tunsigned ,nat) (<= nat 255)])
                     (source-errorf program-src
                       "incompatible types (~{~a~^, ~}) for vector->bytes"
                       (map format-primitive-type primitive-type*))))
         primitive-type*))
     (with-output-language (Lflattened Primitive-Type)
       `(tunsigned ,(- (expt 256 (fx+ (length triv*) 1)) 1)))]
    [(cast-to-field ,ftype ,primitive-type ,[* type])
     ;; TODO(kmillikin): Type checking code needed here.
     (with-output-language (Lflattened Primitive-Type) `(tfield ,ftype))]
    [(cast-from-field ,src ,safe ,nat ,ftype ,[* type])
     ;; TODO(kmillikin): Type checking code needed here.
     (with-output-language (Lflattened Primitive-Type) `(tunsigned ,nat))]
    [(downcast-unsigned ,src ,safe ,nat2 ,nat1 ,[* primitive-type])
     (assert (< nat1 nat2))
     (unless (T primitive-type [(tunsigned ,nat) #t])
       (source-errorf src "expected Uint for downcast-unsigned, received ~a"
         (format-primitive-type primitive-type)))
     (with-output-language (Lflattened Primitive-Type) `(tunsigned ,nat1))]
    [else (internal-errorf 'Single "unhandled form ~s\n" ir)])
  (Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,type ,triv* ...)
     (for-each Triv triv*)
     `(,src ,type ,triv* ...)])
  (Triv : Triv (ir) -> * (type)
    [,var-name
     (Idtype-case (get-idtype var-name)
       [(Idtype-Base type) type]
       [(Idtype-Function kind arg-name* arg-type* return-type*)
        (source-errorf program-src "invalid context for reference to ~s name ~s"
                     kind
                     var-name)])]
    [,nat (with-output-language (Lflattened Primitive-Type) `(tunsigned ,nat))])
  )
