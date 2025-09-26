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
  (export circuit-passes print-Lflattened-passes)
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
               (if (Lnodisclose-Type-Definition? pelt)
                   pelt*
                   (cons (Program-Element pelt) pelt*)))
             '()
             pelt*)
          ...)])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [,typedef (assert cannot-happen)])
    (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
      [(public-ledger-declaration ,[pl-array] ,lconstructor)
       `(public-ledger-declaration ,pl-array)])
    (Public-Ledger-ADT : Public-Ledger-ADT (ir) -> Public-Ledger-ADT ()
      [(,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op*] ...) (,adt-rt-op* ...))
       `(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))])
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
      [(!= ,src ,[type] ,[expr1] ,[expr2]) (do-not src `(== ,src ,type ,expr1 ,expr2))])
    (Type : Type (ir) -> Type ()
      [,tvar-name (assert cannot-happen)]))

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
                      `(upcast ,src (tunsigned ,src ,maxval) (tunsigned ,src ,i) (quote ,src ,i)))
                  (begin
                    (assert (not (null? elt-name*)))
                    (loop (car elt-name*) (cdr elt-name*) (fx+ i 1))))))]
         [else (assert cannot-happen)])]
      [(enum->field ,src ,[type] ,[expr]) `(upcast ,src (tfield ,src) ,type ,expr)])
    (Type : Type (ir) -> Type ()
      [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
       (let ([maxval (length elt-name*)])
         `(tunsigned ,src ,maxval))]))

  (define-pass unroll-loops : Lnoenums (ir) -> Lunrolled ()
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
        (define (tvector->length t)
          (nanopass-case (Lunrolled Type) t
            ; at present the ttuple case isn't reached because map and fold record only vector types
            [(ttuple ,src ,type* ...) (length type*)]
            [(tvector ,src ,nat ,type) nat]
            [else (assert cannot-happen)]))
        )
      [(call ,src ,function-name ,[expr*] ...)
       `(call ,src ,function-name ,expr* ...)]
      [(map ,src ,[type^] ,fun (,[expr] ,[type]) (,[expr*] ,[type*]) ...)
       (maybe-add-flet fun
         (lambda (function-name)
           (let ([gen-id (make-gen-id src)])
             (let* ([t (gen-id type)] [t* (maplr gen-id type*)])
               `(let* ,src ([(,t ,type) ,expr] [(,t* ,type*) ,expr*] ...)
                  (tuple ,src
                    ,(map (lambda (i)
                            `(call ,src ,function-name
                               (tuple-ref ,src (var-ref ,src ,t) ,i)
                               ,(map (lambda (t) `(tuple-ref ,src (var-ref ,src ,t) ,i)) t*)
                               ...))
                       (iota (tvector->length type)))
                    ...))))))]
      [(fold ,src ,type^ ,fun (,[expr0] ,[type0]) (,[expr] ,[type]) (,[expr*] ,[type*]) ...)
       (maybe-add-flet fun
         (lambda (function-name)
           (let ([gen-id (make-gen-id src)])
             (let* ([t0 (gen-id type0)] [t (gen-id type)] [t* (maplr gen-id type*)])
               `(let* ,src ([(,t0 ,type0) ,expr0] [(,t ,type) ,expr] [(,t* ,type*) ,expr*] ...)
                  ,(let ([n (tvector->length type)])
                     (let f ([i 0] [a `(var-ref ,src ,t0)])
                       (if (fx= i n)
                           a
                           (f (fx+ i 1)
                              `(call ,src ,function-name
                                 ,a
                                 (tuple-ref ,src (var-ref ,src ,t) ,i)
                                 ,(map (lambda (t) `(tuple-ref ,src (var-ref ,src ,t) ,i)) t*)
                                 ...))))))))))])
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
      (define (local->name local)
        (nanopass-case (Linlined Local) local
          [(,var-name ,adt-type) var-name]))
      (define (local->adt-type local)
        (nanopass-case (Linlined Local) local
          [(,var-name ,adt-type) adt-type]))
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
           (let-values ([(p var-name*) (extend-env p (map local->name local*))]
                        [(adt-type*) (map local->adt-type local*)])
             `(let* ,src ([(,var-name* ,adt-type*) ,expr*] ...) ,(Expression expr p)))])
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
                 [,edecl (cons (External-Declaration edecl) pelt*)]
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
    (External-Declaration : External-Declaration (ir) -> External-Declaration ())
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
           (nanopass-case (Linlined Public-Ledger-ADT-Type) ty clause ... [else #f])]))
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
      (define (local->name local)
        (nanopass-case (Linlined Local) local
          [(,var-name ,adt-type) var-name]))
      (define (local->adt-type local)
        (nanopass-case (Linlined Local) local
          [(,var-name ,adt-type) adt-type]))
      (define (format-type type)
        (define (format-adt-arg adt-arg)
          (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg
            [,nat (format "~d" nat)]
            [,adt-type (format-type adt-type)]))
        (nanopass-case (Linlined Public-Ledger-ADT-Type) type
          [(tboolean ,src) "Boolean"]
          [(tfield ,src) "Field"]
          [(tunsigned ,src ,nat) (format "Uint<0..~d>" nat)]
          [(topaque ,src ,opaque-type) (format "Opaque<~s>" opaque-type)]
          [(tunknown) "Unknown"]
          [(tvector ,src ,nat ,type) (format "Vector<~s, ~a>" nat (format-type type))]
          [(tbytes ,src ,nat) (format "Bytes<~s>" nat)]
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
          [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
           (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))]))
      (define (sametype? type1 type2)
        (define (same-adt-arg? adt-arg1 adt-arg2)
          (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg1
            [,nat1
             (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg2
               [,nat2 (= nat1 nat2)]
               [else #f])]
            [,adt-type1
             (nanopass-case (Linlined Public-Ledger-ADT-Arg) adt-arg2
               [,adt-type2 (sametype? adt-type1 adt-type2)]
               [else #f])]))
        (T type1
           [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
           [(tfield ,src1) (T type2 [(tfield ,src2) #t])]
           [(tunsigned ,src1 ,nat1) (T type2 [(tunsigned ,src2 ,nat2) (= nat1 nat2)])]
           [(tbytes ,src1 ,nat1) (T type2 [(tbytes ,src2 ,nat2) (= nat1 nat2)])]
           [(topaque ,src1 ,opaque-type1)
            (T type2
               [(topaque ,src2 ,opaque-type2)
                (string=? opaque-type1 opaque-type2)])]
           [(tvector ,src1 ,nat1 ,type1)
            (T type2
               [(tvector ,src2 ,nat2 ,type2)
                (and (= nat1 nat2)
                     (sametype? type1 type2))]
               [(ttuple ,src2 ,type2* ...)
                (and (= nat1 (length type2*))
                     (andmap (lambda (type2) (sametype? type1 type2)) type2*))])]
           [(ttuple ,src1 ,type1* ...)
            (T type2
               [(tvector ,src2 ,nat2 ,type2)
                (and (= (length type1*) nat2)
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
            [(,src1 ,adt-name1 ([,adt-formal1* ,adt-arg1*] ...) ,vm-expr1 (,adt-op1* ...))
             (T type2
                [(,src2 ,adt-name2 ([,adt-formal2* ,adt-arg2*] ...) ,vm-expr2 (,adt-op2* ...))
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
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (build-function 'circuit function-name arg* type)]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (build-function 'witness function-name arg* type)]
      [(public-ledger-declaration ,pl-array) (void)]
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
       (let ([var-name* (map local->name local*)] [adt-type* (map local->adt-type local*)])
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
                     adt-type*
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
      [(default ,src ,adt-type) adt-type]
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
      [(tuple-ref ,src ,expr ,nat)
       (let ([type (Care expr)])
         (nanopass-case (Linlined Type) type
           [(ttuple ,src ,type* ...)
            (let ([nat1 (length type*)])
              (unless (< nat nat1)
                (source-errorf src "index ~s is out-of-bounds for vector of length ~s"
                               nat nat1)))
            (list-ref type* nat)]
           [(tvector ,src1 ,nat1 ,type1)
            (unless (< nat nat1)
              (source-errorf src "index ~s is out-of-bounds for vector of length ~s"
                              nat nat1))
            type1]
           [else
            (source-errorf src "expected vector type, received ~a"
                           (format-type type))]))]
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
       (let ([var-name* (map local->name local*)] [adt-type* (map local->adt-type local*)])
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
                     adt-type*
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
      [(tuple ,src ,[Care : expr* -> * type*] ...)
       (with-output-language (Linlined Type)
         `(ttuple ,src ,type* ...))]
      [(bytes->field ,src ,nat ,[Care : expr -> * type])
       (nanopass-case (Linlined Type) type
         [(tbytes ,src ,nat^)
          (unless (= nat^ nat)
            (source-errorf src "mismatch between Bytes lengths ~s and ~s for bytes->field"
                           nat
                           nat^))]
         [else (source-errorf src "expected Bytes<~d>, got ~a for bytes->field"
                              nat
                              (format-type type))])
       (with-output-language (Linlined Type) `(tfield ,src))]
      [(field->bytes ,src ,nat ,[Care : expr -> * type])
       (check-tfield src "argument to field->bytes" type)
       (with-output-language (Linlined Type) `(tbytes ,src ,nat))]
      [(bytes->vector ,src ,nat ,[Care : expr -> * type])
       (nanopass-case (Linlined Type) type
         [(tbytes ,src ,nat^)
          (unless (= nat^ nat)
            (source-errorf src "mismatch between Bytes lengths ~s and ~s for bytes->vector"
                           nat
                           nat^))])
       (with-output-language (Linlined Type) `(tvector ,src ,nat (tunsigned ,src 255)))]
      [(vector->bytes ,src ,nat ,[Care : expr -> * type])
       (nanopass-case (Linlined Type) type
         [(tvector ,src ,nat^ ,type^)
          (unless (= nat^ nat)
            (source-errorf src "mismatch between Bytes lengths ~s and ~s for vector->bytes"
                           nat
                           nat^))
          (unless (nanopass-case (Linlined Type) type^
                    [(tunsigned ,src^^ ,nat^^) (fx= nat^^ 255)]
                    [else #f])
            (source-errorf src "expected Vector<~d, Uint<8>>, got Vector<~:*~d, ~a> ~a for vector->bytes"
                           nat
                           (format-type type)))])
       (with-output-language (Linlined Type) `(tbytes ,src ,nat))]
      [(field->unsigned ,src ,nat ,[Care : expr -> * type])
       (check-tfield src "argument to field->unsigned" type)
       (with-output-language (Linlined Type) `(tunsigned ,src ,nat))]
      [(downcast-unsigned ,src ,nat ,[Care : expr -> * type] ,safe?)
       (nanopass-case (Linlined Type) type
         [(tunsigned ,src ,nat) (void)]
         [else (source-errorf src "expected Uint, got ~a for downcast-unsigned"
                              (format-type type))])
       (with-output-language (Linlined Type) `(tunsigned ,src ,nat))]
      [(upcast ,src ,type ,type^ ,[Care : expr -> * type^^])
       (unless (sametype? type^^ type^)
         (source-errorf src "expected ~a, got ~a for upcast"
                        (format-type type^)
                        (format-type type^^)))
       type]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[Care : expr* -> * type^*] ...)
       (nanopass-case (Linlined ADT-Op) adt-op
         [(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
          (for-each
            (lambda (adt-type type^ i)
              (unless (sametype? type^ adt-type)
                (source-errorf src "expected ~:r argument of ~s to have type ~a but received ~a"
                               (fx1+ i)
                               ledger-op
                               (format-type adt-type)
                               (format-type type^))))
            adt-type* type^* (enumerate adt-type*))
          adt-type])]
      [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (nanopass-case (Linlined Type) type
         [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
          (let ([adt-type* (map Care expr*)])
            (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
              (if (null? elt-name*)
                (source-errorf src^ "contract ~s has no circuit declaration named ~s"
                               contract-name
                               elt-name)
                (if (eq? (car elt-name*) elt-name)
                  (let ([declared-type* (car type**)])
                    (let ([ndeclared (length declared-type*)] [nactual (length adt-type*)])
                      (unless (fx= nactual ndeclared)
                        (source-errorf src "~s.~s requires ~s argument~:*~p but received ~s"
                                       contract-name elt-name ndeclared nactual)))
                    (for-each
                      (lambda (declared-adt-type actual-adt-type i)
                        (unless (sametype? actual-adt-type declared-adt-type)
                          (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                         (fx1+ i)
                                         contract-name
                                         elt-name
                                         (format-type declared-adt-type)
                                         (format-type actual-adt-type))))
                      declared-type* adt-type* (enumerate declared-type*))
                    (car type*))
                  (loop (cdr elt-name*) (cdr type**) (cdr type*))))))]
         [else (assert cannot-happen)])]
      [else (internal-errorf 'Care "unhandled form Expr-type ~s\n" ir)])
    )

  (define-pass reduce-to-circuit : Linlined (ir) -> Lcircuit ()
    (definitions
      (define fun-ht (make-eq-hashtable))
      (define default-src)
      (define (arg->name arg)
        (nanopass-case (Linlined Argument) arg
          [(,var-name ,type) var-name]))
      (define (Triv expr test bool? k)
        (Rhs expr test bool?
          (lambda (test rhs)
            (if (Lcircuit-Triv? rhs)
                (k rhs)
                (let ([t (make-temp-id default-src 't)])
                  (with-output-language (Lcircuit Statement)
                    (cons
                      `(= ,test ,t ,rhs)
                      (k t))))))))
      (define (Triv* expr* test bool?* k)
        (let f ([expr* expr*] [bool?* bool?*] [rtriv* '()])
          (if (null? expr*)
              (k (reverse rtriv*))
              (Triv (car expr*) test (car bool?*)
                (lambda (triv)
                  (f (cdr expr*) (cdr bool?*) (cons triv rtriv*)))))))
      (define (Path-Element* path-elt* test k)
        (let f ([path-elt* path-elt*] [rpath-elt* '()])
          (if (null? path-elt*)
              (k (reverse rpath-elt*))
              (let ([path-elt (car path-elt*)] [path-elt* (cdr path-elt*)])
                (nanopass-case (Linlined Path-Element) path-elt
                  [,path-index (f path-elt* (cons path-index rpath-elt*))]
                  [(,src ,type ,expr)
                   (Triv expr
                         test
                         (nanopass-case (Linlined Type) type [(tboolean ,src) #t] [else #f])
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
              `(= ,test ,t1 (select #t ,triv ,test (quote #f)))
              `(= ,test ,t2 (select #t ,triv (quote #f) ,test))
              (k t1 t2)))))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       (for-each set-pelt-bool-flags! pelt*)
       `(program ,src ((,export-name* ,name*) ...) ,(map Program-Element pelt*) ...)])
    (set-pelt-bool-flags! : Program-Element (ir) -> * (void)
      (definitions
        (define (set-flags! function-name arg*)
          (hashtable-set! fun-ht function-name
            (map (lambda (arg)
                   (nanopass-case (Linlined Argument) arg
                     [(,var-name (tboolean ,src)) #t]
                     [else #f]))
                 arg*))))
      [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
       ; circuit definitions have been fully inlined, so no refs remain
       (void)]
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (set-flags! function-name arg*)]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (set-flags! function-name arg*)]
      [(public-ledger-declaration ,pl-array)
       (void)]
      [(kernel-declaration ,public-binding)
       (void)])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,expr)
       (fluid-let ([default-src src])
         (let ([triv #f])
           (let ([stmt* (Triv expr
                          (with-output-language (Lcircuit Triv) `(quote #t))
                          #f
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
           (nanopass-case (Linlined Local) local
             [(,var-name ,adt-type)
              (Rhs expr test
                (nanopass-case (Linlined Public-Ledger-ADT-Type) adt-type [(tboolean ,src) #t] [else #f])
                (lambda (test rhs)
                  (cons
                    (with-output-language (Lcircuit Statement)
                      `(= ,test ,var-name ,rhs))
                    stmt*)))]))
         (Statement expr test stmt*)
         local*
         expr*)]
      [(if ,src ,expr0 ,expr1 ,expr2)
       ; we could let the Triv call below handle "if" via Rhs, but we handle
       ; Statement "if" directly here to avoid the generation of a select with
       ; possibly mismatched branch types, which could cause trouble downstream.
       (Triv expr0 test #t
         (lambda (triv0)
           (add-test src test triv0
             (lambda (test1 test2)
               (Statement expr1 test1
                 (Statement expr2 test2 stmt*))))))]
      [else
       (Triv ir test #f
         (lambda (triv)
           ; dropping triv here, since it has no effect
           stmt*))])
    (Rhs : Expression (ir test bool? k) -> * (stmt*)
      [(seq ,src ,expr* ... ,expr)
       (fold-right
         (lambda (expr stmt*) (Statement expr test stmt*))
         (Rhs expr test bool? k)
         expr*)]
      [(if ,src ,expr0 ,expr1 ,expr2)
       (Triv expr0 test #t
         (lambda (triv0)
           (add-test src test triv0
             (lambda (test1 test2)
               (Triv expr1 test1 bool?
                 (lambda (triv1)
                   (Triv expr2 test2 bool?
                     (lambda (triv2)
                       (k test
                          (with-output-language (Lcircuit Rhs)
                            `(select ,bool? ,triv0 ,triv1 ,triv2)))))))))))]
      [(let* ,src ([,local* ,expr*] ...) ,expr)
       (let f ([local* local*] [expr* expr*])
         (if (null? local*)
             (Rhs expr test bool? k)
             (nanopass-case (Linlined Local) (car local*)
               [(,var-name ,adt-type)
                (Rhs (car expr*) test
                  (nanopass-case (Linlined Public-Ledger-ADT-Type) adt-type [(tboolean ,src) #t] [else #f])
                  (lambda (test rhs)
                    (cons
                      (with-output-language (Lcircuit Statement)
                        `(= ,test ,var-name ,rhs))
                      (f (cdr local*) (cdr expr*)))))])))]
      [(call ,src ,function-name ,expr* ...)
       (let ([bool?* (or (hashtable-ref fun-ht function-name #f)
                         (assert cannot-happen))])
         (Triv* expr* test bool?*
           (lambda (triv*)
             (k test
                (with-output-language (Lcircuit Rhs)
                  `(call ,src ,function-name ,triv* ...))))))]
      [(assert ,src ,expr ,mesg)
       (Triv expr test #t
         (lambda (triv)
           (let ([t1 (make-temp-id src 't)] [t2 (make-temp-id src 't)])
             (with-output-language (Lcircuit Statement)
               (cons*
                 `(= ,test ,t1 (select #t ,test (quote #f) (quote #t)))
                 `(= ,test ,t2 (select #t ,triv (quote #t) ,t1))
                 ; TODO: simpler equivalent form isn't optimized as well by optimize-circuit
                 ; `(= ,t1 (select #t ,test ,triv (quote #t)))
                 `(assert ,src ,t2 ,mesg)
                 (k test
                    (with-output-language (Lcircuit Rhs)
                      `(tuple))))))))]
      [(quote ,src ,datum)
       (k test
          (with-output-language (Lcircuit Rhs)
            `(quote ,datum)))]
      [(var-ref ,src ,var-name)
       (k test var-name)]
      [(default ,src ,[adt-type])
       (k test
          (with-output-language (Lcircuit Rhs)
            `(default ,adt-type)))]
      [(+ ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test #f
         (lambda (triv1)
           (Triv expr2 test #f
             (lambda (triv2)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(+ ,mbits ,triv1 ,triv2)))))))]
      [(- ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test #f
         (lambda (triv1)
           (Triv expr2 test #f
             (lambda (triv2)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(- ,mbits ,triv1 ,triv2)))))))]
      [(* ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test #f
         (lambda (triv1)
           (Triv expr2 test #f
             (lambda (triv2)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(* ,mbits ,triv1 ,triv2)))))))]
      [(< ,src ,mbits ,expr1 ,expr2)
       (Triv expr1 test #f
         (lambda (triv1)
           (Triv expr2 test #f
             (lambda (triv2)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(< ,mbits ,triv1 ,triv2)))))))]
      [(== ,src ,type ,expr1 ,expr2)
       (Triv expr1 test #f
         (lambda (triv1)
           (Triv expr2 test #f
             (lambda (triv2)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(== ,triv1 ,triv2)))))))]
      [(new ,src ,[type] ,expr* ...)
       (Triv* expr* test (map (lambda (x) #f) expr*)
         (lambda (triv*)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(new ,type ,triv* ...)))))]
      [(elt-ref ,src ,expr ,elt-name)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(elt-ref ,triv ,elt-name)))))]
      [(tuple ,src ,expr* ...)
       (Triv* expr* test (map (lambda (x) #f) expr*)
         (lambda (triv*)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(tuple ,triv* ...)))))]
      [(tuple-ref ,src ,expr ,nat)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(tuple-ref ,triv ,nat)))))]
      [(bytes->field ,src ,nat ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(bytes->field ,src ,nat ,triv)))))]
      [(field->bytes ,src ,nat ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(field->bytes ,src ,nat ,triv)))))]
      [(bytes->vector ,src ,nat ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(bytes->vector ,src ,nat ,triv)))))]
      [(vector->bytes ,src ,nat ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(vector->bytes ,src ,nat ,triv)))))]
      [(field->unsigned ,src ,nat ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(field->unsigned ,src ,nat ,triv)))))]
      [(downcast-unsigned ,src ,nat ,expr ,safe?)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(downcast-unsigned ,src ,nat ,triv ,safe?)))))]
      [(upcast ,src ,[type] ,[type^] ,expr)
       (Triv expr test #f
         (lambda (triv)
           (k test
              (with-output-language (Lcircuit Rhs)
                `(upcast ,src ,type ,type^ ,triv)))))]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,[adt-op] ,expr* ...)
       (Path-Element* path-elt* test
         (lambda (path-elt*)
           ; FIXME: should compute bool? by looking at adt-op adt-types
           (Triv* expr* test (map (lambda (x) #f) expr*)
             (lambda (triv*)
               (k test
                  (with-output-language (Lcircuit Rhs)
                    `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...)))))))]
      [(contract-call ,src ,elt-name (,expr ,[type]) ,expr* ...)
       ; FIXME: should compute bool? by looking at elt-name parameter types
       (Triv expr test #f
         (lambda (triv)
           (Triv* expr* test (map (lambda (x) #f) expr*)
             (lambda (triv*)
               (k test
                 (with-output-language (Lcircuit Rhs)
                   `(contract-call ,src ,elt-name (,triv ,type) ,triv* ...)))))))]
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
        (Wump-empty)
        )
      (define wump->elts
        (case-lambda
          [(wump) (wump->elts wump '())]
          [(wump elt*)
           (Wump-case wump
             [(Wump-single elt) (cons elt elt*)]
             [(Wump-vector wump*) (fold-right wump->elts elt* wump*)]
             [(Wump-bytes elt^*) (append elt^* elt*)]
             [(Wump-struct elt-name* wump*) (fold-right wump->elts elt* wump*)]
             [(Wump-empty) elt*])]))
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
                 accum))]
            [(Wump-empty) (values wump accum)])))
      (define (Single-Triv triv)
        (let ([triv* (wump->elts (Triv triv))])
          (assert (fx= (length triv*) 1))
          (car triv*)))
      (define (build-type original-type pt*)
        (define (type->alignments type)
          (let f ([type type] [a* '()])
            (with-output-language (Lflattened Alignment)
              (nanopass-case (Lcircuit Public-Ledger-ADT-Type) type
                [(tboolean ,src) (cons `(abytes 1) a*)]
                [(tfield ,src) (cons `(afield) a*)]
                [(tunsigned ,src ,nat) (cons `(abytes ,(ceiling (/ (bitwise-length nat) 8))) a*)]
                [(tbytes ,src ,nat) (cons `(abytes ,nat) a*)]
                [(topaque ,src ,opaque-type) (cons `(acompress) a*)]
                [(tvector ,src ,nat ,type)
                 (let ([a^* (f type '())])
                   (do ([nat nat (- nat 1)] [a* a* (append a^* a*)])
                       ((eqv? nat 0) a*)))]
                [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ... )
                 ; FIXME: acontract?
                 (cons `(acontract) a*)]
                [(ttuple ,src ,type* ...)
                 (fold-right f a* type*)]
                [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                 (fold-right f a* type*)]
                [(tunknown) (assert cannot-happen)]
                [,public-adt (cons `(aadt) a*)]))))
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
       ; like map but arranges to process external declarations first
       ; so that their fun-ht entries are available before processing
       ; any circuits
       `(program ,src ((,export-name* ,name*) ...)
          ,(let f ([pelt* pelt*])
             (if (null? pelt*)
               '()
               (let ([pelt (car pelt*)] [pelt* (cdr pelt*)])
                 (cond
                   [(Lcircuit-External-Declaration? pelt)
                    (let ([pelt (External-Declaration pelt)])
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
    (External-Declaration : External-Declaration (ir) -> External-Declaration ()
      [(external ,src ,function-name ,native-entry ((,var-name* ,[Type->Wump : type* -> * wump*]) ...) ,[Type->Wump : type -> * wump])
       (let ([arg* (map do-argument var-name* type* wump*)] [primitive-type* (wump->elts wump)])
         (hashtable-set! fun-ht function-name wump)
         `(external ,src ,function-name ,native-entry (,arg* ...) ,(build-type type primitive-type*)))])
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
    (Public-Ledger-ADT : Public-Ledger-ADT (ir) -> Public-Ledger-ADT ())
    (ADT-Op : ADT-Op (ir) -> ADT-Op ()
      [(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,[adt-arg*]) ...) ((,var-name* ,[Type : adt-type* -> type*]) ...) ,[Type : adt-type -> type] ,vm-code)
       `(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,(map id-sym var-name*) ...) (,type* ...) ,type ,vm-code)])
    (Type->Wump : Public-Ledger-ADT-Type (ir) -> * (wump) ; produces a wump of Primitive-Types
      [(tvector ,src ,nat ,[Type->Wump : type -> * wump])
       (Wump-vector (make-list nat wump))]
      [(tbytes ,src ,nat)
       (Wump-bytes
         (with-output-language (Lflattened Primitive-Type)
           (let-values ([(q r) (div-and-mod nat (field-bytes))])
             (let ([ls (make-list q `(tfield ,(- (expt 2 (* (field-bytes) 8)) 1)))])
               (if (fx= r 0) ls (cons `(tfield ,(max 0 (- (expt 2 (* r 8)) 1))) ls))))))]
      [(ttuple ,src ,[Type->Wump : type* -> * wump*] ...)
       (Wump-vector wump*)]
      [(tstruct ,src ,struct-name (,elt-name* ,[Type->Wump : type -> * wump*]) ...)
       (Wump-struct elt-name* wump*)]
      [(tunknown) (Wump-empty)] ; not exercised
      [else (Wump-single (Single-Type ir))])
    (Type : Public-Ledger-ADT-Type (ir) -> Type ()
      [else (build-type ir (wump->elts (Type->Wump ir)))])
    (Single-Type : Public-Ledger-ADT-Type (ir) -> Primitive-Type ()
      [(tboolean ,src) `(tfield 1)]
      [(tfield ,src) `(tfield)]
      [(tunsigned ,src ,nat) `(tfield ,nat)]
      [(topaque ,src ,opaque-type) `(topaque ,opaque-type)]
      [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,[Type : type**] ...) ,[Type : type*]) ...)
       `(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)]
      [,public-adt (Public-Ledger-ADT public-adt)])
    (Statement : Statement (ir) -> * (stmt*)
      [(= ,[Single-Triv : test] ,var-name ,rhs) (Rhs rhs test var-name)]
      [(assert ,src ,[Single-Triv : test] ,mesg)
       (with-output-language (Lflattened Statement)
         (list `(assert ,src ,test ,mesg)))])
    (Rhs : Rhs (ir test var-name) -> * (stmt*)
      [,triv
       (hashtable-set! var-ht var-name (Triv triv))
       '()]
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
      [(< ,mbits ,[Single-Triv : triv1] ,[Single-Triv : triv2])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,test ,var-name (< ,mbits ,triv1 ,triv2))))]
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
                          `(= ,test ,t2 (select #t ,triv-accum ,t1 0))
                          (f (cdr triv1*) (cdr triv2*) t2)))))))]
      [(select ,bool? ,[Single-Triv : triv0] ,[* wump1] ,[* wump2])
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
                    `(= ,test ,var-name (select ,bool? ,triv0 ,triv1 ,triv2))))
                var-name* triv1* triv2*)))]
      [(tuple ,[* wump*] ...)
       (hashtable-set! var-ht var-name (Wump-vector wump*))
       '()]
      [(tuple-ref ,[* wump] ,nat)
       (hashtable-set! var-ht var-name
         (Wump-case wump
           [(Wump-vector wump*) (list-ref wump* nat)]
           [else (assert cannot-happen)]))
       '()]
      [(new ,type ,[* wump*] ...)
       (nanopass-case (Lcircuit Type) type
         [(tstruct ,src ,struct-name (,elt-name* ,type) ...)
          (hashtable-set! var-ht var-name (Wump-struct elt-name* wump*))]
         [else (assert cannot-happen)])
       '()]
      [(bytes->field ,src ,nat ,[* wump])
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
                          `(= ,test ,var-name^ (== ,triv 0))
                          `(assert ,src ,var-name^ "bytes value is too big to fit in a field")
                          ls))))
                  (let-values ([(triv1 triv2) (apply values (list-tail triv* n))])
                    (with-output-language (Lflattened Statement)
                      (list `(= ,test ,var-name (bytes->field ,src ,nat ,triv1 ,triv2)))))
                  (list-head triv* n)))])))]
      [(field->bytes ,src ,nat ,[Single-Triv : triv])
       (let ([var-name1 (make-new-id var-name)]
             [var-name2 (make-new-id var-name)])
         (hashtable-set! var-ht var-name
           (Wump-bytes
             (let ()
               (define (f nat ls)
                 (if (<= nat 0)
                     ls
                     (f (- nat (field-bytes)) (cons 0 ls))))
               (if (fx<= nat (field-bytes))
                   (list var-name2)
                   (f (- nat (fx* 2 (field-bytes))) (list var-name1 var-name2))))))
         (with-output-language (Lflattened Statement)
           (list `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,nat ,triv)))))]
      [(bytes->vector ,src ,nat ,[* wump])
       (let loop ([nat nat] [triv* (reverse (wump->elts wump))] [var-name* '()] [stmt* '()])
         (if (fx= nat 0)
             (begin
               (hashtable-set! var-ht var-name (Wump-vector (map Wump-single var-name*)))
               stmt*)
             (let* ([n (fxmin nat (field-bytes))]
                    [this-var-name* (make-new-ids var-name n)])
               (loop (fx- nat n)
                     (cdr triv*)
                     (append this-var-name* var-name*)
                     (with-output-language (Lflattened Statement)
                       (cons `(= ,test (,this-var-name* ...) (bytes->vector ,src ,(car triv*)))
                             stmt*))))))]
      [(vector->bytes ,src ,nat ,[* wump])
       (let loop ([nat nat] [triv* (reverse (wump->elts wump))] [var-name* '()] [stmt* '()])
         (if (fx= nat 0)
             (begin
               (hashtable-set! var-ht var-name (Wump-bytes var-name*))
               stmt*)
             (let* ([n (fxmin nat (field-bytes))] [this-var-name (make-new-id var-name)])
               (loop (fx- nat n)
                     (list-tail triv* n)
                     (cons this-var-name var-name*)
                     (let ([this-var-name* (reverse (list-head triv* n))])
                       (with-output-language (Lflattened Statement)
                         (cons `(= ,test ,this-var-name (vector->bytes ,src ,(car this-var-name*) ,(cdr this-var-name*) ...))
                             stmt*)))))))]
      [(field->unsigned ,src ,nat ,[Single-Triv : triv])
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,test ,var-name (downcast-unsigned ,src ,nat ,triv #f))))]
      [(downcast-unsigned ,src ,nat ,[Single-Triv : triv] ,safe?)
       (hashtable-set! var-ht var-name (Wump-single var-name))
       (with-output-language (Lflattened Statement)
         (list `(= ,test ,var-name (downcast-unsigned ,src ,nat ,triv ,safe?))))]
      [(upcast ,src ,type ,type^ ,triv)
       (hashtable-set! var-ht var-name (Triv triv))
       '()]
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
                         [(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
                          (Type->Wump adt-type)]))])
         (hashtable-set! var-ht var-name wump)
         (let ([triv* (fold-right wump->elts '() actual-wump*)])
           (with-output-language (Lflattened Statement)
             (list `(= ,test
                       (,var-name* ...)
                       (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op^ ,triv* ...))))))]
      [(contract-call ,src ,elt-name (,[Single-Triv : triv] ,type) ,[* wump*] ...)
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
             (list `(= ,test
                       (,var-name* ...)
                       (contract-call ,src ,elt-name (,triv ,(Single-Type type)) ,triv* ...))))))]
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
      [(default ,adt-type)
       (let dowump ([adt-type adt-type])
         (nanopass-case (Lcircuit Public-Ledger-ADT-Type) adt-type
           [(tboolean ,src) (Wump-single 0)]
           [(tfield ,src) (Wump-single 0)]
           [(tunsigned ,src ,nat) (Wump-single 0)]
           [(tbytes ,src ,nat)
            (Wump-bytes
              (make-list
                (quotient (+ nat (- (field-bytes) 1)) (field-bytes))
                0))]
           [(topaque ,src ,opaque-type) (Wump-single 0)]
           [(tvector ,src ,nat ,type)
            (Wump-vector (make-list nat (dowump type)))]
           [(ttuple ,src ,type* ...)
            (Wump-vector (map dowump type*))]
           [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
            (Wump-struct elt-name* (map dowump type*))]
           [,public-adt (Wump-single 0)]
           [else (assert cannot-happen)]))]
      [else (assert cannot-happen)])
    (Path-Element : Path-Element (ir) -> Path-Element ()
      [,path-index path-index]
      [(,src ,type ,triv) `(,src ,(Type type) ,(wump->elts (Triv triv)) ...)]))

  ;;; propagate copies
  ;;; eliminate unused bindings
  ;;; eliminate pure forms in effect context
  ;;; eliminate common subexpressions
  ;;; paritially fold operators, e.g., (+ x 0) -> x
  ;;; simplify nested operations, e.g., (not (not x)) -> x, (or x (not x)) => #t
  ;;; drop asserts that can never fail
  (define-pass optimize-circuit : Lflattened (ir) -> Lflattened ()
    (definitions
      (module (triv-equal? nontriv-single-equal? nat.triv-equal? assert-equal?)
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
             [(select ,bool? ,triv0 ,triv1 ,triv2) (select ,bool?^ ,triv0^ ,triv1^ ,triv2^)
              (and (eq? bool? bool?^)
                   (trivs-equal? triv0 triv0^ triv1 triv1^ triv2 triv2^))]
             [(bytes->field ,src ,nat ,triv1 ,triv2) (bytes->field ,src^ ,nat^ ,triv1^ ,triv2^)
              (and (eqv? nat nat^)
                   (trivs-equal? triv1 triv1^ triv2 triv2^))]
             [(downcast-unsigned ,src ,nat ,triv ,safe?) (downcast-unsigned ,src^ ,nat^ ,triv^ ,safe?^)
              (and (eqv? nat nat^)
                   (eqv? safe? safe?^)
                   (triv-equal? triv triv^))]))
        (define (nat.triv-equal? p1 p2)
          (and (eqv? (car p1) (car p2))
               (triv-equal? (cdr p1) (cdr p2))))
        (define (assert-equal? p1 p2)
          (and (triv-equal? (car p1) (car p2))
               (string=? (cdr p1) (cdr p2)))))
      ; single-hash is adapted from Chez Scheme equal-hash
      ; Copyright 1984-2017 Cisco Systems Inc. and licensed under Apache Version 2.0
      (module (nontriv-single-hash nat.triv-hash assert-hash)
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
            [(select ,bool? ,triv0 ,triv1 ,triv2)
             (triv-hash triv0
               (triv-hash triv1
                 (triv-hash triv2
                   (if bool? 281730407 729589248))))]
            [(bytes->field ,src ,nat ,triv1 ,triv2)
             (triv-hash triv1
               (triv-hash triv2
                 (triv-hash nat 536285952)))]
            [(vector->bytes ,src ,triv ,triv* ...)
             (fold-left (lambda (hc triv) (triv-hash triv hc))
               729589248
               (cons triv triv*))]
            [(downcast-unsigned ,src ,nat ,triv ,safe?)
             (triv-hash triv
               (triv-hash nat (if safe? 631426763 314267636)))]
            [else (internal-errorf 'single-hash "unhandled form ~s" single)]))
        (define (nat.triv-hash p)
          (nat-hash (car p) (triv-hash (cdr p) 883823588)))
        (define (assert-hash p)
          (triv-hash (car p) (update 398346201 (string-hash (cdr p))))))
      (define var->triv (make-eq-hashtable))
      (define var->nontriv-single (make-eq-hashtable))
      (define nontriv-single->var (make-hashtable nontriv-single-hash nontriv-single-equal?))
      (define ref-ht (make-eq-hashtable))
      (define fbexpr->vars (make-hashtable nat.triv-hash nat.triv-equal?))
      (define bvexpr->vars (make-hashtable nat.triv-hash nat.triv-equal?))
      (define assert-ht (make-hashtable assert-hash assert-equal?))
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
         `(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...)))]
      [else (internal-errorf 'Circuit-Definition "unexpected ir ~s" ir)])
    (FWD-Statement : Statement (ir rstmt*) -> * (rstmt*)
      ; NB. BWD-Statement must eliminate all statements whose conditional-executation
      ; flag (test) is the constant 0. if it does so only sometimes or for some
      ; forms, the circuit can contain references to unbound variables (uses of wires
      ; that don't exist).
      [(= ,[FWD-Triv : test] ,var-name ,single)
       (if (eqv? test 0)
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
               (cons `(= ,test ,var-name ,single) rstmt*))))]
      [(= ,[FWD-Triv : test] (,var-name* ...) ,multiple)
       (if (eqv? test 0)
           (begin
             (for-each (lambda (var-name) (hashtable-set! var->triv var-name 0) (undefined! var-name)) var-name*)
             rstmt*)
           (FWD-Multiple multiple test var-name* rstmt*))]
      [(assert ,src ,[FWD-Triv : test^ -> test] ,mesg)
       ; NB. Similarly, BWD-Statement must eliminate all asserts whose test is 1 or
       ; whose test is an undefined variable, which can occur only if the assert itself
       ; is in a part of the circuit that is never enabled.
       (if (or (eqv? test 1) (undefined? test^))
           rstmt*
           (with-output-language (Lflattened Statement)
             (let ([a (hashtable-cell assert-ht (cons test mesg) #f)])
               (if (cdr a)
                   rstmt*
                   (begin
                     (set-cdr! a #t)
                     (cons `(assert ,src ,test ,mesg) rstmt*))))))]
      [else (internal-errorf 'FWD-Statement "unexpected ir ~s" ir)])
    (FWD-Multiple : Multiple (ir test var-name* rstmt*) -> * (rstmt*)
      [(call ,src ,function-name ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= ,test (,var-name* ...) (call ,src ,function-name ,triv* ...)) rstmt*))]
      [(contract-call ,src ,elt-name (,triv ,primitive-type) ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= ,test (,var-name* ...) (contract-call ,src ,elt-name (,triv ,primitive-type) ,triv* ...)) rstmt*))]
      [(field->bytes ,src ,nat ,[FWD-Triv : triv])
       (assert (fx= (length var-name*) 2))
       (with-output-language (Lflattened Statement)
         (let ([var-name1 (car var-name*)] [var-name2 (cadr var-name*)])
           (or (ifconstant triv
                 (lambda (nat^)
                   (and (< nat^ (expt 2 (* 8 nat)))
                        (let-values ([(q r) (div-and-mod nat^ (expt 2 (* 8 (field-bytes))))])
                          (hashtable-set! var->triv var-name1 q)
                          (hashtable-set! var->triv var-name2 r)
                          rstmt*))))
               (let ([a (hashtable-cell fbexpr->vars (cons nat triv) #f)])
                 (cond
                   [(cdr a) =>
                    (lambda (vars)
                      (hashtable-set! var->triv var-name1 (car vars))
                      (hashtable-set! var->triv var-name2 (cdr vars))
                      rstmt*)]
                   [else
                    (set-cdr! a (cons var-name1 var-name2))
                    (cons `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,nat ,triv)) rstmt*)])))))]
      [(bytes->vector ,src ,[FWD-Triv : triv])
       (with-output-language (Lflattened Statement)
         (or (ifconstant triv
               (lambda (bytes)
                 (fold-right
                   (lambda (var-name bytes)
                     (let-values ([(q r) (div-and-mod bytes 256)])
                       (hashtable-set! var->triv var-name r)
                       q))
                   bytes
                   var-name*)
                 rstmt*))
             (let ([a (hashtable-cell bvexpr->vars (cons (length var-name*) triv) #f)])
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
                  (cons `(= ,test (,var-name* ...) (bytes->vector ,src ,triv)) rstmt*)]))))]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,[FWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[FWD-Triv : triv*] ...)
       (with-output-language (Lflattened Statement)
         (cons `(= ,test
                   (,var-name* ...)
                   (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
               rstmt*))])
    (FWD-Single : Single (ir) -> Single ()
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
                [(select ,bool? ,triv0 ,nat1 ,nat2)
                 (guard (and bool? (eqv? nat1 0) (eqv? nat2 1)))
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
      [(select ,bool? ,[FWD-Triv : triv0] ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
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
                     [(select ,bool?^ ,triv0^ ,triv1^ ,triv2^)
                      (maybe-fold (f (subst triv0^) val0) (f (subst triv1^) val0) (f (subst triv2^) val0))]
                     [else #f])))
               triv))
         (let ([triv1 (f triv1 1)] [triv2 (f triv2 0)])
           (or (maybe-fold triv0 triv1 triv2)
               `(select ,bool? ,triv0 ,triv1 ,triv2))))]
      [(bytes->field ,src ,nat ,[FWD-Triv : triv1] ,[FWD-Triv : triv2])
       (or (ifconstant triv1
             (lambda (nat1)
               (ifconstant triv2
                 (lambda (nat2)
                   (let ([x (+ (bitwise-arithmetic-shift-left nat1 (* 8 (field-bytes))) nat2)])
                     (and (<= x (max-field)) x))))))
           `(bytes->field ,src ,nat ,triv1 ,triv2))]
      [(vector->bytes ,src ,[FWD-Triv : triv] ,[FWD-Triv : triv*] ...)
       (let-values ([(triv triv*) (let trim-leading-zeros ([triv triv] [triv* triv*])
                                    (if (and (not (null? triv*))
                                             (nanopass-case (Lflattened Triv) triv
                                               [,nat (eqv? nat 0)]
                                               [else #f]))
                                        (trim-leading-zeros (car triv*) (cdr triv*))
                                        (values triv triv*)))])
         (or (ifconstant triv
               (lambda (u8)
                 (ifconstants triv*
                   (lambda (u8*)
                     (do ([u8* u8* (cdr u8*)]
                          [bytes u8 (+ (ash bytes 8) (car u8*))])
                       ((null? u8*) bytes))))))
             `(vector->bytes ,src ,triv ,triv* ...)))]
      [(downcast-unsigned ,src ,nat ,[FWD-Triv : triv] ,safe?)
       (or (ifconstant triv
             (lambda (nat^)
               (and (<= nat^ nat) nat^)))
           `(downcast-unsigned ,src ,nat ,triv ,safe?))]
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
            [(select ,bool? ,triv0 ,triv1 ,triv2) #t]
            ; downcast asserts with maximum value check
            ; TODO: could discard when nat is small enough that the operation cannot fail
            [(bytes->field ,src ,nat ,triv1 ,triv2) #f]
            ; downcast asserts with maximum value check
            [(vector->bytes ,src ,triv ,triv* ...) #t]
            [(downcast-unsigned ,src ,nat ,triv ,safe?) safe?])))
      [(= ,test ,var-name ,single)
       (guard
         (not (hashtable-contains? ref-ht var-name))
         (pure? single))
       ; discard without processing any of the subexpressions to avoid marking any variables referenced
       stmt*]
      ; consider enabling:
      ; [(= ,test ,var-name ,single)
      ;  ; (harmless-for-all-inputs? single) should be true iff evaluating single cannot cause
      ;  ; an error regardless of the input values, which might not be defined
      ;  (guard (harmless-for-all-inputs? single))
      ;  ; replace test with 1 without processing test to avoid marking it referenced if it is a var
      ;  (cons `(= 1 ,var-name ,(BWD-Single single)) stmt*)]
      [(= ,[BWD-Triv : test] ,var-name ,[BWD-Single : single])
       (cons `(= ,test ,var-name ,single) stmt*)]
      [(= ,[BWD-Triv : test] (,var-name* ...) (call ,src ,function-name ,[BWD-Triv : triv*] ...))
       (cons `(= ,test (,var-name* ...) (call ,src ,function-name ,triv* ...)) stmt*)]
      [(= ,[BWD-Triv : test] (,var-name* ...) (contract-call ,src ,elt-name (,triv ,primitive-type) ,[BWD-Triv : triv*] ...))
       (cons `(= ,test (,var-name* ...) (contract-call ,src ,elt-name (,triv ,primitive-type) ,triv* ...)) stmt*)]
      [(= ,[BWD-Triv : test] (,var-name1 ,var-name2) (field->bytes ,src ,nat ,[BWD-Triv : triv]))
       ; TODO: could discard when nat is large enough that the operation cannot fail
       (cons `(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,nat ,triv)) stmt*)]
      [(= ,[BWD-Triv : test] (,var-name* ...) (bytes->vector ,src ,[BWD-Triv : triv]))
       (if (ormap (lambda (var-name) (hashtable-contains? ref-ht var-name)) var-name*)
           (cons `(= ,test (,var-name* ...) (bytes->vector ,src ,triv)) stmt*)
           stmt*)]
      [(= ,[BWD-Triv : test] (,var-name* ...)
          (public-ledger ,src ,ledger-field-name ,sugar? (,[BWD-Path-Element : path-elt*] ...) ,src^ ,adt-op ,[BWD-Triv : triv*] ...))
       (cons `(= ,test
                 (,var-name* ...)
                 (public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,triv* ...))
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
      [(select ,bool? ,[BWD-Triv : triv0] ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
       `(select ,bool? ,triv0 ,triv1 ,triv2)]
      [(bytes->field ,src ,nat ,[BWD-Triv : triv1] ,[BWD-Triv : triv2])
       `(bytes->field ,src ,nat ,triv1 ,triv2)]
      [(vector->bytes ,src ,[BWD-Triv : triv] ,[BWD-Triv : triv*] ...)
       `(vector->bytes ,src ,triv ,triv* ...)]
      [(downcast-unsigned ,src ,nat ,[BWD-Triv : triv] ,safe?)
       `(downcast-unsigned ,src ,nat ,triv ,safe?)]
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
      (module (set-idtype! unset-idtype! get-idtype)
        (define ht (make-eq-hashtable))
        (define (set-idtype! id idtype)
          (hashtable-set! ht id idtype))
        (define (unset-idtype! id)
          (hashtable-delete! ht id))
        (define (get-idtype id)
          (or (hashtable-ref ht id #f)
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
      (define (format-type type)
        (define (format-adt-arg adt-arg)
          (nanopass-case (Lflattened Public-Ledger-ADT-Arg) adt-arg
            [,nat (format "~d" nat)]
            [,type (format "(~{~a~^, ~})" (map format-type (type->primitive-types type)))]))
        (nanopass-case (Lflattened Primitive-Type) type
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
          [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
           (format "~s~@[<~{~a~^, ~}>~]" adt-name (and (not (null? adt-arg*)) (map format-adt-arg adt-arg*)))]
          [else (internal-errorf 'format-type "unexpected primitive type ~s" type)]))
      (define (subtype? type1 type2)
        (T type1
           [(tfield)
            (T type2
               [(tfield) #t])]
           [(tfield ,nat1)
            (T type2
               [(tfield ,nat2) (<= nat1 nat2)]
               [(tfield) #t]
               ; tfield value 0 of type (tfield 0) is produced by default<Opaque<"type">>
               [(topaque ,opaque-type2) (eqv? nat1 0)]
               ; default<public-adt> is the only value of type public-adt and is represented by 0
               [,public-adt (eqv? nat1 0)])]
           [(topaque ,opaque-type1)
            (T type2
               [(topaque ,opaque-type2)
                (string=? opaque-type1 opaque-type2)])]
           [(tcontract ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
            (T type2
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
           [,public-adt1
            (T type2
               [,public-adt2 #t])]))
      (define (type-error what declared-type type)
        (source-errorf program-src "mismatch between actual type ~a and expected type ~a for ~a"
          (format-type type)
          (format-type declared-type)
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
                             (<= (fxmax 1 (integer-length (max maybe-nat1 maybe-nat2))) mbits)))
              (source-errorf program-src "mismatched mbits ~s and type ~a for ~s"
                    mbits
                    (format-type type1)
                    op))
            type1)))
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
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
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
       (let ([id* (apply append (map arg->names arg*))]
             [arg-type* (apply append (map arg->types arg*))]
             [type* (type->primitive-types type)])
         (for-each (lambda (id type) (set-idtype! id (Idtype-Base type))) id* arg-type*)
         (for-each Statement stmt*)
         (let ([actual-type* (map Triv triv*)])
           (unless (and (fx= (length actual-type*) (length type*))
                        (andmap subtype? actual-type* type*))
             (source-errorf src "mismatch between actual return types ~a and declared return types ~a in ~a"
               (map format-type actual-type*)
               (map format-type type*)
               (symbol->string (id-sym function-name))))))]
      [else (void)])
    (Statement : Statement (ir) -> * (void)
      (definitions
        (define (verify-test src test)
          (let ([type (Triv test)])
            (unless (nanopass-case (Lflattened Primitive-Type) type
                      [(tfield ,nat) (<= nat 1)]
                      [else #f])
              (source-errorf src
                             "expected test to have type Boolean, received ~a"
                             (format-type type))))))
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
                    (andmap subtype? actual-type* arg-type*)))))
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
                (map format-type actual-type*)
                (format-source-object (id-src function-name))
                (map format-type arg-type*)))
            (for-each
              (lambda (var-name type)
                (set-idtype! var-name (Idtype-Base type)))
              var-name*
              return-type*)]
           [else (source-errorf src "invalid context for reference to ~s (defined at ~a)"
                                function-name
                                (format-source-object (id-src function-name)))]))]
      [(= ,test (,var-name* ...) (contract-call ,src ,elt-name (,[* type] ,primitive-type) ,[* type*] ...))
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
                            (unless (subtype? actual-type declared-type)
                              (source-errorf src "expected ~:r argument of ~s.~s to have type ~a but received ~a"
                                             (fx1+ i)
                                             contract-name
                                             elt-name
                                             (format-type declared-type)
                                             (format-type actual-type))))
                          declared-type* actual-type* (enumerate declared-type*))
                        (for-each
                          (lambda (var-name type)
                            (set-idtype! var-name (Idtype-Base type)))
                          var-name*
                          return-type*))
                      (loop (cdr elt-name*) (cdr type**) (cdr type*)))))]
           [else (source-errorf src "expected primitive type tcontract for contract call, received ~a"
                                (format-type primitive-type))]))]
      [(= ,test (,var-name1 ,var-name2) (field->bytes ,src ,nat ,[* type]))
       (verify-test src test)
       (check-tfield (format "argument to field->bytes at ~a" (format-source-object src)) type)
       (with-output-language (Lflattened Primitive-Type)
         (set-idtype! var-name1 (Idtype-Base `(tfield ,(max 0 (- (expt 2 (* (fxmin (fxmax 0 (fx- nat (field-bytes))) (field-bytes)) 8)) 1)))))
         (set-idtype! var-name2 (Idtype-Base `(tfield ,(max 0 (- (expt 2 (* (fxmin nat (field-bytes)) 8)) 1))))))]
      [(= ,test (,var-name* ...) (bytes->vector ,src ,[* type]))
       (verify-test src test)
       (check-tfield (format "argument to bytes->vector at ~a" (format-source-object src)) type)
       (with-output-language (Lflattened Primitive-Type)
         (for-each
           (lambda (var-name) (set-idtype! var-name (Idtype-Base `(tfield 8))))
           var-name*))]
      [(= ,test (,var-name* ...) (public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,adt-op ,[* type^*] ...))
       (verify-test src test)
       (nanopass-case (Lflattened ADT-Op) adt-op
         [(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
          (let ([arg-type* (apply append (map type->primitive-types type*))]
                [actual-type* type^*]
                [type* (type->primitive-types type)])
            (define compatible?
              (let ([nactual (length actual-type*)])
                (lambda (arg-type*)
                  (and (= (length arg-type*) nactual)
                       (andmap subtype? actual-type* arg-type*)))))
            (unless (compatible? arg-type*)
              (source-errorf src
                             "incompatible arguments for ledger.~a.~a;\n    \
                             supplied argument types:\n      \
                             (~{~a~^, ~});\n    \
                             declared argument types:\n      \
                             (~{~a~^, ~})"
                         (id-sym ledger-field-name)
                         ledger-op
                         (map format-type actual-type*)
                         (map format-type arg-type*)))
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
                (format-type type1)
                (format-type type2)))
             (with-output-language (Lflattened Primitive-Type) `(tfield 1))))]
      [(== ,[* type1] ,[* type2])
       (unless (or (subtype? type1 type2)
                   (subtype? type2 type1))
        ; the error message say "equality operator" here rather than "==" to avoid misleading
        ; type-mismatch messages for !=, which gets converted to == earlier in the compiler.
        (source-errorf program-src "incompatible types ~a and ~a for equality operator"
                 (format-type type1)
                 (format-type type2)))
       (with-output-language (Lflattened Primitive-Type) `(tfield 1))]
      [(select ,bool? ,[* type0] ,[* type1] ,[* type2])
       (unless (nanopass-case (Lflattened Primitive-Type) type0 [(tfield ,nat) (<= nat 1)] [else #f])
         (source-errorf program-src "expected select test to have type Boolean, received ~a"
                 (format-type type0)))
       (if bool?
           (begin
             (unless (nanopass-case (Lflattened Primitive-Type) type1 [(tfield ,nat) (<= nat 1)] [else #f])
               (source-errorf program-src "expected boolean select first branch to have type Boolean, received ~a"
                       (format-type type1)))
             (unless (nanopass-case (Lflattened Primitive-Type) type2 [(tfield ,nat) (<= nat 1)] [else #f])
               (source-errorf program-src "expected boolean select second branch to have type Boolean, received ~a"
                       (format-type type2))))
           (cond
             [(subtype? type1 type2) type2]
             [(subtype? type2 type1) type1]
             [else (source-errorf program-src "mismatch between type ~a and type ~a of condition branches"
                           (format-type type1)
                           (format-type type2))]))
       type1]
      [(bytes->field ,src ,nat ,[* type1] ,[* type2])
       (nanopass-case (Lflattened Primitive-Type) type1
         [(tfield ,nat) #t]
         [else (source-errorf src "unexpected ~a of first argument to bytes->field"
                              (format-type type1))])
       (nanopass-case (Lflattened Primitive-Type) type2
         [(tfield ,nat) #t]
         [else (source-errorf src "unexpected ~a of second argument to bytes->field"
                              (format-type type2))])
       (with-output-language (Lflattened Primitive-Type) `(tfield))]
      [(vector->bytes ,src ,triv ,triv* ...)
       (let* ([triv* (cons triv triv*)] [type* (map Triv triv*)])
         (let ([maybe-nat* (map (lambda (triv type) (check-tfield (format "argument ~a of vector->bytes" triv) type)) triv* type*)])
           (unless (andmap (lambda (maybe-nat) (eqv? maybe-nat 255)) maybe-nat*)
             (source-errorf src "incompatible types (~{~a~^, ~}) for vector->bytes"
               (map format-type type*)))))
       (with-output-language (Lflattened Primitive-Type) `(tfield ,(- (expt 256 (fx+ (length triv*) 1)) 1)))]
      [(downcast-unsigned ,src ,nat ,[* type] ,safe?)
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

  (define-pass print-Lflattened : Lflattened (ir) -> Lflattened ()
    (definitions
      (define (format-id id)
        (if (id-exported? id)
            (symbol->string (id-sym id))
            (format "~s" id)))
      (define (format-primitive-type pt)
        (nanopass-case (Lflattened Primitive-Type) pt
          [(tfield) "Field"]
          [(tfield ,nat) (format "Field<~s>" nat)]
          [(topaque ,opaque-type) (format "Opaque<~s>" opaque-type)]))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
       (parameterize ([id-prefix ""] [current-output-port (get-target-port 'lflattened.out)])
         (unless (null? pelt*)
           (Program-Element (car pelt*))
           (for-each (lambda (pelt) (newline) (Program-Element pelt)) (cdr pelt*))))
       ir])
    (Program-Element : Program-Element (ir) -> * (void)
      (definitions
        (define (print-header what name arg* return-type*)
          (printf "~s ~a\n" what (format-id name))
          (printf "        (~{~a~^, ~})\n" arg*)
          (printf "        ~a" return-type*)))
      [(circuit ,src ,function-name (,[Argument : arg -> * arg*] ...) ,[Type : type -> * return-type] ,stmt* ... (,[Triv : triv -> * triv*] ...))
       (print-header 'circuit function-name arg* return-type)
       (printf "\n{\n")
       (for-each Statement stmt*)
       (printf "    return~{ ~a~^,~};\n" triv*)
       (printf "}\n")]
      [(external ,src ,function-name ,native-entry (,[Argument : arg -> * arg*] ...) ,[Type : type -> * return-type])
       (print-header 'circuit function-name arg* return-type)
       (printf ";\n")]
      [(witness ,src ,function-name (,[Argument : arg -> * arg*] ...) ,[Type : type -> * return-type])
       (print-header 'witness function-name arg* return-type)
       (printf ";\n")]
      [(kernel-declaration ,[public-binding])
       (printf "ledger ~a;" public-binding)]
      [(public-ledger-declaration ,[Public-Ledger-Array : pl-array '() -> * public-binding*])
       (printf "ledger {\n~{  ~a;\n~}}" public-binding*)])
    (Public-Ledger-Array : Public-Ledger-Array (ir str*) -> * (str*)
      [(public-ledger-array ,pl-array-elt* ...)
       (fold-right
         (lambda (pl-array-elt str*)
           (nanopass-case (Lflattened Public-Ledger-Array-Element) pl-array-elt
             [,pl-array (Public-Ledger-Array pl-array str*)]
             [,public-binding (cons (Public-Ledger-Binding public-binding) str*)]))
         str*
         pl-array-elt*)])
    (Public-Ledger-Binding : Public-Ledger-Binding (ir) -> * (str)
      [(,src ,ledger-field-name (,path-index* ...) ,[Public-Ledger-ADT : public-adt -> * public-adt])
       (format "~a: ~a" (id-sym ledger-field-name) public-adt)])
    (Public-Ledger-ADT : Public-Ledger-ADT (ir) -> * (str)
      [(,src ,adt-name ((,adt-formal* ,adt-arg*) ...) ,vm-expr (,adt-op* ...))
       (if (null? adt-arg*)
           (format "~s" adt-name)
           (format "~s[~{~a~^, ~}]" adt-name (map Public-Ledger-ADT-Arg adt-arg*)))])
    (Public-Ledger-ADT-Arg : Public-Ledger-ADT-Arg (ir) -> * (str)
      [,nat (format "~s" nat)]
      [,type (Type type)])
    (Alignment : Alignment (ir) -> * (str)
      [(acompress) "compress"]
      [(abytes ,nat) (format "bytes ~a" nat)]
      [(afield) "field"]
      [(aadt) "aadt"]
      [(acontract) "contract"])
    (Argument : Argument (ir) -> * (str)
      [(argument (,var-name* ...) ,[Type : type -> * type]) (format "~{~a~^, ~} : ~a" (map format-id var-name*) type)])
    (Type : Type (ir) -> * (str)
      [(ty (,alignment* ...) (,primitive-type* ...))
       (format "(~{~a~^, ~} / ~{~a~^, ~})" (map format-primitive-type primitive-type*) (map Alignment alignment*))])
    (Statement : Statement (ir) -> * (void)
      [(= ,[* test] ,var-name ,[* single])
       (printf "    [~a] ~a = ~a;\n" test (format-id var-name) single)]
      [(= ,[* test] (,var-name* ...) ,[* app])
       (if (null? var-name*)
           (printf "    [~a] ~a;\n" test app)
           (printf "   [~a] ~{ ~a~^, ~} = ~a;\n" test (map format-id var-name*) app))]
      [(assert ,src ,[* triv] ,mesg)
       (printf "    assert ~a ~s;\n" triv mesg)])
    (Multiple : Multiple (ir) -> * (str)
      [(call ,src ,function-name ,[* triv*] ...)
       (format "~a(~{~a~^, ~})" (format-id function-name) triv*)]
      [(field->bytes ,src ,nat ,[* triv])
       (format "field->bytes(~d, ~a)" nat triv)]
      [(bytes->vector ,src ,[* triv])
       (format "bytes->vector(~a)" triv)]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[* triv*] ...)
       (nanopass-case (Lflattened ADT-Op) adt-op
         [(,ledger-op ,ledger-op-class (,adt-name (,adt-formal* ,adt-arg*) ...) (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
          (format "ledger.~a.~a(~{~a~^, ~})" (id-sym ledger-field-name) ledger-op triv*)])]
      [(contract-call ,src ,elt-name (,[* triv] ,primitive-type) ,[* triv*] ...)
       (nanopass-case (Lflattened Primitive-Type) primitive-type
         [(tcontract ,contract-name)
          (format "~a.~a(~{~a~^, ~})" contract-name elt-name triv*)]
         [else (assert cannot-happen)])])
    (Single : Single (ir) -> * (str)
      [,triv (Triv triv)] ; not exercised when optimize-circuit is run
      [(+ ,mbits ,[* triv1] ,[* triv2])
       (format "~a +~@[~d~] ~a" triv1 mbits triv2)]
      [(- ,mbits ,[* triv1] ,[* triv2])
       (format "~a -~@[~d~] ~a" triv1 mbits triv2)]
      [(bytes->field ,src ,nat ,[* triv1] ,[* triv2])
       (format "bytes->field(~d, ~a, ~a)" nat triv1 triv2)]
      [(vector->bytes ,src ,[* triv] ,[* triv*] ...)
       (format "vector->bytes(~a~{, ~a~})" triv triv*)]
      [(downcast-unsigned ,src ,nat ,[* triv] ,safe?)
       (format "downcast-unsigned(~d, ~a)" nat triv)]
      [(* ,mbits ,[* triv1] ,[* triv2])
       (format "~a *~@[~d~] ~a" triv1 mbits triv2)]
      [(< ,mbits ,[* triv1] ,[* triv2])
       (format "~a <~@[~d~] ~a" triv1 mbits triv2)]
      [(== ,[* triv1] ,[* triv2])
       (format "~a == ~a" triv1 triv2)]
      [(select ,bool? ,[* triv0] ,[* triv1] ,[* triv2])
       (format "select(~a, ~a, ~A)" triv0 triv1 triv2)])
    (Triv : Triv (ir) -> * (str)
      [,var-name (format-id var-name)]
      [,nat (format "~s" nat)])
    )

  (define-passes circuit-passes
    (drop-ledger-runtime             Lposttypescript)
    (replace-enums                   Lnoenums)
    (unroll-loops                    Lunrolled)
    (inline-circuits                 Linlined)
    (reduce-to-circuit               Lcircuit)
    (flatten-datatypes               Lflattened)
    (optimize-circuit                Lflattened))

  (define-passes print-Lflattened-passes
    (print-Lflattened                Lflattened))

  (define-checker check-types/Linlined Linlined)
  (define-checker check-types/Lflattened Lflattened)
)
