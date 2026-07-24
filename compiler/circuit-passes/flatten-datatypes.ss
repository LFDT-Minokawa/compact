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

(define-pass flatten-datatypes : Lcircuit (ir) -> Lflattened ()
  (definitions
    (define fun-ht (make-eq-hashtable))
    (define var-ht (make-eq-hashtable))
    (define (make-new-id id)
      (make-temp-id (id-src id) (id-sym id)))
    (define (make-new-ids id n)
      (do ([n n (fx- n 1)] [id* '() (cons (make-new-id id) id*)])
          ((fx= n 0) id*)))
    (define-datatype Wump
      (Wump-single elt)
      (Wump-vector wump*)
      (Wump-bytes elt*)
      (Wump-struct elt-name* wump*)
      )
    (define wump->elts
      (case-lambda
        [(wump) (wump->elts wump '())]
        [(wump elt*)
         (Wump-case wump
           [(Wump-single elt) (cons elt elt*)]
           [(Wump-vector wump*) (fold-right wump->elts elt* wump*)]
           [(Wump-bytes elt^*) (append elt^* elt*)]
           [(Wump-struct elt-name* wump*) (fold-right wump->elts elt* wump*)])]))
    (define (wump-fold-right p accum wump)
      (let do-wump ([wump wump] [accum accum])
        (define (do-wumps wump* accum)
          (if (null? wump*)
              (values '() accum)
              (let*-values ([(new-wump* accum) (do-wumps (cdr wump*) accum)]
                            [(wump accum) (do-wump (car wump*) accum)])
                (values (cons wump new-wump*) accum))))
        (Wump-case wump
          [(Wump-single elt)
           (let-values ([(elt accum) (p elt accum)])
             (values (Wump-single elt) accum))]
          [(Wump-vector wump*)
           (let-values ([(wump* accum) (do-wumps wump* accum)])
             (values
               (Wump-vector wump*)
               accum))]
          [(Wump-bytes elt*)
           (let-values ([(elt* accum)
                         (let do-elts ([elt* elt*] [accum accum])
                           (if (null? elt*)
                               (values '() accum)
                               (let*-values ([(new-elt* accum) (do-elts (cdr elt*) accum)]
                                             [(elt accum) (p (car elt*) accum)])
                                 (values (cons elt new-elt*) accum))))])
             (values (Wump-bytes elt*) accum))]
          [(Wump-struct elt-name* wump*)
           (let-values ([(wump* accum) (do-wumps wump* accum)])
             (values
               (Wump-struct elt-name* wump*)
               accum))])))
    (define (Single-Triv triv)
      (let ([triv* (wump->elts (Triv triv))])
        (unless (fx= (length triv*) 1)
          (internal-errorf 'Single-Triv "expected ~s to produce one triv, got ~s"
                           (unparse-Lcircuit triv)
                           (map unparse-Lflattened triv*)))
        (car triv*)))
    (define (build-type original-type pt*)
      (define (type->alignments type)
        (let f ([type type] [a* '()])
          (with-output-language (Lflattened Alignment)
            (nanopass-case (Lcircuit Type) type
              [(tboolean ,src) (cons `(abytes 1) a*)]
              [(tfield ,src ,ftype)
               (nanopass-case (Lcircuit Field-Type) ftype
                 [(field-native)
                  (cons `(afield) a*)]
                 [(field-scalar (curve-jubjub))
                  (if (feature-zkir-v3)
                      (cons `(anative "JubjubScalar") a*)
                      (cons `(afield) a*))]
                 [(field-base (curve-secp256k1))
                  (cons `(anative "Secp256k1Base") a*)]
                 [(field-scalar (curve-secp256k1))
                  (cons `(anative "Secp256k1Scalar") a*)])]
              [(tunsigned ,src ,nat)
               (let ([len (max 1 (ceiling (/ (bitwise-length nat) 8)))])
                 (cons `(abytes ,len) a*))]
              [(tbytes ,src ,len) (cons `(abytes ,len) a*)]
              [(topaque ,src ,opaque-type)
               (case opaque-type
                 [("JubjubPoint")
                  (if (feature-zkir-v3)
                      (cons `(anative ,opaque-type) a*)
                      (cons* `(afield) `(afield) a*))]
                 [("Secp256k1Point")
                  (assert (feature-zkir-v3))
                  (cons `(anative ,opaque-type) a*)]
                 [else (cons `(acompress) a*)])]
              [(tvector ,src ,len ,type)
               (let ([a^* (f type '())])
                 (do ([len len (- len 1)] [a* a* (append a^* a*)])
                     ((eqv? len 0) a*)))]
              [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
               ; A contract value at the canonical AlignedValue level is a length 32 byte string
               (cons `(abytes 32) a*)]
              [(ttuple ,src ,type* ...)
               (fold-right f a* type*)]
              [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
               (fold-right f a* type*)]
              [(tunknown) (assert cannot-happen)]
              [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
               (cons `(aadt) a*)]))))
      (with-output-language (Lflattened Type)
        `(ty (,(type->alignments original-type) ...)
             (,pt* ...))))
    (define (do-argument var-name original-type wump)
      (let-values ([(wump vn.pt*)
                    (wump-fold-right
                      (lambda (pt vn.pt*)
                        (let ([var-name (make-new-id var-name)])
                          (values
                            var-name
                            (cons (cons var-name pt) vn.pt*))))
                      '()
                      wump)])
        (hashtable-set! var-ht var-name wump)
        (with-output-language (Lflattened Argument)
          `(argument (,(map car vn.pt*) ...) ,(build-type original-type (map cdr vn.pt*))))))
    ;; Flattened Primitive-Types for a `len`-byte value: ⌈len/field-bytes⌉
    ;; `tfield` limbs, where the high limb is bounded by `len mod field-bytes`
    ;; (or full-width if it divides evenly).  Shared by the tbytes and
    ;; tcontract cases of Type->Wump — both flatten as Bytes<len>, the
    ;; former with the source-level length, the latter with 32 (a contract
    ;; address).
    (define (bytes->primitive-types len)
      (with-output-language (Lflattened Primitive-Type)
        (let-values ([(q r) (div-and-mod len (field-bytes))])
          (let ([ls (make-list q `(tunsigned ,(- (expt 2 (* (field-bytes) 8)) 1)))])
            (if (fx= r 0) ls (cons `(tunsigned ,(max 0 (- (expt 2 (* r 8)) 1))) ls))))))
    ;; All-zero limb list for `default<…>` of a `len`-byte value.  Same
    ;; ⌈len/field-bytes⌉ count as `bytes->primitive-types`, just filled
    ;; with 0s rather than tfield types.  Shared by the tbytes and
    ;; tcontract cases of the (default …) Rhs handler.
    (define (bytes-default-limbs len)
      (make-list (quotient (+ len (- (field-bytes) 1)) (field-bytes)) 0))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
     `(program ,src ((,export-name* ,name*) ...)
        ; like map but arranges to process native and witness declarations first
        ; so that their fun-ht entries are available before processing
        ; any circuits
        ,(let f ([pelt* pelt*])
           (if (null? pelt*)
             '()
             (let ([pelt (car pelt*)] [pelt* (cdr pelt*)])
               (cond
                 [(Lcircuit-Native-Declaration? pelt)
                  (let ([pelt (Native-Declaration pelt)])
                    (cons pelt (f pelt*)))]
                 [(Lcircuit-Witness-Declaration? pelt)
                  (let ([pelt (Witness-Declaration pelt)])
                    (cons pelt (f pelt*)))]
                 [(Lcircuit-Circuit-Definition? pelt)
                  (let ([pelt* (f pelt*)])
                    (cons (Circuit-Definition pelt) pelt*))]
                 [(Lcircuit-Kernel-Declaration? pelt)
                  (let ([pelt* (f pelt*)])
                    (cons (Kernel-Declaration pelt) pelt*))]
                 [(Lcircuit-Ledger-Declaration? pelt)
                  (let ([pelt* (f pelt*)])
                    (cons (Ledger-Declaration pelt) pelt*))]
                 [else (assert cannot-happen)]))))
        ...)])
  (Native-Declaration : Native-Declaration (ir) -> Native-Declaration ()
    [(native ,src ,function-name ,native-entry ((,var-name* ,[Type->Wump : type* -> * wump*]) ...) ,[Type->Wump : type -> * wump])
     (let ([arg* (map do-argument var-name* type* wump*)] [primitive-type* (wump->elts wump)])
       (hashtable-set! fun-ht function-name wump)
       `(native ,src ,function-name ,native-entry (,arg* ...) ,(build-type type primitive-type*)))])
  (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
    [(witness ,src ,function-name ((,var-name* ,[Type->Wump : type* -> * wump*]) ...) ,[Type->Wump : type -> * wump])
     (let ([arg* (map do-argument var-name* type* wump*)] [primitive-type* (wump->elts wump)])
       (hashtable-set! fun-ht function-name wump)
       `(witness ,src ,function-name (,arg* ...) ,(build-type type primitive-type*)))])
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name ((,var-name* ,[Type->Wump : type* -> * wump*]) ...) ,[Type->Wump : type -> * wump] ,stmt* ... ,triv)
     (let ([arg* (map do-argument var-name* type* wump*)] [primitive-type* (wump->elts wump)])
       (let ([stmt** (maplr Statement stmt*)])
         (let ([triv* (if (null? primitive-type*) '() (wump->elts (Triv triv)))])
           `(circuit ,src ,function-name
                     (,arg* ...)
                     ,(build-type type primitive-type*)
                     ,(apply append stmt**) ...
                     (,triv* ...)))))])
  (Kernel-Declaration : Kernel-Declaration (ir) -> Kernel-Declaration ())
  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ())
  (ADT-Op : ADT-Op (ir) -> ADT-Op ()
    [(,ledger-op ,[op-class] (,adt-name (,adt-formal* ,[adt-arg*]) ...) ((,var-name* ,[Type : type* -> type*]) ...) ,[Type : type -> type] ,vm-code)
     `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,(map id-sym var-name*) ...) (,type* ...) ,type ,vm-code)])
  (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
  (Type->Wump : Type (ir) -> * (wump) ; produces a wump of Primitive-Types
    [(tvector ,src ,len ,[Type->Wump : type -> * wump])
     (Wump-vector (make-list len wump))]
    [(tbytes ,src ,len)
     (Wump-bytes (bytes->primitive-types len))]
    [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
     ; A contract value flattens identically to (tbytes 32).
     (Wump-bytes (bytes->primitive-types 32))]
    [(ttuple ,src ,[Type->Wump : type* -> * wump*] ...)
     (Wump-vector wump*)]
    [(tstruct ,src ,struct-name (,elt-name* ,[Type->Wump : type -> * wump*]) ...)
     (Wump-struct elt-name* wump*)]
    [(tunknown) (assert cannot-happen)]
    [(topaque ,src ,opaque-type)
     (guard (string=? opaque-type "JubjubPoint") (not (feature-zkir-v3)))
     (Wump-bytes
       (with-output-language (Lflattened Primitive-Type)
         (list `(tfield (field-native)) `(tfield (field-native)))))]
    [else (Wump-single (Single-Type ir))])
  (Type : Type (ir) -> Type ()
    [else (build-type ir (wump->elts (Type->Wump ir)))])
  (Single-Type : Type (ir) -> Primitive-Type ()
    [(tboolean ,src) `(tunsigned 1)]
    [(tfield ,src ,[ftype]) `(tfield ,ftype)]
    [(tunsigned ,src ,nat) `(tunsigned ,nat)]
    [(topaque ,src ,opaque-type) `(topaque ,opaque-type)]
    [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,[Type : type**] ...) ,[Type : type*]) ...)
     `(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)]
    [(tadt ,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op*] ...))
     `(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))])
  (Statement : Statement (ir) -> * (stmt*)
    [(= ,[Single-Triv : test] ,var-name ,rhs) (Rhs rhs test var-name)]
    [(assert ,src ,[Single-Triv : test] ,mesg)
     (with-output-language (Lflattened Statement)
       (list `(assert ,src ,test ,mesg)))])
  (Rhs : Rhs (ir test var-name) -> * (stmt*)
    [,triv
     (hashtable-set! var-ht var-name (Triv triv))
     '()]
    [(default ,type)
     (letrec ([trivial (lambda (wump) (values wump '()))]
              [do-type
                (lambda (type)
                  (nanopass-case (Lcircuit Type) type
                    [(tboolean ,src) (trivial (Wump-single 0))]
                    [(tfield ,src ,ftype) (trivial (Wump-single 0))]
                    [(tunsigned ,src ,nat) (trivial (Wump-single 0))]
                    [(tbytes ,src ,len)
                     (trivial (Wump-bytes (bytes-default-limbs len)))]
                    [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                     ; `default<C>` is the all-zero address.
                     (trivial (Wump-bytes (bytes-default-limbs 32)))]
                    [(topaque ,src ,opaque-type)
                     (with-output-language (Lflattened Statement)
                       (case opaque-type
                         [("JubjubPoint")
                          (let ([t1 (make-new-id var-name)])
                            (if (feature-zkir-v3)
                                (values
                                  (Wump-single t1)
                                  (list `(= ,test (,t1) (default ,opaque-type))))
                                (let ([t2 (make-new-id var-name)])
                                  (values
                                    (Wump-vector (list (Wump-single t1) (Wump-single t2)))
                                    (list `(= ,test (,t1 ,t2) (default ,opaque-type)))))))]
                         [("Secp256k1Point")
                          (let ([t1 (make-new-id var-name)])
                            (values
                              (Wump-single t1)
                              (list `(= ,test (,t1) (default ,opaque-type)))))]
                         [else (trivial (Wump-single 0))]))]
                    [(tvector ,src ,len ,type)
                     (let-values ([(wump stmt*) (do-type type)])
                       (values (Wump-vector (make-list len wump)) stmt*))]
                    [(ttuple ,src ,type* ...)
                     (let-values ([(wump* stmt*) (do-types type*)])
                       (values (Wump-vector wump*) stmt*))]
                    [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                     (let-values ([(wump* stmt*) (do-types type*)])
                       (values (Wump-struct elt-name* wump*) stmt*))]
                    [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
                     (trivial (Wump-single 0))]
                    [else (assert cannot-happen)]))]
              [do-types
                (lambda (type*)
                  (if (null? type*)
                      (values '() '())
                      (let-values ([(wump instr0*) (do-type (car type*))]
                                   [(wump* instr1*) (do-types (cdr type*))])
                        (values (cons wump wump*) (append instr0* instr1*)))))])
       (let-values ([(wump stmt*) (do-type type)])
         (hashtable-set! var-ht var-name wump)
         stmt*))]
    [(+ ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (+ ,mbits ,triv1 ,triv2))))]
    [(- ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (- ,mbits ,triv1 ,triv2))))]
    [(* ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (* ,mbits ,triv1 ,triv2))))]
    [(< ,bits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (< ,bits ,triv1 ,triv2))))]
    [(== ,[* wump1] ,[* wump2])
     (let ([triv1* (wump->elts wump1)] [triv2* (wump->elts wump2)])
       (assert (fx= (length triv1*) (length triv2*)))
       (let f ([triv1* triv1*] [triv2* triv2*] [triv-accum 1])
         (with-output-language (Lflattened Statement)
           (if (null? triv1*)
               (begin
                 (hashtable-set! var-ht var-name (Wump-single triv-accum))
                 (list `(= ,test ,var-name ,triv-accum)))
               (let ([t1 (make-new-id var-name)] [t2 (make-new-id var-name)])
                 (cons* `(= ,test ,t1 (== ,(car triv1*) ,(car triv2*)))
                        `(= ,test ,t2 (select ,triv-accum ,t1 0))
                        (f (cdr triv1*) (cdr triv2*) t2)))))))]
    [(select ,[Single-Triv : triv0] ,[* wump1] ,[* wump2])
     (let-values ([(wump var-name*)
                   (wump-fold-right
                     (lambda (triv var-name*)
                       (let ([var-name (make-new-id var-name)])
                         (values
                           var-name
                           (cons var-name var-name*))))
                     '()
                     wump1)])
       (let ([triv1* (wump->elts wump1)] [triv2* (wump->elts wump2)])
         (assert (fx= (length triv1*) (length triv2*)))
         (hashtable-set! var-ht var-name wump)
         (map (lambda (var-name triv1 triv2)
                (with-output-language (Lflattened Statement)
                  `(= ,test ,var-name (select ,triv0 ,triv1 ,triv2))))
              var-name* triv1* triv2*)))]
    [(tuple ,[* wump**] ...)
     (hashtable-set! var-ht var-name (Wump-vector (apply append wump**)))
     '()]
    [(vector ,[* wump**] ...)
     (hashtable-set! var-ht var-name (Wump-vector (apply append wump**)))
     '()]
    [(tuple-ref ,[* wump] ,nat)
     (Wump-case wump
       [(Wump-vector wump*)
        (hashtable-set! var-ht var-name (list-ref wump* nat))
        '()]
       [else (assert cannot-happen)])]
    [(bytes-ref ,[* wump] ,nat)
     (Wump-case wump
       [(Wump-bytes wump*)
        (hashtable-set! var-ht var-name (Wump-single var-name))
        (let loop ([nat nat] [triv* (reverse (wump->elts wump))])
          (if (fx< nat (field-bytes))
              (with-output-language (Lflattened Statement)
                (list `(= ,test ,var-name (bytes-ref ,(car triv*) ,nat))))
              (loop (fx- nat (field-bytes)) (cdr triv*))))]
       [else (assert cannot-happen)])]
    [(new ,type ,[* wump*] ...)
     (nanopass-case (Lcircuit Type) type
       [(tstruct ,src ,struct-name (,elt-name* ,type) ...)
        (hashtable-set! var-ht var-name (Wump-struct elt-name* wump*))]
       [else (assert cannot-happen)])
     '()]
    [(bytes->field ,src ,[ftype] ,len ,[* wump])
     (let ([triv* (Wump-case wump
                    [(Wump-bytes elt*) elt*]
                    [else (assert cannot-happen)])])
       (with-output-language (Lflattened Statement)
         (define (make-secp256k1-cast)
           ;; The only possible source type is Bytes<32>, which is two trivs.
           (assert (= (length triv*) 2))
           (hashtable-set! var-ht var-name (Wump-single var-name))
           (list `(= ,test ,var-name (bytes->field ,src ,ftype ,len ,(car triv*) ,(cadr triv*)))))
         (nanopass-case (Lflattened Field-Type) ftype
           [(field-base (curve-secp256k1)) (make-secp256k1-cast)]
           [(field-scalar (curve-secp256k1)) (make-secp256k1-cast)]
           [(field-native)
            (let ([n (length triv*)])
              (cond
                [(= n 0)
                 (hashtable-set! var-ht var-name (Wump-single 0))
                 '()]
                [(= n 1)
                 (hashtable-set! var-ht var-name (Wump-single (car triv*)))
                 '()]
                [else
                  (hashtable-set! var-ht var-name (Wump-single var-name))
                  (let ([n (fx- n 2)])
                    (fold-right
                      (lambda (triv ls)
                        (let ([t1 (make-temp-id src 't1)]
                              [t2 (make-temp-id src 't2)])
                          (cons*
                            `(= ,test ,t1 (== ,triv 0))
                            `(= ,test ,t2 (select ,test ,t1 1)) 
                            `(assert ,src ,t2 "bytes value is too big to fit in a field")
                            ls)))
                      (let-values ([(triv1 triv2) (apply values (list-tail triv* n))])
                        (list `(= ,test ,var-name (bytes->field ,src ,ftype ,len ,triv1 ,triv2))))
                      (list-head triv* n)))]))])))]
    [(field->bytes ,src ,len ,[ftype] ,[Single-Triv : triv])
     (assert (not (= len 0)))
     (let ([var-name1 (make-new-id var-name)]
           [var-name2 (make-new-id var-name)])
       (hashtable-set! var-ht var-name
         (Wump-bytes
           (let ()
             (define (f len ls)
               (if (<= len 0)
                   ls
                   (f (- len (field-bytes)) (cons 0 ls))))
             (if (fx<= len (field-bytes))
                 (list var-name2)
                 (f (- len (fx* 2 (field-bytes))) (list var-name1 var-name2))))))
       (with-output-language (Lflattened Statement)
         (list `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,len ,ftype ,triv)))))]
    [(bytes->vector ,len ,[* wump])
     (let loop ([len len] [triv* (reverse (wump->elts wump))] [rvar-name** '()] [stmt* '()])
       (if (fx= len 0)
           (let ([var-name* (apply append (reverse rvar-name**))])
             (hashtable-set! var-ht var-name (Wump-vector (map Wump-single var-name*)))
             stmt*)
           (let* ([n (fxmin len (field-bytes))]
                  [this-var-name* (make-new-ids var-name n)])
             (loop (fx- len n)
                   (cdr triv*)
                   (cons this-var-name* rvar-name**)
                   (with-output-language (Lflattened Statement)
                     (cons `(= ,test (,this-var-name* ...) (bytes->vector ,(car triv*)))
                           stmt*))))))]
    [(vector->bytes ,len ,[* wump])
     (let loop ([len len] [triv* (wump->elts wump)] [var-name* '()] [stmt* '()])
       (if (fx= len 0)
           (begin
             (hashtable-set! var-ht var-name (Wump-bytes var-name*))
             stmt*)
           (let* ([n (fxmin len (field-bytes))] [this-var-name (make-new-id var-name)])
             (loop (fx- len n)
                   (list-tail triv* n)
                   (cons this-var-name var-name*)
                   (let ([this-triv* (list-head triv* n)])
                     (with-output-language (Lflattened Statement)
                       (cons
                         `(= ,test ,this-var-name (vector->bytes ,(car this-triv*) ,(cdr this-triv*) ...))
                         stmt*)))))))]
    [(cast-to-field ,src ,[ftype] ,[Single-Type : primitive-type] ,[Single-Triv : triv])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (cast-to-field ,ftype ,primitive-type ,triv))))]
    [(cast-from-field ,src ,nat ,[ftype] ,[Single-Triv : triv])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (cast-from-field ,src #f ,nat ,ftype ,triv))))]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,[Single-Triv : triv])
     (hashtable-set! var-ht var-name (Wump-single var-name))
     (with-output-language (Lflattened Statement)
       (list `(= ,test ,var-name (downcast-unsigned ,src #f ,nat2 ,nat1 ,triv))))]
    [(elt-ref ,[* wump] ,elt-name)
     (hashtable-set! var-ht var-name
       (Wump-case wump
         [(Wump-struct elt-name* wump*)
          (let loop ([elt-name* elt-name*] [wump* wump*])
            (assert (not (null? elt-name*)))
            (if (eq? (car elt-name*) elt-name)
                (car wump*)
                (loop (cdr elt-name*) (cdr wump*))))]
         [else (assert cannot-happen)]))
     '()]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,[adt-op -> adt-op^] ,[* actual-wump*] ...)
     (let-values ([(wump var-name*)
                   (wump-fold-right
                     (lambda (type var-name*)
                       (let ([var-name (make-new-id var-name)])
                         (values var-name (cons var-name var-name*))))
                     '()
                     (nanopass-case (Lcircuit ADT-Op) adt-op
                       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
                        (Type->Wump type)]))])
       (hashtable-set! var-ht var-name wump)
       (let ([triv* (fold-right wump->elts '() actual-wump*)])
         (with-output-language (Lflattened Statement)
           (list `(= ,test
                     (,var-name* ...)
                     (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op^ ,triv* ...))))))]
    [(emit ,src ,event-version ,event-tag ,len ,[* wump] ,vm-code)
     (hashtable-set! var-ht var-name (Wump-vector '()))
     (let ([triv* (wump->elts wump)])
       (with-output-language (Lflattened Statement)
         (list `(= ,test
                   ()
                   (emit ,src ,event-version ,event-tag ,len ,triv* ... ,vm-code)))))]
    ; A tcontract value now flattens like Bytes<32> — multiple ZKIR variables, one
    ; alignment atom (abytes 32) — so the receiver position in Lflattened's
    ; contract-call holds a *list* of trivs.  `[* recv-wump]` runs the default
    ; Triv processor (which looks the receiver var-name up in var-ht), giving us
    ; the wump that was assigned at the receiver's binding site.
    ;
    ; The `type` here is still the source-level tcontract; Single-Type produces
    ; the tcontract primitive-type tag we attach to the flattened form so the
    ; type-checker and later passes can find the callee's circuit signatures.
    [(contract-call ,src ,elt-name (,[* recv-wump] ,type) ,[* wump*] ...)
     (let-values ([(wump var-name*)
                   (wump-fold-right
                     (lambda (type var-name*)
                       (let ([var-name (make-new-id var-name)])
                         (values var-name (cons var-name var-name*))))
                     '()
                     (nanopass-case (Lcircuit Type) type
                       [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                        (Type->Wump
                          (cdr (assert (find
                                         (lambda (x) (eq? (car x) elt-name))
                                         (map cons elt-name* type*)))))]))])
       (hashtable-set! var-ht var-name wump)
       (let ([triv* (fold-right wump->elts '() wump*)]
             [recv* (wump->elts recv-wump)])
         (with-output-language (Lflattened Statement)
           (list `(= ,test
                     (,var-name* ...)
                     (contract-call ,src ,elt-name ((,recv* ...) ,(Single-Type type)) ,triv* ...))))))]
    [(call ,src ,function-name ,[* wump*] ...)
     (let ([funwump (or (hashtable-ref fun-ht function-name #f)
                        (assert cannot-happen))])
       (let-values ([(wump var-name*)
                     (wump-fold-right
                       (lambda (type var-name*)
                         (let ([var-name (make-new-id var-name)])
                           (values var-name (cons var-name var-name*))))
                       '()
                       funwump)])
         (hashtable-set! var-ht var-name wump)
         (let ([triv* (fold-right wump->elts '() wump*)])
           (with-output-language (Lflattened Statement)
             (list `(= ,test
                       (,var-name* ...)
                       (call ,src ,function-name ,triv* ...)))))))])
  (Triv : Triv (ir) -> * (wump)
    [,var-name
     (or (hashtable-ref var-ht var-name #f)
         (assert cannot-happen))]
    [(quote ,datum)
     (cond
       [(boolean? datum) (Wump-single (if datum 1 0))]
       [(field? datum) (Wump-single datum)]
       [(bytevector? datum)
        (Wump-bytes
          (let ([n (bytevector-length datum)])
            (let loop ([i 0] [elt* '()])
              (if (fx= i n)
                  elt*
                  (let ([j (fxmin (fx- n i) (field-bytes))])
                    (loop (fx+ i j)
                      (cons
                        (bytevector-uint-ref datum i (endianness little) j)
                        elt*)))))))])]
    [else (assert cannot-happen)])
  (Tuple-Argument : Tuple-Argument (ir) -> * (wump*)
    [(single ,src ,[* wump]) (list wump)]
    [(spread ,src ,nat ,[* wump])
     (Wump-case wump
       [(Wump-vector wump*) wump*]
       [else (assert cannot-happen)])])
  (Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,type ,triv) `(,src ,(Type type) ,(wump->elts (Triv triv)) ...)]))
