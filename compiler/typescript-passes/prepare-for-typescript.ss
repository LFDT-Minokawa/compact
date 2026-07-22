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

(define-pass prepare-for-typescript : Lloweredemit (ir) -> Ltypescript ()
  (definitions
    (define program-src)
    (define local-local*)
    (define (arg->id arg)
      (nanopass-case (Ltypescript Argument) arg
        [(,var-name ,type) var-name]))
    (define (arg->type arg)
      (nanopass-case (Ltypescript Argument) arg
        [(,var-name ,type) type]))
    (define (de-alias type)
      (nanopass-case (Ltypescript Type) type
        [(talias ,src ,nominal? ,type-name ,type)
         (de-alias type)]
        [else type]))
    (module (descriptor-table register-descriptor! maybe-register-descriptor! get-descriptors)
      (define-syntax T
        (syntax-rules ()
          [(T ty clause ...)
           (nanopass-case (Ltypescript Type) ty clause ... [else #f])]))
      (define (subst-tcontract type)
        (nanopass-case (Ltypescript Type) (de-alias type)
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (with-output-language (Ltypescript Type)
             `(tstruct ,src ContractAddress (bytes (tbytes ,src 32))))]
          [else type]))
      (define (type-hash type)
        (define max-tuple-elts-to-hash 10)
        (define (update hc k)
          (fxlogxor (#3%fx+ (#3%fxsll hc 2) hc) k))
        (define (nat-hash nat)
          (if (fixnum? nat) nat (modulo nat (most-positive-fixnum))))
        (nanopass-case (Ltypescript Type) (de-alias type)
          [(tboolean ,src) 523634023]
          [(tfield ,src ,ftype)
           (nanopass-case (Ltypescript Field-Type) ftype
             [(field-native) 22268065]
             [(field-scalar (curve-jubjub)) 474914719]
             [(field-base (curve-secp256k1)) 952780025]
             [(field-scalar (curve-secp256k1)) 817054627])]
          [(tunsigned ,src ,nat) (update 149561537 (nat-hash nat))]
          [(tbytes ,src ,len) (update 38297147 (nat-hash len))]
          [(topaque ,src ,opaque-type) (update 145867104 (string-hash opaque-type))]
           ; arrange for equivalent vectors and tuples to hash to same value with same elements,
           ; limiting the cost in the case of large vectors
          [(tvector ,src ,len ,type)
           (let ([hc* (make-list (min len max-tuple-elts-to-hash) (type-hash type))])
             (fold-left update 37919937 hc*))]
          [(ttuple ,src ,type* ...)
           (fold-left
             (lambda (hc type) (update hc (type-hash type)))
             37919937
             (list-head type* (min (length type*) max-tuple-elts-to-hash)))]
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (type-hash (subst-tcontract type))]
          [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
           (fold-left
             (lambda (hc type) (update hc (type-hash type)))
             (fold-left
               (lambda (hc elt-name) (update hc (symbol-hash elt-name)))
               (update 278965905 (symbol-hash struct-name))
               elt-name*)
             type*)]
          [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
           (fold-left
             (lambda (hc elt-name) (update hc (symbol-hash elt-name)))
             (update 419937385 (symbol-hash enum-name))
             (cons elt-name elt-name*))]
          [(tunknown) 241715055]
          [else (assert cannot-happen)]))
      (define (curve-type=? ctype1 ctype2)
        (nanopass-case (Ltypescript Curve-Type) ctype1
          [(curve-jubjub)
           (nanopass-case (Ltypescript Curve-Type) ctype2
             [(curve-jubjub) #t]
             [else #f])]
          [(curve-secp256k1)
           (nanopass-case (Ltypescript Curve-Type) ctype2
             [(curve-secp256k1) #t]
             [else #f])]))
      (define (field-type=? ftype1 ftype2)
        (nanopass-case (Ltypescript Field-Type) ftype1
          [(field-native)
           (nanopass-case (Ltypescript Field-Type) ftype2
             [(field-native) #t]
             [else #f])]
          [(field-base ,ctype1)
           (nanopass-case (Ltypescript Field-Type) ftype2
             [(field-base ,ctype2) (curve-type=? ctype1 ctype2)]
             [else #f])]
          [(field-scalar ,ctype1)
           (nanopass-case (Ltypescript Field-Type) ftype2
             [(field-scalar ,ctype2) (curve-type=? ctype1 ctype2)]
             [else #f])]))
      (define (type=? type1 type2)
        (let ([type1 (de-alias type1)] [type2 (de-alias type2)])
          (let ([type1 (subst-tcontract type1)] [type2 (subst-tcontract type2)])
            (T type1
               [(tboolean ,src1) (T type2 [(tboolean ,src2) #t])]
               [(tfield ,src1 ,ftype1)
                (T type2 [(tfield ,src2 ,ftype2) (field-type=? ftype1 ftype2)])]
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
                         (type=? type1 type2))]
                   [(ttuple ,src2 ,type2* ...)
                    (and (= len1 (length type2*))
                         (andmap (lambda (type2) (type=? type1 type2)) type2*))])]
               [(ttuple ,src1 ,type1* ...)
                (T type2
                   [(tvector ,src2 ,len2 ,type2)
                    (and (= (length type1*) len2)
                         (andmap (lambda (type1) (type=? type1 type2)) type1*))]
                   [(ttuple ,src2 ,type2* ...)
                    (and (= (length type1*) (length type2*))
                         (andmap type=? type1* type2*))])]
               [(tunknown) (T type2 [(tunknown) #t])]
               [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                ; since we substitute out tcontract types, this is not exercised
                (assert cannot-happen)]
               [(tstruct ,src1 ,struct-name1 (,elt-name1* ,type1*) ...)
                (T type2
                   [(tstruct ,src2 ,struct-name2 (,elt-name2* ,type2*) ...)
                    ; include struct-name and elt-name tests for nominal typing; remove
                    ; for structural typing.
                    (and (eq? struct-name1 struct-name2)
                         (fx= (length elt-name1*) (length elt-name2*))
                         (andmap eq? elt-name1* elt-name2*)
                         (andmap type=? type1* type2*))])]
               [(tenum ,src1 ,enum-name1 ,elt-name1 ,elt-name1* ...)
                (T type2
                   [(tenum ,src2 ,enum-name2 ,elt-name2 ,elt-name2* ...)
                    (and (eq? enum-name1 enum-name2)
                         (eq? elt-name1 elt-name2)
                         (andmap eq? elt-name1* elt-name2*))])]))))
      (define (public-adt? type)
        (nanopass-case (Ltypescript Type) (de-alias type)
          [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)) #t]
          [else #f]))
      (define descriptor-table (make-hashtable type-hash type=?))
      (define rdescriptor* '())
      (define (register-descriptor! type)
        (let ([type (subst-tcontract type)])
          (unless (public-adt? type)
            ; types aren't recursive, so no need to handle cycles here
            (T (de-alias type)
               [(tvector ,src ,len ,type)
                (register-descriptor! type)]
               [(ttuple ,src ,type* ...)
                (for-each register-descriptor! type*)]
               [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                (for-each register-descriptor! type*)]
               [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                (assert cannot-happen)])
            (let ([a (hashtable-cell descriptor-table type #f)])
              (unless (cdr a)
                (let ([id (make-temp-id program-src 'descriptor)])
                  (set-cdr! a id)
                  (set! rdescriptor* (cons (cons id type) rdescriptor*))))))))
      (define (maybe-register-descriptor! type)
        (nanopass-case (Ltypescript Type) (de-alias type)
          [(ttuple ,src) (void)]
          [else (register-descriptor! type)]))
      (define (get-descriptors)
        (let ([ldescriptor* (reverse rdescriptor*)])
          (values (map car ldescriptor*) (map cdr ldescriptor*))))))
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (fluid-let ([program-src src])
       (let ([pelt* (map Program-Element pelt*)])
         ; FIXME: assuming we get only (align <value> 1) or (align <value> 8).
         ; we should probably expand vm instructions earlier and create descriptors for
         ; VMalign ops on demand, perhaps still one for each seen value of bytes. expanding
         ; vm instructions earlier might also help enable flow analysis to determine when
         ; f-cached can be true.
         (register-descriptor! ; for align with bytes = 1
           (with-output-language (Ltypescript Type)
             `(tunsigned ,src ,(- (expt 2 8) 1))))
         (register-descriptor! ; for align with bytes = 4
           (with-output-language (Ltypescript Type)
             `(tunsigned ,src ,(- (expt 2 32) 1))))
         (register-descriptor! ; for align with bytes = 8
           (with-output-language (Ltypescript Type)
             `(tunsigned ,src ,(- (expt 2 64) 1))))
         (register-descriptor! ; for align with bytes = 16
           (with-output-language (Ltypescript Type)
             `(tunsigned ,src ,(- (expt 2 128) 1))))
         (let-values ([(descriptor-id* type*) (get-descriptors)])
           `(program ,src (,contract-type* ...) ((,export-name* ,name*) ...)
              (type-descriptors ,descriptor-table (,descriptor-id* ,type*) ...)
              ,pelt* ...))))])
  (Program-Element : Program-Element (ir) -> Program-Element ()
    [(native ,src ,function-name ,native-entry (,[arg*] ...) ,[type])
     ;; TODO: We shouldn't actually need to register all these
     ;; descriptors, just the generic arguments.
     ;; But those aren't around anymore, so this is a safe stand-in.
     (for-each register-descriptor! (map arg->type arg*))
     (maybe-register-descriptor! type)
     `(native ,src ,function-name ,native-entry (,arg* ...) ,type)]
    [(witness ,src ,function-name (,[arg*] ...) ,[type])
     (maybe-register-descriptor! type)
     `(witness ,src ,function-name (,arg* ...) ,type)])
  (Type : Type (ir) -> Type ()
    [(tadt ,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op* adt-name -> adt-op*] ...) (,[adt-rt-op*] ...))
     `(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))])
  (Public-Ledger-ADT-Arg : Public-Ledger-ADT-Arg (ir) -> Public-Ledger-ADT-Arg ()
     [,nat nat]
     [,type (let ([type (Type type)])
              (register-descriptor! type)
              type)])
  (ADT-Runtime-Op : ADT-Runtime-Op (ir) -> ADT-Runtime-Op ())
  (ADT-Op : ADT-Op (ir adt-name) -> ADT-Op ()
    [(,ledger-op ,[op-class] (,adt-name (,adt-formal* ,[adt-arg*]) ...) ((,var-name* ,[type*]) ...) ,[type] ,vm-code)
     ; FIXME: this can result in too many descriptors being created.  the root problem is that
     ; print-typescript opts not to generate all of the runtime ops if an op named read is
     ; available.  the solution is probably to weed out ops we don't want to generate earlier
     ; ideally much earlier, but at least in this pass.
     (when (eq? op-class 'read)
       (for-each register-descriptor! type*)
       (maybe-register-descriptor! type))
     `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)])
  (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,[arg*] ...) ,[type0 -> type] ,[Stmt : expr src -> stmt])
     (for-each register-descriptor! (map arg->type arg*))
     (maybe-register-descriptor! type)
     `(circuit ,src ,function-name (,arg* ...) ,type ,stmt)])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,[arg*] ...) ,[Stmt : expr src -> stmt])
     `(constructor ,src (,arg* ...) ,stmt)])
  (Function : Function (ir) -> Function ()
    [(circuit ,src (,[arg*] ...) ,[type] ,[Stmt : expr src -> stmt])
     `(circuit ,src (,arg* ...) ,type ,stmt)])
  (Stmt : Expression (ir src) -> Statement ()
    (definitions
      (define (statement-expression expr)
        (with-output-language (Ltypescript Statement)
          `(statement-expression ,expr)))
      (define (handle-expr expr k)
        (fluid-let ([local-local* '()])
          (let ([expr (k (Expr expr))])
            (if (null? local-local*)
                expr
                (with-output-language (Ltypescript Statement)
                  `(seq ,src
                     (const ,src (,local-local* ...))
                     ,expr)))))))
    [(if ,src ,expr0 (quote ,src1 ,datum1) (quote ,src2 ,datum2))
     (guard (eq? datum1 #f) (eq? datum2 #t))
     (handle-expr ir statement-expression)]
    [(if ,src ,expr0 ,expr1 (quote ,src2 ,datum2))
     (guard (eq? datum2 #f))
     (handle-expr ir statement-expression)]
    [(if ,src ,expr0 (quote ,src1 ,datum1) ,expr2)
     (guard (eq? datum1 #t))
     (handle-expr ir statement-expression)]
    [(if ,src ,expr0 ,[stmt1] (tuple ,src^))
     (handle-expr expr0 (lambda (expr0) `(if ,src ,expr0 ,stmt1)))]
    [(if ,src ,expr0 ,[stmt1] ,[stmt2])
     (handle-expr expr0 (lambda (expr0) `(if ,src ,expr0 ,stmt1 ,stmt2)))]
    [(seq ,src ,[stmt*] ... ,[stmt])
     `(seq ,src ,stmt* ... ,stmt)]
    [(let* ,src ([,[local*] ,expr*] ...) ,[stmt])
     (if (null? local*)
         stmt
         `(seq ,src
            ,(map (lambda (local expr)
                    (handle-expr expr (lambda (expr) `(const ,src ,local ,expr))))
                  local* expr*)
            ...
            ,stmt))]
    [(return ,src ,expr) (Stmt expr src)]
    [else (handle-expr ir statement-expression)])
  (Expr : Expression (ir) -> Expression ()
    [(if ,src ,[expr0] (quote ,src1 ,datum1) (quote ,src2 ,datum2))
     (guard (eq? datum1 #f) (eq? datum2 #t))
     `(not ,src ,expr0)]
    [(if ,src ,[expr0] ,[expr1] (quote ,src2 ,datum2))
     (guard (eq? datum2 #f))
     `(and ,src ,expr0 ,expr1)]
    [(if ,src ,[expr0] (quote ,src1 ,datum1) ,[expr2])
     (guard (eq? datum1 #t))
     `(or ,src ,expr0 ,expr2)]
    [(let* ,src ([,[local*] ,[expr*]] ...) ,[expr])
     (if (null? local*)
         expr
         (begin
           (set! local-local* (append local* local-local*))
           `(seq ,src
              ,(map (lambda (local expr) `(= ,src ,(arg->id local) ,expr)) local* expr*)
              ...
              ,expr)))]
    [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,[adt-op] ,[expr*] ...)
     (nanopass-case (Ltypescript ADT-Op) adt-op
       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
        (for-each register-descriptor! type*)
        (maybe-register-descriptor! type)
        `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)])]
    [(return ,src ,expr) (Expr expr)]
    [(emit ,src ,event-version ,event-tag ,len ,[expr] ,vm-code)
     (let ([type (with-output-language (Ltypescript Type) `(tbytes ,src ,len))])
       (register-descriptor! type)
       `(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code))])
  (Path-Element : Path-Element (ir) -> Path-Element ()
    [,path-index path-index]
    [(,src ,[type] ,[expr])
     (register-descriptor! type)
     `(,src ,type ,expr)]))
