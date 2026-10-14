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

(define-pass extract-analyzed-ir : Lloweredemit (ir proof-circuit-name*) -> * (sexp)
  (definitions
    (define (fail what x) (internal-errorf 'save-analyzed-ir "unsupported ~a: ~s" what x))

    (define (id->sym i) (string->symbol (format "~a" i)))

    ;; Scan the result because a type parameter can occur there without appearing in an argument.
    (define (native-type-argument* native-entry arg* type)
      (let ([seen (make-hashtable symbol-hash eq?)])
        (fold-right
          (lambda (maybe-type-param type acc)
            (if (and maybe-type-param (not (hashtable-contains? seen maybe-type-param)))
                (begin
                  (hashtable-set! seen maybe-type-param #t)
                  (cons (Type type) acc))
                acc))
          '()
          (native-entry-maybe-type-param* native-entry)
          (append (map (lambda (a)
                         (nanopass-case (Lloweredemit Argument) a
                           [(,var-name ,type) type]))
                       arg*)
                  (list type)))))

    (define (Ftype ftype) (unparse-Lloweredemit ftype))
    (define (Type type) (unparse-Lloweredemit type))
    (define (Arg arg) (unparse-Lloweredemit arg))

    (define (rendered? v) (and (pair? v) (symbol? (car v))))

    (define (vm-value->sexp v)
      (cond
        [(or (integer? v) (boolean? v) (string? v)) v]
        [(and (pair? v) (not (rendered? v))) (map vm-value->sexp v)]
        [(rendered? v) v]
        [(null? v) '()]
        [(VMop? v)
         (VMop-case v
           [(VMstack) '(stack)]
           [(VMvoid) '(void)]
           [(VMalign value bytes) `(align ,value ,bytes)]
           [(VM+ x y) `(+ ,(vm-value->sexp x) ,(vm-value->sexp y))]
           [(VMvalue->int x) `(value->int ,(vm-value->sexp x))]
           ;; These operands are IR types, so expression serialization does not apply.
           [(VMnull x) `(null ,(Type x))]
           [(VMmax-sizeof x) `(max-sizeof ,(Type x))]
           [(VMleaf-hash x) `(leaf-hash ,(vm-value->sexp x))]
           [(VMcoin-commit coin recipient)
            `(coin-commit ,(vm-value->sexp coin) ,(vm-value->sexp recipient))]
           [(VMaligned-concat x*) `(aligned-concat ,@(map vm-value->sexp x*))]
           [(VMstate-value-null) '(state-value null)]
           [(VMstate-value-cell val) `(state-value cell ,(vm-value->sexp val))]
           ;; Keep the type because it determines whether the value needs a cell.
           [(VMstate-value-ADT val type) `(state-value ADT ,(vm-value->sexp val) ,(Type type))]
           [(VMstate-value-array val*) `(state-value array ,@(map vm-value->sexp val*))]
           [(VMstate-value-map key* val*)
            `(state-value map ,@(map (lambda (k v) `(,(vm-value->sexp k) ,(vm-value->sexp v))) key* val*))]
           [(VMstate-value-merkle-tree nat key* val*)
            `(state-value merkle-tree ,nat
               ,@(map (lambda (k v) `(,(vm-value->sexp k) ,(vm-value->sexp v))) key* val*))]
           [else (fail "VM value" v)])]
        [else (Expr v)]))

    (define (vm-suppressed? v)
      (and (VMop? v) (VMop-case v [(VMsuppress) #t] [else #f])))

    (define (vminstr->sexp vi)
      (let ([args (vminstr-arg* vi)])
        (if (ormap (lambda (a) (vm-suppressed? (cdr a))) args)
            #f
            (let ([rendered
                   `(,(string->symbol (vminstr-op vi))
                     ,@(map (lambda (a) `(,(string->symbol (car a)) ,(vm-value->sexp (cdr a)))) args))])
              ;; An ins with (void) has no runtime effect.
              (if (and (eq? (car rendered) 'ins)
                       (member '(n (void)) (cdr rendered)))
                  #f
                  rendered)))))

    (define (instructions->sexp vminstr*)
      (fold-right
        (lambda (vi acc) (let ([s (vminstr->sexp vi)]) (if s (cons s acc) acc)))
        '()
        vminstr*))

    (define (expand-ops src path-elt* adt-formal* adt-arg* var-name* expr* vm-code)
      (instructions->sexp
        (expand-vm-code src
          (map (lambda (pe)
                 (nanopass-case (Lloweredemit Path-Element) pe
                   [,path-index (VMalign path-index 1)]
                   [(,src ,type ,expr) (Expr expr)]))
               path-elt*)
          #f
          (append (map cons adt-formal* adt-arg*)
                  (map (lambda (vn ex) (cons (id-sym vn) (Expr ex))) var-name* expr*))
          (vm-code-code vm-code)))))

  (OpClass : ADT-Op-Class (op-class) -> * (sexp)
    [,ledger-op-class ledger-op-class]
    [(,ledger-op-class ,nat ,nat^) `(,ledger-op-class ,nat ,nat^)]
    [else (fail "operation class" op-class)])

  (TupleArg : Tuple-Argument (ta) -> * (sexp)
    [(single ,src ,expr) `(single ,(Expr expr))]
    [(spread ,src ,nat ,expr) `(spread ,nat ,(Expr expr))])

  (MapArg : Map-Argument (ma) -> * (sexp)
    [(,expr ,type ,type^) `(,(Expr expr) ,(Type type) ,(Type type^))])

  (Fun : Function (fun) -> * (sexp)
    [(fref ,src ,function-name) `(fref ,(id->sym function-name))]
    [(circuit ,src (,arg* ...) ,type ,expr)
     `(circuit ,(map Arg arg*) ,(Type type) ,(Expr expr))])

  (Expr : Expression (expr) -> * (sexp)
    [(quote ,src ,datum) `(quote ,datum)]
    [(var-ref ,src ,var-name) `(var-ref ,(id->sym var-name))]
    [(default ,src ,type) `(default ,(Type type))]
    [(if ,src ,expr0 ,expr1 ,expr2)
     `(if ,(Expr expr0) ,(Expr expr1) ,(Expr expr2))]
    [(elt-ref ,src ,expr ,elt-name ,nat) `(elt-ref ,(Expr expr) ,elt-name ,nat)]
    [(enum-ref ,src ,type ,elt-name) `(enum-ref ,(Type type) ,elt-name)]
    [(tuple ,src ,tuple-arg* ...) `(tuple ,@(map TupleArg tuple-arg*))]
    [(vector ,src ,tuple-arg* ...) `(vector ,@(map TupleArg tuple-arg*))]
    [(tuple-ref ,src ,expr ,kindex) `(tuple-ref ,(Expr expr) ,kindex)]
    [(tuple-slice ,src ,type ,expr ,kindex ,len)
     `(tuple-slice ,(Type type) ,(Expr expr) ,kindex ,len)]
    [(vector-ref ,src ,type ,expr ,index)
     `(vector-ref ,(Type type) ,(Expr expr) ,(Expr index))]
    [(vector-slice ,src ,type ,expr ,index ,len)
     `(vector-slice ,(Type type) ,(Expr expr) ,(Expr index) ,len)]
    [(bytes-ref ,src ,type ,expr ,index)
     `(bytes-ref ,(Type type) ,(Expr expr) ,(Expr index))]
    [(bytes-slice ,src ,type ,expr ,index ,len)
     `(bytes-slice ,(Type type) ,(Expr expr) ,(Expr index) ,len)]
    [(+ ,src ,type ,expr1 ,expr2) `(+ ,(Type type) ,(Expr expr1) ,(Expr expr2))]
    [(- ,src ,type ,expr1 ,expr2) `(- ,(Type type) ,(Expr expr1) ,(Expr expr2))]
    [(* ,src ,type ,expr1 ,expr2) `(* ,(Type type) ,(Expr expr1) ,(Expr expr2))]
    [(< ,src ,bits ,expr1 ,expr2) `(< ,bits ,(Expr expr1) ,(Expr expr2))]
    [(<= ,src ,bits ,expr1 ,expr2) `(<= ,bits ,(Expr expr1) ,(Expr expr2))]
    [(> ,src ,bits ,expr1 ,expr2) `(> ,bits ,(Expr expr1) ,(Expr expr2))]
    [(>= ,src ,bits ,expr1 ,expr2) `(>= ,bits ,(Expr expr1) ,(Expr expr2))]
    [(== ,src ,type ,expr1 ,expr2) `(== ,(Type type) ,(Expr expr1) ,(Expr expr2))]
    [(!= ,src ,type ,expr1 ,expr2) `(!= ,(Type type) ,(Expr expr1) ,(Expr expr2))]
    [(map ,src ,len ,fun ,map-arg ,map-arg* ...)
     `(map ,len ,(Fun fun) ,@(map MapArg (cons map-arg map-arg*)))]
    [(fold ,src ,len ,fun (,expr0 ,type0) ,map-arg ,map-arg* ...)
     `(fold ,len ,(Fun fun) (,(Expr expr0) ,(Type type0))
        ,@(map MapArg (cons map-arg map-arg*)))]
    [(call ,src ,function-name ,expr* ...)
     `(call ,(id->sym function-name) ,@(map Expr expr*))]
    [(new ,src ,type ,expr* ...)
     `(new ,(Type type) ,@(map Expr expr*))]
    [(seq ,src ,expr* ... ,expr)
     `(seq ,@(map Expr expr*) ,(Expr expr))]
    [(let* ,src ([,local* ,expr*] ...) ,expr)
     `(let* ,(map (lambda (l e) `(,(Arg l) ,(Expr e))) local* expr*)
        ,(Expr expr))]
    [(assert ,src ,expr ,mesg) `(assert ,(Expr expr) ,mesg)]
    [(field->bytes ,src ,len ,ftype ,expr)
     `(field->bytes ,len ,(Ftype ftype) ,(Expr expr))]
    [(cast-from-bytes ,src ,type ,len ,expr)
     `(cast-from-bytes ,(Type type) ,len ,(Expr expr))]
    [(vector->bytes ,src ,len ,expr) `(vector->bytes ,len ,(Expr expr))]
    [(bytes->vector ,src ,len ,expr) `(bytes->vector ,len ,(Expr expr))]
    [(cast-from-enum ,src ,type ,type^ ,expr)
     `(cast-from-enum ,(Type type) ,(Type type^) ,(Expr expr))]
    [(cast-to-enum ,src ,type ,type^ ,expr)
     `(cast-to-enum ,(Type type) ,(Type type^) ,(Expr expr))]
    [(cast-to-field ,src ,ftype ,type ,expr)
     `(cast-to-field ,(Ftype ftype) ,(Type type) ,(Expr expr))]
    [(cast-from-field ,src ,nat ,ftype ,expr)
     `(cast-from-field ,nat ,(Ftype ftype) ,(Expr expr))]
    [(safe-cast ,src ,type ,type^ ,expr)
     `(safe-cast ,(Type type) ,(Type type^) ,(Expr expr))]
    [(downcast-unsigned ,src ,nat2 ,nat1 ,expr)
     `(downcast-unsigned ,nat2 ,nat1 ,(Expr expr))]
    [(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
     `(contract-call ,elt-name (,(Expr expr) ,(Type type))
        ,@(map Expr expr*))]
    [(emit ,src ,event-version ,event-tag ,len ,expr ,vm-code)
     `(emit ,event-version ,event-tag ,len ,(Expr expr)
        (instructions
          ,@(instructions->sexp
              (expand-vm-code src #f #f
                `((emit-version . ,event-version)
                  (emit-tag . ,event-tag)
                  (emit-payload . ,(Expr expr)))
                (vm-code-code vm-code)))))]
    [(public-ledger ,src ,ledger-field-name ,sugar (,path-elt* ...) ,src^ ,adt-op ,expr* ...)
     (nanopass-case (Lloweredemit ADT-Op) adt-op
       [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...) ((,var-name* ,type*) ...) ,type ,vm-code)
        `(public-ledger ,(id->sym ledger-field-name)
           ,(OpClass op-class)
           ,(map (lambda (pe)
                   (nanopass-case (Lloweredemit Path-Element) pe
                     [,path-index path-index]
                     [(,src ,type ,expr) `(,(Type type) ,(Expr expr))]))
                 path-elt*)
           ,ledger-op
           ,(Type type)
           (instructions ,@(expand-ops src path-elt* adt-formal* adt-arg* var-name* expr* vm-code))
           ,@(map Expr expr*))])]
    [(return ,src ,expr) `(return ,(Expr expr))]
    [else (fail "expression" (unparse-Lloweredemit expr))])

  (Pelt : Program-Element (pelt proof-id*) -> * (sexp)
    [(circuit ,src ,function-name (,arg* ...) ,type ,expr)
     `(circuit ,(id->sym function-name)
        (exported ,(id-exported? function-name))
        (pure ,(id-pure? function-name))
        (proof ,(and (memq function-name proof-id*) #t))
        ,(map Arg arg*)
        ,(Type type)
        ,(Expr expr))]
    [(native ,src ,function-name ,native-entry (,arg* ...) ,type)
     `(native ,(id->sym function-name)
        (entry ,(native-entry-function native-entry) ,(native-entry-class native-entry))
        (type-arguments ,@(native-type-argument* native-entry arg* type))
        ,(map Arg arg*)
        ,(Type type))]
    [(witness ,src ,function-name (,arg* ...) ,type)
     `(witness ,(id->sym function-name) ,(map Arg arg*) ,(Type type))]
    [(kernel-declaration ,public-binding)
     `(kernel-declaration ,(Binding public-binding))]
    [(public-ledger-declaration ,pl-array ,lconstructor)
     `(public-ledger-declaration
        ,(PlArray pl-array)
        ,(nanopass-case (Lloweredemit Ledger-Constructor) lconstructor
           [(constructor ,src (,arg* ...) ,expr)
            `(constructor ,(map Arg arg*) ,(Expr expr))]))]
    [(export-typedef ,src ,type-name (,tvar-name* ...) ,type)
     `(export-typedef ,type-name ,tvar-name* ,(Type type))]
    [else (fail "program element" (unparse-Lloweredemit pelt))])

  (Binding : Public-Ledger-Binding (pb) -> * (sexp)
    [(,src ,ledger-field-name (,path-index* ...) ,type)
     `(,(id->sym ledger-field-name)
       ,path-index*
       (exported ,(id-exported? ledger-field-name))
       ,(Type type))])

  (PlArray : Public-Ledger-Array (pl-array) -> * (sexp)
    [(public-ledger-array ,pl-array-elt* ...)
     `(public-ledger-array
        ,@(map (lambda (elt)
                 (nanopass-case (Lloweredemit Public-Ledger-Array-Element) elt
                   [,pl-array (PlArray pl-array)]
                   [,public-binding (Binding public-binding)]))
               pl-array-elt*))])

  (Program : Program (ir) -> * (sexp)
    [(program ,src (,contract-type* ...) ((,export-name* ,name*) ...) ,pelt* ...)
     ;; Resolve proof export names through the export table because selective exports can rename circuits.
     ;; Keep the id records because id-uniq assigns numbers on first print.
     (let ([proof-id*
             (fold-left
               (lambda (acc export-name name)
                 (if (memq export-name proof-circuit-name*) (cons name acc) acc))
               '()
               export-name*
               name*)])
     `(analyzed-ir
        (compiler-version ,compiler-version-string)
        (language-version ,language-version-string)
        (runtime-version ,runtime-version-string)
        (exports ,@(map (lambda (en n) `(,en . ,(id->sym n))) export-name* name*))
        (contract-types ,@(map Type contract-type*))
        ,@(map (lambda (pelt) (Pelt pelt proof-id*)) pelt*)))])

  (Program ir))
