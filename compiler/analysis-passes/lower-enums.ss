;;; This file is part of Compact.
;;; Copyright (C) 2026 Minokawa project contributors
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

;;; lower-enums replaces each enum with fields by a struct holding a tag and the slots
;;; its variants share.  It is the only pass that knows this layout, and it runs before
;;; the compiler splits into its back ends so that they all see the same struct.
;;;
;;; A slot holds one field.  Each field of a variant takes the first slot of the field's
;;; type that the variant has not already used, and a new slot is added when there is
;;; none.  Slots are therefore ordered by first use, and slots a variant does not use hold
;;; default values.  Two fields have the same type when, once an alias around either is
;;; removed, type-key writes their types alike.  It writes a type as the type checker sees
;;; it, so that the layout of a type does not depend on how the type is written.
;;;
;;; An enum the ledger defines is laid out as the ledger does it instead: each variant
;;; with a field has a slot of its own, named for the variant, and the slots come in the
;;; reverse of the order of the variants.

(define-pass lower-enums : Lguarded (ir) -> Lnosum ()
  (definitions
    (define-record-type layout
      (nongenerative)
      (fields src enum-name struct-type tag-type slot-name* slot-type* variant*))
    ; slot* holds, for each field, the index of the slot the field occupies
    (define-record-type variant
      (nongenerative)
      (fields name tag field-type* slot*))
    ; maps each struct type produced for an enum to its layout
    (define layout-ht (make-eq-hashtable))
    (define layout* '())
    (define layout-cache (make-hashtable equal-hash equal?))
    ; false while lowering the types of the standard events and of the kernel's operations,
    ; which every program carries whether or not it uses them and which therefore do not
    ; belong in its enum table
    (define record-layouts? #t)
    (define (de-alias type)
      (nanopass-case (Lnosum Type) type
        [(talias ,src ,nominal? ,type-name ,type) (de-alias type)]
        [else type]))
    (define (type->layout type)
      (eq-hashtable-ref layout-ht (de-alias type) #f))
    (define (same-representation? type1 type2)
      (equal? (unparse-Lnosum type1) (unparse-Lnosum type2)))
    ; type-key writes a type as the type checker sees it: without structural aliases, at
    ; any depth; with a tuple whose elements all have one type written as the vector of that
    ; type, which the type checker takes to be the same type; and with the circuits of a
    ; contract type in order, since the type checker compares them as a set.  A nominal
    ; alias is a type of its own and is kept.  Types written alike are the same to the type
    ; checker, so fields of such types can share a slot, and types the type checker takes
    ; to be the same are written alike, so a type has one layout however it is written.
    ; The exception is the empty tuple, which the type checker takes to be the same as a
    ; vector of no elements of any type, though it takes two such vectors to differ when
    ; their element types do; no way of writing types can match that, and type-key writes
    ; both as they are.  Without type-key, an instance of a generic enum written with an
    ; alias or a tuple in its type arguments would be laid out differently from the same
    ; instance written without one, and a value of the one could not be passed where the
    ; other is expected.
    (define (type-key type)
      (define (canonical type)
        (with-output-language (Lnosum Type)
          (nanopass-case (Lnosum Type) type
            [(talias ,src ,nominal? ,type-name ,type^)
             (if nominal?
                 `(talias ,src ,nominal? ,type-name ,(canonical type^))
                 (canonical type^))]
            [(tvector ,src ,len ,type^)
             `(tvector ,src ,len ,(canonical type^))]
            [(ttuple ,src ,type* ...)
             (let ([type* (map canonical type*)])
               (if (and (not (null? type*))
                        (let ([key (unparse-Lnosum (car type*))])
                          (andmap (lambda (type) (equal? (unparse-Lnosum type) key)) (cdr type*))))
                   `(tvector ,src ,(length type*) ,(car type*))
                   `(ttuple ,src ,type* ...)))]
            [(tstruct ,src ,struct-name (,elt-name* ,type*) ...)
             `(tstruct ,src ,struct-name (,elt-name* ,(map canonical type*)) ...)]
            [(tcontract ,src ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
             (let ([circuit* (sort
                               (lambda (circuit1 circuit2) (string<? (car circuit1) (car circuit2)))
                               (map (lambda (elt-name pure-dcl type* type)
                                      (let ([type* (map canonical type*)] [type (canonical type)])
                                        (list (format "~s" (list elt-name pure-dcl (map unparse-Lnosum type*) (unparse-Lnosum type)))
                                              elt-name pure-dcl type* type)))
                                    elt-name* pure-dcl* type** type*))])
               `(tcontract ,src ,contract-name
                  (,(map cadr circuit*) ,(map caddr circuit*) (,(map cadddr circuit*) ...) ,(map (lambda (circuit) (list-ref circuit 4)) circuit*))
                  ...))]
            [else type])))
      (unparse-Lnosum (canonical type)))
    (define (tag-type src nvariant)
      (with-output-language (Lnosum Type)
        (case nvariant
          [(1) #f]
          [(2) `(tboolean ,src)]
          [else `(tunsigned ,src ,(fx- nvariant 1))])))
    (define (record-layout! layout)
      (let ([struct-type (layout-struct-type layout)])
        (eq-hashtable-set! layout-ht struct-type layout)
        ; two enums may be lowered to the same struct; they are different entries
        (when (and record-layouts?
                   (not (ormap (lambda (layout^)
                                 (and (eq? (layout-src layout^) (layout-src layout))
                                      (same-representation? (layout-struct-type layout^) struct-type)))
                               layout*)))
          (set! layout* (cons layout layout*)))
        layout))
    (define (make-ledger-enum-layout src enum-name elt-name* type**)
      (assert (andmap (lambda (type*) (or (null? type*) (null? (cdr type*)))) type**))
      (let* ([tag-type (tag-type src (length elt-name*))]
             [slot-name* (fold-left (lambda (slot-name* elt-name type*) (if (null? type*) slot-name* (cons elt-name slot-name*)))
                           '() elt-name* type**)]
             [slot-type* (fold-left (lambda (slot-type* type*) (if (null? type*) slot-type* (cons (car type*) slot-type*)))
                           '() type**)]
             [variant* (map (lambda (elt-name type* tag)
                              (make-variant elt-name tag type*
                                (map (lambda (type)
                                       (fx- (length slot-name*) (length (memq elt-name slot-name*))))
                                     type*)))
                            elt-name* type** (enumerate elt-name*))])
        (assert tag-type)
        (record-layout!
          (make-layout src enum-name
            (with-output-language (Lnosum Type)
              `(tstruct ,src ,enum-name (tag ,tag-type) (,slot-name* ,slot-type*) ...))
            tag-type slot-name* slot-type* variant*))))
    (define (make-enum-layout src enum-name elt-name* type**)
      (let ([nvariant (length elt-name*)] [rslot-type* '()] [nslot 0]
            ; maps a field's representation and n to the nth slot of that representation
            [slot-ht (make-hashtable equal-hash equal?)])
        ; used-ht counts the slots of each representation that the variant has taken
        (define (take-slot! field-type used-ht)
          (let* ([slot-type (de-alias field-type)]
                 [representation (type-key slot-type)]
                 [n (hashtable-ref used-ht representation 0)]
                 [key (cons n representation)])
            (hashtable-set! used-ht representation (fx+ n 1))
            (or (hashtable-ref slot-ht key #f)
                (let ([i nslot])
                  (hashtable-set! slot-ht key i)
                  (set! rslot-type* (cons slot-type rslot-type*))
                  (set! nslot (fx+ nslot 1))
                  i))))
        (let* ([variant* (maplr
                           (lambda (elt-name type* tag)
                             (let ([used-ht (make-hashtable equal-hash equal?)])
                               (make-variant elt-name tag type*
                                 (maplr (lambda (type) (take-slot! type used-ht)) type*))))
                           elt-name* type** (enumerate elt-name*))]
               [slot-type* (reverse rslot-type*)]
               [slot-name* (map (lambda (i) (string->symbol (format "s~d" i))) (enumerate slot-type*))]
               [tag-type (tag-type src nvariant)]
               [struct-type (with-output-language (Lnosum Type)
                              (if tag-type
                                  `(tstruct ,src ,enum-name (tag ,tag-type) (,slot-name* ,slot-type*) ...)
                                  `(tstruct ,src ,enum-name (,slot-name* ,slot-type*) ...)))]
               [layout (make-layout src enum-name struct-type tag-type slot-name* slot-type* variant*)])
          (record-layout! layout))))
    ; a slot has its field's type with any alias around it removed, so a field of an
    ; alias's type is cast on its way into the slot and on its way out
    (define (field->slot src expr type)
      (let ([type^ (de-alias type)])
        (if (eq? type^ type)
            expr
            (with-output-language (Lnosum Expression) `(safe-cast ,src ,type^ ,type ,expr)))))
    (define (slot->field src expr type)
      (let ([type^ (de-alias type)])
        (if (eq? type^ type)
            expr
            (with-output-language (Lnosum Expression) `(safe-cast ,src ,type ,type^ ,expr)))))
    ; orders the enum table by declaration and, among the instances of one generic enum, by
    ; struct, so that the table does not depend on the order in which the pass meets types
    (define (layout<? layout1 layout2)
      (let ([src1 (layout-src layout1)] [src2 (layout-src layout2)])
        (or (source-object<? src1 src2)
            (and (not (source-object<? src2 src1))
                 (string<? (format "~s" (unparse-Lnosum (layout-struct-type layout1)))
                           (format "~s" (unparse-Lnosum (layout-struct-type layout2))))))))
    (define (layout->enum-layout layout)
      (with-output-language (Lnosum Enum-Layout)
        `(enum-layout ,(layout-src layout) ,(layout-enum-name layout) ,(layout-struct-type layout)
           ,(map (lambda (variant)
                   (with-output-language (Lnosum Variant-Layout)
                     `(,(variant-name variant) ,(variant-tag variant)
                       (,(variant-field-type* variant)
                        (,(map (lambda (i) (list (list-ref (layout-slot-name* layout) i)))
                               (variant-slot* variant))
                         ...))
                       ...)))
                 (layout-variant* layout))
           ...)))
    (define (find-variant layout elt-name)
      (or (find (lambda (variant) (eq? (variant-name variant) elt-name)) (layout-variant* layout))
          (assert cannot-happen)))
    (define (slot-ref src layout expr i)
      (with-output-language (Lnosum Expression)
        `(elt-ref ,src ,expr ,(list-ref (layout-slot-name* layout) i)
           ,(if (layout-tag-type layout) (fx+ i 1) i))))
    (define (tag-ref src layout expr)
      (with-output-language (Lnosum Expression)
        `(elt-ref ,src ,expr tag 0)))
    (define (tag-constant src layout tag)
      (with-output-language (Lnosum Expression)
        (nanopass-case (Lnosum Type) (layout-tag-type layout)
          [(tboolean ,src^) `(quote ,src ,(fx= tag 1))]
          [(tunsigned ,src^ ,nat)
           (if (= tag nat)
               `(quote ,src ,tag)
               `(safe-cast ,src (tunsigned ,src ,nat) (tunsigned ,src ,tag) (quote ,src ,tag)))]
          [else (assert cannot-happen)])))
    (define (simple? expr)
      (nanopass-case (Lnosum Expression) expr
        [(quote ,src ,datum) #t]
        [(var-ref ,src ,var-name) #t]
        [else #f]))
    (define (tag-test src layout expr tag*)
      ; tag* is a nonempty proper subset of the layout's tags
      (with-output-language (Lnosum Expression)
        (let ([tag-expr (tag-ref src layout expr)] [tag-type (layout-tag-type layout)])
          (nanopass-case (Lnosum Type) tag-type
            [(tboolean ,src^)
             (if (fx= (car tag*) 1)
                 tag-expr
                 `(if ,src ,tag-expr (quote ,src #f) (quote ,src #t)))]
            [else
             (let ([other* (remv* tag* (map variant-tag (layout-variant* layout)))])
               (if (fx<= (length tag*) (length other*))
                   (let f ([tag* tag*])
                     (let ([test `(== ,src ,tag-type ,tag-expr ,(tag-constant src layout (car tag*)))])
                       (if (null? (cdr tag*))
                           test
                           `(if ,src ,test (quote ,src #t) ,(f (cdr tag*))))))
                   (let f ([tag* other*])
                     (let ([test `(!= ,src ,tag-type ,tag-expr ,(tag-constant src layout (car tag*)))])
                       (if (null? (cdr tag*))
                           test
                           `(if ,src ,test ,(f (cdr tag*)) (quote ,src #f)))))))]))))
    (define (remv* x* y*)
      (filter (lambda (y) (not (memv y x*))) y*))
    ; returns the conditions under which the value of expr, which must be simple enough
    ; to duplicate, holds only valid enum values
    (define (validity-conditions src expr type)
      (with-output-language (Lnosum Expression)
        (let ([type (de-alias type)])
          (nanopass-case (Lnosum Type) type
            [(tstruct ,src^ ,struct-name (,elt-name* ,type*) ...)
             (cond
               [(type->layout type) =>
                (lambda (layout)
                  (apply append
                    (map (lambda (slot-type i)
                           (let ([slot-expr (slot-ref src layout expr i)]
                                 [tag* (fold-right
                                         (lambda (variant tag*)
                                           (if (memv i (variant-slot* variant))
                                               (cons (variant-tag variant) tag*)
                                               tag*))
                                         '()
                                         (layout-variant* layout))])
                             (let ([condition* (validity-conditions src slot-expr slot-type)])
                               (if (fx= (length tag*) (length (layout-variant* layout)))
                                   condition*
                                   (cons `(if ,src ,(tag-test src layout expr tag*)
                                              (quote ,src #t)
                                              (== ,src ,slot-type ,slot-expr (default ,src ,slot-type)))
                                         condition*)))))
                         (layout-slot-type* layout)
                         (enumerate (layout-slot-type* layout)))))]
               [else
                (apply append
                  (map (lambda (elt-name type i) (validity-conditions src `(elt-ref ,src ,expr ,elt-name ,i) type))
                       elt-name* type* (enumerate type*)))])]
            [(ttuple ,src^ ,type* ...)
             (apply append
               (map (lambda (type i) (validity-conditions src `(tuple-ref ,src ,expr ,i) type))
                    type* (enumerate type*)))]
            [(tvector ,src^ ,len ,type)
             (if (null? (validity-conditions src expr type))
                 '()
                 (apply append
                   (map (lambda (i) (validity-conditions src `(tuple-ref ,src ,expr ,i) type))
                        (iota len))))]
            [else '()]))))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (let ([type* (fluid-let ([record-layouts? #f]) (maplr Type type*))]
           [pelt* (maplr Program-Element pelt*)])
       `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...)
          (,(map layout->enum-layout (sort layout<? layout*)) ...)
          ((,export-name* ,name*) ...)
          ,pelt* ...))])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Type : Type (ir) -> Type ()
    ; the kernel's operations are no more part of a contract's interface than the standard events
    [(tadt ,src ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...) (,adt-rt-op* ...))
     (guard (eq? adt-name 'Kernel) record-layouts?)
     (fluid-let ([record-layouts? #f]) (Type ir))]
    [(tsum ,src ,enum-name ,ledger-layout? (,elt-name* ,[type**] ...) ...)
     ; a type occurs many times, and its layout can be large.  The key is the type as the
     ; type checker sees it, so that one type has one layout however it is written.
     (let ([key (list ledger-layout? enum-name elt-name*
                      (map (lambda (type*) (map type-key type*)) type**))])
       (layout-struct-type
         (or (let ([layout (hashtable-ref layout-cache key #f)])
               (and layout (record-layout! layout)))
             (let ([layout (if ledger-layout?
                               (make-ledger-enum-layout src enum-name elt-name* type**)
                               (make-enum-layout src enum-name elt-name* type**))])
               (hashtable-set! layout-cache key layout)
               layout))))])
  (Expression : Expression (ir) -> Expression ()
    [(variant-new ,src ,[type] ,elt-name ,[expr*] ...)
     (let* ([layout (type->layout type)]
            [variant (find-variant layout elt-name)]
            [field-type* (variant-field-type* variant)]
            [t* (map (lambda (expr) (if (simple? expr) #f (make-temp-id src 't))) expr*)]
            [slot.part* (map (lambda (expr field-type t i)
                               (cons i (field->slot src (if t `(var-ref ,src ,t) expr) field-type)))
                             expr* field-type* t* (variant-slot* variant))]
            [slot-expr* (map (lambda (slot-type i)
                               (cond
                                 [(assv i slot.part*) => cdr]
                                 [else `(default ,src ,slot-type)]))
                             (layout-slot-type* layout)
                             (enumerate (layout-slot-type* layout)))]
            [new (if (layout-tag-type layout)
                     `(new ,src ,type ,(tag-constant src layout (variant-tag variant)) ,slot-expr* ...)
                     `(new ,src ,type ,slot-expr* ...))])
       (let f ([t* t*] [field-type* field-type*] [expr* expr*])
         (cond
           [(null? t*) new]
           [(car t*) `(let* ,src ([(,(car t*) ,(car field-type*)) ,(car expr*)])
                        ,(f (cdr t*) (cdr field-type*) (cdr expr*)))]
           [else (f (cdr t*) (cdr field-type*) (cdr expr*))])))]
    [(variant-test ,src ,[type] ,[expr] ,elt-name)
     (let ([layout (type->layout type)])
       (if (layout-tag-type layout)
           (tag-test src layout expr (list (variant-tag (find-variant layout elt-name))))
           `(quote ,src #t)))]
    [(variant-field ,src ,[type] ,[expr] ,elt-name ,nat)
     (let* ([layout (type->layout type)] [variant (find-variant layout elt-name)])
       (slot->field src
         (slot-ref src layout expr (list-ref (variant-slot* variant) nat))
         (list-ref (variant-field-type* variant) nat)))]
    [(variant-valid ,src ,[type] ,[expr] ,mesg)
     (assert (simple? expr))
     (let ([condition* (validity-conditions src expr type)])
       (if (null? condition*)
           `(tuple ,src)
           `(seq ,src
              ,(map (lambda (condition) `(assert ,src ,condition ,mesg)) condition*)
              ...
              (tuple ,src))))]))
