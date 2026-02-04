#!chezscheme

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

(library (circuit-passes)
  (export circuit-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers))

  (define-pass drop-ledger-runtime : Lnodisclose (ir) -> Lposttypescript ()
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
       `(program ,src ((,export-name* ,name*) ...)
          ,(fold-right
             (lambda (pelt pelt*)
               (if (Lnodisclose-Export-Type-Definition? pelt)
                   pelt*
                   (cons (Program-Element pelt) pelt*)))
             '()
             pelt*)
          ...)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [,export-tdefn (assert cannot-happen)])
    (Expression : Expression (ir) -> Expression ()
      (definitions
        (define (do-not src expr)
          (with-output-language (Lposttypescript Expression)
            `(if ,src ,expr (quote ,src #f) (quote ,src #t))))
        )
      [(elt-ref ,src ,[expr] ,elt-name ,nat) `(elt-ref ,src ,expr ,elt-name)]
      [(return ,src ,[expr]) expr]
      [(<= ,src ,mbits ,[expr1] ,[expr2]) (do-not src `(< ,src ,mbits ,expr2 ,expr1))]
      [(> ,src ,mbits ,[expr1] ,[expr2]) `(< ,src ,mbits ,expr2 ,expr1)]
      [(>= ,src ,mbits ,[expr1] ,[expr2]) (do-not src `(< ,src ,mbits ,expr1 ,expr2))]
      [(!= ,src ,[type] ,[expr1] ,[expr2]) (do-not src `(== ,src ,type ,expr1 ,expr2))]
      [(cast-from-bytes ,src ,type ,len ,[expr])
       (let ([expr `(bytes->field ,src ,len ,expr)])
         (nanopass-case (Lnodisclose Type) type
           [(tunsigned ,src ,nat) `(downcast-unsigned ,src ,nat ,expr)]
           [else expr]))])
    (Type : Type (ir) -> Type ()
      [,tvar-name (assert cannot-happen)]
      [(tadt ,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op*] ...) (,adt-rt-op* ...))
       `(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))]
      [(talias ,src ,nominal? ,type-name ,[type]) type]))

  (define-pass replace-enums : Lposttypescript (ir) -> Lnoenums ()
    (Expression : Expression (ir) -> Expression ()
      [(enum-ref ,src ,type ,elt-name^)
       (nanopass-case (Lposttypescript Type) type
         [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
          (let ([maxval (length elt-name*)])
            (let loop ([elt-name elt-name] [elt-name* elt-name*] [i 0])
              (if (eq? elt-name elt-name^)
                  (if (= i maxval)
                      `(quote ,src ,i)
                      `(safe-cast ,src (tunsigned ,src ,maxval) (tunsigned ,src ,i) (quote ,src ,i)))
                  (begin
                    (assert (not (null? elt-name*)))
                    (loop (car elt-name*) (cdr elt-name*) (fx+ i 1))))))]
         [else (assert cannot-happen)])]
      [(cast-from-enum ,src ,[type] ,[type^] ,[expr])
       (nanopass-case (Lnoenums Type) type
         [(tfield ,src^) `(safe-cast ,src ,type ,type^ ,expr)]
         [(tunsigned ,src^ ,nat)
          (let ([maxval (nanopass-case (Lnoenums Type) type^
                          [(tunsigned ,src ,nat) nat]
                          [else (assert cannot-happen)])])
            (cond
              [(> nat maxval) `(safe-cast ,src ,type ,type^ ,expr)]
              [(< nat maxval) `(downcast-unsigned ,src ,nat ,expr)]
              [else expr]))]
         [else (assert cannot-happen)])]
      [(cast-to-enum ,src ,[type] ,[type^] ,[expr])
       (let ([maxval (nanopass-case (Lnoenums Type) type
                       [(tunsigned ,src ,nat) nat]
                       [else (assert cannot-happen)])])
         (nanopass-case (Lnoenums Type) type^
           [(tfield ,src^) `(downcast-unsigned ,src ,maxval ,expr)]
           [(tunsigned ,src^ ,nat)
            (cond
              [(> nat maxval) `(downcast-unsigned ,src ,maxval ,expr)]
              [(< nat maxval) `(safe-cast ,src ,type ,type^ ,expr)]
              [else expr])]
           [else (assert cannot-happen)]))])
    (Type : Type (ir) -> Type ()
      [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
       (let ([maxval (length elt-name*)])
         `(tunsigned ,src ,maxval))]))

  (define-pass unroll-loops : Lnoenums (ir) -> Lunrolled ()
    (definitions
      (define (sametype? type1 type2)
        (define-syntax T
          (syntax-rules ()
            [(T ty clause ...)
             (nanopass-case (Lunrolled Type) ty clause ... [else #f])]))
        (T type1
           [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
           [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
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

  (define-pass inline-circuits : Lunrolled (ir) -> Linlined ()
    (definitions
      (define circuit-ht (make-eq-hashtable))
      (define (arg->name arg)
        (nanopass-case (Linlined Argument) arg
          [(,var-name ,type) var-name]))
      (define (arg->type arg)
        (nanopass-case (Linlined Argument) arg
          [(,var-name ,type) type]))
      (define empty-env '())
      (define (extend-env p var-name*)
        (let ([ht (make-eq-hashtable)])
          (let ([new-var-name* (map (lambda (var-name)
                                      (let ([new-var-name (make-temp-id (id-src var-name) (id-sym var-name))])
                                        (hashtable-set! ht var-name new-var-name)
                                        new-var-name))
                                    var-name*)])
          (values (cons ht p) new-var-name*))))
      (define (maybe-rename p var-name)
        (or (ormap (lambda (ht) (hashtable-ref ht var-name #f)) p)
            var-name))
      (define-pass rename-expr : (Linlined Expression) (ir p) -> (Linlined Expression) ()
        (Expression : Expression (ir p) -> Expression ()
          [(var-ref ,src ,var-name) `(var-ref ,src ,(maybe-rename p var-name))]
          [(let* ,src ([,local* ,[expr*]] ...) ,expr)
           (let-values ([(p var-name*) (extend-env p (map arg->name local*))]
                        [(type*) (map arg->type local*)])
             `(let* ,src ([(,var-name* ,type*) ,expr*] ...) ,(Expression expr p)))])
        (Tuple-Argument : Tuple-Argument (ir p) -> Tuple-Argument ())
        (Path-Element : Path-Element (ir p) -> Path-Element ()))
      (define-record-type circuit
        (nongenerative)
        (fields
          src
          name
          arg*                  ; Linlined
          type                  ; Linlined
          (mutable expr)        ; initially Lunrolled; once processed Linlined
          (mutable status)      ; one of {unprocessed, in-process, processed, consumed}
          )
        (protocol
          (lambda (new)
            (lambda (src name arg* type expr)
              (new src name arg* type expr 'unprocessed)))))
      (define (process-circuit! circuit)
        (case (circuit-status circuit)
          [(unprocessed)
           (circuit-status-set! circuit 'in-process)
           (circuit-expr-set! circuit (Expression (circuit-expr circuit)))
           (circuit-status-set! circuit 'processed)]
          ; recursive circuits should be caught by reject-recursive-circuits
          [(in-process) (assert cannot-happen)]
          [(processed consumed) (void)]))
    )
    (Program : Program (ir) -> Program ()
      [(program ,src  ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each record-circuit! pelt*)
       (let ([circuit* (hashtable-values circuit-ht)])
         (vector-for-each process-circuit! circuit*))
       `(program ,src ((,export-name* ,name*) ...)
          ,(fold-right
             (lambda (pelt pelt*)
               (nanopass-case (Lunrolled Program-Element) pelt
                 [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
                  (let ([circuit (hashtable-ref circuit-ht function-name #f)])
                    (assert circuit)
                    (if (and (eq? (circuit-status circuit) 'consumed)
                             (not (id-exported? function-name)))
                        pelt*
                        (cons
                          `(circuit ,src ,function-name
                             (,(circuit-arg* circuit) ...)
                             ,(circuit-type circuit)
                             ,(circuit-expr circuit))
                          pelt*)))]
                 [,ndecl (cons (Native-Declaration ndecl) pelt*)]
                 [,wdecl (cons (Witness-Declaration wdecl) pelt*)]
                 [,kdecl (cons (Kernel-Declaration kdecl) pelt*)]
                 [,ldecl (cons (Ledger-Declaration ldecl) pelt*)]))
             '()
             pelt*)
          ...)])
    (record-circuit! : Program-Element (ir) -> * (void)
      [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
       (hashtable-set! circuit-ht function-name
         (make-circuit src function-name arg* type expr))]
      [else (void)])
    (Native-Declaration : Native-Declaration (ir) -> Native-Declaration ())
    (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ())
    (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ())
    (Kernel-Declaration : Kernel-Declaration (ir) -> Kernel-Declaration ())
    (Expression : Expression (ir) -> Expression ()
      [(flet ,src ,function-name
         (,src^ (,[arg*] ...) ,[type] ,expr^)
         ,expr)
       (hashtable-set! circuit-ht function-name
         (make-circuit src^ function-name arg* type expr^))
       (Expression expr)]
      [(call ,src ,function-name ,[expr*] ...)
       (cond
         [(hashtable-ref circuit-ht function-name #f) =>
          (lambda (circuit)
            (process-circuit! circuit)
            (circuit-status-set! circuit 'consumed)
            (let ([arg* (circuit-arg* circuit)] [expr (circuit-expr circuit)])
              (let-values ([(p var-name*) (extend-env empty-env (map arg->name arg*))]
                           [(type*) (map arg->type arg*)])
                `(let* ,src ([(,var-name* ,type*) ,expr*] ...)
                   ,(rename-expr expr p)))))]
         [else `(call ,src ,function-name ,expr* ...)])]))

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
            [(field? x) (if (<= x (max-unsigned)) `(tunsigned ,src ,x) `(tfield ,src))]
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
      (define (format-type type)
        (define (format-adt-arg adt-arg)
          (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg
            [,nat (format "~d" nat)]
            [,type (format-type type)]))
        (nanopass-case (Linlined Type) type
          [(tboolean ,src) "Boolean"]
          [(tfield ,src) "Field"]
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
           [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
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
      (define-syntax check-tfield
        (syntax-rules ()
          [(_ ?src ?what ?type)
           (let ([type ?type])
             (unless (nanopass-case (Linlined Type) type
                       [(tfield ,src) #t]
                       [else #f])
               (let ([src ?src] [what ?what])
                 (type-error src what
                   (with-output-language (Linlined Type) `(tfield ,src))
                   type))))]))
       (define (arithmetic-binop src op mbits expr1 expr2)
         (let* ([type1 (Care expr1)] [type2 (Care expr2)])
           (or (T type1
                  [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
                  [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
               (source-errorf src "incompatible combination of types ~a and ~a for ~s"
                              (format-type type1)
                              (format-type type2)
                              op))
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
         (let ([actual-type* (maplr Care expr*)])
           (for-each (lambda (var-name declared-type actual-type)
                       (let ([type (nanopass-case (Linlined Type) declared-type
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
                     actual-type*))
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
      [(< ,src ,mbits ,expr1 ,expr2)
       (let* ([type1 (Care expr1)] [type2 (Care expr2)])
         (or (T type1
                [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])])
               ; the error message says "relational operator" here rather than "<" to avoid misleading
               ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
               (source-errorf src "incompatible combination of types ~a and ~a for relational operator"
                              (format-type type1)
                              (format-type type2)))
         (unless (eqv? (T type1 [(tunsigned ,src ,nat) (fxmax 1 (integer-length nat))]) mbits)
           ; the error message says "relational operator" here rather than "<" to avoid misleading
           ; type-mismatch messages for <=, >, and >=; which all get converted to < earlier in the compiler.
           (source-errorf src "mismatched mbits ~s and type ~a for relational operator"
                          mbits
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
         (let ([actual-type* (maplr Care expr*)])
           (for-each (lambda (var-name declared-type actual-type)
                       (let ([type (nanopass-case (Linlined Type) declared-type
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
                     actual-type*))
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
      [(bytes->field ,src ,len ,[Care : expr -> * type])
       (nanopass-case (Linlined Type) type
         [(tbytes ,src ,len^)
          (unless (= len^ len)
            (source-errorf src "mismatch between Bytes lengths ~s and ~s for bytes->field"
                           len
                           len^))]
         [else (source-errorf src "expected Bytes<~d>, got ~a for bytes->field"
                              len
                              (format-type type))])
       (with-output-language (Linlined Type) `(tfield ,src))]
      [(field->bytes ,src ,len ,[Care : expr -> * type])
       (check-tfield src "argument to field->bytes" type)
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
      [(downcast-unsigned ,src ,nat ,[Care : expr -> * type])
       (unless (nanopass-case (Linlined Type) type
                 [(tfield ,src) #t]
                 [(tunsigned ,src ,nat) #t]
                 [else #f])
         (source-errorf src "expected Field or Uint, got ~a for downcast-unsigned"
                              (format-type type)))
       (with-output-language (Linlined Type) `(tunsigned ,src ,nat))]
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

  (define-pass drop-safe-casts : Linlined (ir) -> Lnosafecast ()
    (Expression : Expression (ir) -> Expression ()
      [(safe-cast ,src ,type ,type^ ,[expr]) expr]))

  (define-pass resolve-indices/simplify : Lnosafecast (ir) -> Lnovectorref ()
    (definitions
      (module (no-var-name set-binding! remove-binding! with-binding has-binding? get-binding)
        ; no-var-name is used for CTVs created as the result of evaluating
        ; some expression.  a CTV without a var-name in-scope is recreated with a
        ; var-name x when x is bound to the corresponding expression's value.
        (define no-var-name (cons 'no 'var-name))

        ; var-ht maps var-names (identifiers) to compile-time values (CTVs)
        (define var-ht (make-eq-hashtable))

        (define (set-binding! var-name ctv) (eq-hashtable-set! var-ht var-name ctv))
        (define (remove-binding! var-name) (eq-hashtable-delete! var-ht var-name))
        (define (with-binding var-name ctv k)
          (let ([a (eq-hashtable-cell var-ht var-name #f)])
            (let ([ctv? (cdr a)])
              (set-cdr! a ctv)
              (let-values ([v* (k)])
                (if ctv?
                    (set-cdr! a ctv?)
                    (eq-hashtable-delete! var-ht var-name))
                (apply values v*)))))

        ; has-binding? and get-binding must return #f for no-var-name as well as for
        ; var-names that have no recorded bindings.
        (define (has-binding? var-name) (eq-hashtable-contains? var-ht var-name))
        (define (get-binding var-name) (eq-hashtable-ref var-ht var-name #f))
        )
      (define-datatype (CTV var-name)
        (CTV-const datum)
        (CTV-tuple ctv*)
        (CTV-struct elt-name* ctv*)
        (CTV-unknown)
        )
      (define (same-var-name? ctv1 ctv2)
        ; same-var-name? is used by some operator handlers to recognize one case
        ; where two expressions will evaluate to the same value, namely when both
        ; will evaluate to the value of the same variable.
        (let ([var-name (CTV-var-name ctv1)])
          (and (eq? var-name (CTV-var-name ctv2))
               (has-binding? var-name))))
      (define (handle-let src var-name type expr expr-ctv do-body)
        (set-binding! var-name
          (if (has-binding? (CTV-var-name expr-ctv))
              expr-ctv
              (CTV-case expr-ctv
                [(CTV-const datum) (CTV-const var-name datum)]
                [(CTV-tuple ctv*) (CTV-tuple var-name ctv*)]
                [(CTV-struct elt-name* ctv*) (CTV-struct var-name elt-name* ctv*)]
                [(CTV-unknown) (CTV-unknown var-name)])))
        (let-values ([(body body-ctv) (do-body)])
          (remove-binding! var-name)
          (values
            (with-output-language (Lnovectorref Expression)
              `(let* ,src (((,var-name ,type) ,expr)) ,body))
            body-ctv)))
      (define (new-let src type expr expr-ctv do-body)
        (let ([var-name (make-temp-id src 't)])
          (handle-let src var-name type expr expr-ctv
            (lambda () (do-body var-name)))))
      (define (if-has-in-scope-var-name ctv k)
        (let ([var-name (CTV-var-name ctv)])
          (and (has-binding? var-name)
               (k var-name))))
      (define (ifconstant ctv k)
        (CTV-case ctv
          [(CTV-const datum) (k datum)]
          [else #f]))
      (define (iszero? x) (eqv? x 0)) ; like zero? but more efficient for exact values
      (define (isone? x) (eqv? x 1))
      (define (tvector->length type)
        (nanopass-case (Lnovectorref Type) type
          [(tvector ,src ,len ,type) len]
          [else (assert cannot-happen)]))
      (define (tbytes->length type)
        (nanopass-case (Lnovectorref Type) type
          [(tbytes ,src ,len) len]
          [else (assert cannot-happen)]))
      (define-syntax mvor 
        (syntax-rules ()
          [(_ e) e]
          [(_ e1 e2 e3 ...)
           (call-with-values
             (lambda () e1)
             (lambda (x . r) (if x (apply values x r) (mvor e2 e3 ...))))]))
      (define (handle-var-ref src var-name)
        (with-output-language (Lnovectorref Expression)
          (let ([ctv (assert (get-binding var-name))])
              (mvor (ifconstant ctv
                      (lambda (datum)
                        (and
                          (or (not (bytevector? datum))
                              (<= (bytevector-length datum) (field-bytes))) ; avoid duplicating bytes objects that don't fit in a field
                          (values 
                            `(quote ,src ,datum)
                            ctv))))
                    (if-has-in-scope-var-name ctv
                      (lambda (var-name^)
                        ; second chance: original variable might have been rebound to true or false
                        ; in the consequent or alternative of an if expression; look it up to see
                        (let ([ctv (assert (get-binding var-name^))])
                          (values
                            (or (ifconstant ctv
                                  (lambda (datum)
                                    (and
                                      (or (not (bytevector? datum))
                                          (<= (bytevector-length datum) (field-bytes))) ; avoid duplicating bytes objects that don't fit in a field
                                      `(quote ,src ,datum))))
                                `(var-ref ,src ,var-name^))
                            ctv))))
                    ; should not be reached: the ctv of any var being referenced should at least be associated
                    ; with itself and be in scope
                    (values `(var-ref ,src ,var-name) ctv)))))
      (define (handle-tuple-ref src expr ctv kindex)
        (with-output-language (Lnovectorref Expression)
          (CTV-case ctv
            [(CTV-tuple ctv*)
             (let ([ctv (list-ref ctv* kindex)])
               (values
                 (or (ifconstant ctv
                       (lambda (datum)
                         `(seq ,src ,expr (quote ,src ,datum))))
                     (if-has-in-scope-var-name ctv
                       (lambda (var-name)
                         `(seq ,src ,expr (var-ref ,src ,var-name))))
                     `(tuple-ref ,src ,expr ,kindex))
                 ctv))]
            [else (values
                    `(tuple-ref ,src ,expr ,kindex)
                    (CTV-unknown no-var-name))])))
      (define (handle-bytes-ref src expr ctv kindex)
        (with-output-language (Lnovectorref Expression)
          (CTV-case ctv
            [(CTV-const datum)
             (assert (and (bytevector? datum) (< kindex (bytevector-length datum))))
             (let* ([b (bytevector-u8-ref datum kindex)]
                    [ctv (CTV-const no-var-name b)])
               (values
                 `(quote ,src ,b)
                 ctv))]
            [else (values
                    `(bytes-ref ,src ,expr ,kindex)
                    (CTV-unknown no-var-name))])))
      (define (handle-elt-ref src expr ctv elt-name)
        (with-output-language (Lnovectorref Expression)
          (CTV-case ctv
            [(CTV-struct elt-name* ctv*)
             (let ([ctv (let f ([elt-name* elt-name*] [ctv* ctv*])
                          (assert (not (null? elt-name*)))
                          (if (eq? (car elt-name*) elt-name)
                              (car ctv*)
                              (f (cdr elt-name*) (cdr ctv*))))])
               (values
                 (or (ifconstant ctv
                       (lambda (datum)
                         `(seq ,src ,expr (quote ,src ,datum))))
                     (if-has-in-scope-var-name ctv
                       (lambda (var-name)
                         `(seq ,src ,expr (var-ref ,src ,var-name))))
                     `(elt-ref ,src ,expr ,elt-name))
                 ctv))]
            [else (values
                    `(elt-ref ,src ,expr ,elt-name)
                    (CTV-unknown no-var-name))])))
      (define (handle-binop src proc expr1 expr2 special-cases build-expr)
        ; handle-binop processes expr1 and expr2 to get residual expr1 and expr2 and CTVs ctv1 and ctv2.
        ; If the ctvs are both CTV-const, it applies proc to the constants to effect constant folding.
        ; It assumes proc produced a valid value unless proc raises an exception with condition 'fail.
        ; If the ctvs are not both CTV-const or if proc raises an exception with condition 'fail,
        ; handle-binop invokes special-cases on ctv1 and ctv2.  special-cases should return either #f
        ; or a ctv representing the ctv of the output expression.  If special-cases returns a ctv that
        ; is a CTV-const or a CTV with an in-scope variable, handle-binop returns a quote or
        ; var-ref expression and the ctv.  Otherwise handle-binop punts to build-expr to create a
        ; residual form of the original operation and returns it along with a CTV-unknown.
        (with-output-language (Lnovectorref Expression)
          (let-values ([(expr1 ctv1) (Expression expr1)]
                       [(expr2 ctv2) (Expression expr2)])
            (mvor (ifconstant ctv1
                    (lambda (datum1)
                      (ifconstant ctv2
                        (lambda (datum2)
                          (call/cc
                            (lambda (k)
                              (let ([datum (with-exception-handler
                                             ; (raise-continuable) is unreachable if the compiler is working correctly
                                             (lambda (c) (if (eq? c 'fail) (k #f) (raise-continuable c)))
                                             (lambda () (proc datum1 datum2)))])
                                (values
                                  `(seq ,src ,expr1 ,expr2 (quote ,src ,datum))
                                  (CTV-const no-var-name datum)))))))))
                  (let ([ctv (special-cases ctv1 ctv2)])
                    (and ctv
                         (mvor (ifconstant ctv
                                 (lambda (datum)
                                   (values
                                     `(seq ,src ,expr1 ,expr2 (quote ,src ,datum))
                                     ctv)))
                               (if-has-in-scope-var-name ctv
                                 (lambda (var-name)
                                   (values
                                     `(seq ,src ,expr1 ,expr2 (var-ref ,src ,var-name))
                                     ctv))))))
                  (values
                    (build-expr expr1 expr2)
                    (CTV-unknown no-var-name))))))
      (define (do-circuit-body var-name* expr)
        (for-each
          (lambda (var-name) (set-binding! var-name (CTV-unknown var-name)))
          var-name*)
        (let-values ([(expr ctv) (Expression expr)])
          (for-each remove-binding! var-name*)
          expr))
      )
    (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
      [(public-ledger-declaration ,[pl-array] ,lconstructor)
       (nanopass-case (Lnosafecast Ledger-Constructor) lconstructor
         [(constructor ,src ((,var-name* ,type*) ...) ,expr)
          (do-circuit-body var-name* expr)])
       `(public-ledger-declaration ,pl-array)])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
       (define (arg->var-name arg)
         (nanopass-case (Lnovectorref Argument) arg
           [(,var-name ,type) var-name]))
       (let ([expr (do-circuit-body (map arg->var-name arg*) expr)])
         `(circuit ,src ,function-name (,arg* ...) ,type ,expr))])
    (Path-Element : Path-Element (ir) -> Path-Element ()
      [,path-index path-index]
      [(,src ,[type] ,[expr ctv]) `(,src ,type ,expr)])
    (Expression : Expression (ir) -> Expression (ctv)
      [(quote ,src ,datum)
       (values
         `(quote ,src ,datum)
         (CTV-const no-var-name datum))]
      [(var-ref ,src ,var-name) (handle-var-ref src var-name)]
      [(let* ,src ((,[local*] ,[expr* expr-ctv*]) ...) ,expr)
       (let loop ([local* local*] [expr* expr*] [expr-ctv* expr-ctv*])
         (if (null? local*)
             (Expression expr)
             (nanopass-case (Lnovectorref Argument) (car local*)
               [(,var-name ,type)
                (handle-let src var-name type (car expr*) (car expr-ctv*)
                  (lambda () (loop (cdr local*) (cdr expr*) (cdr expr-ctv*))))])))]
      [(default ,src ,[type])
       (define (ifdefault-value type k)
         (nanopass-case (Lnovectorref Type) type
           [(tboolean ,src) (k #f)]
           [(tfield ,src) (k 0)]
           [(tunsigned ,src ,nat) (k 0)]
           [(tbytes ,src ,len) (and (<= len (field-bytes)) (k (make-bytevector len 0)))]
           [else #f]))
       (define (default-ctv type)
         (call/cc
           (lambda (k)
             (let f ([type type])
               (or (ifdefault-value type
                     (lambda (datum)
                       (CTV-const no-var-name datum)))
                   (nanopass-case (Lnovectorref Type) type
                     [(ttuple ,src ,type* ...) (CTV-tuple no-var-name (map f type*))]
                     [(tvector ,src ,len ,type) (guard (<= len 10)) (CTV-tuple no-var-name (make-list len (f type)))]
                     [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) (CTV-struct no-var-name elt-name* (map f type*))]
                     [else (k (CTV-unknown no-var-name))]))))))
       (mvor (ifdefault-value type
               (lambda (datum)
                 (values
                   `(quote ,src ,datum)
                   (CTV-const no-var-name datum))))
             (values
               `(default ,src ,type)
               (default-ctv type)))]
      [(if ,src ,[expr0 ctv0] ,expr1 ,expr2)
       (define (intersect ctv1 ctv2)
         (if (eq? ctv1 ctv2)
             ctv1
             (let ([var-name (let ([var-name (CTV-var-name ctv1)])
                               (if (eq? var-name (CTV-var-name ctv2))
                                   var-name
                                   no-var-name))])
               (or (CTV-case ctv1
                     [(CTV-const datum1)
                      (CTV-case ctv2
                        [(CTV-const datum2)
                         (and (equal? datum1 datum2)
                              (CTV-const var-name datum1))]
                        [else #f])]
                     [(CTV-tuple ctv1*)
                      (CTV-case ctv2
                        [(CTV-tuple ctv2*)
                         (CTV-tuple var-name (map intersect ctv1* ctv2*))]
                        [else #f])]
                     [(CTV-struct elt-name1* ctv1*)
                      (CTV-case ctv2
                       [(CTV-struct elt-name2* ctv2*)
                        (assert (andmap eq? elt-name1* elt-name2*))
                        (CTV-struct var-name elt-name1* (map intersect ctv1* ctv2*))]
                       [else #f])]
                    [(CTV-unknown) #f])
                   (CTV-unknown var-name)))))
       ; if could process just one of expr1 or expr2 when ctv0 is a CTV-const, but instead
       ; always process both to catch vector-ref/vector-slice index errors
       (let-values ([(expr1 ctv1 expr2 ctv2)
                     (let ([var-name (CTV-var-name ctv0)])
                       (if (eq? var-name no-var-name)
                           (let-values ([(expr1 ctv1) (Expression expr1)]
                                        [(expr2 ctv2) (Expression expr2)])
                             (values expr1 ctv1 expr2 ctv2))
                           (let-values ([(expr1 ctv1) (with-binding var-name (CTV-const no-var-name #t) (lambda () (Expression expr1)))]
                                        [(expr2 ctv2) (with-binding var-name (CTV-const no-var-name #f) (lambda () (Expression expr2)))])
                             (values expr1 ctv1 expr2 ctv2))))])
         (mvor (ifconstant ctv0
                 (lambda (datum)
                   (if datum
                       (values `(seq ,src ,expr0 ,expr1) ctv1)
                       (values `(seq ,src ,expr0 ,expr2) ctv2))))
               (values
                 `(if ,src ,expr0 ,expr1 ,expr2)
                 (intersect ctv1 ctv2))))]
      [(tuple ,src ,[tuple-arg* maybe-ctv**] ...)
       (values
         `(tuple ,src ,tuple-arg* ...)
         (if (andmap values maybe-ctv**)
             (CTV-tuple no-var-name (apply append maybe-ctv**))
             ; this case shouldn't be reachable for tuples
             (CTV-unknown no-var-name)))]
      [(vector ,src ,[tuple-arg* maybe-ctv**] ...)
       (values
         `(vector ,src ,tuple-arg* ...)
         (if (andmap values maybe-ctv**)
             (CTV-tuple no-var-name (apply append maybe-ctv**))
             (CTV-unknown no-var-name)))]
      [(tuple-ref ,src ,[expr ctv] ,kindex)
       (handle-tuple-ref src expr ctv kindex)]
      [(bytes-ref ,src ,[type] ,[expr expr-ctv] ,[index index-ctv])
       (mvor (ifconstant index-ctv
               (lambda (kindex)
                 (let ([len (tbytes->length type)])
                   (unless (< kindex len)
                     (source-errorf src "invalid Bytes index ~d for a Bytes value of length ~d" kindex len)))
                 (new-let src type expr expr-ctv
                   (lambda (var-name)
                     (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                       (let-values ([(expr ctv) (handle-bytes-ref src var-ref var-ctv kindex)])
                         (values
                           `(seq ,src ,index ,expr)
                           ctv)))))))
             (source-errorf src "Bytes index did not reduce to a constant nonnegative value at compile time"))]
      [(vector-ref ,src ,[type] ,[expr expr-ctv] ,[index index-ctv])
       (mvor (ifconstant index-ctv
               (lambda (kindex)
                 (let ([len (tvector->length type)])
                   (unless (< kindex len)
                     (source-errorf src "invalid vector index ~d for vector of length ~d" kindex len)))
                 (new-let src type expr expr-ctv
                   (lambda (var-name)
                     (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                       (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)])
                         (values
                           `(seq ,src ,index ,expr)
                           ctv)))))))
             (source-errorf src "vector index did not reduce to a constant nonnegative value at compile time"))]
      [(tuple-slice ,src ,[type] ,[expr expr-ctv] ,kindex ,len)
       (new-let src type expr expr-ctv
         (lambda (var-name)
           (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
             (let-values ([(expr* ctv*)
                           (let f ([len len] [kindex kindex])
                             (if (fx= len 0)
                                 (values '() '())
                                 (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)]
                                              [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                   (values (cons expr expr*) (cons ctv ctv*)))))])
               (values
                 `(tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...)
                 (CTV-tuple no-var-name ctv*))))))]
      [(bytes-slice ,src ,[type] ,[expr expr-ctv] ,[index index-ctv] ,len)
       (mvor (ifconstant index-ctv
               (lambda (kindex)
                 (let ([input-len (tbytes->length type)] [end (+ kindex len)])
                   (unless (<= end input-len)
                     (source-errorf src "invalid slice index ~d and length ~d for a Bytes value of length ~d" kindex len input-len)))
                 (mvor (ifconstant expr-ctv
                         (lambda (bv)
                           (assert (and (bytevector? bv) (<= (+ kindex len) (bytevector-length bv))))
                           (let ([new-bv (make-bytevector len)])
                             (bytevector-copy! bv kindex new-bv 0 len)
                             (values
                               `(seq ,src ,expr ,index (quote ,src ,new-bv))
                               (CTV-const no-var-name new-bv)))))
                       (new-let src type expr expr-ctv
                         (lambda (var-name)
                           (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                             (let-values ([(expr* ctv*)
                                           (let f ([len len] [kindex kindex])
                                             (if (fx= len 0)
                                                 (values '() '())
                                                 (let-values ([(expr ctv) (handle-bytes-ref src var-ref var-ctv kindex)]
                                                              [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                                   (values (cons expr expr*) (cons ctv ctv*)))))])
                               (values
                                 `(seq ,src ,index (vector->bytes ,src ,len (tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...)))
                                 (CTV-unknown no-var-name)))))))))
             (source-errorf src "slice index did not reduce to a constant nonnegative value at compile time"))]
      [(vector-slice ,src ,[type] ,[expr expr-ctv] ,[index index-ctv] ,len)
       (mvor (ifconstant index-ctv
               (lambda (kindex)
                 (let ([input-len (tvector->length type)] [end (+ kindex len)])
                   (unless (<= end input-len)
                     (source-errorf src "invalid slice index ~d and length ~d for vector of length ~d" kindex len input-len)))
                 (new-let src type expr expr-ctv
                   (lambda (var-name)
                     (let-values ([(var-ref var-ctv) (handle-var-ref src var-name)])
                       (let-values ([(expr* ctv*)
                                     (let f ([len len] [kindex kindex])
                                       (if (fx= len 0)
                                           (values '() '())
                                           (let-values ([(expr ctv) (handle-tuple-ref src var-ref var-ctv kindex)]
                                                        [(expr* ctv*) (f (fx- len 1) (fx+ kindex 1))])
                                             (values (cons expr expr*) (cons ctv ctv*)))))])
                         (values
                           `(seq ,src ,index (tuple ,src ,(map (lambda (expr) `(single ,src ,expr)) expr*) ...))
                           (CTV-tuple no-var-name ctv*))))))))
             (source-errorf src "slice index did not reduce to a constant nonnegative value at compile time"))]
      [(new ,src ,[type] ,[expr* ctv*] ...)
       (values
         `(new ,src ,type ,expr* ...)
         (nanopass-case (Lnovectorref Type) type
           [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
            (CTV-struct no-var-name elt-name* ctv*)]
           [else (assert cannot-happen)]))]
      [(elt-ref ,src ,[expr ctv] ,elt-name)
       (handle-elt-ref src expr ctv elt-name)]
      [(+ ,src ,mbits ,expr1 ,expr2)
       (define (add x y)
         (let ([a (+ x y)])
           (if mbits
               a ; guaranteed by infer-types not to overflow
               (modulo a (+ (max-field) 1)))))
       (handle-binop src add expr1 expr2
         (lambda (ctv1 ctv2)
           (cond
             [(ifconstant ctv1 iszero?) ctv2]
             [(ifconstant ctv2 iszero?) ctv1]
             [else #f]))
         (lambda (expr1 expr2)
           `(+ ,src ,mbits ,expr1 ,expr2)))]
      [(- ,src ,mbits ,expr1 ,expr2)
       (define (subtract x y)
         (let ([a (- x y)])
           (if mbits
               (if (< a 0) (raise 'fail) a)
               (mod a (+ (max-field) 1)))))
       (handle-binop src subtract expr1 expr2
         (lambda (ctv1 ctv2)
           (cond
             [(ifconstant ctv2 iszero?) ctv1]
             [(same-var-name? ctv1 ctv2) (CTV-const no-var-name 0)]
             [else #f]))
         (lambda (expr1 expr2)
           `(- ,src ,mbits ,expr1 ,expr2)))]
      [(* ,src ,mbits ,expr1 ,expr2)
       (define (multiply x y)
         (let ([a (* x y)])
           (if mbits
               a ; guaranteed by infer-types not to overflow
               (modulo a (+ (max-field) 1)))))
       (handle-binop src multiply expr1 expr2
         (lambda (ctv1 ctv2)
           (cond
             [(ifconstant ctv1 iszero?) (CTV-const no-var-name 0)]
             [(ifconstant ctv2 iszero?) (CTV-const no-var-name 0)]
             [(ifconstant ctv1 isone?) ctv2]
             [(ifconstant ctv2 isone?) ctv1]
             [else #f]))
         (lambda (expr1 expr2) `(* ,src ,mbits ,expr1 ,expr2)))]
      [(< ,src ,mbits ,expr1 ,expr2)
       (handle-binop src < expr1 expr2
         (lambda (ctv1 ctv2)
           (cond
             [(same-var-name? ctv1 ctv2) (CTV-const no-var-name #f)]
             [else #f]))
           (lambda (expr1 expr2) `(< ,src ,mbits ,expr1 ,expr2)))]
      [(== ,src ,[type] ,expr1 ,expr2)
       (handle-binop src equal? expr1 expr2
         (lambda (ctv1 ctv2)
           (cond
             [(same-var-name? ctv1 ctv2) (CTV-const no-var-name #t)]
             [else #f]))
         (lambda (expr1 expr2) `(== ,src ,type ,expr1 ,expr2)))]
      [(seq ,src ,[expr* ctv*] ... ,[expr ctv])
       (values
         `(seq ,src ,expr* ... ,expr)
         ctv)]
      [(assert ,src ,[expr ctv] ,mesg)
       (values
         `(assert ,src ,expr ,mesg)
         (CTV-tuple no-var-name '()))]
      [(field->bytes ,src ,len ,[expr ctv])
       (assert (not (= len 0)))
       (cond
         [(ifconstant ctv
            (lambda (datum)
              (and (or (> len (field-bytes)) ; quick check when nat is large
                       (> (expt 2 len) datum))
                   (let ([bv (make-bytevector len)])
                     (bytevector-uint-set! bv 0 datum (endianness little) len)
                     bv)))) =>
          (lambda (bv) (values `(quote ,src ,bv) (CTV-const no-var-name bv)))]
         [else (values
                 `(field->bytes ,src ,len ,expr)
                 (CTV-unknown no-var-name))])]
      [(bytes->field ,src ,len ,[expr ctv])
       (cond
         [(ifconstant ctv
            (lambda (datum)
              (let ([n (bytevector-length datum)])
                (if (fx= n 0)
                    0
                    (let ([x (bytevector-uint-ref datum 0 (endianness little) n)])
                      (and (<= x (max-field)) x)))))) =>
          (lambda (nat) (values `(quote ,src ,nat) (CTV-const no-var-name nat)))]
         [else (values
                 `(bytes->field ,src ,len ,expr)
                 (CTV-unknown no-var-name))])]
      [(vector->bytes ,src ,len ,[expr ctv])
       (cond
         [(CTV-case ctv
            [(CTV-tuple ctv*)
             (let ([maybe-nat* (map (lambda (ctv) (ifconstant ctv values)) ctv*)])
               (and (andmap values maybe-nat*) (apply bytevector maybe-nat*)))]
            [else #f]) =>
          (lambda (bv)
            (values
              ; NB: if we add a (bytes expr ...) like (tuple expr ...) use it here and allow refs to visible vars as well as consts
              `(quote ,src ,bv)
              (CTV-const no-var-name bv)))]
         [else (values
                 `(vector->bytes ,src ,len ,expr)
                 (CTV-unknown no-var-name))])]
      [(bytes->vector ,src ,len ,[expr ctv])
       (cond
         [(ifconstant ctv bytevector->u8-list) =>
          (lambda (u8*)
            (values
              `(tuple ,src ,(map (lambda (u8) `(single ,src (quote ,src ,u8))) u8*) ...)
              (CTV-tuple no-var-name (map (lambda (u8) (CTV-const no-var-name u8)) u8*))))]
         [else (values
                 `(bytes->vector ,src ,len ,expr)
                 (CTV-unknown no-var-name))])]
      [(downcast-unsigned ,src ,nat ,[expr ctv])
       (cond
         [(ifconstant ctv (lambda (datum) (and (<= datum nat) datum))) =>
          (lambda (datum)
            (values
              `(seq ,src ,expr (quote ,src ,datum))
              ctv))]
         [else (values
                 `(downcast-unsigned ,src ,nat ,expr)
                 (CTV-unknown no-var-name))])]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt] ...) ,src^ ,[adt-op] ,[expr* ctv*] ...)
       (values
         `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt ...) ,src^ ,adt-op ,expr* ...)
         (CTV-unknown no-var-name))]
      [(call ,src ,function-name ,[expr* ctv*] ...)
       (values
         `(call ,src ,function-name ,expr* ...)
         (CTV-unknown no-var-name))]
      [(contract-call ,src ,elt-name (,[expr ctv] ,[type]) ,[expr* ctv*] ...)
       (values
         `(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
         (CTV-unknown no-var-name))]
      [else (internal-errorf 'Expression "unexpected expr ~s" (unparse-Lnovectorref ir))])
    (Tuple-Argument : Tuple-Argument (ir) -> Tuple-Argument (maybe-ctv*)
      [(single ,src ,[expr ctv]) (values `(single ,src ,expr) (list ctv))]
      [(spread ,src ,nat ,[expr ctv])
       (values
         `(spread ,src ,nat ,expr)
         (CTV-case ctv
           [(CTV-tuple ctv*) ctv*]
           [else #f]))]))

  (define-pass discard-useless-code : Lnovectorref (ir) -> Lnovectorref ()
    (definitions
      (module (idset-empty idset idset-insert idset-remove idset-union idset-union-all idset-member?)
        ; rkd 2025/07/15: This implementation of set operations is inefficient and, since union is quadratic,
        ; especially inefficient when the sets get large.  To determine if this is likely to be a problem,
        ; I tooled the code to compute average and max set sizes while running the unit tests, which includes
        ; the programs in midnight-applications.  The largest sets contain only 6 elements, and the average
        ; set size is 1.25.  So this might not be a problem, though programs in the wild might be significantly
        ; different from the tests and example applications.  If it does turn out to be a problem, we can
        ; (1) avoid putting anything but let*-bound variables into the sets and (2) adopt some more
        ; efficient set implementation, e.g., the bit-tree operations used for live analysis in
        ; ChezScheme/s/cpnanopass.ss.
        (define (idset-empty) '())
        (define (idset id) (list id))
        (define (idset-insert id idset) (if (memq id idset) idset (cons id idset)))
        (define (idset-remove id idset) (remq id idset))
        (define (idset-union idset1 idset2) (fold-right idset-insert idset1 idset2))
        (define (idset-union-all idset*) (fold-left idset-union (idset-empty) idset*))
        (define (idset-member? id idset) (and (memq id idset) #t)))
      (define (empty-tuple? expr)
        (nanopass-case (Lnovectorref Expression) expr
          [(tuple ,src) #t]
          [else #f]))
      (define (make-seq effect? src expr* expr)
        (let-values ([(final-expr* final-expr?)
                      (let f ([expr* expr*])
                        (if (null? expr*)
                            (nanopass-case (Lnovectorref Expression) expr
                              [(seq ,src ,expr* ... ,expr) (values expr* expr)]
                              [(tuple ,src) (guard effect?) (values '() #f)]
                              [else (values '() expr)])
                            (let-values ([(expr) (car expr*)] [(final-expr* final-expr?) (f (cdr expr*))])
                              (nanopass-case (Lnovectorref Expression) expr
                                [(seq ,src ,expr* ... ,expr)
                                 (if final-expr?
                                     (values (append expr* (cons expr final-expr*)) final-expr?)
                                     (values expr* expr))]
                                [(tuple ,src) (values final-expr* final-expr?)]
                                [else (if final-expr?
                                          (values (cons expr final-expr*) final-expr?)
                                          (values '() expr))]))))])
          (with-output-language (Lnovectorref Expression)
            (if final-expr?
                (if (null? final-expr*)
                    final-expr?
                    `(seq ,src ,final-expr* ... ,final-expr?))
                `(tuple ,src)))))
      (define (handle-let effect? src local* expr* expr idset)
        (define (arg->var-name arg)
          (nanopass-case (Lnovectorref Argument) arg
            [(,var-name ,type) var-name]))
        (let f ([local* local*] [expr* expr*])
          (if (null? local*)
              (values expr idset)
              (let-values ([(body body-idset) (f (cdr local*) (cdr expr*))])
                (let* ([local (car local*)] [var-name (arg->var-name local)])
                  (if (idset-member? var-name body-idset)
                      (let-values ([(rhs rhs-idset) (Value (car expr*))])
                        (values
                          (with-output-language (Lnovectorref Expression)
                            (nanopass-case (Lnovectorref Expression) body
                              [(let* ,src^ ([,local^* ,expr^*] ...) ,expr^)
                               `(let* ,src ([,local ,rhs] [,local^* ,expr^*] ...) ,expr^)]
                              [else `(let* ,src ((,local ,rhs)) ,body)]))
                          (idset-union rhs-idset (idset-remove var-name body-idset))))
                      (let-values ([(rhs rhs-idset) (Effect (car expr*))])
                        (values
                          (make-seq effect? src (list rhs) body)
                          (idset-union rhs-idset body-idset)))))))))
      )
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,[Value : expr idset])
       `(circuit ,src ,function-name (,arg* ...) ,type ,expr)])
    (Path-Element : Path-Element (ir) -> Path-Element (idset)
      [,path-index (values path-index (idset-empty))]
      [(,src ,type ,[Value : expr idset]) (values `(,src ,type ,expr) idset)])
    (Value : Expression (ir) -> Expression (idset)
      [(quote ,src ,datum) (values ir (idset-empty))]
      [(default ,src ,type) (values ir (idset-empty))]
      [(var-ref ,src ,var-name) (values ir (idset var-name))]
      [(let* ,src ([,local* ,expr*] ...) ,[Value : expr idset])
       (handle-let #f src local* expr* expr idset)]
      [(if ,src ,[Value : expr0 idset0] ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(if ,src ,expr0 ,expr1 ,expr2)
         (idset-union idset0 (idset-union idset1 idset2)))]
      [(tuple ,src ,[Tuple-Argument-Value : tuple-arg* idset*] ...)
       (values
         `(tuple ,src ,tuple-arg* ...)
         (idset-union-all idset*))]
      [(vector ,src ,[Tuple-Argument-Value : tuple-arg* idset*] ...)
       (values
         `(vector ,src ,tuple-arg* ...)
         (idset-union-all idset*))]
      [(tuple-ref ,src ,[Value : expr idset] ,nat)
       (values
         `(tuple-ref ,src ,expr ,nat)
         idset)]
      [(bytes-ref ,src ,[Value : expr idset] ,nat)
       (values
         `(bytes-ref ,src ,expr ,nat)
         idset)]
      [(new ,src ,type ,[Value : expr* idset*] ...)
       (values
         `(new ,src ,type ,expr* ...)
         (idset-union-all idset*))]
      [(elt-ref ,src ,[Value : expr idset] ,elt-name)
       (values
         `(elt-ref ,src ,expr ,elt-name)
         idset)]
      [(+ ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(+ ,src ,mbits ,expr1 ,expr2)
         (idset-union idset1 idset2))]
      [(- ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(- ,src ,mbits ,expr1 ,expr2)
         (idset-union idset1 idset2))]
      [(* ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(* ,src ,mbits ,expr1 ,expr2)
         (idset-union idset1 idset2))]
      [(< ,src ,mbits ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(< ,src ,mbits ,expr1 ,expr2)
         (idset-union idset1 idset2))]
      [(== ,src ,type ,[Value : expr1 idset1] ,[Value : expr2 idset2])
       (values
         `(== ,src ,type ,expr1 ,expr2)
         (idset-union idset1 idset2))]
      [(seq ,src ,[Effect : expr* idset*] ... ,[Value : expr idset])
       (values
         (make-seq #f src expr* expr)
         (idset-union-all (cons idset idset*)))]
      [(assert ,src ,[Value : expr idset] ,mesg)
       (values
         (if (nanopass-case (Lnovectorref Expression) expr
               [(quote ,src ,datum) (eq? datum #t)]
               [else #f])
             `(tuple ,src)
             `(assert ,src ,expr ,mesg))
         idset)]
      [(field->bytes ,src ,len ,[Value : expr idset])
       (values
         `(field->bytes ,src ,len ,expr)
         idset)]
      [(bytes->field ,src ,len ,[Value : expr idset])
       (values
         `(bytes->field ,src ,len ,expr)
         idset)]
      [(vector->bytes ,src ,len ,[Value : expr idset])
       (values
         `(vector->bytes ,src ,len ,expr)
         idset)]
      [(bytes->vector ,src ,len ,[Value : expr idset])
       (values
         `(bytes->vector ,src ,len ,expr)
         idset)]
      [(downcast-unsigned ,src ,nat ,[Value : expr idset])
       (values
         `(downcast-unsigned ,src ,nat ,expr)
         idset)]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt idset^*] ...) ,src^ ,adt-op ,[Value : expr* idset*] ...)
       (values
         `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt ...) ,src^ ,adt-op ,expr* ...)
         (idset-union
           (idset-union-all idset^*)
           (idset-union-all idset*)))]
      [(call ,src ,function-name ,[Value : expr* idset*] ...)
       (values
         `(call ,src ,function-name ,expr* ...)
         (idset-union-all idset*))]
      [(contract-call ,src ,elt-name (,[Value : expr idset] ,type) ,[Value : expr* idset*] ...)
       (values
         `(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
         (idset-union-all (cons idset idset*)))])
    (Tuple-Argument-Value : Tuple-Argument (ir) -> Tuple-Argument (idset)
      [(single ,src ,[Value : expr idset])
       (values `(single ,src ,expr) idset)]
      [(spread ,src ,nat ,[Value : expr idset])
       (values `(spread ,src ,nat ,expr) idset)])
    (Effect : Expression (ir) -> Expression (idset)
      [(quote ,src ,datum) (values `(tuple ,src) (idset-empty))]
      [(default ,src ,type) (values `(tuple ,src) (idset-empty))]
      [(var-ref ,src ,var-name) (values `(tuple ,src) (idset-empty))]
      [(let* ,src ([,local* ,expr*] ...) ,[Effect : expr idset])
       (handle-let #t src local* expr* expr idset)]
      [(if ,src ,expr0 ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (if (and (empty-tuple? expr1) (empty-tuple? expr2))
           (Effect expr0)
           (let-values ([(expr0 idset0) (Value expr0)])
             (values
               `(if ,src ,expr0 ,expr1 ,expr2)
               (idset-union idset0 (idset-union idset1 idset2)))))]
      [(tuple ,src ,[Tuple-Argument-Effect : expr* idset*] ...)
       (values
         (make-seq #t src expr* `(tuple ,src))
         (idset-union-all idset*))]
      [(vector ,src ,[Tuple-Argument-Effect : expr* idset*] ...)
       (values
         (make-seq #t src expr* `(tuple ,src))
         (idset-union-all idset*))]
      [(tuple-ref ,src ,expr ,nat)
       (Effect expr)]
      [(bytes-ref ,src ,expr ,nat)
       (Effect expr)]
      [(new ,src ,type ,[Effect : expr* idset*] ...)
       (values
         (make-seq #t src expr* `(tuple ,src))
         (idset-union-all idset*))]
      [(elt-ref ,src ,expr ,elt-name)
       (Effect expr)]
      [(+ ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (values
         (make-seq #t src (list expr1) expr2)
         (idset-union idset1 idset2))]
      [(- ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (values
         (make-seq #t src (list expr1) expr2)
         (idset-union idset1 idset2))]
      [(* ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (values
         (make-seq #t src (list expr1) expr2)
         (idset-union idset1 idset2))]
      [(< ,src ,mbits ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (values
         (make-seq #t src (list expr1) expr2)
         (idset-union idset1 idset2))]
      [(== ,src ,type ,[Effect : expr1 idset1] ,[Effect : expr2 idset2])
       (values
         (make-seq #t src (list expr1) expr2)
         (idset-union idset1 idset2))]
      [(seq ,src ,[Effect : expr* idset*] ... ,[Effect : expr idset])
       (values
         (make-seq #t src expr* expr)
         (idset-union-all (cons idset idset*)))]
      [(field->bytes ,src ,len ,expr)
       (if (> len (field-bytes))
           (Effect expr)
           (let-values ([(expr idset) (Value expr)])
             (values
               `(field->bytes ,src ,len ,expr)
               idset)))]
      [(bytes->field ,src ,len ,expr)
       (if (<= len (field-bytes))
           (Effect expr)
           (let-values ([(expr idset) (Value expr)])
             (values
               `(bytes->field ,src ,len ,expr)
               idset)))]
      [(vector->bytes ,src ,len ,expr)
       (Effect expr)]
      [(bytes->vector ,src ,len ,expr)
       (Effect expr)]
      [(downcast-unsigned ,src ,nat ,expr)
       (let-values ([(expr idset) (Value expr)])
         (values
           `(downcast-unsigned ,src ,nat ,expr)
           idset))]
      [else (Value ir)])
    (Tuple-Argument-Effect : Tuple-Argument (ir) -> Expression (idset)
      [(single ,src ,[Effect : expr idset]) (values expr idset)]
      [(spread ,src ,nat ,[Effect : expr idset]) (values expr idset)]))

  (define-pass prune-unnecessary-circuits : Lnovectorref (ir) -> Lnovectorref ()
    (definitions
      (define keepers (make-eq-hashtable)))
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       (let ([pelt* (fold-right Program-Element '() pelt*)])
         (let-values ([(export-name* name*)
                       (let f ([export-name* export-name*] [name* name*])
                         (if (null? export-name*)
                             (values '() '())
                             (let-values ([(export-name name) (values (car export-name*) (car name*))]
                                          [(export-name* name*) (f (cdr export-name*) (cdr name*))])
                               (if (eq-hashtable-contains? keepers name)
                                   (values (cons export-name export-name*) (cons name name*))
                                   (values export-name* name*)))))])
           `(program ,src ((,export-name* ,name*) ...)
              ,pelt*
              ...)))])
    (Program-Element : Program-Element (ir pelt*) -> * (pelt*)
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       (if (and (id-exported? function-name)
                (guard (c [(eq? c 'ledger) #t])
                  (Expression expr)
                  #f))
           (begin
             (hashtable-set! keepers function-name #t)
             (cons ir pelt*))
           pelt*)]
      [else (cons ir pelt*)])
    (Expression : Expression (ir) -> Expression ()
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[expr*] ...)
       (raise 'ledger)]))

  (define-pass reduce-to-circuit : Lnovectorref (ir) -> Lcircuit ()
    (definitions
      (define fun-ht (make-eq-hashtable))
      (define default-src)
      (define (arg->name arg)
        (nanopass-case (Lnovectorref Argument) arg
          [(,var-name ,type) var-name]))
      (define (Triv expr test k)
        (Rhs expr test
          (lambda (rhs)
            (if (Lcircuit-Triv? rhs)
                (k rhs)
                (let ([t (make-temp-id default-src 't)])
                  (with-output-language (Lcircuit Statement)
                    (cons
                      `(= ,t ,rhs)
                      (k t))))))))
      (define (Triv* expr* test k)
        (let f ([expr* expr*] [rtriv* '()])
          (if (null? expr*)
              (k (reverse rtriv*))
              (Triv (car expr*) test
                (lambda (triv)
                  (f (cdr expr*) (cons triv rtriv*)))))))
      (define (Tuple-Argument tuple-arg test k)
        (with-output-language (Lcircuit Tuple-Argument)
          (nanopass-case (Lnovectorref Tuple-Argument) tuple-arg
            [(single ,src ,expr)
             (Triv expr test
               (lambda (triv)
                 (k `(single ,src ,triv))))]
            [(spread ,src ,nat ,expr)
             (Triv expr test
               (lambda (triv)
                 (k `(spread ,src ,nat ,triv))))])))
      (define (Tuple-Argument* tuple-arg* test k)
        (let f ([tuple-arg* tuple-arg*] [rtuple-arg* '()])
          (if (null? tuple-arg*)
              (k (reverse rtuple-arg*))
              (Tuple-Argument (car tuple-arg*) test
                (lambda (tuple-arg)
                  (f (cdr tuple-arg*) (cons tuple-arg rtuple-arg*)))))))
      (define (Path-Element* path-elt* test k)
        (let f ([path-elt* path-elt*] [rpath-elt* '()])
          (if (null? path-elt*)
              (k (reverse rpath-elt*))
              (let ([path-elt (car path-elt*)] [path-elt* (cdr path-elt*)])
                (nanopass-case (Lnovectorref Path-Element) path-elt
                  [,path-index (f path-elt* (cons path-index rpath-elt*))]
                  [(,src ,type ,expr)
                   (Triv expr test
                     (lambda (triv)
                       (f path-elt*
                          (cons
                            (with-output-language (Lcircuit Path-Element)
                              `(,src ,(Type type) ,triv))
                            rpath-elt*))))])))))
      (define (add-test src test triv k)
        (let ([t1 (make-temp-id src 't)] [t2 (make-temp-id src 't)])
          (with-output-language (Lcircuit Statement)
            (cons*
              `(= ,t1 (select ,triv ,test (quote #f)))
              `(= ,t2 (select ,triv (quote #f) ,test))
              (k t1 t2)))))
      )
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
       (fluid-let ([default-src src])
         (let ([triv #f])
           (let ([stmt* (Triv expr
                          (with-output-language (Lcircuit Triv) `(quote #t))
                          (lambda (triv^) (set! triv triv^) '()))])
             `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... ,triv))))])
    (Statement : Expression (ir test stmt*) -> * (stmt*)
      [(seq ,src ,expr* ... ,expr)
       (fold-right
         (lambda (expr stmt*) (Statement expr test stmt*))
         (Statement expr test stmt*)
         expr*)]
      [(let* ,src ([,local* ,expr*] ...) ,expr)
       (fold-right
         (lambda (local expr stmt*)
           (nanopass-case (Lnovectorref Argument) local
             [(,var-name ,type)
              (Rhs expr test
                (lambda (rhs)
                  (cons
                    (with-output-language (Lcircuit Statement)
                      `(= ,var-name ,rhs))
                    stmt*)))]))
         (Statement expr test stmt*)
         local*
         expr*)]
      [(if ,src ,expr0 ,expr1 ,expr2)
       ; we could let the Triv call below handle "if" via Rhs, but we handle
       ; Statement "if" directly here to avoid the generation of a select with
       ; possibly mismatched branch types, which could cause trouble downstream.
       (Triv expr0 test
         (lambda (triv0)
           (add-test src test triv0
             (lambda (test1 test2)
               (Statement expr1 test1
                 (Statement expr2 test2 stmt*))))))]
      [else
       (Triv ir test
         (lambda (triv)
           ; dropping triv here, since it has no effect
           stmt*))])
    (Rhs : Expression (ir test k) -> * (stmt*)
      [(seq ,src ,expr* ... ,expr)
       (fold-right
         (lambda (expr stmt*) (Statement expr test stmt*))
         (Rhs expr test k)
         expr*)]
      [(if ,src ,expr0 ,expr1 ,expr2)
       (Triv expr0 test
         (lambda (triv0)
           (add-test src test triv0
             (lambda (test1 test2)
               (Triv expr1 test1
                 (lambda (triv1)
                   (Triv expr2 test2
                     (lambda (triv2)
                       (k (with-output-language (Lcircuit Rhs)
                            `(select ,triv0 ,triv1 ,triv2)))))))))))]
      [(let* ,src ([,local* ,expr*] ...) ,expr)
       (let f ([local* local*] [expr* expr*])
         (if (null? local*)
             (Rhs expr test k)
             (nanopass-case (Lnovectorref Argument) (car local*)
               [(,var-name ,type)
                (Rhs (car expr*) test
                  (lambda (rhs)
                    (cons
                      (with-output-language (Lcircuit Statement)
                        `(= ,var-name ,rhs))
                      (f (cdr local*) (cdr expr*)))))])))]
      [(call ,src ,function-name ,expr* ...)
       (Triv* expr* test
         (lambda (triv*)
           (k (with-output-language (Lcircuit Rhs)
                `(call ,src ,test ,function-name ,triv* ...)))))]
      [(assert ,src ,expr ,mesg)
       (Triv expr test
         (lambda (triv)
           (let ([t1 (make-temp-id src 't)] [t2 (make-temp-id src 't)])
             (with-output-language (Lcircuit Statement)
               (cons*
                 `(= ,t2 (select ,test ,triv (quote #t)))
                 `(assert ,src ,t2 ,mesg)
                 (k (with-output-language (Lcircuit Rhs)
                    `(tuple))))))))]
      [(quote ,src ,datum)
       (k (with-output-language (Lcircuit Rhs)
            `(quote ,datum)))]
      [(var-ref ,src ,var-name)
       (k var-name)]
      [(default ,src ,[type])
       (k (with-output-language (Lcircuit Rhs)
            `(default ,type)))]
      [(+ ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test
         (lambda (triv1)
           (Triv expr2 test
             (lambda (triv2)
               (k (with-output-language (Lcircuit Rhs)
                 `(+ ,mbits ,triv1 ,triv2)))))))]
      [(- ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test
         (lambda (triv1)
           (Triv expr2 test
             (lambda (triv2)
               (k (with-output-language (Lcircuit Rhs)
                  `(- ,mbits ,triv1 ,triv2)))))))]
      [(* ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test
         (lambda (triv1)
           (Triv expr2 test
             (lambda (triv2)
               (k (with-output-language (Lcircuit Rhs)
                  `(* ,mbits ,triv1 ,triv2)))))))]
      [(< ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test
         (lambda (triv1)
           (Triv expr2 test
             (lambda (triv2)
               (k (with-output-language (Lcircuit Rhs)
                  `(< ,mbits ,triv1 ,triv2)))))))]
      [(== ,src ,type ,expr1 ,expr2)
       (Triv expr1 test
         (lambda (triv1)
           (Triv expr2 test
             (lambda (triv2)
               (k (with-output-language (Lcircuit Rhs)
                  `(== ,triv1 ,triv2)))))))]
      [(new ,src ,[type] ,expr* ...)
       (Triv* expr* test
         (lambda (triv*)
           (k (with-output-language (Lcircuit Rhs)
              `(new ,type ,triv* ...)))))]
      [(elt-ref ,src ,expr ,elt-name)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
              `(elt-ref ,triv ,elt-name)))))]
      [(tuple ,src ,tuple-arg* ...)
       (Tuple-Argument* tuple-arg* test
         (lambda (tuple-arg*)
           (k (with-output-language (Lcircuit Rhs)
              `(tuple ,tuple-arg* ...)))))]
      [(vector ,src ,tuple-arg* ...)
       (Tuple-Argument* tuple-arg* test
         (lambda (tuple-arg*)
           (k (with-output-language (Lcircuit Rhs)
              `(vector ,tuple-arg* ...)))))]
      [(tuple-ref ,src ,expr ,nat)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
              `(tuple-ref ,triv ,nat)))))]
      [(bytes-ref ,src ,expr ,nat)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
              `(bytes-ref ,triv ,nat)))))]
      [(bytes->field ,src ,len ,expr)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
                `(bytes->field ,src ,test ,len ,triv)))))]
      [(field->bytes ,src ,len ,expr)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
                `(field->bytes ,src ,test ,len ,triv)))))]
      [(bytes->vector ,src ,len ,expr)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
             `(bytes->vector ,len ,triv)))))]
      [(vector->bytes ,src ,len ,expr)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
              `(vector->bytes ,len ,triv)))))]
      [(downcast-unsigned ,src ,nat ,expr)
       (Triv expr test
         (lambda (triv)
           (k (with-output-language (Lcircuit Rhs)
                `(downcast-unsigned ,src ,test ,nat ,triv)))))]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,[adt-op] ,expr* ...)
       (Path-Element* path-elt* test
         (lambda (path-elt*)
           (Triv* expr* test
             (lambda (triv*)
               (k (with-output-language (Lcircuit Rhs)
                    `(public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...)))))))]
      [(contract-call ,src ,elt-name (,expr ,[type]) ,expr* ...)
       (Triv expr test
         (lambda (triv)
           (Triv* expr* test
             (lambda (triv*)
               (k (with-output-language (Lcircuit Rhs)
                   `(contract-call ,src ,test ,elt-name (,triv ,type) ,triv* ...)))))))]
      [else (internal-errorf 'Rhs "unexpected ir ~s" ir)])
    (Type : Type (ir) -> Type ())
    )

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
                [(tfield ,src) (cons `(afield) a*)]
                [(tunsigned ,src ,nat) (cons `(abytes ,(ceiling (/ (bitwise-length nat) 8))) a*)]
                [(tbytes ,src ,len) (cons `(abytes ,len) a*)]
                [(topaque ,src ,opaque-type) (cons `(acompress) a*)]
                [(tvector ,src ,len ,type)
                 (let ([a^* (f type '())])
                   (do ([len len (- len 1)] [a* a* (append a^* a*)])
                       ((eqv? len 0) a*)))]
                [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
                 ; FIXME: acontract?
                 (cons `(acontract) a*)]
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
       (Wump-bytes
         (with-output-language (Lflattened Primitive-Type)
           (let-values ([(q r) (div-and-mod len (field-bytes))])
             (let ([ls (make-list q `(tfield ,(- (expt 2 (* (field-bytes) 8)) 1)))])
               (if (fx= r 0) ls (cons `(tfield ,(max 0 (- (expt 2 (* r 8)) 1))) ls))))))]
      [(ttuple ,src ,[Type->Wump : type* -> * wump*] ...)
       (Wump-vector wump*)]
      [(tstruct ,src ,struct-name (,elt-name* ,[Type->Wump : type -> * wump*]) ...)
       (Wump-struct elt-name* wump*)]
      [(tunknown) (assert cannot-happen)]
      [else (Wump-single (Single-Type ir))])
    (Type : Type (ir) -> Type ()
      [else (build-type ir (wump->elts (Type->Wump ir)))])
    (Single-Type : Type (ir) -> Primitive-Type ()
      [(tboolean ,src) `(tfield 1)]
      [(tfield ,src) `(tfield)]
      [(tunsigned ,src ,nat) `(tfield ,nat)]
      [(topaque ,src ,opaque-type) `(topaque ,opaque-type)]
      [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,[Type : type**] ...) ,[Type : type*]) ...)
       `(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)]
      [(tadt ,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op*] ...))
       `(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))])
    (Statement : Statement (ir) -> * (stmt*)
      [(= ,var-name ,rhs) (Rhs rhs var-name)]
      [(assert ,src ,[Single-Triv : test] ,mesg)
       (with-output-language (Lflattened Statement)
         (list `(assert ,src ,test ,mesg)))])
    (Rhs : Rhs (ir var-name) -> * (stmt*)
      [,triv
       (hashtable-set! var-ht var-name (Triv triv))
       '()]
      [(+ ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,var-name (+ ,mbits ,triv1 ,triv2))))]
      [(- ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,var-name (- ,mbits ,triv1 ,triv2))))]
      [(* ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,var-name (* ,mbits ,triv1 ,triv2))))]
      [(< ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,var-name (< ,mbits ,triv1 ,triv2))))]
      [(== ,[* wump1] ,[* wump2])
       (let ([triv1* (wump->elts wump1)] [triv2* (wump->elts wump2)])
         (assert (fx= (length triv1*) (length triv2*)))
         (let f ([triv1* triv1*] [triv2* triv2*] [triv-accum 1])
           (with-output-language (Lflattened Statement)
             (if (null? triv1*)
                 (begin
                   (hashtable-set! var-ht var-name (Wump-single triv-accum))
                   (list `(= ,var-name ,triv-accum)))
                 (let ([t1 (make-new-id var-name)] [t2 (make-new-id var-name)])
                   (cons* `(= ,t1 (== ,(car triv1*) ,(car triv2*)))
                          `(= ,t2 (select ,triv-accum ,t1 0))
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
                    `(= ,var-name (select ,triv0 ,triv1 ,triv2))))
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
                  (list `(= ,var-name (bytes-ref ,(car triv*) ,nat))))
                (loop (fx- nat (field-bytes)) (cdr triv*))))]
         [else (assert cannot-happen)])]
      [(new ,type ,[* wump*] ...)
       (nanopass-case (Lcircuit Type) type
         [(tstruct ,src ,struct-name (,elt-name* ,type) ...)
          (hashtable-set! var-ht var-name (Wump-struct elt-name* wump*))]
         [else (assert cannot-happen)])
       '()]
      [(bytes->field ,src ,[Single-Triv : test] ,len ,[* wump])
       (let ([triv* (Wump-case wump
                      [(Wump-bytes elt*) elt*]
                      [else (assert cannot-happen)])])
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
                    (let ([var-name^ (make-new-id var-name)])
                      (with-output-language (Lflattened Statement)
                        (cons*
                          `(= ,var-name^ (== ,triv 0))
                          `(assert ,src ,var-name^ "bytes value is too big to fit in a field")
                          ls))))
                  (let-values ([(triv1 triv2) (apply values (list-tail triv* n))])
                    (with-output-language (Lflattened Statement)
                      (list `(= ,var-name (bytes->field ,src ,test ,len ,triv1 ,triv2)))))
                  (list-head triv* n)))])))]
      [(field->bytes ,src ,[Single-Triv : test] ,len ,[Single-Triv : triv])
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
           (list `(= (,var-name1 ,var-name2) (field->bytes ,src ,test ,len ,triv)))))]
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
                       (cons `(= (,this-var-name* ...) (bytes->vector ,(car triv*)))
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
                     (let ([this-var-name* (list-head triv* n)])
                       (with-output-language (Lflattened Statement)
                         (cons `(= ,this-var-name (vector->bytes ,(car this-var-name*) ,(cdr this-var-name*) ...))
                               stmt*)))))))]
      [(downcast-unsigned ,src ,[Single-Triv : test] ,nat ,[Single-Triv : triv])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,var-name (downcast-unsigned ,src ,test ,nat ,triv))))]
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
      [(public-ledger ,src ,[Single-Triv : test] ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,[adt-op -> adt-op^] ,[* actual-wump*] ...)
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
             (list `(= (,var-name* ...)
                       (public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op^ ,triv* ...))))))]
      ; NB: the uses of Single-Triv and Single-Type will probably have to change with the
      ; replacement of abstract contract values with contract addresses, since a contract address
      ; might not fit into one field
      [(contract-call ,src ,[Single-Triv : test] ,elt-name (,[Single-Triv : triv] ,type) ,[* wump*] ...)
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
         (let ([triv* (fold-right wump->elts '() wump*)])
           (with-output-language (Lflattened Statement)
             (list `(= (,var-name* ...)
                       (contract-call ,src ,test ,elt-name (,triv ,(Single-Type type)) ,triv* ...))))))]
      [(call ,src ,[Single-Triv : test] ,function-name ,[* wump*] ...)
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
               (list `(= (,var-name* ...)
                         (call ,src ,test ,function-name ,triv* ...)))))))])
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
      [(default ,type)
       (let dowump ([type type])
         (nanopass-case (Lcircuit Type) type
           [(tboolean ,src) (Wump-single 0)]
           [(tfield ,src) (Wump-single 0)]
           [(tunsigned ,src ,nat) (Wump-single 0)]
           [(tbytes ,src ,len)
            (Wump-bytes
              (make-list
                (quotient (+ len (- (field-bytes) 1)) (field-bytes))
                0))]
           [(topaque ,src ,opaque-type) (Wump-single 0)]
           [(tvector ,src ,len ,type)
            (Wump-vector (make-list len (dowump type)))]
           [(ttuple ,src ,type* ...)
            (Wump-vector (map dowump type*))]
           [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
            (Wump-struct elt-name* (map dowump type*))]
           [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
            (Wump-single 0)]
           [else (assert cannot-happen)]))]
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

  ;;; optimize-circuit:
  ;;;  - propagates copies
  ;;;  - eliminates unused bindings
  ;;;  - eliminates pure forms in effect context
  ;;;  - eliminates common subexpressions
  ;;;  - paritially folds operators, e.g., (+ x 0) -> x
  ;;;  - simplifies nested operations, e.g., (not (not x)) -> x, (or x (not x)) => #t
  ;;;  - drops asserts that can never fail
  (define-pass optimize-circuit : Lflattened (ir) -> Lflattened ()
    ; this pass is an optimization pass and is thus optional.
    (definitions
      (module (triv-equal? nontriv-single-equal? triv-vec-equal? assert-equal?)
        (define-syntax T
          (syntax-rules ()
            [(_ NT ir ir^ [pat pat^ e] ...)
             (nanopass-case (Lflattened NT) ir
               [pat (nanopass-case (Lflattened NT) ir^ [pat^ e] [else #f])]
               ...
               [else #f])]))
        (define (triv-equal? triv triv^)
          (T Triv triv triv^
             [,var-name ,var-name^ (eq? var-name var-name^)]
             [,nat ,nat^ (equal? nat nat^)]))
        (define trivs-equal?
          (case-lambda
            [(triv1 triv1^ triv2 triv2^)
             (and (triv-equal? triv1 triv1^)
                  (triv-equal? triv2 triv2^))]
            [(triv1 triv1^ triv2 triv2^ triv3 triv3^)
             (and (trivs-equal? triv1 triv1^ triv2 triv2^)
                  (triv-equal? triv3 triv3^))]))
        (define (commutative-trivs-equal? triv1 triv1^ triv2 triv2^)
          (or (trivs-equal? triv1 triv1^ triv2 triv2^)
              (trivs-equal? triv1 triv2^ triv2 triv1^)))
        (define (nontriv-single-equal? single single^)
          (T Single single single^
             [(+ ,mbits ,triv1 ,triv2) (+ ,mbits^ ,triv1^ ,triv2^)
              (and (eqv? mbits mbits^)
                   (commutative-trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(- ,mbits ,triv1 ,triv2) (- ,mbits^ ,triv1^ ,triv2^)
              (and (eqv? mbits mbits^)
                   (trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(* ,mbits ,triv1 ,triv2) (* ,mbits^ ,triv1^ ,triv2^)
              (and (eqv? mbits mbits^)
                   (commutative-trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(< ,mbits ,triv1 ,triv2) (< ,mbits^ ,triv1^ ,triv2^)
              (and (eqv? mbits mbits^)
                   (trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(== ,triv1 ,triv2) (== ,triv1^ ,triv2^)
              (commutative-trivs-equal? triv1 triv1^ triv2 triv2^)]
             [(select ,triv0 ,triv1 ,triv2) (select ,triv0^ ,triv1^ ,triv2^)
              (trivs-equal? triv0 triv0^ triv1 triv1^ triv2 triv2^)]
             [(bytes-ref ,triv ,nat) (bytes-ref ,triv^ ,nat^)
              (and (eqv? nat nat^)
                   (triv-equal? triv triv^))]
             [(bytes->field ,src ,test ,len ,triv1 ,triv2) (bytes->field ,src^ ,test^ ,len^ ,triv1^ ,triv2^)
              (and (triv-equal? test test^)
                   (eqv? len len^)
                   (trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(downcast-unsigned ,src ,test ,nat ,triv) (downcast-unsigned ,src^ ,test^ ,nat^ ,triv^)
              (and (triv-equal? test test^)
                   (eqv? nat nat^)
                   (triv-equal? triv triv^))]))
        (define (triv-vec-equal? v1 v2)
          (let ([n (vector-length v1)])
            (and (fx= (vector-length v2) n)
                 (let f ([i 0])
                   (or (fx= i n)
                       (and (triv-equal? (vector-ref v1 i) (vector-ref v2 i))
                            (f (fx+ i 1))))))))
        (define (assert-equal? p1 p2)
          (and (triv-equal? (car p1) (car p2))
               (string=? (cdr p1) (cdr p2)))))
      ; single-hash is adapted from Chez Scheme equal-hash
      ; Copyright 1984-2017 Cisco Systems Inc. and licensed under Apache Version 2.0
      (module (nontriv-single-hash triv-vec-hash assert-hash)
        (define (update hc k)
          (fxlogxor (#3%fx+ (#3%fxsll hc 2) hc) k))
        (define (nat-hash nat hc)
          (update hc (if (fixnum? nat) nat (modulo nat (most-positive-fixnum)))))
        (define (mbits-hash mbits hc)
          (if mbits (nat-hash mbits hc) (update hc 729589248)))
        (define (triv-hash triv hc)
          (nanopass-case (Lflattened Triv) triv
            [,var-name (update hc (id-uniq var-name))]
            [,nat (nat-hash nat hc)]
            [else (assert cannot-happen)]))
        (define (commutative-triv-hash triv1 triv2 hc)
          (fxlogxor (triv-hash triv1 hc) (triv-hash triv2 hc)))
        (define (nontriv-single-hash single)
          (nanopass-case (Lflattened Single) single
            [(+ ,mbits ,triv1 ,triv2) (mbits-hash mbits (commutative-triv-hash triv1 triv2 119001092))]
            [(- ,mbits ,triv1 ,triv2) (mbits-hash mbits (triv-hash triv1 (triv-hash triv2 410225874)))]
            [(* ,mbits ,triv1 ,triv2) (mbits-hash mbits (commutative-triv-hash triv1 triv2 513566316))]
            [(< ,mbits ,triv1 ,triv2) (mbits-hash mbits (triv-hash triv1 (triv-hash triv2 730407)))]
            [(== ,triv1 ,triv2) (commutative-triv-hash triv1 triv2 729589248)]
            [(select ,triv0 ,triv1 ,triv2)
             (triv-hash triv0
               (triv-hash triv1
                 (triv-hash triv2
                   729589248)))]
            [(bytes-ref ,triv ,nat)
             (triv-hash nat
               (triv-hash triv 729589248))]
            [(bytes->field ,src ,test ,len ,triv1 ,triv2)
             (triv-hash test
               (triv-hash triv1
                 (triv-hash triv2
                   (triv-hash len 536285952))))]
            [(vector->bytes ,triv ,triv* ...)
             (fold-left (lambda (hc triv) (triv-hash triv hc))
               729589248
               (cons triv triv*))]
            [(downcast-unsigned ,src ,test ,nat ,triv)
             (triv-hash test
               (triv-hash triv
                 (triv-hash nat 314267636)))]
            [else (internal-errorf 'nontriv-single-hash "unhandled form ~s" single)]))
        (define (triv-vec-hash v)
          (let ([n (vector-length v)])
            (do ([i 0 (fx+ i 1)]
                 [hc 883823588 (triv-hash (vector-ref v i) hc)])
                ((fx= i n) hc))))
        (define (assert-hash p)
          (triv-hash (car p) (update 398346201 (string-hash (cdr p))))))
      (define var->triv)
      (define var->nontriv-single)
      (define nontriv-single->var)
      (define ref-ht)
      (define fbexpr->vars)
      (define bvexpr->vars)
      (define assert-ht)
      (define-syntax with-hashtables
        (syntax-rules ()
          [(_ b1 b2 ...)
           (fluid-let ([var->triv (make-eq-hashtable)]
                       [var->nontriv-single (make-eq-hashtable)]
                       [nontriv-single->var (make-hashtable nontriv-single-hash nontriv-single-equal?)]
                       [ref-ht (make-eq-hashtable)]
                       [fbexpr->vars (make-hashtable triv-vec-hash triv-vec-equal?)]
                       [bvexpr->vars (make-hashtable triv-vec-hash triv-vec-equal?)]
                       [assert-ht (make-hashtable assert-hash assert-equal?)])
             (let () b1 b2 ...))]))
      (define (ifconstant triv k)
        (nanopass-case (Lflattened Triv) triv
          [,nat (k nat)]
          [else #f]))
       (define (ifconstants triv* k)
         (if (null? triv*)
             (k '())
             (ifconstant (car triv*)
               (lambda (x)
                 (ifconstants (cdr triv*)
                   (lambda (x*) (k (cons x x*))))))))
      (module (undefined! undefined?)
        ; the additional undefined marker on var-names would not be necessary if we
        ; replaced assert in Lcircuit and beyond with assert-not so that a 0 value
        ; for the tests suppresses the message rather than a 1 value.
        (define undefined-ht (make-eq-hashtable))
        (define (undefined! var-name) (hashtable-set! undefined-ht var-name #t))
        (define (undefined? triv)
          (nanopass-case (Lflattened Triv) triv
            [,var-name (hashtable-ref undefined-ht var-name #f)]
            ; this case isn't exercised because reduce-to-circuit always produces
            ; a variable reference for the assert form's test
            [else #f])))
      )
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
       (with-hashtables
         (let* ([rstmt* (fold-left
                          (lambda (rstmt* stmt) (FWD-Statement stmt rstmt*))
                          '()
                          stmt*)]
                [triv* (map FWD-Triv triv*)]
                [triv* (map BWD-Triv triv*)]
                [stmt* (fold-left
                         (lambda (stmt* stmt) (BWD-Statement stmt stmt*))
                         '()
                         rstmt*)])
           `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))))]
      [else (internal-errorf 'Circuit-Definition "unexpected ir ~s" ir)])
    (FWD-Statement : Statement (ir rstmt*) -> * (rstmt*)
      ; NB. FWD-Statement eliminates all statements whose conditional-execution
      ; flag (test) is the constant 0 (assignments) or 1 (asserts).  it also eliminates
      ; asserts if the flag is undefined, which can happen only if the statement is in
      ; a part of the circuit that is never enabled.  the undefined check is necessary
      ; for asserts but not assignments because undefined vars are given the value 0.
      [(= ,var-name ,[Single-Test : single -> * maybe-test])
       (if (eqv? maybe-test 0)
           (begin
             (hashtable-set! var->triv var-name 0)
             (undefined! var-name)
             rstmt*)
           (with-output-language (Lflattened Statement)
             (let* ([single (FWD-Single single)]
                    [single (cond
                              [(Lflattened-Triv? single)
                               (hashtable-set! var->triv var-name single)
                               single]
                              [(hashtable-ref nontriv-single->var single #f) =>
                               (lambda (var-name^)
                                 (hashtable-set! var->triv var-name var-name^)
                                 var-name^)]
                              [else
                               (hashtable-set! nontriv-single->var single var-name)
                               (hashtable-set! var->nontriv-single var-name single)
                               single])])
               (cons `(= ,var-name ,single) rstmt*))))]
      [(= (,var-name* ...) ,[Multiple-Test : multiple -> * maybe-test])
       (if (eqv? maybe-test 0)
           (begin
             (for-each (lambda (var-name) (hashtable-set! var->triv var-name 0) (undefined! var-name)) var-name*)
             rstmt*)
           (FWD-Multiple multiple var-name* rstmt*))]
      [(assert ,src ,[FWD-Triv : test] ,mesg)
       (if (or (eqv? test 1) (undefined? test))
           rstmt*
           (with-output-language (Lflattened Statement)
             (let ([a (hashtable-cell assert-ht (cons test mesg) #f)])
               (if (cdr a)
                   rstmt*
                   (begin
                     (set-cdr! a #t)
                     (cons `(assert ,src ,test ,mesg) rstmt*))))))]
      [else (internal-errorf 'FWD-Statement "unexpected ir ~s" ir)])
    (Single-Test : Single (ir) -> * (maybe-test)
      [(bytes->field ,src ,[FWD-Triv : test] ,len ,triv1 ,triv2) test]
      [(downcast-unsigned ,src ,[FWD-Triv : test] ,nat ,triv) test]
      [else #f])
    (Multiple-Test : Multiple (ir) -> * (maybe-test)
      [(call ,src ,[FWD-Triv : test] ,function-name ,triv* ...) test]
      [(contract-call ,src ,[FWD-Triv : test] ,elt-name (,triv ,primitive-type) ,triv* ...) test]
      [(field->bytes ,src ,[FWD-Triv : test] ,len ,triv) test]
      [(public-ledger ,src ,[FWD-Triv : test] ,ledger-field-name ,sugar? (,[FWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,triv* ...) test]
      [else #f])
    (FWD-Multiple : Multiple (ir var-name* rstmt*) -> * (rstmt*)
      [(call ,src ,[FWD-Triv : test] ,function-name ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= (,var-name* ...) (call ,src ,test ,function-name ,triv* ...)) rstmt*))]
      [(contract-call ,src ,[FWD-Triv : test] ,elt-name (,[FWD-Triv : triv] ,primitive-type) ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= (,var-name* ...) (contract-call ,src ,test ,elt-name (,triv ,primitive-type) ,triv* ...)) rstmt*))]
      [(field->bytes ,src ,[FWD-Triv : test] ,len ,[FWD-Triv : triv])
       (assert (fx= (length var-name*) 2))
       (assert (not (= len 0)))
       (with-output-language (Lflattened Statement)
         (let ([var-name1 (car var-name*)] [var-name2 (cadr var-name*)])
           (or (ifconstant triv
                 (lambda (len^)
                   (and (< len^ (expt 2 (* 8 len)))
                        ; case currently unreachable if resolve-indices/simplify is doing its job
                        (let-values ([(q r) (div-and-mod len^ (expt 2 (* 8 (field-bytes))))])
                          (hashtable-set! var->triv var-name1 q)
                          (hashtable-set! var->triv var-name2 r)
                          rstmt*))))
               (let ([a (hashtable-cell fbexpr->vars (vector test len triv) #f)])
                 (cond
                   [(cdr a) =>
                    (lambda (vars)
                      (hashtable-set! var->triv var-name1 (car vars))
                      (hashtable-set! var->triv var-name2 (cdr vars))
                      rstmt*)]
                   [else
                    (set-cdr! a (cons var-name1 var-name2))
                    (cons `(= (,var-name1 ,var-name2) (field->bytes ,src ,test ,len ,triv)) rstmt*)])))))]
      [(bytes->vector ,[FWD-Triv : triv])
       (with-output-language (Lflattened Statement)
         (or (ifconstant triv
               (lambda (bytes)
                 (fold-left
                   (lambda (bytes var-name)
                     (let-values ([(q r) (div-and-mod bytes 256)])
                       (hashtable-set! var->triv var-name r)
                       q))
                   bytes
                   var-name*)
                 rstmt*))
             (let ([a (hashtable-cell bvexpr->vars (vector (length var-name*) triv) #f)])
               (cond
                 [(cdr a) =>
                  (lambda (vars)
                    (for-each
                      (lambda (var-name var)
                        (hashtable-set! var->triv var-name var))
                      var-name*
                      vars)
                    rstmt*)]
                 [else
                  (set-cdr! a var-name*)
                  (cons `(= (,var-name* ...) (bytes->vector ,triv)) rstmt*)]))))]
      [(public-ledger ,src ,[FWD-Triv : test] ,ledger-field-name ,sugar? (,[FWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= (,var-name* ...)
                   (public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
               rstmt*))])
    (FWD-Single : Single (ir) -> Single ()
      ; some of the expressions in FWD-Single are unreachable because they duplicate the folding
      ; already done by resolve-indices/simplify
      (definitions
        (define == (lambda (x y) (if (= x y) 1 0)))
        (define lessthan (lambda (x y) (if (< x y) 1 0)))
        (module (add subtract multiply)
          (define m (+ (max-field) 1))
          (define (add mbits)
            (lambda (x y)
              (let ([a (+ x y)])
                (if mbits
                    a ; guaranteed by infer-types to be less than 2^mbits
                    (modulo a m)))))
          (define (subtract mbits)
            (lambda (x y)
              (let ([a (- x y)])
                (if mbits
                    (and (>= a 0) a)
                    (modulo a m)))))
          (define (multiply mbits)
            (lambda (x y)
              (let ([a (* x y)])
                (if mbits
                    a ; guaranteed by infer-types to be less than 2^mbits
                    (modulo a m))))))
        (define (ifsingle triv k)
          (let ([maybe-single (nanopass-case (Lflattened Triv) triv
                                [,var-name (hashtable-ref var->nontriv-single var-name #f)]
                                [else #f])])
            (and maybe-single (k maybe-single))))
        (define (ifnot triv k)
          (ifsingle triv
            (lambda (single)
              (nanopass-case (Lflattened Single) single
                [(select ,triv0 ,nat1 ,nat2)
                 (guard (and (eqv? nat1 0) (eqv? nat2 1)))
                 (k triv0)]
                [else #f]))))
        (define ($fold2 op triv1 triv2 commutative? rewrite default)
          (let ([triv1 (FWD-Triv triv1)] [triv2 (FWD-Triv triv2)])
            (or (ifconstant triv1
                  (lambda (nat1)
                    (ifconstant triv2
                      (lambda (nat2)
                        (op nat1 nat2)))))
                (or (rewrite triv1 triv2)
                    (and commutative? (rewrite triv2 triv1)))
                    #| not presently needed
                    (and nontrivial?
                         (or (ifsingle triv1
                               (lambda (single1)
                                 (or (rewrite single1 triv2)
                                     (and commutative? (rewrite triv2 single1)))))
                             (ifsingle triv2
                               (lambda (single2)
                                 (or (rewrite triv1 single2)
                                     (and commutative? (rewrite single2 triv1)))))))
                    ; NB: (rewrite maybe-single1 maybe-single2) is not presently supported
                    |#
                    (default triv1 triv2))))
        (define-syntax fold2
          (lambda (x)
            (syntax-case x ()
              [(_ ?op ?mbits ?triv1 ?triv2 commutative? [(_ pat1 pat2) e1 e2 ...] ...)
               #`($fold2 (lambda (x y) (?op x y)) ?triv1 ?triv2 commutative?
                   (lambda (single1 single2)
                     (or (nanopass-case (Lflattened Single) single1
                           [pat1 (nanopass-case (Lflattened Single) single2
                                   [pat2 e1 e2 ...]
                                   [else #f])]
                           [else #f])
                         ...))
                   (lambda (triv1 triv2)
                     (with-output-language (Lflattened Single)
                       #,(if (datum ?mbits)
                             #'`(?op ,?mbits ,triv1 ,triv2)
                             #'`(?op ,triv1 ,triv2)))))]))))
      [,triv (FWD-Triv ir)]
      [(+ ,mbits ,triv1 ,triv2)
       (let ([+ (add mbits)])
         (fold2 + mbits triv1 triv2 #t
           [(_ ,triv ,nat) (and (eqv? nat 0) triv)]))]
      [(- ,mbits ,triv1 ,triv2)
       (let ([- (subtract mbits)])
         (fold2 - mbits triv1 triv2 #f
           [(_ ,triv ,nat) (and (eqv? nat 0) triv)]
           [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 0)]))]
      [(* ,mbits ,triv1 ,triv2)
       (let ([* (multiply mbits)])
         (fold2 * mbits triv1 triv2 #t
           [(_ ,triv ,nat)
            (or (and (eqv? nat 0) 0)
                (and (eqv? nat 1) triv))]))]
      [(< ,mbits ,triv1 ,triv2)
       (let ([< lessthan])
         (fold2 < mbits triv1 triv2 #f
           ; TODO: special-case
           ;  (< var-name 0)
           ;  (< var-name (+ var-name n>0))
           ;  (< (- var-name n>0) var-name)
           [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 0)]))]
      [(== ,triv1 ,triv2)
       (fold2 == #f triv1 triv2 #t
         ; TODO: special case (= (+ var-name n>0) 0) and (= (+ n>0 var-name) 0)?
         [(_ ,var-name ,var-name^) (and (eq? var-name var-name^) 1)])]
      [(select ,[FWD-Triv : triv0] ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
       (let-values ([(triv0 triv1 triv2)
                     (cond
                       [(ifnot triv0 values) => (lambda (triv0) (values triv0 triv2 triv1))]
                       [else (values triv0 triv1 triv2)])])
         (define (maybe-fold triv0 triv1 triv2)
           (or (ifconstant triv0
                 (lambda (b) (if (eqv? b 1) triv1 triv2)))
               (and (triv-equal? triv1 triv2) triv1)
               (and (or (eq? triv1 triv0)
                        (ifconstant triv1 (lambda (b) (eq? b 1))))
                    (or (eq? triv2 triv0)
                        (ifconstant triv2 (lambda (b) (eq? b 0))))
                    triv0)))
         (define (f triv val0)
           (define (subst triv) (if (eq? triv triv0) val0 triv))
           (or (and (eq? triv triv0) val0)
               (ifsingle triv
                 (lambda (single)
                   (nanopass-case (Lflattened Single) single
                     [(select ,triv0^ ,triv1^ ,triv2^)
                      (maybe-fold (f (subst triv0^) val0) (f (subst triv1^) val0) (f (subst triv2^) val0))]
                     [else #f])))
               triv))
         (let ([triv1 (f triv1 1)] [triv2 (f triv2 0)])
           (or (maybe-fold triv0 triv1 triv2)
               `(select ,triv0 ,triv1 ,triv2))))]
      [(bytes-ref ,[FWD-Triv : triv] ,nat)
       (or (ifconstant triv
             (lambda (nat^)
               (let* ([start (* nat 8)] [end (+ start 8)])
                 (bitwise-bit-field nat^ start end))))
           `(bytes-ref ,triv ,nat))]
      [(bytes->field ,src ,[FWD-Triv : test] ,len ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
       (or (ifconstant triv1
             (lambda (nat1)
               (ifconstant triv2
                 (lambda (nat2)
                   (let ([x (+ (bitwise-arithmetic-shift-left nat1 (* 8 (field-bytes))) nat2)])
                     (and (<= x (max-field)) x))))))
           `(bytes->field ,src ,test ,len ,triv1 ,triv2))]
      [(vector->bytes ,[FWD-Triv : triv] ,[FWD-Triv : triv*] ...)
       (or (ifconstant triv
             (lambda (u8)
               (ifconstants triv*
                 (lambda (u8*)
                   (fold-right
                     (lambda (u8 bytes) (+ (ash bytes 8) u8))
                     0
                     (cons u8 u8*))))))
           (let ([triv* (fold-right
                          (lambda (triv triv*)
                            (if (and (null? triv*)
                                     (nanopass-case (Lflattened Triv) triv
                                       [,nat (eqv? nat 0)]
                                       [else #f]))
                                triv*
                                (cons triv triv*)))
                          '()
                          triv*)])
             `(vector->bytes ,triv ,triv* ...)))]
      [(downcast-unsigned ,src ,[FWD-Triv : test] ,nat ,[FWD-Triv : triv])
       (or (ifconstant triv
             (lambda (nat^)
               (and (<= nat^ nat) nat^)))
           `(downcast-unsigned ,src ,test ,nat ,triv))]
      [else (internal-errorf 'FWD-Single "unexpected ir ~s" ir)])
    (FWD-Path-Element : Path-Element (ir) -> Path-Element ()
      [,path-index path-index]
      [(,src ,type ,[FWD-Triv : triv*] ...) `(,src ,type ,triv* ...)])
    (FWD-Triv : Triv (ir) -> Triv ()
      [,var-name (hashtable-ref var->triv var-name var-name)]
      [else ir])
    (BWD-Statement : Statement (ir stmt*) -> Statement (stmt*)
      (definitions
        (define (pure? single)
          (nanopass-case (Lflattened Single) single
            [,triv #t]
            [(+ ,mbits ,triv1 ,triv2) #t]
            [(- ,mbits ,triv1 ,triv2) #t]
            [(* ,mbits ,triv1 ,triv2) #t]
            [(< ,mbits ,triv1 ,triv2) #t]
            [(== ,triv1 ,triv2) #t]
            [(select ,triv0 ,triv1 ,triv2) #t]
            [(bytes-ref ,triv ,nat) #t]
            [(bytes->field ,src ,test ,len ,triv1 ,triv2) (<= len (field-bytes))]
            [(vector->bytes ,triv ,triv* ...) #t]
            [(downcast-unsigned ,src ,test ,nat ,triv) #f])))
      [(= ,var-name ,single)
       (guard
         (not (hashtable-contains? ref-ht var-name))
         (pure? single))
       ; discard without processing any of the subexpressions to avoid marking any variables referenced
       stmt*]
      [(= ,var-name ,[BWD-Single : single])
       (cons `(= ,var-name ,single) stmt*)]
      [(= (,var-name* ...) (call ,src ,[BWD-Triv : test] ,function-name ,[BWD-Triv : triv*] ...))
       (cons `(= (,var-name* ...) (call ,src ,test ,function-name ,triv* ...)) stmt*)]
      [(= (,var-name* ...) (contract-call ,src ,[BWD-Triv : test] ,elt-name (,[BWD-Triv : triv] ,primitive-type) ,[BWD-Triv : triv*] ...))
       (cons `(= (,var-name* ...) (contract-call ,src ,test ,elt-name (,triv ,primitive-type) ,triv* ...)) stmt*)]
      [(= (,var-name1 ,var-name2) (field->bytes ,src ,test ,len ,triv))
       (guard
         (>= len (field-bytes))
         (not (hashtable-contains? ref-ht var-name1))
         (not (hashtable-contains? ref-ht var-name2)))
       stmt*]
      [(= (,var-name1 ,var-name2) (field->bytes ,src ,[BWD-Triv : test] ,len ,[BWD-Triv : triv]))
       (cons `(= (,var-name1 ,var-name2) (field->bytes ,src ,test ,len ,triv)) stmt*)]
      [(= (,var-name* ...) (bytes->vector ,triv))
       (guard (not (ormap (lambda (var-name) (hashtable-contains? ref-ht var-name)) var-name*)))
       stmt*]
      [(= (,var-name* ...) (bytes->vector ,[BWD-Triv : triv]))
       (cons `(= (,var-name* ...) (bytes->vector ,triv)) stmt*)]
      [(= (,var-name* ...)
          (public-ledger ,src ,[BWD-Triv : test] ,ledger-field-name ,sugar? (,[BWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[BWD-Triv : triv*] ...))
       (cons `(= (,var-name* ...)
                 (public-ledger ,src ,test ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
             stmt*)]
      [(assert ,src ,[BWD-Triv : test] ,mesg)
       (cons `(assert ,src ,test ,mesg) stmt*)]
      [else (internal-errorf 'BWD-Statement "unexpected ir ~s" ir)])
    (BWD-Single : Single (ir) -> Single ()
      [,triv (BWD-Triv ir)] ; not exercised since FWD-Single propagates Triv Rhs
      [(+ ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(+ ,mbits ,triv1 ,triv2)]
      [(- ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(- ,mbits ,triv1 ,triv2)]
      [(* ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(* ,mbits ,triv1 ,triv2)]
      [(< ,mbits ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(< ,mbits ,triv1 ,triv2)]
      [(== ,[BWD-Triv : triv1] ,[BWD-Triv : triv2]) `(== ,triv1 ,triv2)]
      [(select ,[BWD-Triv : triv0] ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
       `(select ,triv0 ,triv1 ,triv2)]
      [(bytes-ref ,[BWD-Triv : triv] ,nat) `(bytes-ref ,triv ,nat)]
      [(bytes->field ,src ,[BWD-Triv : test] ,len ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
       `(bytes->field ,src ,test ,len ,triv1 ,triv2)]
      [(vector->bytes ,[BWD-Triv : triv] ,[BWD-Triv : triv*] ...)
       `(vector->bytes ,triv ,triv* ...)]
      [(downcast-unsigned ,src ,[BWD-Triv : test] ,nat ,[BWD-Triv : triv])
       `(downcast-unsigned ,src ,test ,nat ,triv)]
      [else (internal-errorf 'BWD-Single "unexpected ir ~s" ir)])
    (BWD-Path-Element : Path-Element (ir) -> Path-Element ()
      [,path-index path-index]
      [(,src ,type ,[BWD-Triv : triv*] ...) `(,src ,type ,triv* ...)])
    (BWD-Triv : Triv (ir) -> Triv ()
      [,var-name
       (hashtable-set! ref-ht var-name #f)
       var-name]
      [else ir])
    )

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
      (define (format-primitive-type primitive-type)
        (define (format-type type)
          (format "(~{~a~^, ~})" (map format-primitive-type (type->primitive-types type))))
        (define (format-adt-arg adt-arg)
          (nanopass-case (Lflattened Public-Ledger-ADT-Arg) adt-arg
            [,nat (format "~d" nat)]
            [,type (format-type type)]))
        (nanopass-case (Lflattened Primitive-Type) primitive-type
          [(tfield) "Field"]
          [(tfield ,nat) (format "Field[~s]" nat)]
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
               (andmap subprimitivetype? primitive-type1* primitive-type2*))))
      (define (subprimitivetype? primitive-type1 primitive-type2)
        (T primitive-type1
           [(tfield)
            (T primitive-type2
               [(tfield) #t])]
           [(tfield ,nat1)
            (T primitive-type2
               [(tfield ,nat2) (<= nat1 nat2)]
               [(tfield) #t]
               ; tfield value 0 of type (tfield 0) is produced by default<Opaque<"type">>
               [(topaque ,opaque-type2) (eqv? nat1 0)]
               ; default<public-adt> is the only value of type public-adt and is represented by 0
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
      (define-syntax check-tfield
        (syntax-rules ()
          [(_ ?what ?type)
           (let ([type ?type])
             (nanopass-case (Lflattened Primitive-Type) type
               [(tfield) #f]
               [(tfield ,nat) nat]
               [else (let ([what ?what])
                       (type-error what
                         (with-output-language (Lflattened Primitive-Type) `(tfield))
                         type))]))]))
      (define (arithmetic-binop op mbits triv1 triv2)
        (let* ([type1 (Triv triv1)] [type2 (Triv triv2)])
          (let ([maybe-nat1 (check-tfield (format "first argument ~s to ~a" triv1 op) type1)]
                [maybe-nat2 (check-tfield (format "second argument ~s to ~a" triv2 op) type2)])
            (unless (or (not mbits)
                        (and (and maybe-nat1 maybe-nat2)
                             (let ([nat (if (equal? op "-") maybe-nat1 (max maybe-nat1 maybe-nat2))])
                               (<= (fxmax 1 (integer-length nat)) mbits))))
              (source-errorf program-src "mismatched mbits ~s and types ~a and ~a for ~s"
                             mbits
                             (format-primitive-type type1)
                             (format-primitive-type type2)
                             op))
            type1)))
      (define (verify-test src test)
        (let ([type (Triv test)])
          (unless (nanopass-case (Lflattened Primitive-Type) type
                    [(tfield ,nat) (<= nat 1)]
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
                          (andmap subprimitivetype? actual-type* type*))
               (source-errorf src "mismatch between actual return types ~a and declared return types ~a in ~a"
                 (map format-primitive-type actual-type*)
                 (map format-primitive-type type*)
                 (symbol->string (id-sym function-name)))))))]
      [else (void)])
    (Statement : Statement (ir) -> * (void)
      [(= ,var-name ,[Single : single -> * type])
       (set-idtype! var-name (Idtype-Base type))]
      [(= (,var-name* ...) (call ,src ,test ,function-name ,[* type*] ...))
       (let ([actual-type* type*])
         (define compatible?
           (let ([nactual (length actual-type*)])
             (lambda (arg-type*)
               (and (= (length arg-type*) nactual)
                    (andmap subprimitivetype? actual-type* arg-type*)))))
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
      [(= (,var-name* ...) (contract-call ,src ,test ,elt-name (,[* type] ,primitive-type) ,[* type*] ...))
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
                            (unless (subprimitivetype? actual-type declared-type)
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
      [(= (,var-name1 ,var-name2) (field->bytes ,src ,test ,len ,[* type]))
       (verify-test src test)
       (check-tfield (format "argument to field->bytes at ~a" (format-source-object src)) type)
       (assert (not (= len 0)))
       (with-output-language (Lflattened Primitive-Type)
         (set-idtype! var-name1 (Idtype-Base `(tfield ,(max 0 (- (expt 2 (* (fxmin (fxmax 0 (fx- len (field-bytes))) (field-bytes)) 8)) 1)))))
         (set-idtype! var-name2 (Idtype-Base `(tfield ,(max 0 (- (expt 2 (* (fxmin len (field-bytes)) 8)) 1))))))]
      [(= (,var-name* ...) (bytes->vector ,[* type]))
       (check-tfield "argument to bytes->vector" type)
       (with-output-language (Lflattened Primitive-Type)
         (for-each
           (lambda (var-name) (set-idtype! var-name (Idtype-Base `(tfield 8))))
           var-name*))]
      [(= (,var-name* ...) (public-ledger ,src ,test ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,adt-op ,[* type^*] ...))
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
                       (andmap subprimitivetype? actual-type* arg-type*)))))
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
      [(< ,mbits ,triv1 ,triv2)
       (let* ([type1 (Triv triv1)] [type2 (Triv triv2)])
         (let ([maybe-nat1 (check-tfield (format "first argument ~s to relational operator" triv1) type1)]
               [maybe-nat2 (check-tfield (format "second argument ~s to relational operator" triv2) type2)])
           (unless (and mbits
                        maybe-nat1
                        maybe-nat2
                        (<= (fxmax 1 (integer-length (max maybe-nat1 maybe-nat2))) mbits))
             (source-errorf program-src "incompatible types ~a and ~a for relational operator"
                (format-primitive-type type1)
                (format-primitive-type type2)))
             (with-output-language (Lflattened Primitive-Type) `(tfield 1))))]
      [(== ,[* type1] ,[* type2])
       (unless (or (subprimitivetype? type1 type2)
                   (subprimitivetype? type2 type1))
        ; the error message say "equality operator" here rather than "==" to avoid misleading
        ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
        (source-errorf program-src "incompatible types ~a and ~a for equality operator"
                 (format-primitive-type type1)
                 (format-primitive-type type2)))
       (with-output-language (Lflattened Primitive-Type) `(tfield 1))]
      [(select ,[* type0] ,[* type1] ,[* type2])
       (unless (nanopass-case (Lflattened Primitive-Type) type0 [(tfield ,nat) (<= nat 1)] [else #f])
         (source-errorf program-src "expected select test to have type Boolean, received ~a"
                 (format-primitive-type type0)))
       (cond
         [(subprimitivetype? type1 type2) type2]
         [(subprimitivetype? type2 type1) type1]
         [else (source-errorf program-src "mismatch between type ~a and type ~a of condition branches"
                       (format-primitive-type type1)
                       (format-primitive-type type2))])
       type1]
      [(bytes-ref ,[* type] ,nat)
       (unless (< nat (field-bytes))
         (source-errorf program-src "expected bytes-ref nat to be less than (field-bytes) but received ~d"
                 nat))
       (check-tfield "bytes-ref argument" type)
       (with-output-language (Lflattened Primitive-Type) `(tfield 255))]
      [(bytes->field ,src ,test ,len ,[* type1] ,[* type2])
       (verify-test src test)
       (nanopass-case (Lflattened Primitive-Type) type1
         [(tfield ,nat) #t]
         [else (source-errorf src "unexpected ~a of first argument to bytes->field"
                              (format-primitive-type type1))])
       (nanopass-case (Lflattened Primitive-Type) type2
         [(tfield ,nat) #t]
         [else (source-errorf src "unexpected ~a of second argument to bytes->field"
                              (format-primitive-type type2))])
       (with-output-language (Lflattened Primitive-Type) `(tfield))]
      [(vector->bytes ,triv ,triv* ...)
       (let* ([triv* (cons triv triv*)] [type* (map Triv triv*)])
         (let ([maybe-nat* (map (lambda (triv type) (check-tfield (format "argument ~a of vector->bytes" triv) type)) triv* type*)])
           (unless (andmap (lambda (maybe-nat) (<= maybe-nat 255)) maybe-nat*)
             (source-errorf program-src "incompatible types (~{~a~^, ~}) for vector->bytes"
               (map format-primitive-type type*)))))
       (with-output-language (Lflattened Primitive-Type) `(tfield ,(- (expt 256 (fx+ (length triv*) 1)) 1)))]
      [(downcast-unsigned ,src ,test ,nat ,[* type])
       (verify-test src test)
       (check-tfield (format "argument to downcast-unsigned at ~a" (format-source-object src)) type)
       (with-output-language (Lflattened Primitive-Type) `(tfield ,nat))]
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
      [,nat (with-output-language (Lflattened Primitive-Type) `(tfield ,nat))])
    )

  (define-passes circuit-passes
    (drop-ledger-runtime             Lposttypescript)
    (replace-enums                   Lnoenums)
    (unroll-loops                    Lunrolled)
    (inline-circuits                 Linlined)
    (drop-safe-casts                 Lnosafecast)
    (resolve-indices/simplify        Lnovectorref)
    (discard-useless-code            Lnovectorref)
    (prune-unnecessary-circuits      Lnovectorref)
    (reduce-to-circuit               Lcircuit)
    (flatten-datatypes               Lflattened)
    (optimize-circuit                Lflattened))

  (define-checker check-types/Linlined Linlined)
  (define-checker check-types/Lflattened Lflattened)
)
