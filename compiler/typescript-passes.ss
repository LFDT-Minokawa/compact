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

(library (typescript-passes)
  (export typescript-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs)
          (pass-helpers)
          (natives)
          (runtime-version)
          (ledger)
          (vm)
          (sourcemaps))

  (define-pass prepare-for-typescript : Lnodisclose (ir) -> Ltypescript ()
    (definitions
      (define program-src)
      (define local-local*)
      (define (local->id arg)
        (nanopass-case (Ltypescript Local) arg
          [(,var-name ,adt-type) var-name]))
      (define (arg->type arg)
        (nanopass-case (Ltypescript Argument) arg
          [(,var-name ,type) type]))
      (module (descriptor-table register-descriptor! maybe-register-descriptor! get-descriptors)
        (define-syntax T
          (syntax-rules ()
            [(T ty clause ...)
             (nanopass-case (Ltypescript Public-Ledger-ADT-Type) ty clause ... [else #f])]))
        (define (subst-tcontract adt-type)
          (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
            [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
             (with-output-language (Ltypescript Public-Ledger-ADT-Type)
               `(tstruct ,src ContractAddress (bytes (tbytes ,src 32))))]
            [else adt-type]))
        (define (type-hash type)
          (define max-tuple-elts-to-hash 10)
          (define (update hc k)
            (fxlogxor (#3%fx+ (#3%fxsll hc 2) hc) k))
          (define (nat-hash nat)
            (if (fixnum? nat) nat (modulo nat (most-positive-fixnum))))
          (nanopass-case (Ltypescript Type) type
            [(tboolean ,src) 523634023]
            [(tfield ,src) 22268065]
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
        (define (type=? type1 type2)
          (let ([type1 (subst-tcontract type1)] [type2 (subst-tcontract type2)])
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
                         (andmap eq? elt-name1* elt-name2*))])])))
        (define descriptor-table (make-hashtable type-hash type=?))
        (define rdescriptor* '())
        (define (register-descriptor! adt-type)
          (let ([adt-type (subst-tcontract adt-type)])
            (when (Ltypescript-Type? adt-type)
              ; types aren't recursive, so no need to handle cycles here
              (T adt-type
                 [(tvector ,src ,len ,type)
                  (register-descriptor! type)]
                 [(ttuple ,src ,type* ...)
                  (for-each register-descriptor! type*)]
                 [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                  (for-each register-descriptor! type*)]
                 [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                  (assert cannot-happen)])
              (let ([a (hashtable-cell descriptor-table adt-type #f)])
                (unless (cdr a)
                  (let ([id (make-temp-id program-src 'descriptor)])
                    (set-cdr! a id)
                    (set! rdescriptor* (cons (cons id adt-type) rdescriptor*))))))))
        (define (maybe-register-descriptor! adt-type)
          (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
            [(ttuple ,src) (void)]
            [else (register-descriptor! adt-type)]))
        (define (get-descriptors)
          (let ([ldescriptor* (reverse rdescriptor*)])
            (values (map car ldescriptor*) (map cdr ldescriptor*))))))
    (Program : Program (ir) -> Program ()
      [(program ,src (,contract-name* ...) ((,export-name* ,name*) ...) ,pelt* ...)
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
           (register-descriptor! ; for align with bytes = 8
             (with-output-language (Ltypescript Type)
               `(tunsigned ,src ,(- (expt 2 64) 1))))
           (register-descriptor! ; for align with bytes = 16
             (with-output-language (Ltypescript Type)
               `(tunsigned ,src ,(- (expt 2 128) 1))))
           (let-values ([(descriptor-id* type*) (get-descriptors)])
             `(program ,src ((,export-name* ,name*) ...)
                (type-descriptors ,descriptor-table (,descriptor-id* ,type*) ...)
                ,pelt* ...))))])
    (Program-Element : Program-Element (ir) -> Program-Element ()
      [(external ,src ,function-name ,native-entry (,[arg*] ...) ,[type])
       ;; TODO: We shouldn't actually need to register all these
       ;; descriptors, just the generic arguments.
       ;; But those aren't around anymore, so this is a safe stand-in.
       (for-each register-descriptor! (map arg->type arg*))
       (maybe-register-descriptor! type)
       `(external ,src ,function-name ,native-entry (,arg* ...) ,type)]
      [(witness ,src ,function-name (,[arg*] ...) ,[type])
       (maybe-register-descriptor! type)
       `(witness ,src ,function-name (,arg* ...) ,type)])
    (Public-Ledger-ADT : Public-Ledger-ADT (ir) -> Public-Ledger-ADT ()
      [(,src ,adt-name ([,adt-formal* ,[adt-arg*]] ...) ,vm-expr (,[adt-op* adt-name -> adt-op*] ...) (,[adt-rt-op*] ...))
       `(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))])
    (Public-Ledger-ADT-Arg : Public-Ledger-ADT-Arg (ir) -> Public-Ledger-ADT-Arg ()
       [,nat nat]
       [,adt-type (let ([adt-type (Public-Ledger-ADT-Type adt-type)])
                    (register-descriptor! adt-type)
                    adt-type)])
    (Public-Ledger-ADT-Type : Public-Ledger-ADT-Type (ir) -> Public-Ledger-ADT-Type ())
    (ADT-Runtime-Op : ADT-Runtime-Op (ir) -> ADT-Runtime-Op ())
    (ADT-Op : ADT-Op (ir adt-name) -> ADT-Op ()
      [(,ledger-op ,[op-class] (,adt-name (,adt-formal* ,[adt-arg*]) ...) ((,var-name* ,[adt-type*]) ...) ,[adt-type] ,vm-code)
       ; FIXME: this can result in too many descriptors being created.  the root problem is that
       ; print-typescript opts not to generate all of the runtime ops if an op named read is
       ; available.  the solution is probably to weed out ops we don't want to generate earlier
       ; ideally much earlier, but at least in this pass.
       (when (eq? op-class 'read)
         (for-each register-descriptor! adt-type*)
         (maybe-register-descriptor! adt-type))
       `(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)])
    (ADT-Op-Class : ADT-Op-Class (ir) -> ADT-Op-Class ())
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,[Stmt : expr src -> stmt])
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
                ,(map (lambda (local expr) `(= ,src ,(local->id local) ,expr)) local* expr*)
                ...
                ,expr)))]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,[path-elt*] ...) ,src^ ,[adt-op] ,[expr*] ...)
       (nanopass-case (Ltypescript ADT-Op) adt-op
         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
          (for-each register-descriptor! adt-type*)
          (maybe-register-descriptor! adt-type)
          `(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,expr* ...)])]
      [(return ,src ,expr) (Expr expr)])
    (Path-Element : Path-Element (ir) -> Path-Element ()
      [,path-index path-index]
      [(,src ,[type] ,[expr])
       (register-descriptor! type)
       `(,src ,type ,expr)]))

  (define-pass print-typescript : Ltypescript (ir) -> Ltypescript ()
    (definitions
      (define sourcemap-tracker)
      (define compact-stdlib-entries
         '(
           "CompactError"
           "typeError"
           "assert"
           "convertFieldToBytes"
           "convertBytesToField"
           "convertBytesToUint"
           "addField"
           "subField"
           "mulField"
           ))
      (define (compact-stdlib name)
        (unless (member name compact-stdlib-entries)
          (internal-errorf 'print-typescript "~s is not listed in compact-stdlib-entries" name))
        (format "__compactRuntime.~a" name))
      (module (with-local-unique-names demand-unique-local-name! unique-global-name unique-local-name
               format-internal-binding format-id-reference)
        (define unique-id-names (make-eq-hashtable))
        (define global-ht (make-hashtable string-hash string=?))
        (define local-ht #f)
        (define (make-local-ht ht)
          (if ht
              (hashtable-copy ht #t)
              (let ([ht (make-hashtable string-hash string=?)])
                ; amateur javascript language design makes "eval" and "arguments" invalid as parameter names
                (hashtable-set! ht "eval" #t)
                (hashtable-set! ht "arguments" #t)
                ht)))
        (define-syntax with-local-unique-names
          (syntax-rules ()
            [(_ b1 b2 ...)
             (fluid-let ([local-ht (make-local-ht local-ht)])
               b1 b2 ...)]))
        (define (demand-unique-local-name! uname)
          (let ([global-a (hashtable-cell global-ht uname #f)]
                [local-a (hashtable-cell local-ht uname #f)])
            (when (or (cdr global-a) (cdr local-a))
              (internal-errorf 'register-local-name! "~a is already taken" uname))
            (set-cdr! local-a #t)))
        (define (unique-global-name str)
          (let loop ([suffix 0])
            (let ([uname (format "_~a_~s" str suffix)])
              (let ([global-a (hashtable-cell global-ht uname #f)]
                    [local-a (and local-ht (hashtable-cell local-ht uname #f))])
                (if (or (cdr global-a) (and local-a (cdr local-a)))
                    (loop (fx+ suffix 1))
                    (begin
                      (set-cdr! global-a #t)
                      uname))))))
        (define (unique-local-name str)
          (assert local-ht)
          (let loop ([suffix 0])
            (let ([uname (format "~a_~s" str suffix)])
              (let ([global-a (hashtable-cell global-ht uname #f)]
                    [local-a (hashtable-cell local-ht uname #f)])
                (if (or (cdr global-a) (cdr local-a))
                    (loop (fx+ suffix 1))
                    (begin
                      (set-cdr! local-a #t)
                      uname))))))
        (define (format-internal-binding unique-name id)
          (let ([name (unique-name (symbol->string (id-sym id)))])
            (eq-hashtable-set! unique-id-names id name)
            name))
        (define (format-id-reference id)
          (let ([a (eq-hashtable-cell unique-id-names id #f)])
            (or (cdr a)
                (internal-errorf 'format-id-reference "format-internal-binding has not yet been called on ~s" id)))))
      (define (format-function-reference src function-name)
        (format "this.~a" (format-id-reference function-name)))
      (define (arg->id arg)
        (nanopass-case (Ltypescript Argument) arg
          [(,var-name ,type) var-name]))
      (define (arg->type arg)
        (nanopass-case (Ltypescript Argument) arg
          [(,var-name ,type) type]))
      (define exported-type-ht)
      (define-record-type tinfo
        (nongenerative)
        (fields export-name tvar* type))
      (define helper*)
      (define-syntax precedence-table
        (lambda (x)
          (define (parse-levels level*)
            (let f ([level* level*] [i 0])
              (if (null? level*)
                  '()
                  (syntax-case (car level*) ()
                    [(op ...)
                     (andmap identifier? #'(op ...))
                     (fold-right
                       (lambda (op alist)
                         (cons (cons op i) alist))
                       (f (cdr level*) (fx+ i 1))
                       #'(op ...))]))))
          (syntax-case x ()
            [(_ name level ...)
             (with-syntax ([alist (parse-levels #'(level ...))])
               #'(define-syntax name
                   (lambda (x)
                     (define (go op)
                       (cond
                         [(assq op 'alist) => cdr]
                         [else (syntax-error x "unrecognized operator")]))
                     (syntax-case x (add1)
                       [(_ op) (go (datum op))]
                       [(_ add1 op) (add1 (go (datum op)))]))))])))
      (precedence-table precedence
        (none)
        (comma)
        (=)
        (if)
        (or)
        (and)
        (== !=)
        (< <= > >=)
        (as)
        (+ -)
        (* %)
        (not)
        (new call struct-ref vector-ref))
      (define-datatype XPelt
        (XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
        (XPelt-internal-circuit src internal-id arg* type stmt pure?)
        (XPelt-witness src internal-id arg* type external-name)
        (XPelt-external-circuit src internal-id native-entry arg* type external-name pure?)
        (XPelt-type-definition src type-name export-name tvar-name* type)
        (XPelt-public-ledger pl-array lconstructor external-names)
        (XPelt-ledger-kernel))
      (define (xpelt->uname xpelt)
        (XPelt-case xpelt
          [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
           (format-internal-binding unique-global-name internal-id)]
          [(XPelt-internal-circuit src internal-id arg* type stmt pure?)
           (format-internal-binding unique-global-name internal-id)]
          [(XPelt-witness src internal-id arg* type external-name)
           (format-internal-binding unique-global-name internal-id)]
          [(XPelt-external-circuit src internal-id native-entry arg* type external-name pure?)
           (format-internal-binding unique-global-name internal-id)]
          [(XPelt-type-definition src type-name export-name tvar-name* type) #f]
          [(XPelt-public-ledger pl-array lconstructor external-names) #f]
          [(XPelt-ledger-kernel) #f]))

      (module (descriptor-table type->maybe-descriptor-name type->descriptor-name)
        (define descriptor-table #f)

        (define (type->maybe-descriptor-name type)
          (assert descriptor-table)
          (cond
            [(hashtable-ref descriptor-table type #f) => format-id-reference]
            [else #f]))

        (define (type->descriptor-name type)
          (assert descriptor-table)
          (format-id-reference (assert (hashtable-ref descriptor-table type #f)))))

      (define (pl-array->public-bindings pl-array)
        (let f ([pl-array pl-array] [pb* '()])
          (nanopass-case (Ltypescript Public-Ledger-Array) pl-array
            [(public-ledger-array ,pl-array-elt* ...)
             (fold-right
               (lambda (pl-array-elt pb*)
                 (nanopass-case (Ltypescript Public-Ledger-Array-Element) pl-array-elt
                   [,pl-array (f pl-array pb*)]
                   [,public-binding (cons public-binding pb*)]))
               pb*
               pl-array-elt*)])))

      (define (construct-typed-value descriptor-name q)
        (make-Qconcat
          "{ "
          ((make-Qsep ",")
           (make-Qconcat
             "value: "
             (make-Qconcat
               (format "~a.toValue(" descriptor-name)
               q
               ")"))
           (format "alignment: ~a.alignment()" descriptor-name))
          " }"))

      (module (construct-query)
        (define (construct-vm-instructions src path-elt* adt-formal* adt-arg* adt-op expr*)
          (define-record-type vmref
            (nongenerative)
            (fields type q)
            (protocol
              (lambda (new)
                (lambda (type q)
                  (new type q)))))
          (define-condition-type &suppressed &condition make-suppressed-condition suppressed-condition?)
          (define (construct-query-value v top-level?)
            (cond
              [(eq? v #f) "false"]
              [(eq? v #t) "true"]
              [(and (integer? v) (exact? v)) (format "~d" v)]
              [(list? v)
               (make-Qconcat
                 "["
                 1 (apply
                     (make-Qsep ",")
                     (map
                       (lambda (v)
                         (let ([is-stack (and (VMop? v) (VMop-case v
                                                          [(VMstack) #t]
                                                          [else #f]))])
                           (if is-stack
                               (construct-query-value v #f)
                               (make-Qconcat
                                 "{ "
                                 ((make-Qsep ",")
                                  "tag: 'value'"
                                  (make-Qconcat
                                    "value: "
                                    (construct-query-value v #f)))
                                 " }"))))
                       v))
                 "]")]
              [(vmref? v)
               (let ([adt-type (vmref-type v)] [q (vmref-q v)])
                 (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
                   [,type (construct-typed-value (type->descriptor-name type) q)]
                   [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                    ; FIXME: at present, we can assume that whenever we passs a value of some
                    ; public-adt as a query argument, it must be the result of default<public-adt>,
                    ; since that's all that can get past the type checker.  if we generalize to
                    ; allow first-class public-adt values, this code will no longer be valid.
                    (construct-query-value
                      (expand-vm-expr
                        src
                        (map cons adt-formal* adt-arg*)
                        (vm-expr-expr vm-expr))
                      top-level?)]))]
              [(VMop? v)
               (VMop-case v
                 [(VMstack) "{ tag: 'stack' }"]
                 [(VMvoid) "undefined"]
                 [(VMsuppress) (raise (make-suppressed-condition))]
                 [(VM+ x y)
                  (make-Qconcat
                    "("
                    (construct-query-value x #f)
                    "+"
                    (construct-query-value y #f)
                    ")")]
                 [(VMvalue->int v)
                  (make-Qconcat
                    "parseInt(__compactRuntime.valueToBigInt("
                    2 (construct-query-value v #f)
                    4 ".value"
                    0 "))")]
                 [(VMalign value bytes)
                  (assert (or (= bytes 1) (= bytes 8) (= bytes 16)))
                  (construct-typed-value
                    (type->descriptor-name (with-output-language (Ltypescript Type) `(tunsigned ,src ,(- (expt 2 (* bytes 8)) 1))))
                    (format "~dn" value))]
                 [(VMnull type)
                  (nanopass-case (Ltypescript Public-Ledger-ADT-Type) type
                    [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                     (construct-query-value
                       (expand-vm-expr
                         src
                         (map cons adt-formal* adt-arg*)
                         (vm-expr-expr vm-expr))
                       top-level?)]
                    [,type
                     (construct-typed-value
                       (type->descriptor-name type)
                       (Expr (with-output-language (Ltypescript Expression) `(default ,src ,type))
                             (precedence add1 comma)
                             #f))]
                    [else (assert cannot-happen)])]
                 [(VMmax-sizeof type)
                  (assert (Ltypescript-Type? type))
                  (make-Qconcat
                    "Number(__compactRuntime.maxAlignedSize("
                    2 (type->descriptor-name type)
                    2 ".alignment()"
                    0 "))")]
                 [(VMstate-value-cell val)
                  (make-Qconcat
                    "__compactRuntime.StateValue.newCell("
                    (construct-query-value val #f)
                    (if top-level?
                        ").encode()"
                        ")"))]
                 [(VMstate-value-ADT val adt-type)
                  (if (Ltypescript-Public-Ledger-ADT? adt-type)
                      (construct-query-value val top-level?)
                      (make-Qconcat
                        "__compactRuntime.StateValue.newCell("
                        (construct-query-value val #f)
                        (if top-level?
                            ").encode()"
                            ")")))]
                 [(VMstate-value-null)
                  (if top-level?
                      "__compactRuntime.StateValue.newNull().encode()"
                      "__compactRuntime.StateValue.newNull()")]
                 [(VMstate-value-map key* val*)
                  (make-Qconcat
                    "__compactRuntime.StateValue.newMap("
                    2 (apply (make-Qsep ",")
                        "new __compactRuntime.StateMap()"
                        (map (lambda (key val)
                               ; at present, midnight-ledger.ss doesn't create maps with arguments
                               (make-Qconcat
                                 ".insert("
                                 ((make-Qsep ",")
                                  (construct-query-value key #f)
                                  (construct-query-value val #f))
                                 ")"))
                             key*
                             val*))
                    0 (if top-level?
                          ").encode()"
                          ")"))]
                 [(VMstate-value-merkle-tree nat key* val*)
                  (make-Qconcat
                    "__compactRuntime.StateValue.newBoundedMerkleTree("
                    2 (apply (make-Qsep ",")
                        (make-Qconcat
                          "new __compactRuntime.StateBoundedMerkleTree("
                          (construct-query-value nat #f)
                          ")")
                        (map (lambda (key val)
                               ; at present, midnight-ledger.ss doesn't create MerkleTrees with arguments
                               (make-Qconcat
                                 ".update("
                                 ((make-Qsep ",")
                                  (construct-query-value key #f)
                                  (construct-query-value val #f))
                                 ")"))
                             key*
                             val*))
                    0 (if top-level?
                          ").encode()"
                          ")"))]
                 [(VMstate-value-array val*)
                  (make-Qconcat
                    "__compactRuntime.StateValue.newArray()"
                    2 (apply make-Qconcat
                             (map (lambda (val)
                                    (make-Qconcat
                                      ".arrayPush("
                                      (construct-query-value val #f)
                                      ")"))
                                  val*))
                    2 (if top-level?
                          ".encode()"
                          ""))]
                 [(VMaligned-concat x*)
                  (make-Qconcat
                    "__compactRuntime.alignedConcat("
                    2 (apply (make-Qsep ",")
                             (map (lambda (x) (construct-query-value x #f)) x*))
                    0 (if top-level?
                          ").encode()"
                          ")"))]
                 [(VMcoin-commit coin recipient)
                  (make-Qconcat
                    "__compactRuntime.runtimeCoinCommitment("
                    2 ((make-Qsep ",")
                        (construct-query-value coin #f)
                        (construct-query-value recipient #f))
                    0 ")")]
                 [(VMleaf-hash x)
                  (make-Qconcat
                    "__compactRuntime.leafHash("
                    2 (construct-query-value x #f)
                    0 ")")])]
              [else (internal-errorf 'construct-query-value "unhandled case ~s" v)]))
          (nanopass-case (Ltypescript ADT-Op) adt-op
            [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
             (assert (fx= (length expr*) (length var-name*)))
             (let ([vminstr* (expand-vm-code
                               src
                               (map (lambda (path-elt)
                                      (nanopass-case (Ltypescript Path-Element) path-elt
                                        [,path-index (VMalign path-index 1)]
                                        [(,src ,type ,expr) (make-vmref type (Expr expr (precedence add1 comma) #f))]))
                                    path-elt*)
                               #f
                               (append (map cons adt-formal* adt-arg*)
                                       (map (lambda (var-name adt-type expr)
                                              (let ([sym (id-sym var-name)])
                                                (cons sym (make-vmref adt-type expr))))
                                            var-name*
                                            adt-type*
                                            expr*))
                               (vm-code-code vm-code))])
               (make-Qconcat
                 "["
                 1 (apply (make-Qsep ",")
                          (fold-right
                            (lambda (vminstr q*)
                              (guard (c [(suppressed-condition? c) q*])
                                (cons (let ([op (vminstr-op vminstr)] [arg* (vminstr-arg* vminstr)])
                                        (if (null? arg*)
                                            (format "'~a'" op)
                                            (make-Qconcat
                                              "{ " op ": { "
                                              (apply (make-Qsep ",")
                                                     (map (lambda (arg)
                                                            (let ([name (car arg)] [val (cdr arg)])
                                                              (make-Qconcat name ": " (construct-query-value val #t))))
                                                          arg*))
                                              " } }")))
                                      q*)))
                            '()
                            vminstr*))
                 "]"))]))

        (define (coin-recipient-indices adt-op)
          (nanopass-case (Ltypescript ADT-Op) adt-op
            [(,ledger-op (,ledger-op-class ,nat ,nat^) (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
             (list nat nat^)]))

        (define (should-check-coin-commitment? adt-op)
          (nanopass-case (Ltypescript ADT-Op) adt-op
            [(,ledger-op (,ledger-op-class ,nat ,nat^) (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
             (eq? ledger-op-class 'update-with-coin-check)]
            [else #f]))

        (define (coin-commitment-check adt-op expr*)
          (let* ([indices (coin-recipient-indices adt-op)]
                 [coin-idx (car indices)]
                 [recipient-idx (cadr indices)]
                 [coin-expr (list-ref expr* coin-idx)]
                 [recipient-expr (list-ref expr* recipient-idx)])
            (make-Qconcat
             "__compactRuntime.hasCoinCommitment("
             ((make-Qsep ",") "context" coin-expr recipient-expr)
             ")")))

        (define (construct-query src path-elt* adt-formal* adt-arg* adt-op expr*)
          (let ([query (make-Qconcat/src src
                         "__compactRuntime.queryLedgerState("
                         ((make-Qsep ",")
                          "context"
                          "partialProofData"
                          (construct-vm-instructions src path-elt* adt-formal* adt-arg* adt-op expr*))
                         ")")])
            (if (should-check-coin-commitment? adt-op)
                (make-Qconcat
                  (coin-commitment-check adt-op expr*)
                  " ? "
                  query
                  " : "
                  (format "(() => { throw new __compactRuntime.CompactError(`~a: Coin commitment not found. Check the coin has been received (or call 'createZswapOutput')`); })()" (format-source-object src)))
                query))
          ))

      (define (has-read? adt-op*)
        (ormap (lambda (adt-op)
                 (and (eq? (op-name adt-op) 'read)
                      (is-runtime-op? adt-op)
                      adt-op))
               adt-op*))
      (define (op-name adt-op)
        (if (Ltypescript-ADT-Op? adt-op)
            (nanopass-case (Ltypescript ADT-Op) adt-op
              [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
               ledger-op])
            (nanopass-case (Ltypescript ADT-Runtime-Op) adt-op
              [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
              ledger-op])))
      (define (is-runtime-op? adt-op)
        (or (not (Ltypescript-ADT-Op? adt-op))
            (nanopass-case (Ltypescript ADT-Op) adt-op
              [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
               (eq? op-class 'read)])))
      (define (maybe-iterator op-name)
        (if (eq? op-name 'iter)
            "[Symbol.iterator]"
            (to-camel-case (symbol->string op-name) #f)))
      (define (exported-public-binding? public-binding)
        (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
          [(,src ,ledger-field-name (,path-index* ...) ,public-adt)
           (id-exported? ledger-field-name)]))
      (define (get-self-contract-name)
        (source-file-name))
      (define (print-contract-name contract-name)
          (if (symbol? contract-name)
              (symbol->string contract-name)
              contract-name))
      (define (get-contract-dependencies)
        (define (contract-info-filename contract-name)
          (format "~a/~a/compiler/contract-info.json"
            (path-parent (target-directory))
            contract-name))
        (define (malformed msg contract-name . args)
          (external-errorf "malformed contract-info file ~a for ~s: ~a; try recompiling ~a"
                           (contract-info-filename contract-name)
                           contract-name
                           (apply format msg args)
                           contract-name))
        (define (get-assoc key contract-name alist)
          (cond
            [(and (pair? alist) (assoc key alist)) => cdr]
            [else (malformed "missing association for ~s" contract-name key)]))
        (define (get-witness-names contract-name v)
          (fold-right (lambda (alist name*) (cons (get-assoc "name" contract-name alist) name*))
                      '()
                      (vector->list v)))
        (let* ([contract-has-witness-ht (make-hashtable symbol-hash eq?)]
               [contract-ht (contract-ht)]
               [dep-contracts (vector->list (hashtable-keys contract-ht))]
               [contract-has-witness*
                 (fold-right (lambda (contract-name contract-name*)
                               (let ([a (hashtable-cell contract-has-witness-ht contract-name 'unvisited)])
                                 (when (eq? (cdr a) 'unvisited)
                                   (let* ([info (hashtable-cell contract-ht contract-name #f)]
                                          [alist (cdr info)]
                                          [v (get-assoc "witnesses" contract-name alist)])
                                     (unless (vector? v) (malformed "\"witnesses\" is not associated with a vector" contract-name))
                                     (set-cdr! a (get-witness-names contract-name v))))
                                 (if (eq? (cdr a) '())
                                     contract-name*
                                     (cons (car a) contract-name*))))
                   '()
                   dep-contracts)])
          (values contract-has-witness* contract-has-witness-ht)))

      (define (subst-tcontract adt-type)
        (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
          [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
           (with-output-language (Ltypescript Public-Ledger-ADT-Type)
             `(tstruct ,src ContractAddress (bytes (tbytes ,src 32))))]
          [else adt-type]))

      (define (print-contract.d.ts src xpelt* uname*)
        (define (print-exported-impure-circuit-declaration do-me?)
          (lambda (xpelt uname)
            (XPelt-case xpelt
              [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
               (when (do-me? pure?)
                 (for-each
                   (lambda (external-name)
                     (with-local-unique-names
                       (demand-unique-local-name! "context")
                       (print-Q 2
                         (make-Qconcat
                           external-name
                           "("
                           (apply (make-Qsep ",")
                             "context: __compactRuntime.CircuitContext<PS>"
                             (map Typed-Argument arg*))
                           "): "
                           "__compactRuntime.CircuitResults<PS, " (Type type) ">"
                           ";")))
                     (newline))
                   external-name*))]
              [else (void)])))
        (define (print-exported-pure-circuit-declaration xpelt uname)
          (XPelt-case xpelt
            [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
             (when pure?
               (for-each
                 (lambda (external-name)
                   (with-local-unique-names
                     (print-Q 2
                       (make-Qconcat
                         external-name
                         "("
                         (apply (make-Qsep ",") (map Typed-Argument arg*))
                         "): "
                         (Type type)
                         ";")))
                   (newline))
                 external-name*))]
            [else (void)]))
        (define (print-exported-circuit-declaration xpelt uname)
          (XPelt-case xpelt
            [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
             (apply (print-exported-impure-circuit-declaration
                      (if pure?
                          (lambda (x) x)
                          not))
                    (list xpelt uname))]
            [else (void)]))
        (define (print-witness-declaration xpelt uname)
          (XPelt-case xpelt
            [(XPelt-witness src internal-id arg* type external-name)
             (with-local-unique-names
               (demand-unique-local-name! "private_state")
               (print-Q 2
                 (make-Qconcat
                   external-name
                   "("
                   (apply (make-Qsep ",")
                     "context: __compactRuntime.WitnessContext<Ledger, PS>"
                     (map Typed-Argument arg*))
                   "): "
                   "[PS, " (Type type) "]"
                   ";")))
             (newline)]
            [else (void)]))

        (module (print-ledger-declaration)
          (define (op-signature-Q adt-op)
            (nanopass-case (Ltypescript ADT-Op) adt-op
              [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
               (with-local-unique-names
                 (let ([formal* (map (lambda (var-name) (format-internal-binding unique-local-name var-name))
                                     var-name*)])
                   (apply list
                     "("
                     (apply (make-Qsep ",")
                       (map (lambda (formal adt-type)
                              (assert (Ltypescript-Type? adt-type))
                              (make-Qconcat formal ": " (Type adt-type)))
                            formal*
                            adt-type*))
                     "): "
                     (if (Ltypescript-Public-Ledger-ADT? adt-type)
                         (nanopass-case (Ltypescript Public-Ledger-ADT) adt-type
                           [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                            (let* ([all-op* (filter is-runtime-op? (append adt-op* adt-rt-op*))]
                                   [all-op* (cond [(has-read? all-op*) => list] [else all-op*])])
                              (list
                                "{"
                                2 (ledger-field-decl-Q src adt-arg* all-op*)
                                0 "}"))])
                         (list (Type adt-type))))))]))
          (define (rt-op-return-type adt-arg* result-type)
            (let ([targs (map (lambda (adt-arg)
                                (nanopass-case (Ltypescript Public-Ledger-ADT-Arg) adt-arg
                                  [,nat (number->string nat)]
                                  [,adt-type
                                   (if (Ltypescript-Public-Ledger-ADT? adt-type)
                                       ; at present, this case should be ruled out by the ledger meta-type checks
                                       "undefined"
                                       (with-output-to-string
                                         (lambda ()
                                           (print-Q 0 (Type adt-type)))))]))
                              adt-arg*)])
              (apply result-type "__compactRuntime." targs)))
          (define (rt-op-signature-Q adt-rt-op adt-arg*)
            (nanopass-case (Ltypescript ADT-Runtime-Op) adt-rt-op
              [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
               (with-local-unique-names
                 (let ([formal* (map Untyped-Argument arg*)])
                   (list
                     "("
                     (apply (make-Qsep ",")
                       (map (lambda (formal arg)
                              (make-Qconcat formal ": " (Type (arg->type arg))))
                            formal*
                            arg*))
                     "): "
                     (rt-op-return-type adt-arg* result-type))))]))
          (define (ledger-field-decl-Q src adt-arg* all-op*)
            (apply (make-Qsep ";")
              (map (lambda (op)
                     (with-local-unique-names
                       (apply make-Qconcat
                         (maybe-iterator (op-name op))
                         (if (Ltypescript-ADT-Op? op)
                             (op-signature-Q op)
                             (rt-op-signature-Q op adt-arg*)))))
                   (remp (lambda (op)
                           ; run-time ops like iterators that expect to be supplied a descriptor
                           ; for use in decoding values.  we don't have a decoder for adt values, and if we did,
                           ; it's not clear what they would do with an adt value anyway.  so we just don't
                           ; generate such runtime ops.
                           (and (Ltypescript-ADT-Runtime-Op? op)
                                (ormap (lambda (adt-arg)
                                         (nanopass-case (Ltypescript Public-Ledger-ADT-Arg) adt-arg
                                           [,public-adt #t]
                                           [else #f]))
                                       adt-arg*)))
                         all-op*))))
          (define (print-public-binding public-binding external-names)
            (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
              [(,src ,ledger-field-name (,path-index* ...) (,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)))
               (for-each
                 (lambda (export-name)
                   (print-Q 2
                     (let* ([all-op* (filter is-runtime-op? (append adt-op* adt-rt-op*))]
                            [maybe-read (has-read? all-op*)])
                       (if maybe-read
                           (make-Qconcat
                             "readonly "
                             export-name
                             ": "
                             (if (Ltypescript-ADT-Op? maybe-read)
                                 (nanopass-case (Ltypescript ADT-Op) maybe-read
                                   [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
                                    (assert (Ltypescript-Type? adt-type))
                                    (Type adt-type)])
                                 ; at present, no adt-rt-ops qualify (i.e., none are named "read")
                                 (nanopass-case (Ltypescript ADT-Runtime-Op) maybe-read
                                   [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
                                    (rt-op-return-type adt-arg* result-type)]))
                             ";")
                           (make-Qconcat
                             export-name
                             ": {"
                             2 (ledger-field-decl-Q src adt-arg* all-op*)
                             0 "};"))))
                   (newline))
                 (external-names ledger-field-name))]))
          (define (print-ledger-declaration xpelt uname)
            (XPelt-case xpelt
              [(XPelt-public-ledger pl-array ledger-constructor external-names)
               (for-each
                 (lambda (public-binding) (print-public-binding public-binding external-names))
                 (filter
                   exported-public-binding?
                   (pl-array->public-bindings pl-array)))]
              [else (void)])))

        (define (print-exported-types xpelt*)
          (for-each
            (lambda (xpelt)
              (XPelt-case xpelt
                [(XPelt-type-definition src type-name export-name tvar-name* type)
                 (hashtable-update! exported-type-ht type-name
                   (lambda (ls) (cons (make-tinfo export-name tvar-name* type) ls))
                   '())]
                [else (void)]))
            xpelt*)
          (for-each
            (lambda (xpelt)
              (XPelt-case xpelt
                [(XPelt-type-definition src type-name export-name tvar-name* type)
                 (newline)
                 (nanopass-case (Ltypescript Type) type
                   [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                     (assert cannot-happen)]
                   [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                    (print-Q 0
                      (make-Qconcat
                        "export type "
                        (let ([q (symbol->string export-name)])
                          (if (null? tvar-name*)
                              q
                              (make-Qconcat q "<" (apply (make-Qsep ",") (map symbol->string tvar-name*)) ">")))
                        " = "
                        (make-Qconcat
                          "{ "
                          (apply (make-Qsep ";")
                                 (map (lambda (elt-name type)
                                        (make-Qconcat (format "~a" elt-name) ": " (Type type)))
                                      elt-name*
                                      type*))
                          0 "};")))]
                   [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                    (print-Q 0
                      (make-Qconcat
                        "export enum "
                        (make-Qconcat (format "~a" export-name))
                        " { "
                        (apply (make-Qsep ",")
                               (let ([elt-name+ (cons elt-name elt-name*)])
                                 (map (lambda (elt-name i)
                                        (make-Qconcat (format "~a" elt-name) " = " (format "~d" i)))
                                      elt-name+
                                      (enumerate elt-name+))))
                        0 "}"))]
                   [else (assert cannot-happen)])
                 (newline)]
                [else (void)]))
            xpelt*))
        (define (print-constructor-declaration xpelt*)
          (let loop ([xpelt* xpelt*])
            (assert (not (null? xpelt*)))
            (XPelt-case (car xpelt*)
              [(XPelt-public-ledger pl-array lconstructor external-names)
               (nanopass-case (Ltypescript Ledger-Constructor) lconstructor
                 [(constructor ,src (,arg* ...) ,stmt)
                  (with-local-unique-names
                    (demand-unique-local-name! "context")
                    (print-Q 2
                      (make-Qconcat
                        "initialState("
                        (apply (make-Qsep ",")
                               "context: __compactRuntime.ConstructorContext<PS>"
                               (map (lambda (arg)
                                      (nanopass-case (Ltypescript Argument) arg
                                        [(,var-name ,type)
                                         (make-Qconcat
                                           (format-internal-binding unique-local-name var-name)
                                           ": "
                                           (Type type))]))
                                    arg*))
                        "): __compactRuntime.ConstructorResult<PS>;"))
                    (newline))])]
              [else (loop (cdr xpelt*))])))
        (parameterize ([current-output-port (get-target-port 'contract.d.ts)])
          (with-local-unique-names
            (demand-unique-local-name! "T")
            (demand-unique-local-name! "W")
            (fluid-let ([exported-type-ht (make-hashtable symbol-hash eq?)])
              (display-string "import type * as __compactRuntime from '@midnight-ntwrk/compact-runtime';\n")
              (print-exported-types xpelt*)
              (newline)
              (display-string "export type Witnesses<PS> = {\n")
              (for-each print-witness-declaration xpelt* uname*)
              (display-string "}\n")
              (newline)
              (display-string "export type ImpureCircuits<PS> = {\n")
              (for-each (print-exported-impure-circuit-declaration not) xpelt* uname*)
              (display-string "}\n")
              (newline)
              (display-string "export type PureCircuits = {\n")
              (for-each print-exported-pure-circuit-declaration xpelt* uname*)
              (display-string "}\n")
              (newline)
              (display-string "export type Circuits<PS> = {\n")
              (for-each print-exported-circuit-declaration xpelt* uname*)
              (display-string "}\n")
              (newline)
              (display-string "export type Ledger = {\n")
              (for-each print-ledger-declaration xpelt* uname*)
              (display-string "}\n")
              (newline)
              (display-string "export type ContractReferenceLocations = any;\n")
              (newline)
              (display-string "export declare const contractReferenceLocations : ContractReferenceLocations;\n")
              (newline)
              (display-string "export declare class Contract<PS = any, W extends Witnesses<PS> = Witnesses<PS>> {\n")
              (display-string "  witnesses: W;\n")
              (display-string "  circuits: Circuits<PS>;\n")
              (display-string "  impureCircuits: ImpureCircuits<PS>;\n")
              (display-string "  constructor(witnesses: W);\n")
              (print-constructor-declaration xpelt*)
              (display-string "}\n")
              (newline)
              (display-string "export declare function ledger(state: __compactRuntime.StateValue | __compactRuntime.ChargedState): Ledger;\n")
              (display-string "export declare const pureCircuits: PureCircuits;\n")
              ))))

      (module (print-contract.js)
        (define (print-contract-header)
          (display-string "import * as __compactRuntime from '@midnight-ntwrk/compact-runtime';\n")
          (printf "__compactRuntime.checkRuntimeVersion('~a');\n" runtime-version-string)
          (display-string "\n"))

        (define (print-contract-descriptors src descriptor-id* type*)
          (define (print-struct-class class-name elt-name* type*)
            (let ([descriptor-name* (map type->descriptor-name type*)])
              (printf "class ~a {\n" class-name)
              (printf "  alignment() {\n")
              (if (null? elt-name*)
                  (printf "    return [];\n")
                  (printf "    return ~{~a.alignment()~^.concat(~}~:*~{~*~^)~};\n" descriptor-name*))
              (printf "  }\n")
              (with-local-unique-names
                (let ([value (format-internal-binding unique-local-name (make-temp-id src 'value))])
                  (printf "  fromValue(~a) {\n" value)
                  (printf "    return {")
                  (printf "~{\n      ~a~^,~}"
                          (map (lambda (elt-name descriptor-name)
                                 (format "~a: ~a.fromValue(~a)" elt-name descriptor-name value))
                               elt-name*
                               descriptor-name*))
                  (printf "\n    }\n")
                  (printf "  }\n")))
              (with-local-unique-names
                (let ([value (format-internal-binding unique-local-name (make-temp-id src 'value))])
                  (printf "  toValue(~a) {\n" value)
                  (if (null? elt-name*)
                      (printf "    return [];\n")
                      (printf "    return ~{~a~^.concat(~}~:*~{~*~^)~};\n"
                              (map (lambda (elt-name descriptor-name)
                                     (format "~a.toValue(~a.~a)" descriptor-name value elt-name))
                                   elt-name*
                                   descriptor-name*)))
                  (printf "  }\n")))
              (printf "}\n\n")))
          (define (print-tuple-class tuple-name type*)
            (let ([descriptor-name* (map type->descriptor-name type*)])
              (printf "class ~a {\n" tuple-name)
              (printf "  alignment() {\n")
              (if (null? type*)
                  (printf "    return [];\n")
                  (printf "    return ~{~a.alignment()~^.concat(~}~:*~{~*~^)~};\n" descriptor-name*))
              (printf "  }\n")
              (with-local-unique-names
                (let ([value (format-internal-binding unique-local-name (make-temp-id src 'value))])
                  (printf "  fromValue(~a) {\n" value)
                  (printf "    return [")
                  (printf "~{\n      ~a~^,~}"
                          (map (lambda (descriptor-name)
                                 (format "~a.fromValue(~a)" descriptor-name value))
                               descriptor-name*))
                  (printf "\n    ]\n")
                  (printf "  }\n")))
              (with-local-unique-names
                (let ([value (format-internal-binding unique-local-name (make-temp-id src 'value))])
                  (printf "  toValue(~a) {\n" value)
                  (if (null? type*)
                      (printf "    return [];\n")
                      (printf "    return ~{~a~^.concat(~}~:*~{~*~^)~};\n"
                              (map (lambda (eltno descriptor-name)
                                     (format "~a.toValue(~a[~d])" descriptor-name value eltno))
                                   (enumerate type*)
                                   descriptor-name*)))
                  (printf "  }\n")))
              (printf "}\n\n")))
          (define (print-descriptor descriptor-id type)
            (define (byte-length n) (div (+ (integer-length n) 7) 8))
            (let ([descriptor-name (format-internal-binding unique-global-name descriptor-id)])
              (printf "const ~a = ~a;\n\n"
                descriptor-name
                (nanopass-case (Ltypescript Type) type
                  [(tboolean ,src)
                   "__compactRuntime.CompactTypeBoolean"]
                  [(tfield ,src)
                   "__compactRuntime.CompactTypeField"]
                  [(tunsigned ,src ,nat)
                   (format "new __compactRuntime.CompactTypeUnsignedInteger(~dn, ~d)" nat (byte-length nat))]
                  [(tbytes ,src ,len)
                   (format "new __compactRuntime.CompactTypeBytes(~d)" len)]
                  [(topaque ,src ,opaque-type)
                   (case opaque-type
                     [("string") (format "__compactRuntime.CompactTypeOpaqueString")]
                     [("Uint8Array") (format "__compactRuntime.CompactTypeOpaqueUint8Array")]
                     ; FIXME: what should happen with other opaque types?
                     [else (source-errorf src "opaque type ~a is not supported" opaque-type)])]
                  [(tvector ,src ,len ,type)
                   (format "new __compactRuntime.CompactTypeVector(~d, ~a)"
                           len
                           (type->descriptor-name type))]
                  [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                   (assert cannot-happen)]
                  [(ttuple ,src ,type* ...)
                   (let ([tuple-name (format-internal-binding unique-global-name (make-temp-id src 'tuple))])
                     (print-tuple-class tuple-name type*)
                     (format "new ~a()" tuple-name))]
                  [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                   (let ([class-name (format-internal-binding unique-global-name (make-temp-id src struct-name))])
                     (print-struct-class class-name elt-name* type*)
                     (format "new ~a()" class-name))]
                  [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                   (let ([n (length elt-name*)])
                     (format "new __compactRuntime.CompactTypeEnum(~d, ~d)" n (byte-length n)))]
                  [(tunknown) (assert cannot-happen)]
                  [else (assert cannot-happen)]))))
          (for-each print-descriptor descriptor-id* type*))

        (module (print-contract-class)
          (define (ledger-initializers src state pl-array q*)
            (define (initialize-array pl-array stateValue q*)
              (cons*
                2 (format "let ~a = __compactRuntime.StateValue.newArray();" stateValue)
                (nanopass-case (Ltypescript Public-Ledger-Array) pl-array
                  [(public-ledger-array ,pl-array-elt* ...)
                   (fold-right
                     (lambda (pl-array-elt q*)
                       (nanopass-case (Ltypescript Public-Ledger-Array-Element) pl-array-elt
                         [,pl-array
                          (let ([stateValue^ (format-internal-binding unique-local-name (make-temp-id src 'stateValue))])
                            (initialize-array pl-array stateValue^
                              (cons*
                                2 (format "~a = ~:*~a.arrayPush(~a);" stateValue stateValue^)
                                q*)))]
                         [,public-binding
                          (cons*
                            2 (format "~a = ~:*~a.arrayPush(__compactRuntime.StateValue.newNull());" stateValue)
                            q*)]))
                     q*
                     pl-array-elt*)])))
            (let ([stateValue (format-internal-binding unique-local-name (make-temp-id src 'stateValue))])
              (initialize-array pl-array stateValue
                (cons*
                  2 (format "~a.data = new __compactRuntime.ChargedState(~a);" state stateValue)
                  q*))))

          (define (ledger-reset-to-default src pl-array q*)
            (define (find-adt-op ledger-op adt-op*)
              (assert (find (lambda (adt-op)
                              (nanopass-case (Ltypescript ADT-Op) adt-op
                                [(,ledger-op^ ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
                                 (eq? ledger-op^ ledger-op)]))
                            adt-op*)))
            (fold-right
              (lambda (public-binding q*)
                (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
                  [(,src ,ledger-field-name (,path-index* ...) (,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)))
                   (cons*
                     2 (construct-query src path-index* adt-formal* adt-arg* (find-adt-op 'resetToDefault adt-op*) '()) ";"
                     q*)]))
              q*
              (pl-array->public-bindings pl-array)))

          (module (argument-type-checks context-type-check result-type-check)
            (define (typeof adt-type var)
              (let ([adt-type (subst-tcontract adt-type)])
                (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
                  [(tboolean ,src) (format "typeof(~a) === 'boolean'" var)]
                  [(tfield ,src) (format "typeof(~a) === 'bigint' && ~:*~a >= 0 && ~:*~a <= __compactRuntime.MAX_FIELD" var)]
                  [(tunsigned ,src ,nat) (format "typeof(~a) === 'bigint' && ~:*~a >= 0n && ~:*~a <= ~dn" var nat)]
                  [(tbytes ,src ,len) (format "~a.buffer instanceof ArrayBuffer && ~:*~a.BYTES_PER_ELEMENT === 1 && ~:*~a.length === ~s" var len)]
                  [(topaque ,src ,opaque-type) "true"]
                  [(tvector ,src ,len ,type)
                   (format "Array.isArray(~a) && ~:*~a.length === ~d && ~2:*~a.every((t) => ~*~a)"
                           var len (typeof type "t"))]
                  [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                   (assert cannot-happen)]
                  [(ttuple ,src ,type* ...)
                   (format "Array.isArray(~a) && ~:*~a.length === ~d ~{ && ~a~}"
                     var
                     (length type*)
                     (map (lambda (eltno type) (typeof type (format "~a[~d]" var eltno)))
                          (enumerate type*)
                          type*))]
                  [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                   ; ignoring struct-name, so we're getting structural typing.  also ignoring extra fields.
                   (format "typeof(~a) === 'object'~{ && ~a~}" var (map (lambda (elt-name type) (typeof type (format "~a.~s" var elt-name))) elt-name* type*))]
                  [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                   (format "typeof(~a) === 'number' && ~:*~a >= 0 && ~:*~a <= ~d" var (length elt-name*))]
                  [(tunknown) (assert cannot-happen)]
                  [,public-adt (assert cannot-happen)])))

            (define (format-type adt-type)
              (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
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
                [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                 (format "Enum<~a, ~s~{, ~s~}>" enum-name elt-name elt-name*)]
                [,public-adt (assert cannot-happen)]))

            (define (argument-type-checks src what extra-arguments var-name* adt-type* q*)
              (fold-right
                (lambda (var-name adt-type i q*)
                  (let ([arg-name (format-id-reference var-name)])
                    (let ([typeof-expr (typeof adt-type arg-name)])
                      (if (equal? typeof-expr "true")
                          q*
                          (cons*
                            2
                            (make-Qconcat
                              "if (!("
                              typeof-expr
                              ")) {"
                              2 (compact-stdlib "typeError")
                              "("
                              ((make-Qsep ",")
                                (format "'~a'" what)
                                (let ([i (fx+ i 1)])
                                  (if (= extra-arguments 0)
                                      (format "'argument ~d'" i)
                                      (format "'argument ~d (argument ~d as invoked from Typescript)'" i (fx+ i extra-arguments))))
                                (format "'~a'" (format-source-object src))
                                (format "'~a'" (format-type adt-type))
                                arg-name)
                              ")"
                              0 "}")
                            q*)))))
                q*
                var-name*
                adt-type*
                (enumerate var-name*)))

            (define (context-type-check src what var q*)
              (cons*
                2 (make-Qconcat
                    "if (!("
                    ; we don't insist on currentPrivateState being defined
                    (format "typeof(~a) === 'object' && ~:*~a.currentQueryContext != undefined" var)
                    ")) {"
                    2 (compact-stdlib "typeError")
                    "("
                    ((make-Qsep ",")
                     (format "'~a'" what)
                     "'argument 1 (as invoked from Typescript)'"
                     (format "'~a'" (format-source-object src))
                     "'CircuitContext'"
                     var)
                    ")"
                    0 "}")
                q*))

            (define (result-type-check src what type result q*)
              (let ([typeof-expr (typeof type result)])
                (if (equal? typeof-expr "true")
                    q*
                    (cons*
                      2
                      (make-Qconcat
                        "if (!("
                        typeof-expr
                        ")) {"
                        2 (compact-stdlib "typeError")
                        "("
                        ((make-Qsep ",")
                          (format "'~a'" what)
                          "'return value'"
                          (format "'~a'" (format-source-object src))
                          (format "'~a'" (format-type type))
                          result)
                        ")"
                        0 "}")
                      q*)))))

          (define (witness-checks witnesses xpelt* q*)
            (cons*
              2 (format "if (typeof(~a) !== 'object') {" witnesses)
              4 (format "throw new ~a('first (witnesses) argument to Contract constructor is not an object');"
                        (compact-stdlib "CompactError"))
              2 "}"
              (fold-right
                (lambda (xpelt q*)
                  (XPelt-case xpelt
                    [(XPelt-witness src internal-id arg* type external-name)
                     (cons*
                       2 (format "if (typeof(~a.~a) !== 'function') {" witnesses external-name)
                       4 (format "throw new ~a('first (witnesses) argument to Contract constructor does not contain a function-valued field named ~a');"
                                 (compact-stdlib "CompactError")
                                 external-name)
                       2 "}"
                       q*)]
                    [else q*]))
                q*
                xpelt*)))

          (module (bind-args bind-args-with-context)
            (define (bind-arg-helper with-context? args)
              (lambda (q-name i q*)
                (cons* 2 "const " q-name (format " = ~a[~d];" args (if with-context? (+ i 1) i)) q*)))
            (define (bind-args args name* q*)
              (fold-right
                (bind-arg-helper #f args)
                q*
                name*
                (enumerate name*)))

            (define (bind-args-with-context ctxt args name* q*)
              (cons*
                2 "const " ctxt (format " = ~a[~d];" args 0)
                (fold-right
                  (bind-arg-helper #t args)
                q*
                name*
                (enumerate name*)))))

          (define (build-exported-pure-circuits xpelt* uname*)
            (apply (make-Qsep ",")
              (fold-right
                (lambda (xpelt uname q*)
                  (XPelt-case xpelt
                    [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
                     (if pure?
                        (for-each
                          (lambda (external-name)
                            (with-local-unique-names
                              (let* ([args (format-internal-binding unique-local-name (make-temp-id src 'args))]
                                     [q-formal* (map make-Qformal! arg*)]
                                     [nargs (length arg*)])
                                (cons
                                  (apply make-Qconcat/src src
                                    (make-Qconcat/src (id-src internal-id) external-name)
                                    (format ": (...~a) => {" args)
                                    2 (make-Qconcat
                                        (format "if (~a.length !== ~d) {" args nargs)
                                        2 (format "throw new ~a(`~a: expected ~d argument~:*~p (as invoked from Typescript), received ${~a.length}`);"
                                                  (compact-stdlib "CompactError")
                                                  (format "~a" external-name)
                                                  nargs
                                                  args)
                                        0 "}")
                                    (bind-args args q-formal*
                                      (argument-type-checks src external-name 0 (map arg->id arg*) (map arg->type arg*)
                                        (list
                                          2 "return _dummyContract." uname "(" (apply (make-Qsep ",") q-formal*) ");"
                                          0 "}"))))
                                  q*))))
                          external-name*)
                       q*)]
                    [else q*]))
                '()
                xpelt*
                uname*)))

          (define (build-exported-circuits xpelt* uname*)
            (apply (make-Qsep ",")
              (fold-right
                (lambda (xpelt uname q*)
                  (XPelt-case xpelt
                    [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
                     (if (not pure?)
                       (with-local-unique-names
                         (let* ([args (format-internal-binding unique-local-name (make-temp-id src 'args))]
                                [contextOrig (format-internal-binding unique-local-name (make-temp-id src 'contextOrig))]
                                [result (format-internal-binding unique-local-name (make-temp-id src 'result))]
                                [descriptor-name* (map type->descriptor-name (map arg->type arg*))]
                                [descriptor-name? (type->maybe-descriptor-name type)]
                                [q-formal* (map make-Qformal! arg*)]
                                [nargs (fx+ (length arg*) 1)])
                           (append
                             (map (lambda (external-name)
                                    (apply make-Qconcat/src src
                                      (make-Qconcat/src (id-src internal-id) external-name)
                                      (format ": (...~a) => {" args)
                                      2 (make-Qconcat
                                          (format "if (~a.length !== ~d) {" args nargs)
                                          2 (format "throw new ~a(`~a: expected ~d argument~:*~p (as invoked from Typescript), received ${~a.length}`);"
                                                    (compact-stdlib "CompactError")
                                                    (format "~a" external-name)
                                                    nargs
                                                    args)
                                          0 "}")
                                      (bind-args-with-context contextOrig args q-formal*
                                        (context-type-check src external-name contextOrig
                                          (argument-type-checks src external-name 1 (map arg->id arg*) (map arg->type arg*)
                                            (list
                                              ; Shallow clone context to ensure no-one else has a reference to it
                                              2 (format "const context = { ...~a, gasCost: __compactRuntime.emptyRunningCost() };" contextOrig)
                                              2 "const partialProofData = {"
                                              4 (make-Qconcat
                                                  "input: {"
                                                  2 ((make-Qsep ",")
                                                     (make-Qconcat
                                                       "value: "
                                                       (if (null? q-formal*)
                                                           "[]"
                                                           (let f ([descriptor-name* descriptor-name*]
                                                                   [q-formal* q-formal*])
                                                             (let ([descriptor-name (car descriptor-name*)]
                                                                   [q-formal (car q-formal*)]
                                                                   [descriptor-name* (cdr descriptor-name*)]
                                                                   [q-formal* (cdr q-formal*)])
                                                               (let ([q (make-Qconcat
                                                                          (format "~a.toValue(" descriptor-name)
                                                                          q-formal
                                                                          ")")])
                                                                 (if (null? descriptor-name*)
                                                                     q
                                                                     (make-Qconcat
                                                                       q
                                                                       ".concat("
                                                                       (f descriptor-name* q-formal*)
                                                                       ")")))))))
                                                     (make-Qconcat
                                                       "alignment: "
                                                       (if (null? q-formal*)
                                                           "[]"
                                                           (let f ([descriptor-name* descriptor-name*]
                                                                   [q-formal* q-formal*])
                                                             (let ([descriptor-name (car descriptor-name*)]
                                                                   [q-formal (car q-formal*)]
                                                                   [descriptor-name* (cdr descriptor-name*)]
                                                                   [q-formal* (cdr q-formal*)])
                                                               (let ([q (format "~a.alignment()" descriptor-name)])
                                                                 (if (null? descriptor-name*)
                                                                     q
                                                                     (make-Qconcat
                                                                       q
                                                                       ".concat("
                                                                       (f descriptor-name* q-formal*)
                                                                       ")"))))))))
                                                  0 "},")
                                              4 "output: undefined,"
                                              4 "publicTranscript: [],"
                                              4 "privateTranscriptOutputs: []"
                                              2 "};"
                                              2 (format "const ~a = this." result)
                                                uname "("
                                                (apply (make-Qsep ",") "context" "partialProofData" q-formal*)
                                                ");"
                                              2 "partialProofData.output = { "
                                                "value: " (if descriptor-name?
                                                              (format "~a.toValue(~a)" descriptor-name? result)
                                                              "[]")
                                                ", "
                                                "alignment: " (if descriptor-name?
                                                                  (format "~a.alignment()" descriptor-name?)
                                                                  "[]")
                                                " };"
                                              2 "return { "
                                                "result: " result ", "
                                                "context: " "context" ", "
                                                "proofData: " "partialProofData" ", "
                                                "gasCost: " "context.gasCost"
                                                " };"
                                              0 "}"))))))
                                  external-name*)
                             q*)))
                       (with-local-unique-names
                         (let ([args (format-internal-binding unique-local-name (make-temp-id src 'args))])
                           (append
                             (map (lambda (external-name)
                                    (make-Qconcat/src src
                                      (make-Qconcat/src (id-src internal-id) external-name)
                                      (format "(context, ...~a) {" args)
                                      2 (format "return { result: pureCircuits.~a(...~a), context };" external-name args)
                                      0 "}"))
                               external-name*)
                             q*))))]
                      [else q*]))
                '()
                xpelt*
                uname*)))

          (define (get-pure&impure-circuit-names xpelt*)
            (if (null? xpelt*)
                (values '() '())
                (let-values ([(pure-name* impure-name*) (get-pure&impure-circuit-names (cdr xpelt*))])
                  (XPelt-case (car xpelt*)
                    [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
                     (if pure?
                         (values
                           (append external-name* pure-name*)
                           impure-name*)
                         (values
                           pure-name*
                           (append external-name* impure-name*)))]
                    [else (values pure-name* impure-name*)]))))

          (define (get-witness-names xpelt*)
            (fold-right
              (lambda (xpelt witness-name*)
                (XPelt-case xpelt
                  [(XPelt-witness src internal-id arg* type external-name)
                   (cons external-name witness-name*)]
                  [else witness-name*]))
              '()
              xpelt*))

          (define (print-contract-constructor xpelt0* uname* impure-name*)
            (let loop ([xpelt* xpelt0*])
              (assert (not (null? xpelt*)))
              (XPelt-case (car xpelt*)
                [(XPelt-public-ledger pl-array lconstructor external-names)
                 (nanopass-case (Ltypescript Ledger-Constructor) lconstructor
                   [(constructor ,src (,arg* ...) ,stmt)
                    (with-local-unique-names
                      (print-Q 2
                        (let* ([witnesses (format-internal-binding unique-local-name (make-temp-id src 'witnesses))]
                               [args (format-internal-binding unique-local-name (make-temp-id src 'args))]
                               [nargs 1])
                          (apply make-Qconcat/src src
                                 (format "constructor(...~a) {" args)
                                 2 (format "if (~a.length !== ~d) {" args nargs)
                                 4 (format "throw new __compactRuntime.CompactError(`Contract constructor: expected ~d argument~:*~p, received ${~a.length}`);" nargs args)
                                 2 "}"
                                 (bind-args args (list witnesses)
                                   (witness-checks witnesses xpelt0*
                                     (list
                                       2 (format "this.witnesses = ~a;" witnesses)
                                       2 "this.circuits = {"
                                       4 (build-exported-circuits xpelt0* uname*)
                                       2 "};"
                                       2 (apply make-Qconcat
                                           "this.impureCircuits = {"
                                           (if (null? impure-name*)
                                               (list "};")
                                               (let f ([impure-name* impure-name*])
                                                 (let ([impure-name (car impure-name*)]
                                                       [impure-name* (cdr impure-name*)])
                                                   (let ([q (format "~a: this.circuits.~:*~a" impure-name)])
                                                     (if (null? impure-name*)
                                                         (list 2 q 0 "};")
                                                         (cons* 2 q "," (f impure-name*))))))))
                                       0 "}")))))))
                    (newline)])]
                [else (loop (cdr xpelt*))])))

          (define (print-contract-ledger src xpelt0* uname*)
            (with-local-unique-names
              (define (ledger-field-Q src path-elt* adt-arg* all-op*)
                (apply (make-Qsep ",")
                  (map (lambda (op)
                         (with-local-unique-names
                           (let-values ([(var-name* adt-type*) (op-args op)])
                             (let ([formal* (map (lambda (var-name) (format-internal-binding unique-local-name var-name)) var-name*)]
                                   [args (format-internal-binding unique-local-name (make-temp-id src 'args))]
                                   [nargs (length var-name*)]
                                   [name (op-name op)])
                               (apply make-Qconcat
                                 (maybe-iterator name)
                                 (format "(...~a) {" args)
                                 2 (format "if (~a.length !== ~d) {" args nargs)
                                 4 (format "throw new __compactRuntime.CompactError(`~a: expected ~d argument~:*~p, received ${~a.length}`);" name nargs args)
                                 2 "}"
                                 (bind-args args formal*
                                   (argument-type-checks src name 0 var-name* adt-type*
                                     (list
                                       2 (adt-op-body-Q src op path-elt* formal* adt-arg*)
                                       0 "}"))))))))
                       (remp (lambda (op)
                               ; run-time ops like iterators that expect to be supplied a descriptor
                               ; for use in decoding values.  we don't have a decoder for adt values, and if we did,
                               ; it's not clear what they would do with an adt value anyway.  so we just don't
                               ; generate such runtime ops.
                               (and (Ltypescript-ADT-Runtime-Op? op)
                                    (ormap (lambda (adt-arg)
                                             (nanopass-case (Ltypescript Public-Ledger-ADT-Arg) adt-arg
                                               [,public-adt #t]
                                               [else #f]))
                                           adt-arg*)))
                             all-op*))))
              (define (adt-op-body-Q src adt-op path-elt* formal* adt-arg*)
                (define (path-chain-Q path-elt*)
                  (apply make-Qconcat
                         (map (lambda (path-elt)
                                (nanopass-case (Ltypescript Path-Element) path-elt
                                  [,path-index (format ".asArray()[~d]" path-index)]
                                  [(,src ,type ,expr) (make-Qconcat
                                                        ".asMap().get("
                                                        (construct-typed-value
                                                          (type->descriptor-name type)
                                                          (Expr expr (precedence add1 comma) #f))
                                                        ")")]))
                              path-elt*)))
                (if (Ltypescript-ADT-Op? adt-op)
                    (nanopass-case (Ltypescript ADT-Op) adt-op
                      [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
                       (if (Ltypescript-Public-Ledger-ADT? adt-type)
                           (begin
                             (assert (and (eq? ledger-op 'lookup)
                                          (fx= (length adt-type*) 1)
                                          (Ltypescript-Type? (car adt-type*))))
                             (let ([path-elt* (append path-elt*
                                                      (list (with-output-language (Ltypescript Path-Element)
                                                              `(,src ,(car adt-type*) (var-ref ,src ,(car var-name*))))))])
                               (make-Qconcat
                                 "if (state"
                                 (path-chain-Q path-elt*)
                                 " === undefined) {"
                                 2 "throw new __compactRuntime.CompactError("
                                 (format "`Map value undefined for ${~a}`" (format-id-reference (car var-name*)))
                                 ");"
                                 0 "}"
                                 0 "return {"
                                 2 (nanopass-case (Ltypescript Public-Ledger-ADT) adt-type
                                     [(,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
                                      (let* ([all-op* (filter is-runtime-op? (append adt-op* adt-rt-op*))]
                                             [all-op* (cond [(has-read? all-op*) => list] [else all-op*])])
                                        (ledger-field-Q src path-elt* adt-arg* all-op*))])
                                 0 "}")))
                           (let ([q (construct-query src path-elt* adt-formal* adt-arg* adt-op formal*)])
                             (let ([descriptor-name? (and (eq? op-class 'read)
                                                          (type->maybe-descriptor-name adt-type))])
                               (if descriptor-name?
                                   (make-Qconcat
                                     "return "
                                     descriptor-name?
                                     ".fromValue("
                                     q
                                     ".value);")
                                   ; at present, this shouldn't happen.  we don't include side-effecting
                                   ; operations in ledger(state) return value, so all operations should
                                   ; return a value that needs to be decoded
                                   q))))])
                    (nanopass-case (Ltypescript ADT-Runtime-Op) adt-op
                      [(,ledger-op (,arg* ...) ,result-type ,runtime-code)
                       (let ([self (format-internal-binding unique-local-name (make-temp-id src 'self))])
                         (make-Qconcat
                           (format "const ~a = state" self)
                           (path-chain-Q path-elt*)
                           ";"
                           0 "return "
                           (apply make-Qconcat
                             (apply runtime-code
                                    "__compactRuntime."
                                    self
                                    (append
                                      formal*
                                      (map (lambda (adt-arg)
                                             (nanopass-case (Ltypescript Public-Ledger-ADT-Arg) adt-arg
                                               [,nat (number->string nat)]
                                               [,type (type->descriptor-name type)]
                                               [,public-adt (assert cannot-happen)]))
                                           adt-arg*))))
                           ";"))])))
              (define (op-args adt-op)
                (if (Ltypescript-ADT-Op? adt-op)
                    (nanopass-case (Ltypescript ADT-Op) adt-op
                      [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
                       (values var-name* adt-type*)])
                    (nanopass-case (Ltypescript ADT-Runtime-Op) adt-op
                      [(,ledger-op ((,var-name* ,type*) ...) ,result-type ,runtime-code)
                       (values var-name* type*)])))
              (let loop ([xpelt* xpelt0*])
                (assert (not (null? xpelt*)))
                (XPelt-case (car xpelt*)
                  [(XPelt-public-ledger pl-array lconstructor external-names)
                   (print-Q 0
                      (make-Qconcat
                        "export function ledger(stateOrChargedState) {"
                        2 "const state = stateOrChargedState instanceof __compactRuntime.StateValue ? stateOrChargedState : stateOrChargedState.state;"
                        2 "const chargedState = stateOrChargedState instanceof __compactRuntime.StateValue ? new __compactRuntime.ChargedState(stateOrChargedState) : stateOrChargedState;"
                        2 "const context = {"
                        4 "currentQueryContext: new __compactRuntime.QueryContext(chargedState, __compactRuntime.dummyContractAddress()),"
                        4 "costModel: __compactRuntime.CostModel.initialCostModel()"
                        2 "};"
                        2 "const partialProofData = {"
                        4 "input: { value: [], alignment: [] },"
                        4 "output: undefined,"
                        4 "publicTranscript: [],"
                        4 "privateTranscriptOutputs: []"
                        2 "};"
                        2 "return {"
                        4 (apply (make-Qsep ",")
                            (fold-right
                              (lambda (binding q*)
                                (nanopass-case (Ltypescript Public-Ledger-Binding) binding
                                  [(,src ,ledger-field-name (,path-index* ...) (,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...)))
                                   (fold-right
                                     (lambda (export-name q*)
                                       (cons
                                         (let* ([all-op* (filter is-runtime-op? (append adt-op* adt-rt-op*))]
                                                [read-op (has-read? all-op*)])
                                           (if read-op
                                               (make-Qconcat/src src
                                                                 "get "
                                                                 export-name
                                                                 "() {"
                                                                 2 (adt-op-body-Q src read-op path-index* '() adt-arg*)
                                                                 0 "}")
                                               (make-Qconcat/src src
                                                                 export-name
                                                                 ": {"
                                                                 2 (ledger-field-Q src path-index* adt-arg* all-op*)
                                                                 0 "}")))
                                         q*))
                                     q*
                                     (external-names ledger-field-name))]))
                              '()
                              (filter
                                exported-public-binding?
                                (pl-array->public-bindings pl-array))))
                        2 "};"
                        0 "}"))
                   (newline)]
                  [else (loop (cdr xpelt*))]))))

          (define (set-operations state xpelt* q*)
            (fold-right
              (lambda (xpelt q*)
                (XPelt-case xpelt
                  [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
                   (if pure?
                       q*
                       (fold-right
                         (lambda (external-name q*)
                           (cons*
                             2 (format
                                 "~a.setOperation('~a', new __compactRuntime.ContractOperation());"
                                 state
                                 external-name)
                             q*))
                         q*
                         external-name*))]
                  [else q*]))
              q*
              xpelt*))

          (define (print-contract-initializer xpelt0* uname*)
            (let loop ([xpelt* xpelt0*])
              (assert (not (null? xpelt*)))
              (XPelt-case (car xpelt*)
                [(XPelt-public-ledger pl-array lconstructor external-names)
                 (nanopass-case (Ltypescript Ledger-Constructor) lconstructor
                   [(constructor ,src (,arg* ...) ,stmt)
                    (with-local-unique-names
                      (print-Q 2
                        (let* ([args (format-internal-binding unique-local-name (make-temp-id src 'args))]
                               [constructorContext (format-internal-binding unique-local-name (make-temp-id src 'constructorContext))]
                               [state (format-internal-binding unique-local-name (make-temp-id src 'state))]
                               [q-formal* (map make-Qformal! arg*)]
                               [nargs (fx+ (length arg*) 1)])
                          (define (maybe-add-private-state-check k)
                            (if (null? (get-witness-names xpelt0*))
                                k
                                (cons*
                                  2 (format "if (!('initialPrivateState' in ~a)) {" constructorContext)
                                  4 "throw new __compactRuntime.CompactError(`Contract state constructor: expected 'initialPrivateState' in argument 1 (as invoked from Typescript)`);"
                                  2 "}"
                                  k)))
                          (apply make-Qconcat/src src
                                 (format "initialState(...~a) {" args)
                                 2 (format "if (~a.length !== ~d) {" args nargs)
                                 4 (format "throw new __compactRuntime.CompactError(`Contract state constructor: expected ~d argument~:*~p (as invoked from Typescript), received ${~a.length}`);" nargs args)
                                 2 "}"
                                 (bind-args args (cons constructorContext q-formal*)
                                   (cons*
                                     2 (format "if (typeof(~a) !== 'object') {" constructorContext)
                                     4 "throw new __compactRuntime.CompactError(`Contract state constructor: expected 'constructorContext' in argument 1 (as invoked from Typescript) to be an object`);"
                                     2 "}"
                                     (maybe-add-private-state-check
                                       (cons*
                                         2 (format "if (!('initialZswapLocalState' in ~a)) {" constructorContext)
                                         4 "throw new __compactRuntime.CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript)`);"
                                         2 "}"
                                         2 (format "if (typeof(~a.initialZswapLocalState) !== 'object') {" constructorContext)
                                         4 "throw new __compactRuntime.CompactError(`Contract state constructor: expected 'initialZswapLocalState' in argument 1 (as invoked from Typescript) to be an object`);"
                                         2 "}"
                                         (argument-type-checks src "Contract state constructor" 1 (map arg->id arg*) (map arg->type arg*)
                                           (cons*
                                             2 (format "const ~a = new __compactRuntime.ContractState();" state)
                                             (ledger-initializers src state pl-array
                                               (set-operations state xpelt0*
                                                 (cons*
                                                   2 (format "const context = __compactRuntime.createCircuitContext(__compactRuntime.dummyContractAddress(), ~a.initialZswapLocalState.coinPublicKey, ~a.data, ~a.initialPrivateState);" constructorContext state constructorContext)
                                                   2 "const partialProofData = {"
                                                   4 "input: { value: [], alignment: [] },"
                                                   4 "output: undefined,"
                                                   4 "publicTranscript: [],"
                                                   4 "privateTranscriptOutputs: []"
                                                   2 "};"
                                                   (ledger-reset-to-default src pl-array
                                                     (list
                                                       2 (Stmt stmt #f #f)
                                                       2 (format "~a.data = context.currentQueryContext.state;" state)
                                                       2 "return {"
                                                       4 (format "currentContractState: ~a," state)
                                                       4 "currentPrivateState: context.currentPrivateState,"
                                                       4 "currentZswapLocalState: context.currentZswapLocalState"
                                                       2 "}"
                                                       0 "}")))))))))))))))
                    (newline)])]
                [else (loop (cdr xpelt*))])))

          (define (print-unexported-circuit xpelt uname)
            (define (print-local-circuit src internal-id arg* stmt pure?)
              (with-local-unique-names
                (print-Q 2
                  (let ([q-formal* (map make-Qformal! arg*)])
                    (make-Qconcat/src src
                      (make-Qconcat
                        (make-Qconcat/src (id-src internal-id) (format "~a" uname))
                        "("
                        (make-Qargs pure? q-formal*)
                        ")"
                        0 "{")
                      2 (Stmt stmt #t pure?)
                      0 "}"))))
              (newline))
            (XPelt-case xpelt
              [(XPelt-exported-circuit src internal-id arg* type stmt external-name* pure?)
               (print-local-circuit src internal-id arg* stmt pure?)]
              [(XPelt-internal-circuit src internal-id arg* type stmt pure?)
               (print-local-circuit src internal-id arg* stmt pure?)]
              [(XPelt-witness src internal-id arg* type external-name)
               (print-external-witness src internal-id uname arg* type external-name)]
              [(XPelt-external-circuit src internal-id native-entry arg* type external-name pure?)
               (print-external-circuit src internal-id native-entry uname arg* type external-name pure?)]
              [else (void)]))

          (define (print-external-circuit src internal-id native-entry uname arg* type external-name pure?)
            (with-local-unique-names
              (let ([q-formal* (map make-Qformal! arg*)]
                    [result (format-internal-binding unique-local-name (make-temp-id src 'result))])
                (define (maybe-add-trascript-push q*)
                  (if (eq? (native-entry-class native-entry) 'witness)
                      (let ([descriptor-name? (type->maybe-descriptor-name type)])
                        (cons*
                          2 "partialProofData.privateTranscriptOutputs.push({"
                          4 "value: " (if descriptor-name?
                                          (format "~a.toValue(~a)" descriptor-name? result)
                                          "[]")
                          ","
                          4 "alignment: " (if descriptor-name?
                                              (format "~a.alignment()" descriptor-name?)
                                              "[]")
                          2 "});"
                          q*))
                      q*))
                (print-Q 2
                  (apply make-Qconcat/src src
                    (make-Qconcat
                      (make-Qconcat/src (id-src internal-id) (format "~a" uname))
                      "("
                      (make-Qargs pure? q-formal*)
                      ")"
                      0 "{")
                    2 (format "const ~a = " result)
                    (make-Qconcat
                      (native-entry-function native-entry)
                      "("
                      (apply (make-Qsep ",")
                             (fold-right
                               (let ([ht (make-hashtable symbol-hash eq?)])
                                 (lambda (native-type type q*)
                                   (native-type-case native-type
                                     [(native-type-param name)
                                      (if (hashtable-contains? ht name)
                                          q*
                                          (begin
                                            (hashtable-set! ht name #t)
                                            (cons
                                              (type->descriptor-name type)
                                              q*)))]
                                      [else q*])))
                               (let ([arg-q* (map (lambda (arg)
                                                    (let ([var-name (arg->id arg)])
                                                      (make-Qconcat/src
                                                        (id-src var-name)
                                                        (format-id-reference var-name))))
                                                  arg*)])
                                 (if (eq? (native-entry-class native-entry) 'witness)
                                     (cons "context" arg-q*)
                                     arg-q*))
                               (append
                                 (native-entry-argument-types native-entry)
                                 (list (native-entry-result-type native-entry)))
                               (append
                                 (map arg->type arg*)
                                 (list type))))
                      ")")
                    ";"
                    (maybe-add-trascript-push
                      (list
                        2 "return " result ";"
                        0 "}"))))))
            (newline))

          (define (print-external-witness src internal-id uname arg* type external-name)
            (with-local-unique-names
              (let ([result (format-internal-binding unique-local-name (make-temp-id src 'result))]
                    [witnessContext (format-internal-binding unique-local-name (make-temp-id src 'witnessContext))]
                    [nextPrivateState (format-internal-binding unique-local-name (make-temp-id src 'nextPrivateState))]
                    [descriptor-name? (type->maybe-descriptor-name type)])
                (print-Q 2
                  (let ([q-formal* (map make-Qformal! arg*)])
                    (apply make-Qconcat/src src
                      (make-Qconcat
                        (make-Qconcat/src (id-src internal-id) (format "~a" uname))
                        "("
                        (make-Qargs #f q-formal*)
                        ")"
                        0 "{")
                      2 (format "const ~a = __compactRuntime.createWitnessContext(ledger(context.currentQueryContext.state), context.currentPrivateState, context.currentQueryContext.address);" witnessContext)
                      2 (format "const [~a, ~a] = " nextPrivateState result)
                      "this.witnesses."
                      (make-Qconcat/src (id-src internal-id) external-name)
                      "("
                      (apply (make-Qsep ",") witnessContext q-formal*)
                      ");"
                      2 (format "context.currentPrivateState = ~a;" nextPrivateState)
                      (result-type-check src external-name type result
                        (list
                          2 "partialProofData.privateTranscriptOutputs.push({"
                          4 "value: " (if descriptor-name?
                                          (format "~a.toValue(~a)" descriptor-name? result)
                                          "[]")
                            ","
                          4 "alignment: " (if descriptor-name?
                                              (format "~a.alignment()" descriptor-name?)
                                              "[]")
                          2 "});"
                          2 "return "
                          result
                          ";"
                          0 "}")))))
                (newline))))

          (define (print-contract-class src xpelt* uname*)
            (with-local-unique-names
              (demand-unique-local-name! "this")
              (demand-unique-local-name! "context")
              (demand-unique-local-name! "partialProofData")
              (let-values ([(pure-name* impure-name*) (get-pure&impure-circuit-names xpelt*)])
                (display-string "export class Contract {\n")
                (display-string "  witnesses;\n")
                (fluid-let ([helper* '()])
                  (print-contract-constructor xpelt* uname* impure-name*)
                  (print-contract-initializer xpelt* uname*)
                  (for-each print-unexported-circuit xpelt* uname*)
                  (for-each display-string (reverse helper*)))
                (display-string "}\n")
                (print-contract-ledger src xpelt* uname*)
                (display-string "const _emptyContext = {\n")
                (display-string "  currentQueryContext: new __compactRuntime.QueryContext(new __compactRuntime.ContractState().data, __compactRuntime.dummyContractAddress())\n")
                (display-string "};\n")
                (print-Q 0
                  (make-Qconcat
                    "const _dummyContract = new Contract({"
                    2 (apply (make-Qsep ",")
                             (map (lambda (witness-name)
                                    (format "~a: (...args) => undefined" witness-name))
                                  (get-witness-names xpelt*)))
                    0 "});"))
                (newline)
                (print-Q 0
                  (apply make-Qconcat
                    "export const pureCircuits = {"
                    (if (null? pure-name*)
                        (list "};")
                        (list 2 (build-exported-pure-circuits xpelt* uname*) 0 "};"))))
                (newline)))))

        (define (print-exported-types xpelt*)
          (for-each
            (lambda (xpelt)
              (XPelt-case xpelt
                [(XPelt-type-definition src type-name export-name tvar-name* type)
                 (nanopass-case (Ltypescript Type) type
                   [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                    (void)]
                   [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                    (printf "export var ~a;\n" export-name)
                    (printf "(function (~a) {\n" export-name)
                    (let ([elt-name* (cons elt-name elt-name*)])
                      (for-each
                        (lambda (elt-name i)
                          (printf "  ~a[~:*~a['~a'] = ~d] = '~2:*~a';\n" export-name elt-name i))
                        elt-name*
                        (enumerate elt-name*)))
                    (printf "})(~a || (~:*~a = {}));\n\n" export-name)]
                   [else (assert cannot-happen)])]
                [else (void)]))
            xpelt*))

        (module (print-contract-reference-locations)
          (define (do-type type)
            (nanopass-case (Ltypescript Type) type
              [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
               (make-Qconcat
                 "{"
                 1 "tag: 'contractAddress'"
                 0 "}")]
              [(tvector ,src ,len ,type)
               (guard (not (= len 0)))
               (let ([q (do-type type)])
                 (and q
                      (make-Qconcat
                        "{"
                        1 ((make-Qsep ",")
                           "tag: 'vector'"
                           (make-Qconcat "sparseType: " q))
                        0 "}")))]
              [(ttuple ,src ,type* ...)
               ; FIXME: need to teach the runtime about this.
               ; tuple is like publicLedgerArray; consider replacing latter with former
               (let ([q* (map do-type type*)] [i* (enumerate type*)])
                 (and (ormap values q*)
                      (make-Qconcat
                        "{"
                        1 ((make-Qsep ",")
                            "tag: 'tuple'"
                            (make-Qconcat
                              "indices: {"
                              2 (apply (make-Qsep ",")
                                  (fold-right
                                    (lambda (q i q*)
                                      (if q
                                          (cons
                                            (make-Qconcat
                                              (format "~d: " i)
                                              q)
                                            q*)
                                          q*))
                                    '()
                                    q*
                                    (enumerate type*)))
                              0 "}"))
                        0 "}")))]
              [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
               (let ([q* (map do-type type*)])
                 (and (ormap values q*)
                      (make-Qconcat
                        "{"
                        1 ((make-Qsep ",")
                           "tag: 'struct'"
                           (make-Qconcat
                             "elements: "
                             2 (make-Qconcat
                                 "{"
                                 1 (apply (make-Qsep ",")
                                     (fold-right
                                       (lambda (elt-name q q*)
                                         (if q
                                             (cons
                                               (make-Qconcat (format "~a: " elt-name) q)
                                               q*)
                                             q*))
                                       '()
                                       elt-name*
                                       q*))
                                 0 "}")))
                        0 "}")))]
              [else #f]))
          (define (do-adt-arg adt-arg)
            (nanopass-case (Ltypescript Public-Ledger-ADT-Arg) adt-arg
              ; can't get a nat at present since only merkle trees have nat adt-args
              ; and contract references cannot be retrieved from merkle trees
              [,nat #f]
              [,type (let ([q (do-type type)])
                       (and q
                            (make-Qconcat
                              "{"
                              1 ((make-Qsep ",")
                                 "tag: 'compactValue'"
                                 (make-Qconcat "descriptor: " (type->descriptor-name type))
                                 (make-Qconcat "sparseType: " q))
                              0 "}")))]
              [,public-adt (do-public-adt public-adt)]))
          (define (do-public-adt public-adt)
            (nanopass-case (Ltypescript Public-Ledger-ADT) public-adt
              [(,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
               ; FIXME: building in knowledge of the ledger here
               ; contract references cannot be retreived from merkle trees
               (and (not (or (eq? adt-name 'MerkleTree) (eq? adt-name 'HistoricMerkleTree)))
                    (let ([maybe-q* (map do-adt-arg adt-arg*)])
                      (and (ormap values maybe-q*)
                           (make-Qconcat
                             "{ "
                             1 (apply (make-Qsep ",")
                                      (format "tag: '~a'"
                                        (if (eq? adt-name '__compact_Cell)
                                            "cell"
                                            (to-camel-case (symbol->string adt-name) #f)))
                                      (fold-right
                                        (lambda (adt-formal maybe-q q*)
                                          (if maybe-q
                                              (cons
                                                (make-Qconcat
                                                  (format "~a: " (to-camel-case (symbol->string adt-formal) #f))
                                                  maybe-q)
                                                q*)
                                              q*))
                                        '()
                                        adt-formal*
                                        maybe-q*))
                             0 "}"))))]))
          (define (do-public-binding public-binding)
            (nanopass-case (Ltypescript Public-Ledger-Binding) public-binding
              [(,src ,ledger-field-name (,path-index* ...) ,public-adt)
               (do-public-adt public-adt)]))
          (define (do-pl-array-elt pl-array-elt)
            (nanopass-case (Ltypescript Public-Ledger-Array-Element) pl-array-elt
              [,pl-array (do-pl-array pl-array #f)]
              [,public-binding (do-public-binding public-binding)]))
          (define (do-pl-array pl-array even-if-empty?)
            (nanopass-case (Ltypescript Public-Ledger-Array) pl-array
              [(public-ledger-array ,pl-array-elt* ...)
               (let ([maybe-q* (map do-pl-array-elt pl-array-elt*)])
                 (and (or even-if-empty? (ormap values maybe-q*))
                      (make-Qconcat
                        "{"
                        1 ((make-Qsep ",")
                            "tag: 'publicLedgerArray'"
                            (make-Qconcat
                              "indices: {"
                              2 (apply (make-Qsep ",")
                                  (fold-right
                                    (lambda (maybe-q i q*)
                                      (if maybe-q
                                          (cons
                                            (make-Qconcat
                                              (format "~d: " i)
                                              maybe-q)
                                            q*)
                                          q*))
                                    '()
                                    maybe-q*
                                    (enumerate pl-array-elt*)))
                              0 "}"))
                        0 "}")))]))
          (define (print-contract-reference-locations xpelt)
            (XPelt-case xpelt
              [(XPelt-public-ledger pl-array ledger-constructor external-names)
               (print-Q 0
                 (make-Qconcat
                   "export const contractReferenceLocations ="
                   2 (do-pl-array pl-array #t)
                   ";"))
               (newline)]
              [else (void)])))

        (define (print-contract-footer)
          (display-string "//# sourceMappingURL=index.js.map\n"))

        (define (print-contract.js src descriptor-id* type* xpelt* uname*)
          (parameterize ([current-output-port (get-target-port 'contract.js)])
            (fluid-let ([sourcemap-tracker (make-sourcemap-tracker)])
              (let-values ([(contract-dependency* contract-has-witness-ht) (get-contract-dependencies)])
                (print-contract-header)
                (print-exported-types xpelt*)
                (print-contract-descriptors src descriptor-id* type*)
                (print-contract-class src xpelt* uname*)
                (for-each print-contract-reference-locations xpelt*)
                (print-contract-footer)
                (record-sourcemap-eof! sourcemap-tracker (port-position (current-output-port)))
                (display-sourcemap sourcemap-tracker (get-target-port 'contract.js.map)))))))

      (define (format-javascript-string s)
        (define quote-seen #f)
        ((lambda (s) (format "~c~a~2:*~c" (if (eqv? quote-seen #\') #\" #\') s))
         (with-output-to-string
           (lambda ()
             (let ([n (string-length s)])
               (do ([i 0 (fx+ i 1)])
                   ((fx= i n))
                 (let ([c (string-ref s i)])
                   (cond
                     [(or (char=? c #\") (char=? c #\'))
                      (cond
                        [(not quote-seen) (set! quote-seen c)]
                        [(eqv? c quote-seen)]
                        [else (write-char #\\)])
                      (write-char c)]
                     [(char=? c #\\) (display-string "\\\\")]
                     [(or (char<=? #\x20 c #\x7e)
                          (and (char>=? c #\x80)
                               (not (char=? c #\nel))
                               (not (char=? c #\ls))))
                      (write-char c)]
                     [(char=? c #\newline) (display-string "\\n")]
                     [(char=? c #\return) (display-string "\\r")]
                     [(char=? c #\nul) (display-string "\\0")]
                     [(char=? c #\backspace) (display-string "\\b")]
                     [(char=? c #\page) (display-string "\\f")]
                     [(char=? c #\tab) (display-string "\\t")]
                     [(char=? c #\vtab) (display-string "\\v")]
                     [(char<=? c #\xFF) (printf "\\x~2,'0x" (char->integer c))]
                     [else (printf "\\u~4,'0x" (char->integer c))]))))))))


      ;; The Q mechanism defined below is used for pretty-printing of generated javascript.
      ;; "Q" doesn't stand for anything; it's just an arbitrary flag identifiying entites
      ;; related to pretty-printing.

      ;; A Q is a string, a fixnum, or a Q record.
      ;;  string:   used to signify what will actually be printed
      ;;  fixnum:   used for spacing and indentation
      ;;  Qconcat:  formed from a sequence of Qs and used for grouping
      ;;  Qsegment: formed from a source object and a flag saying whether
      ;;            it marks the start or end of a source region and used
      ;;            to emit source-map segments to a source-map file

      ;; Every Q has a size:
      ;;   string:   the string's length
      ;;   fixnum:   1
      ;;   Qconcat:  sum of the sizes of its consituents
      ;;   Qsegment: 0

      ;; When a Q is printed, the sum of its size and the current indentation is
      ;; compared with the target line length.

      ;; If there is enough room, the entire Q is printed on one line as follows:
      ;;   string:   print the contents of the string
      ;;   fixnum:   print a space
      ;;   Qconcat:  print the components in sequence
      ;;   Qsegment: emit source-map segment to the map file

      ;; If there isn't enough room, the Q is potentially printed on multiple lines:
      ;;   string:   print the contents of the string
      ;;             (even if it runs beyond the end of the line)
      ;;   fixnum:   print a newline followed by n spaces, where n is the sum of the
      ;;             fixnum and the starting column of the closest enclosing Qconcat.
      ;;             should be used only in a sequence (i.e., within a Qconcat), where
      ;;             it increases the current indentation for the next item in the
      ;;             sequence only
      ;;   Qconcat:  recur on the constituents in sequence at the current indentation
      ;;   Qsegment: emit source-map segment to the map file
      
      ;; There are a few synthetic Q types (Qsep, Qconcat/src, and Qformal) that are
      ;; constructed    from the base Q types:
      ;;   Qsep:        takes a separator (e.g., "," or ";") and returns a procedure
      ;;                that constructs a qconcat with the separator placed between the
      ;;                elements.
      ;;   Qconcat/src: creates a Qconcat with a Qsegment on each end
      ;;   Qformal:     creates a Qconcat/src from an identifier, extracting the
      ;;                src and string to print from the identifier

      ;; A Qformal must be created before any references to the formal are created.

      (define-record-type Q
        (nongenerative)
        (fields (immutable size $Q-size)))
      (define (Q-size x)
        (cond
          [(string? x) (string-length x)]
          [(fixnum? x) 1]
          [(Q? x) ($Q-size x)]
          [else (internal-errorf 'Q-size "unrecognized Q ~s" x)]))
      (define-record-type Qconcat
        (nongenerative)
        (parent Q)
        (fields q*)
        (protocol
          (lambda (p->new)
            (lambda q*
              ((p->new (apply fx+ (map Q-size q*)))
               q*)))))
      (define-record-type Qsegment
        (nongenerative)
        (parent Q)
        (fields src start?)
        (protocol
          (lambda (p->new)
            (lambda (src start?)
              ((p->new 0)
               src start?)))))
      (define (make-Qsep sep)
        (case-lambda
          [() ""]
          [(q . q*)
           (apply make-Qconcat
             q
             (fold-right
               (lambda (q q*) (cons* sep 0 q q*))
               '()
               q*))]))
      (define (make-Qconcat/src src . q*)
        (apply make-Qconcat
          (cons
            (make-Qsegment src #t)
            (append q* (list (make-Qsegment src #f))))))
      (define (make-Qlocal! local)
        ; make-Qlocal! calls format-internal-binding, which must be called before
        ; format-id-reference is called on the same id
        (nanopass-case (Ltypescript Local) local
          [(,var-name ,adt-type)
           (make-Qconcat/src
             (id-src var-name)
             (format-internal-binding unique-local-name var-name))]))
      (define (make-Qlocals! . arg*)
        (apply (make-Qsep ",") (map make-Qlocal! arg*)))
      (define (make-Qformal! arg)
        ; make-Qformal! calls format-internal-binding, which must be called before
        ; format-id-reference is called on the same id
        (nanopass-case (Ltypescript Argument) arg
          [(,var-name ,type)
           (make-Qconcat/src
             (id-src var-name)
             (format-internal-binding unique-local-name var-name))]))
      (define (make-Qformals! . arg*)
        (apply (make-Qsep ",") (map make-Qformal! arg*)))
      (define (make-Qargs pure? q-formal*)
        (if pure?
            (apply (make-Qsep ",") q-formal*)
            (apply (make-Qsep ",") (cons* "context" "partialProofData" q-formal*))))

      (define (parenthesize required-level inner-level q)
        (if (>= inner-level required-level)
            q
            (make-Qconcat "(" q ")")))

      (define (print-indent indent) (printf "~v@t" indent))

      (define (for-each/sep use-sep p ls . ls*)
        (let loop ([ls ls] [ls* ls*] [sep ""])
          (unless (null? ls)
            (display-string sep)
            (apply p (car ls) (map car ls*))
            (loop (cdr ls) (map cdr ls*) use-sep))))

      (define (print-Q indent q)
        (define line-length 80)
        (print-indent indent)
        (let f ([q* (list q)] [col indent] [reset-col indent] [break? #f])
          (if (null? q*)
              col
              (let ([q (car q*)] [q* (cdr q*)])
                (cond
                  [(fixnum? q)
                   (cond
                     [(null? q*) (f q* col reset-col break?)]
                     [(equal? (car q*) "") (f (cdr q*) col reset-col break?)]
                     [break?
                      (let ([col (fx+ reset-col q)])
                        (newline)
                        (print-indent col)
                        (f q* col reset-col break?))]
                     [else
                      (write-char #\space)
                      (f q* (fx+ col 1) reset-col break?)])]
                  [(string? q)
                   (display-string q)
                   (f q* (fx+ col (Q-size q)) reset-col break?)]
                  [(Qsegment? q)
                   (record-sourcemap-segment! sourcemap-tracker (Qsegment-src q) (Qsegment-start? q))
                   (f q* col reset-col break?)]
                  [(Qconcat? q)
                   (let ([col (f (Qconcat-q* q) col col (fx> (fx+ col (Q-size q)) line-length))])
                     (f q* col reset-col break?))]
                  [else (assert cannot-happen)])))))
      )
    (Program : Program (ir) -> Program ()
      [(program ,src ((,export-name* ,name*) ...) (type-descriptors ,descriptor-table^ (,descriptor-id* ,type*) ...) ,pelt* ...)
       (let* ([xpelt* (maplr (lambda (x) (Program-Element x (map cons export-name* name*))) pelt*)]
              [uname* (maplr xpelt->uname xpelt*)])
         (print-contract.d.ts src xpelt* uname*)
         (fluid-let ([descriptor-table descriptor-table^])
           (print-contract.js src descriptor-id* type* xpelt* uname*)))
       ir])
    (Program-Element : Program-Element (ir export-alist) -> * (xpelt)
      (definitions
        (define (external-names id)
          (fold-right
            (lambda (a external-name*)
              (if (eq? (cdr a) id)
                  (cons (symbol->string (car a)) external-name*)
                  external-name*))
            '()
            export-alist)))
      [(circuit ,src ,function-name (,arg* ...) ,type ,stmt)
       (if (id-exported? function-name)
           (let ([external-name* (external-names function-name)])
             (XPelt-exported-circuit src function-name arg* type stmt external-name* (id-pure? function-name)))
           (XPelt-internal-circuit src function-name arg* type stmt (id-pure? function-name)))]
      [(witness ,src ,function-name (,arg* ...) ,type)
       (let ([external-name (symbol->string (id-sym function-name))])
         (XPelt-witness src function-name arg* type external-name))]
      [(external ,src ,function-name ,native-entry (,arg* ...) ,type)
       (let ([external-name (symbol->string (id-sym function-name))])
         (XPelt-external-circuit src function-name native-entry arg* type external-name (id-pure? function-name)))]
      [(type-definition ,src ,type-name (,tvar-name* ...) ,type)
       (let ([actual-type-name
              (nanopass-case (Ltypescript Type) type
                [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) struct-name]
                [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) enum-name]
                [else (assert cannot-happen)])])
         (XPelt-type-definition src actual-type-name type-name tvar-name* type))]
      [(public-ledger-declaration ,pl-array ,lconstructor)
       (XPelt-public-ledger pl-array lconstructor external-names)]
      [,kdecl (XPelt-ledger-kernel)])
    (Untyped-Argument : Argument (ir) -> * (str)
      [(,var-name ,type)
       (format-internal-binding unique-local-name var-name)])
    (Typed-Argument : Argument (ir) -> * (str)
      [(,var-name ,[Type : type -> * type])
       (make-Qconcat (format-internal-binding unique-local-name var-name) ": " type)])
    (Stmt : Statement (ir return? outer-pure?) -> * (Q)
      [(if ,src ,[Expr : expr (precedence add1 none) outer-pure? -> * expr] ,[* stmt])
       (make-Qconcat
         (make-Qconcat
           "if ("
           expr
           ")"
           0 "{")
         2 stmt
         0 "}")]
      [(if ,src ,[Expr : expr (precedence add1 none) outer-pure? -> * expr] ,[* stmt1] ,[* stmt2])
       (make-Qconcat
         (make-Qconcat
           "if ("
           expr
           ")"
           0 "{")
         2 stmt1
         0 "} else {"
         2 stmt2
         0 "}")]
      [(seq ,src ,stmt* ... ,stmt)
       (let* ([stmt* (maplr (lambda (stmt) (Stmt stmt #f outer-pure?)) stmt*)]
              [stmt (Stmt stmt return? outer-pure?)]
              [stmt+ (if (and (> (length stmt*) 0) (equal? stmt "return;"))
                         stmt*
                         (append stmt* (list stmt)))])
         (apply make-Qconcat
                (car stmt+)
                (fold-right
                  (lambda (stmt q*) (cons* 0 stmt q*))
                  '()
                  (cdr stmt+))))]
      [(const ,src ,local ,[Expr : expr (precedence add1 =) outer-pure? -> * expr])
       (make-Qconcat
         "const " 
         (make-Qlocal! local)
         " = "
         expr
         ";")]
      [(const ,src (,local* ...))
       (make-Qconcat
         "let " 
         (apply make-Qlocals! local*)
         ";")]
      [(statement-expression (tuple ,src))
       (guard (not return?))
       ""]
      [(statement-expression ,[Expr : expr (precedence add1 none) outer-pure? -> * expr])
       (if return?
           (make-Qconcat "return " expr ";")
           (make-Qconcat expr ";"))])
    (Expr : Expression (ir level outer-pure?) -> * (Q)
      (definitions
        (define (make-tuple tuple-arg*)
          (make-Qconcat
            "["
            (apply (make-Qsep ",")
              (map
                (lambda (tuple-arg)
                  (nanopass-case (Ltypescript Tuple-Argument) tuple-arg
                    [(single ,src ,expr)
                     (Expr expr (precedence add1 comma) outer-pure?)]
                    [(spread ,src ,nat ,expr)
                     (make-Qconcat "..." (Expr expr (precedence add1 comma) outer-pure?))]))
                tuple-arg*))
            "]"))
        (define (build-equal-helper! type equal-name)
          (define (build-equal-body type)
            (with-output-to-string
              (lambda ()
                (let f ([type type] [i 0] [indent 4])
                  (nanopass-case (Ltypescript Type) type
                    [(tbytes ,src ,len)
                     (print-indent indent)
                     (printf "if (!x~s.every((x, i) => y~:*~s[i] === x)) { return false; }\n" i)]
                    [(tvector ,src ,len ,type)
                     (print-indent indent)
                     (printf "for (let i~s = 0; i~:*~s < ~s; i~2:*~s++) {\n" i len)
                     (let ([next-i (fx+ i 1)] [next-indent (fx+ indent 2)])
                       (print-indent next-indent)
                       (printf "let x~s = x~s[i~:*~s];\n" next-i i)
                       (print-indent next-indent)
                       (printf "let y~s = y~s[i~:*~s];\n" next-i i)
                       (f type next-i next-indent))
                     (print-indent indent)
                     (printf "}\n")]
                    [(ttuple ,src ,type* ...)
                     (for-each
                       (lambda (eltno type)
                         (print-indent indent)
                         (printf "{\n")
                         (let ([next-i (fx+ i 1)] [next-indent (fx+ indent 2)])
                           (print-indent next-indent)
                           (printf "let x~s = x~s[~d];\n" next-i i eltno)
                           (print-indent next-indent)
                           (printf "let y~s = y~s[~d];\n" next-i i eltno)
                           (f type next-i next-indent))
                         (print-indent indent)
                         (printf "}\n"))
                       (enumerate type*)
                       type*)]
                    [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
                     (for-each
                       (lambda (elt-name type)
                         (print-indent indent)
                         (printf "{\n")
                         (let ([next-i (fx+ i 1)] [next-indent (fx+ indent 2)])
                           (print-indent next-indent)
                           (printf "let x~s = x~s.~s;\n" next-i i elt-name)
                           (print-indent next-indent)
                           (printf "let y~s = y~s.~s;\n" next-i i elt-name)
                           (f type next-i next-indent))
                         (print-indent indent)
                         (printf "}\n"))
                       elt-name*
                       type*)]
                    [else
                     (print-indent indent)
                     (printf "if (x~s !== y~:*~s) { return false; }\n" i)])))))
          (parenthesize level (precedence call)
            (set! helper*
              (cons
                (format "  ~a(x0, y0) {\n~a    return true;\n  }\n"
                  equal-name
                  (build-equal-body type))
                helper*))))
        )
      [(quote ,src ,datum)
       (cond
         [(field? datum) (format "~dn" datum)]
         [(boolean? datum) (if datum "true" "false")]
         [(bytevector? datum)
          (parenthesize level (precedence new)
            (format "new Uint8Array([~{~a~^, ~}])"
              (bytevector->u8-list datum)))]
         [else (assert cannot-happen)])]
      [(var-ref ,src ,var-name)
       (make-Qconcat/src src (format-id-reference var-name))]
      [(default ,src ,adt-type)
       (let default-value ([adt-type adt-type])
         ; even though tstruct is substituted for tcontract, we will never generate a default value
         ; for a tcontract since that would be caught earlier. so this substitution is safe.
         (let ([adt-type (subst-tcontract adt-type)])
           (nanopass-case (Ltypescript Public-Ledger-ADT-Type) adt-type
             [(tboolean ,src) "false"]
             [(tfield ,src) "0n"]
             [(tunsigned ,src ,nat) "0n"]
             [(tbytes ,src ,len)
              (parenthesize level (precedence new)
                (format "new Uint8Array(~d)" len))]
             [(topaque ,src ,opaque-type)
              (case opaque-type
                [("string") "''"]
                [("Uint8Array") "new Uint8Array(0)"]
                ; FIXME: what should happen with other opaque types?
                [else (source-errorf src "opaque type ~a is not supported" opaque-type)])]
             [(tvector ,src ,len ,type)
              (parenthesize level (precedence new)
                (format "new Array(~a).fill(~a)"
                  len
                  (default-value type)))]
             [(ttuple ,src ,type* ...)
              (format "[~{~a~^, ~}]" (map default-value type*))]
             [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
              (format "{ ~{~a~^, ~} }"
                (map (lambda (elt-name type)
                       (format "~a: ~a" elt-name (default-value type)))
                     elt-name*
                     type*))]
             [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) "0"]
             ; FIXME: this should not appear in the output at present, but might if we implement
             ; first-class ADT values
             [,public-adt "undefined"]
             [else (assert cannot-happen)])))]
      [(not ,src ,[Expr : expr (precedence not) outer-pure? -> * expr])
       (parenthesize level (precedence not)
         (make-Qconcat "!" expr))]
      [(and ,src ,[Expr : expr1 (precedence and) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 and) outer-pure? -> * expr2])
       (parenthesize level (precedence and)
         (make-Qconcat expr1 0 "&&" 0 expr2))]
      [(or ,src ,[Expr : expr1 (precedence or) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 or) outer-pure? -> * expr2])
       (parenthesize level (precedence or)
         (make-Qconcat expr1 0 "||" 0 expr2))]
      [(if ,src ,[Expr : expr0 (precedence add1 if) outer-pure? -> * expr0] ,[Expr : expr1 (precedence if) outer-pure? -> * expr1] ,[Expr : expr2 (precedence if) outer-pure? -> * expr2])
       (parenthesize level (precedence if)
         (make-Qconcat
           (make-Qconcat expr0 0 "?")
           0 (make-Qconcat expr1 0 ":")
           0 expr2))]
      [(elt-ref ,src ,[Expr : expr (precedence struct-ref) outer-pure? -> * expr] ,elt-name ,nat)
       (parenthesize level (precedence struct-ref)
         (make-Qconcat
           expr
           "."
           (format "~s" elt-name)))]
      [(enum-ref ,src ,type ,elt-name^)
       (parenthesize level (precedence call)
         (nanopass-case (Ltypescript Type) type
           [(tenum ,src^ ,enum-name ,elt-name ,elt-name* ...)
            (let loop ([elt-name elt-name] [elt-name* elt-name*] [i 0])
              (if (eq? elt-name elt-name^)
                  (format "~d" i)
                  (begin
                    (assert (not (null? elt-name*)))
                    (loop (car elt-name*) (cdr elt-name*) (fx+ i 1)))))]
           [else (assert cannot-happen)]))]
      [(tuple ,src ,tuple-arg* ...)
       (make-tuple tuple-arg*)]
      [(vector ,src ,tuple-arg* ...)
       (make-tuple tuple-arg*)]
      [(tuple-ref ,src ,[Expr : expr (precedence vector-ref) outer-pure? -> * expr] ,kindex)
       (parenthesize level (precedence vector-ref)
         (make-Qconcat expr (format "[~d]" kindex)))]
      [(bytes-ref ,src ,type ,[Expr : expr (precedence vector-ref) outer-pure? -> * expr] ,[Expr : index (precedence add1 comma) outer-pure? -> * index])
       ; NB: counting on check in optimize/resolve-indices to guarantee that the computed
       ; index cannot be out-of-range
       (parenthesize level (precedence vector-ref)
         (make-Qconcat "BigInt(" expr "[" index "])"))]
      [(vector-ref ,src ,type ,[Expr : expr (precedence vector-ref) outer-pure? -> * expr] ,[Expr : index (precedence add1 comma) outer-pure? -> * index])
       ; NB: counting on check in optimize/resolve-indices to guarantee that the computed
       ; index cannot be out-of-range
       (parenthesize level (precedence vector-ref)
         (make-Qconcat expr "[" index "]"))]
      [(tuple-slice ,src ,type ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,kindex ,len)
       (parenthesize level (precedence call)
         (make-Qconcat
           (format "((e) => e.slice(~d, ~d))(" kindex (+ kindex len))
           expr
           ")"))]
      [(bytes-slice ,src ,type ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,[Expr : index (precedence add1 comma) outer-pure? -> * index] ,len)
       ; NB: counting on check in optimize/resolve-indices to guarantee that the computed
       ; index + len cannot be out-of-range
       (parenthesize level (precedence call)
         (make-Qconcat
           (format "((e, i) => e.slice(i, i+~d))(" len)
           ((make-Qsep ",") expr (make-Qconcat "Number(" index ")"))
           ")"))]
      [(vector-slice ,src ,type ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,[Expr : index (precedence add1 comma) outer-pure? -> * index] ,len)
       ; NB: counting on check in optimize/resolve-indices to guarantee that the computed
       ; index + len cannot be out-of-range
       (parenthesize level (precedence call)
         (make-Qconcat
           (format "((e, i) => e.slice(i, i+~d))(" len)
           ((make-Qsep ",") expr (make-Qconcat "Number(" index ")"))
           ")"))]
      [(+ ,src ,mbits ,[Expr : expr1 (precedence add1 comma) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 comma) outer-pure? -> * expr2])
       (guard (not mbits))
       (parenthesize level (precedence call)
         (make-Qconcat
           (compact-stdlib "addField")
           "("
           ((make-Qsep ",") expr1 expr2)
           ")"))]
      [(+ ,src ,mbits ,[Expr : expr1 (precedence +) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 +) outer-pure? -> * expr2])
       (parenthesize level (precedence +)
         ; infer-type guarantees that the result is in range via range analysis
         (make-Qconcat expr1 0 "+" 0 expr2))]
      [(- ,src ,mbits ,[Expr : expr1 (precedence add1 comma) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 comma) outer-pure? -> * expr2])
       (guard (not mbits))
       (parenthesize level (precedence call)
         (make-Qconcat
           (compact-stdlib "subField")
           "("
           ((make-Qsep ",") expr1 expr2)
           ")"))]
      [(- ,src ,mbits ,[Expr : expr1 (precedence -) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 -) outer-pure? -> * expr2])
       (parenthesize level (precedence -)
         ; infer-type guarantees that the result isn't negative by inserting a run-time check
         (make-Qconcat expr1 0 "-" 0 expr2))]
      [(* ,src ,mbits ,[Expr : expr1 (precedence add1 comma) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 comma) outer-pure? -> * expr2])
       (guard (not mbits))
       (parenthesize level (precedence call)
         (make-Qconcat
           (compact-stdlib "mulField")
           "("
           ((make-Qsep ",") expr1 expr2)
           ")"))]
      [(* ,src ,mbits ,[Expr : expr1 (precedence *) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 *) outer-pure? -> * expr2])
       (parenthesize level (precedence *)
         ; infer-type guarantees that the result is in range via range analysis
         (make-Qconcat expr1 0 "*" 0 expr2))]
      [(< ,src ,mbits ,[Expr : expr1 (precedence <) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 <) outer-pure? -> * expr2])
       (parenthesize level (precedence <)
         (make-Qconcat expr1 0 "<" 0 expr2))]
      [(<= ,src ,mbits ,[Expr : expr1 (precedence <=) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 <=) outer-pure? -> * expr2])
       (parenthesize level (precedence <=)
         (make-Qconcat expr1 0 "<=" 0 expr2))]
      [(> ,src ,mbits ,[Expr : expr1 (precedence >) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 >) outer-pure? -> * expr2])
       (parenthesize level (precedence >)
         (make-Qconcat expr1 0 ">" 0 expr2))]
      [(>= ,src ,mbits ,[Expr : expr1 (precedence >=) outer-pure? -> * expr1] ,[Expr : expr2 (precedence add1 >=) outer-pure? -> * expr2])
       (parenthesize level (precedence >=)
         (make-Qconcat expr1 0 ">=" 0 expr2))]
      [(== ,src ,type ,expr1 ,expr2)
       (if (nanopass-case (Ltypescript Type) type
             [(tboolean ,src) #t]
             [(tfield ,src) #t]
             [(topaque ,src ,opaque-type) #t]
             [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #t]
             [else #f])
           (parenthesize level (precedence ==)
             (make-Qconcat
               (Expr expr1 (precedence ==) outer-pure?)
               0 "==="
               0 (Expr expr2 (precedence add1 ==) outer-pure?)))
           (parenthesize level (precedence call)
             (let ([equal-name (unique-global-name "equal")])
               (build-equal-helper! type equal-name)
               (make-Qconcat
                 "this."
                 equal-name
                 "("
                 ((make-Qsep ",")
                  (Expr expr1 (precedence add1 comma) outer-pure?)
                  (Expr expr2 (precedence add1 comma) outer-pure?))
                 ")"))))]
      [(!= ,src ,type ,expr1 ,expr2)
       (if (nanopass-case (Ltypescript Type) type
             [(tboolean ,src) #t]
             [(tfield ,src) #t]
             [(topaque ,src ,opaque-type) #t]
             [(tenum ,src ,enum-name ,elt-name ,elt-name* ...) #t]
             [else #f])
           (parenthesize level (precedence ==)
             (make-Qconcat
               (Expr expr1 (precedence ==) outer-pure?)
               0 "!=="
               0 (Expr expr2 (precedence add1 ==) outer-pure?)))
           (parenthesize level (precedence not)
             (let ([equal-name (unique-global-name "equal")])
               (build-equal-helper! type equal-name)
               (make-Qconcat
                 "!this."
                 equal-name
                 "("
                 ((make-Qsep ",")
                  (Expr expr1 (precedence add1 comma) outer-pure?)
                  (Expr expr2 (precedence add1 comma) outer-pure?))
                 ")"))))]
      [(map ,src ,len ,[Function : fun0 outer-pure? -> * fun]
            ,[Map-Argument : map-arg (precedence add1 comma) outer-pure? -> * expr byte-ref?]
            ,[Map-Argument : map-arg* (precedence add1 comma) outer-pure? -> * expr* byte-ref?*]
            ...)
       (let ([mapper-name (unique-global-name "mapper")]
             [pure? (nanopass-case (Ltypescript Function) fun0
                      [(fref ,src ,function-name) (id-pure? function-name)]
                      [else outer-pure?])])
         (set! helper*
           (cons
             (let ([i+ (enumerate (cons expr expr*))])
               (format "  ~a(~@[~*context, partialProofData, ~]f, ~{~a~^, ~}) {\n    let a = [];\n    for (let i = 0; i < ~a; i++) { a[i] = f(~@[~*context, partialProofData, ~]~{~a~^, ~}); }\n    return a;\n  }\n"
                 mapper-name
                 (not pure?)
                 (map (lambda (i) (format "a~s" i)) i+)
                 len
                 (not pure?)
                 (map (lambda (i byte-ref?)
                        (let ([ref (format "a~d[i]" i)])
                          (if byte-ref? (format "BigInt(~a)" ref) ref)))
                      i+
                      (cons byte-ref? byte-ref?*))))
             helper*))
         (parenthesize level (precedence call)
           (make-Qconcat
             "this."
             mapper-name
             "("
             (make-Qargs pure?
               (cons*
                 (nanopass-case (Ltypescript Function) fun0
                   [(fref ,src ,function-name)
                    (let ([args (format-internal-binding unique-local-name (make-temp-id src 'args))])
                      (make-Qconcat "(..." args ") =>" 2 fun "(..." args ")"))]
                   [else fun])
                 expr
                 expr*))
             ")")))]
      [(fold ,src ,len ,[Function : fun0 outer-pure? -> * fun]
             (,[Expr : expr0 (precedence add1 comma) outer-pure? -> * expr0] ,type)
             ,[Map-Argument : map-arg (precedence add1 comma) outer-pure? -> * expr byte-ref?]
             ,[Map-Argument : map-arg* (precedence add1 comma) outer-pure? -> * expr* byte-ref?*]
             ...)
       (let ([folder-name (unique-global-name "folder")]
             [pure? (nanopass-case (Ltypescript Function) fun0
                      [(fref ,src ,function-name) (id-pure? function-name)]
                      [else outer-pure?])])
         (set! helper*
           (cons
             (let ([i+ (enumerate (cons expr expr*))])
               (format "  ~a(~@[~*context, partialProofData, ~]f, x, ~{~a~^, ~}) {\n    for (let i = 0; i < ~a; i++) { x = f(~@[~*context, partialProofData, ~]x, ~{~a~^, ~}); }\n    return x;\n  }\n"
                 folder-name
                 (not pure?)
                 (map (lambda (i) (format "a~s" i)) i+)
                 len
                 (not pure?)
                 (map (lambda (i byte-ref?)
                        (let ([ref (format "a~d[i]" i)])
                          (if byte-ref? (format "BigInt(~a)" ref) ref)))
                      i+
                      (cons byte-ref? byte-ref?*))))
             helper*))
         (parenthesize level (precedence call)
           (make-Qconcat
             "this."
             folder-name
             "("
             (make-Qargs pure?
               (cons*
                 (nanopass-case (Ltypescript Function) fun0
                   [(fref ,src ,function-name)
                    (let ([args (format-internal-binding unique-local-name (make-temp-id src 'args))])
                      (make-Qconcat "(..." args ") =>" 2 fun "(..." args ")"))]
                   [else fun])
                 expr0
                 expr
                 expr*))
             ")")))]
      [(call ,src ,function-name ,[Expr : expr* (precedence add1 comma) outer-pure? -> * expr*] ...)
       (parenthesize level (precedence call)
         (make-Qconcat
           (format-function-reference src function-name)
           "("
           (make-Qargs (id-pure? function-name) expr*)
           ")"))]
      [(new ,src ,type ,[Expr : expr* (precedence add1 comma) outer-pure? -> * expr*] ...)
       (nanopass-case (Ltypescript Type) type
         [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
          (make-Qconcat
            "{ "
            (apply (make-Qsep ",")
              (map (lambda (elt-name expr)
                     (make-Qconcat (format "~a" elt-name) ":" 2 expr))
                   elt-name*
                   expr*))
            " }")]
         [else (assert cannot-happen)])]
      ; can't happen because no one-element seqs are produced by upstream passes
      [(seq ,src ,[Expr : expr level outer-pure? -> * expr]) expr]
      [(seq ,src ,[Expr : expr* (precedence add1 comma) outer-pure? -> * expr*] ... ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence comma)
         (apply (make-Qsep ",") (append expr* (list expr))))]
      [(= ,src ,var-name ,[Expr : expr (precedence =) outer-pure? -> * expr])
       (parenthesize level (precedence =)
         (make-Qconcat
           (format-id-reference var-name)
           " = "
           expr))]
      [(assert ,src ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,mesg)
       (parenthesize level (precedence call)
         (make-Qconcat
           (compact-stdlib "assert")
           "("
           ((make-Qsep ",")
             expr
             (format-javascript-string mesg))
           ")"))]
      [(field->bytes ,src ,len ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (make-Qconcat
           (compact-stdlib "convertFieldToBytes")
           "("
           ((make-Qsep ",") (format "~d" len) expr (format "'~a'" (format-source-object src)))
           ")"))]
      [(cast-from-bytes ,src ,type ,len ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (nanopass-case (Ltypescript Type) type
           [(tfield ,src^)
            (make-Qconcat
              (compact-stdlib "convertBytesToField")
              "("
              ((make-Qsep ",") (format "~d" len) expr (format "'~a'" (format-source-object src)))
              ")")]
           [(tunsigned ,src^ ,nat^)
            (make-Qconcat
              (compact-stdlib "convertBytesToUint")
              "("
              ((make-Qsep ",") (format "~d" nat^) (format "~d" len) expr (format "'~a'" (format-source-object src)))
              ")")]
           [else (assert cannot-happen)]))]
      [(vector->bytes ,src ,len ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (make-Qconcat
           "Uint8Array.from("
           ((make-Qsep ",") expr "Number")
           ")"))]
      [(bytes->vector ,src ,len ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (make-Qconcat
           "Array.from("
           ((make-Qsep ",") expr "BigInt")
           ")"))]
      [(cast-from-enum ,src ,type ,type^ ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (let-values ([(enum-name maxval)
                       (nanopass-case (Ltypescript Type) type^
                         [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                          (values enum-name (length elt-name*))]
                         [else (assert cannot-happen)])])
           (cond
             [(nanopass-case (Ltypescript Type) type
                [(tfield ,src) #f]
                [(tunsigned ,src ,nat) (guard (< nat maxval)) nat]
                [else #f]) =>
              (lambda (nat)
                (make-Qconcat
                  "((t1) => {"
                  2 (format "if (t1 > ~d) {" nat)
                  4 (format "throw new ~a('~a: cast from enum ~a to Uint<0..~d> failed: enum value ' + t1 + ' is greater than ~d');"
                      (compact-stdlib "CompactError")
                      (format-source-object src)
                      enum-name
                      (+ nat 1)
                      nat)
                  2 "}"
                  2 "return BigInt(t1);"
                  0 "})("
                  expr
                  ")"))]
             [else (make-Qconcat "BigInt(" expr ")")])))]
      [(cast-to-enum ,src ,type ,type^ ,[Expr : expr (precedence add1 comma) outer-pure? -> * expr])
       (parenthesize level (precedence call)
         (let-values ([(enum-name maxval)
                       (nanopass-case (Ltypescript Type) type
                         [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
                          (values enum-name (length elt-name*))]
                         [else (assert cannot-happen)])])
           (if (nanopass-case (Ltypescript Type) type
                 [(tunsigned ,src ,nat) (<= nat maxval)]
                 [else #f])
               (make-Qconcat "Number(" expr ")")
               (make-Qconcat
                 "((t1) => {"
                 2 (format "if (t1 > ~dn) {" maxval)
                 4 (format "throw new ~a('~a: cast from Field or Uint value to enum ~a failed: ' + t1 + ' is greater than maximum enum value ~dn');"
                     (compact-stdlib "CompactError")
                     (format-source-object src)
                     enum-name
                     maxval)
                 2 "}"
                 2 "return Number(t1);"
                 0 "})("
                 expr
                 ")"))))]
      [(downcast-unsigned ,src ,nat ,expr)
       (let ([expr (Expr expr (precedence add1 comma) outer-pure?)])
         (parenthesize level (precedence call)
           (make-Qconcat
             "((t1) => {"
             2 (format "if (t1 > ~an) {" nat)
             4 (format "throw new ~a('~a: cast from Field or Uint value to smaller Uint value failed: ' + t1 + ' is greater than ~a');"
                 (compact-stdlib "CompactError")
                 (format-source-object src)
                 nat)
             2 "}"
             2 "return t1;"
             0 "})("
             expr
             ")")))]
      [(safe-cast ,src ,type ,type^ ,expr)
       ; no checks needed for safe casts
       (Expr expr level outer-pure?)]
      [(public-ledger ,src ,ledger-field-name ,sugar? (,path-elt* ...) ,src^ ,adt-op ,[Expr : expr* (precedence add1 comma) outer-pure? -> * expr*] ...)
       (nanopass-case (Ltypescript ADT-Op) adt-op
         [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,adt-type*) ...) ,adt-type ,vm-code)
          ; this should be caught by ledger meta-type checks or by propagate-ledger-paths
          (when (Ltypescript-Public-Ledger-ADT? adt-type) (source-errorf src "incomplete reference to nested ADT"))
          (let ([descriptor-name? (and (eq? op-class 'read) (type->maybe-descriptor-name adt-type))])
            (let ([q (construct-query src path-elt* adt-formal* adt-arg* adt-op expr*)])
              (nanopass-case (Ltypescript Type) adt-type
                [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
                 (assert not-implemented)]
                [else
                 (if descriptor-name?
                     (make-Qconcat
                       descriptor-name?
                       ".fromValue("
                       q
                       ".value)")
                     q)])))])]
      [(contract-call ,src ,elt-name (,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,type) ,[Expr : expr* (precedence add1 comma) outer-pure? -> * expr*] ...)
       (source-errorf src "contract types are not yet implemented")])
    (Map-Argument : Map-Argument (ir level outer-pure?) -> * (Q byte-ref?)
      [(,[Expr : expr (precedence add1 comma) outer-pure? -> * expr] ,type ,type^)
       (values
         expr
         (nanopass-case (Ltypescript Type) type
           [(tbytes ,src ,len) #t]
           [else #f]))])
    (Function : Function (ir outer-pure?) -> * (str)
      [(fref ,src ,function-name) (format-function-reference src function-name)]
      [(circuit ,src (,arg* ...) ,type ,stmt)
       (let ([q-formal* (map make-Qformal! arg*)])
         (make-Qconcat
           "("
           (make-Qconcat
             "("
             (make-Qargs outer-pure? q-formal*)
             ") =>"
             0 "{"
             2 (Stmt stmt #t outer-pure?)
             0 "}")
           ")"))])
    (Type : Type (ir) -> * (str)
      (definitions
        (define (same-type? type1 type2)
          (and (unify-type '() type1 type2) #t))
        (define (unify-type tvar-name* type1 type2)
          (define-syntax T
            (syntax-rules ()
              [(T ty clause ...)
               (nanopass-case (Ltypescript Type) ty clause ... [else #f])]))
          (let ([subst* (map (lambda (x) (cons x #f)) tvar-name*)])
            (and (let unify? ([type1 type1] [type2 type2])
                   (T type1
                      [,tvar-name1
                       (cond
                         [(assq tvar-name1 subst*) =>
                          (lambda (a)
                            (if (eq? (cdr a) #f)
                                (begin (set-cdr! a type2) #t)
                                (same-type? (cdr a) type2)))]
                         [else
                          ; can't happen at present, since type2 should not contain tvar refs
                          (T type2 [,tvar-name2 (eq? tvar-name1 tvar-name2)])])]
                      [(tboolean ,src) (T type2 [(tboolean ,src) #t])]
                      [(tfield ,src) (T type2 [(tfield ,src) #t] [(tunsigned ,src ,nat2) #t])]
                      [(tunsigned ,src ,nat1) (T type2 [(tunsigned ,src ,nat2) #t] [(tfield ,src) #t])]
                      [(tbytes ,src ,len1) (T type2 [(tbytes ,src ,len2) #t])]
                      [(topaque ,src ,opaque-type1) (T type2 [(topaque ,src ,opaque-type2) (string=? opaque-type1 opaque-type2)])]
                      [(tvector ,src ,len1 ,type1) (T type2 [(tvector ,src ,len2 ,type2) (unify? type1 type2)])]
                      [(tcontract ,src1 ,contract-name1 (,elt-name1* ,pure-dcl1* (,type1** ...) ,type1*) ...)
                       (T type2
                          [(tcontract ,src2 ,contract-name2 (,elt-name2* ,pure-dcl2* (,type2** ...) ,type2*) ...)
                           (define (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*)
                             (andmap (lambda (elt-name2 pure-dcl2 type2* type2)
                                       (ormap (lambda (elt-name1 pure-dcl1 type1* type1)
                                                (and (eq? elt-name1 elt-name2)
                                                     (eq? pure-dcl1 pure-dcl2)
                                                     (fx= (length type1*) (length type2*))
                                                     (andmap unify? type1* type2*)
                                                     (unify? type1 type2)))
                                         elt-name1* pure-dcl1* type1** type1*))
                               elt-name2* pure-dcl2* type2** type2*))
                            (and (eq? contract-name1 contract-name2)
                                 (fx= (length elt-name1*) (length elt-name2*))
                                 (circuit-superset? elt-name1* pure-dcl1* type1** type1* elt-name2* pure-dcl2* type2** type2*))])]
                      [(ttuple ,src ,type1* ...)
                       (T type2
                          [(ttuple ,src ,type2* ...)
                           (and (fx= (length type1*) (length type2*))
                                (andmap unify? type1* type2*))])]
                      [(tstruct ,src ,struct-name1 (,elt-name1* ,type1*) ...)
                       (T type2
                          [(tstruct ,src ,struct-name2 (,elt-name2* ,type2*) ...)
                           (and (eq? struct-name1 struct-name2)
                                (fx= (length elt-name1*) (length elt-name2*))
                                (andmap eq? elt-name1* elt-name2*)
                                (andmap unify? type1* type2*))])]
                      [(tenum ,src ,enum-name1 ,elt-name1 ,elt-name1* ...)
                       (T type2
                          [(tenum ,src ,enum-name2 ,elt-name2 ,elt-name2* ...)
                           (and (eq? enum-name1 enum-name2)
                                (eq? elt-name1 elt-name2)
                                (fx= (length elt-name1*) (length elt-name2*))
                                (andmap eq? elt-name1* elt-name2*))])]))
                 (map cdr subst*)))))
      [,tvar-name (symbol->string tvar-name)]
      [(tboolean ,src) "boolean"]
      [(tfield ,src) "bigint"]
      [(tunsigned ,src ,nat) "bigint"]
      [(tbytes ,src ,len) "Uint8Array"]
      [(topaque ,src ,opaque-type)
       (case opaque-type
         [("string" "Uint8Array") opaque-type]
         ; FIXME: what should happen with other opaque types?
         [else (source-errorf src "opaque type ~a is not supported" opaque-type)])]
      [(tvector ,src ,len ,[Type : type -> * type])
       (make-Qconcat type "[]")]
      [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
       "{ bytes: Uint8Array }"]
      [(ttuple ,src ,type* ...)
       (make-Qconcat
         "["
         (apply (make-Qsep ",")
           (map Type type*))
         "]")]
      [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
       (or (ormap (lambda (tinfo)
                    (cond
                      [(unify-type (tinfo-tvar* tinfo) (tinfo-type tinfo) ir) =>
                       (lambda (maybe-type*)
                         (let ([q (format "~a" (tinfo-export-name tinfo))])
                           (if (null? maybe-type*)
                               q
                               (make-Qconcat
                                 q
                                 "<"
                                 (apply (make-Qsep ",")
                                        (map (lambda (maybe-type)
                                               (if maybe-type
                                                   (Type maybe-type)
                                                   "any"))
                                             maybe-type*))
                                 ">"))))]
                      [else #f]))
                  (hashtable-ref exported-type-ht struct-name '()))
           (make-Qconcat
             "{ "
             (apply (make-Qsep ",")
                    (map (lambda (elt-name type)
                           (make-Qconcat (format "~a" elt-name) ": " (Type type)))
                         elt-name*
                         type*))
             0 "}"))]
      [(tenum ,src ,enum-name ,elt-name ,elt-name* ...)
       (or (ormap (lambda (tinfo)
                    (and (null? (tinfo-tvar* tinfo))
                         (same-type? (tinfo-type tinfo) ir)
                         (symbol->string (tinfo-export-name tinfo))))
                  (hashtable-ref exported-type-ht enum-name '()))
           ; FIXME: we could create a new global definition with a unique global name generated
           ;        from enum-name to avoid using just "number" as the type, preferably avoiding duplicates
           "number")]
      [else (assert cannot-happen)]))

  (define-passes typescript-passes
    (prepare-for-typescript          Ltypescript)
    (print-typescript                Ltypescript))
)
