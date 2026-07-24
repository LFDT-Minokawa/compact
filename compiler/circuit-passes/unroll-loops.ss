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

(define-pass unroll-loops : Lnoenums (ir) -> Lunrolled ()
  (definitions
    (define (sametype? type1 type2)
      (define-syntax T
        (syntax-rules ()
          [(T ty clause ...)
           (nanopass-case (Lunrolled Type) ty clause ... [else #f])]))
      (T type1
         [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
         [(tfield ,src1 (field-native)) (T type2 [(tfield ,src2 (field-native)) #t])]
         [(tfield ,src1 (field-scalar (curve-jubjub)))
          (T type2
            [(tfield ,src2 (field-scalar (curve-jubjub))) #t])]
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
         ; this case can't presently be reached since we don't have first-class ADTs that can be stored in vectors
         [(tadt ,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr1 (,adt-op1* ...))
          (define (same-adt-arg? adt-arg1 adt-arg2)
            (nanopass-case (Lunrolled Public-Ledger-ADT-Arg) adt-arg1
              [,nat1
               (nanopass-case (Lunrolled Public-Ledger-ADT-Arg) adt-arg2
                 [,nat2 (= nat1 nat2)]
                 [else #f])]
              [,type1
               (nanopass-case (Lunrolled Public-Ledger-ADT-Arg) adt-arg2
                 [,type2 (sametype? type1 type2)]
                 [else #f])]))
          (T type2
             [(tadt ,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr2 (,adt-op2* ...))
              (and (eq? adt-name1 adt-name2)
                   (fx= (length adt-arg1*) (length adt-arg2*))
                   (andmap same-adt-arg? adt-arg1* adt-arg2*))])]))
    (define (maybe-upcast src new-type old-type expr)
      (if (sametype? new-type old-type)
          expr
          (with-output-language (Lunrolled Expression)
            `(safe-cast ,src ,new-type ,old-type ,expr))))
    )
  (Expression : Expression (ir) -> Expression ()
    (definitions
      (define (make-gen-id src)
        (lambda (ignore)
          (make-temp-id src 't)))
      (define (maybe-add-flet fun k)
        (nanopass-case (Lnoenums Function) fun
          [(fref ,src ,function-name) (k function-name)]
          [(circuit ,src (,[Argument : arg*] ...) ,[Type : type] ,expr)
           (let ([function-name (make-temp-id src 'circ)])
             (with-output-language (Lunrolled Expression)
               (let ([expr (Expression expr)])
                 `(flet ,src ,function-name (,src (,arg* ...) ,type ,expr)
                    ,(k function-name)))))]))
      )
    [(call ,src ,function-name ,[expr*] ...)
     `(call ,src ,function-name ,expr* ...)]
    [(map ,src ,len ,fun ,[map-arg src -> expr type make-ref] ,[map-arg* src -> expr* type* make-ref*] ...)
     (let ([expr+ (cons expr expr*)]
           [type+ (cons type type*)]
           [make-ref+ (cons make-ref make-ref*)])
       (maybe-add-flet fun
         (lambda (function-name)
           (let ([gen-id (make-gen-id src)])
             (let ([t+ (map gen-id type+)])
               `(let* ,src ([(,t+ ,type+) ,expr+] ...)
                  (tuple ,src
                    ,(map (lambda (i)
                            `(single ,src
                               (call ,src ,function-name
                                 ,(map (lambda (make-ref t) (make-ref t i)) make-ref+ t+)
                                 ...)))
                          (iota len))
                    ...)))))))]
    [(fold ,src ,len ,fun (,[expr0] ,[type0]) ,[map-arg src -> expr type make-ref] ,[map-arg* src -> expr* type* make-ref*] ...)
     (let ([expr+ (cons expr expr*)]
           [type+ (cons type type*)]
           [make-ref+ (cons make-ref make-ref*)])
       (maybe-add-flet fun
         (lambda (function-name)
           (let ([gen-id (make-gen-id src)])
             (let ([t0 (gen-id type0)] [t+ (map gen-id type+)])
               `(let* ,src ([(,t0 ,type0) ,expr0] [(,t+ ,type+) ,expr+] ...)
                  ,(let f ([i 0] [a `(var-ref ,src ,t0)])
                     (if (fx= i len)
                         a
                         (f (fx+ i 1)
                            `(call ,src ,function-name
                               ,a
                               ,(map (lambda (make-ref t) (make-ref t i)) make-ref+ t+)
                               ...))))))))))])
  (Map-Argument : Map-Argument (ir src) -> Expression (type make-ref)
    [(,[expr] ,[type] ,[type^])
     (values
       expr 
       type
       (nanopass-case (Lunrolled Type) type
         [(ttuple ,src ,type* ...)
          (lambda (t i)
            (maybe-upcast src type^ (list-ref type* i)
              (with-output-language (Lunrolled Expression)
                `(tuple-ref ,src (var-ref ,src ,t) ,i))))]
         [(tbytes ,src ,len)
          (lambda (t i)
            (maybe-upcast src type^
              (with-output-language (Lunrolled Type)
                `(tunsigned ,src 255))
              (with-output-language (Lunrolled Expression)
                `(bytes-ref ,src ,type (var-ref ,src ,t) (quote ,src ,i)))))]
         [(tvector ,src ,len ,type)
          (lambda (t i)
            (maybe-upcast src type^ type
              (with-output-language (Lunrolled Expression)
                `(tuple-ref ,src (var-ref ,src ,t) ,i))))]))])
  (Argument : Argument (ir) -> Argument ())
  (Type : Type (ir) -> Type ()))
