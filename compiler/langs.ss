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

(library (langs)
  (export max-field field-bytes max-unsigned unsigned-bits field? datum? path-index?
          max-bytes/vector-length len? kindex? max-merkle-tree-depth min-merkle-tree-depth
          maximum-ledger-segment-length 
          make-vm-expr vm-expr? vm-expr-expr make-vm-code vm-code? vm-code-code
          Lsrc unparse-Lsrc Lsrc-pretty-formats Lsrc-Include?
          Lnoinclude unparse-Lnoinclude Lnoinclude-pretty-formats
          Lsingleconst unparse-Lsingleconst Lsingleconst-pretty-formats
          Lnopattern unparse-Lnopattern Lnopattern-pretty-formats
          Lhoisted unparse-Lhoisted Lhoisted-pretty-formats
          Lexpr unparse-Lexpr Lexpr-pretty-formats
          Lnoandornot unparse-Lnoandornot Lnoandornot-pretty-formats
          Lpreexpand unparse-Lpreexpand Lpreexpand-pretty-formats
          id-counter make-source-id make-temp-id id? id-src id-sym id-uniq id-refcount id-refcount-set! id-temp? id-exported? id-exported?-set! id-pure? id-pure?-set! id-sealed? id-sealed?-set! id-prefix
          Lexpanded unparse-Lexpanded Lexpanded-pretty-formats Lexpanded-Public-Ledger-ADT?
          Ltypes unparse-Ltypes Ltypes-pretty-formats Ltypes-Public-Ledger-ADT?
          Lnotundeclared unparse-Lnotundeclared Lnotundeclared-pretty-formats Lnotundeclared-Type? Lnotundeclared-Ledger-Declaration? Lnotundeclared-Ledger-Constructor?
          Loneledger unparse-Loneledger Loneledger-pretty-formats Loneledger-Ledger-Declaration?
          Lnodca unparse-Lnodca Lnodca-pretty-formats Lnodca-Expression?
          Lwithpaths0 unparse-Lwithpaths0 Lwithpaths0-pretty-formats
          Lwithpaths unparse-Lwithpaths Lwithpaths-pretty-formats Lwithpaths-Public-Ledger-ADT? Lwithpaths-Type?
          Lnodisclose unparse-Lnodisclose Lnodisclose-pretty-formats Lnodisclose-Export-Type-Definition?
          Ltypescript unparse-Ltypescript Ltypescript-pretty-formats Ltypescript-Public-Ledger-ADT? Ltypescript-ADT-Op? Ltypescript-ADT-Runtime-Op? Ltypescript-Type?
          Lposttypescript unparse-Lposttypescript Lposttypescript-pretty-formats
          Lnoenums unparse-Lnoenums Lnoenums-pretty-formats
          Lunrolled unparse-Lunrolled Lunrolled-pretty-formats
          Linlined unparse-Linlined Linlined-pretty-formats
          Lnosafecast unparse-Lnosafecast Lnosafecast-pretty-formats
          Lnovectorref unparse-Lnovectorref Lnovectorref-pretty-formats
          Lcircuit unparse-Lcircuit Lcircuit-pretty-formats Lcircuit-External-Declaration? Lcircuit-Witness-Declaration? Lcircuit-Circuit-Definition? Lcircuit-Kernel-Declaration? Lcircuit-Ledger-Declaration? Lcircuit-Triv?
          Lflattened unparse-Lflattened Lflattened-pretty-formats Lflattened-Triv? Lflattened-Circuit-Definition? Lflattened-Type? Lflattened-Public-Ledger-ADT?
          Lzkir unparse-Lzkir Lzkir-pretty-formats
          )
  (import (chezscheme) (nanopass) (nanopass-extension) (field) (natives))

  ; field-bits is the number of full bits that can be represented by a field value and is
  ; necessarily smaller than the number of bits required to represent the maximum field value
  (define (field-bits) (- (integer-length (max-field)) 1))
  ; field-bytes is the number of full bytes that can be represented by a field value and is
  ; one smaller than the number of bytes required to represent the maximum field value
  (define (field-bytes) (quotient (field-bits) 8))

  ; unsigned values are natural numbers that fit into the number of full bytes representable
  ; by a field.  larger unsigned values would fit in a field when (field-bits) is not an
  ; even multiple of (field-bytes), but the lower limit allows the ledger to measure unsigned
  ; alignments in bytes rather than bits
  (define (unsigned-bits) (* (field-bytes) 8))
  (define (max-unsigned) (- (expt 2 (unsigned-bits)) 1))

  (define (maybe-bits? x)
    (or (not x)
        (and (integer? x)
             (exact? x)
             (<= 1 x (unsigned-bits)))))

  (define (field-bytes? x)
    (and (integer? x)
         (exact? x)
         (<= 0 x (field-bytes))))

  (define (datum? x)
    (or (boolean? x)
        (field? x)
        (and (bytevector? x)
             (<= (bytevector-length x) (max-bytes/vector-length)))))

  (define max-bytes/vector-length (make-parameter (expt 2 24)))

  (define (len? x)
    (and (integer? x)
         (exact? x)
         (<= 0 x (max-bytes/vector-length))))

  (define (kindex? x)
    (and (integer? x)
         (exact? x)
         (<= 0 x (- (max-bytes/vector-length) 1))))

  (define (max-merkle-tree-depth) 32)
  (define (min-merkle-tree-depth) 2)

  (define (zkir-field-rep? x)
    (and (integer? x)
         (exact? x)
         (<= (- (max-field)) x (max-field))))

  (define-record-type vm-expr
    (nongenerative)
    (fields expr))

  (define-record-type vm-code
    (nongenerative)
    (fields code))

  (define-language/pretty Lsrc
    (terminals
      (field (nat))
      (boolean (exported sealed pure-dcl nominal))
      (symbol (var-name name module-name function-name contract-name struct-name enum-name tvar-name tsize-name elt-name ledger-field-name type-name))
      (string (prefix mesg opaque-type file))
      (datum (datum))
      (source-object (src))
      )
    (Program (p)
      (program src pelt* ...) => (program #f pelt* ...)
      )
    (Program-Element (pelt)
      incld
      mdefn
      idecl
      xdecl
      ldecl
      lconstructor
      cdefn
      edecl
      wdecl
      ecdecl
      structdef
      enumdef
      tdefn)
    (Include (incld)
      (include src file) =>
        (include file)
      )
    (Module-Definition (mdefn)
      (module src exported? module-name (type-param* ...) pelt* ...) =>
        (module exported? module-name (type-param* ...) #f pelt* ...)
      )
    (Import-Declaration (idecl)
      (import src import-name (targ* ...) prefix) =>
        (import import-name (targ* 0 ...) #f prefix)
      (import src import-name (targ* ...) prefix (ielt* ...)) =>
        (import import-name (targ* 0 ...) #f prefix #f (ielt* ...))
      )
    (Import-Element (ielt)
      (src name name^) => (name name^)
      )
    (Import-Name (import-name)
      module-name
      file)
    (Export-Declaration (xdecl)
      (export src (src* name*) ...) =>
        (export #f name* ...)
      )
    (Ledger-Declaration (ldecl)
      (public-ledger-declaration src exported? sealed? ledger-field-name type) =>
        (public-ledger-declaration exported? sealed? #f ledger-field-name #f type)
      )
    (Ledger-Constructor (lconstructor)
      (constructor src (parg* ...) stmt) => (constructor (parg* 0 ...) #f stmt))
    (Circuit-Definition (cdefn)
      (circuit src exported? pure-dcl? function-name (type-param* ...) (parg* ...) type stmt) =>
        (circuit exported? pure-dcl? function-name (type-param* ...) (parg* 0 ...) 4 type #f stmt)
      )
    (External-Declaration (edecl)
      (external src exported? function-name (type-param* ...) (arg* ...) type) =>
        (external exported? function-name (type-param* ...) (arg* 0 ...) 4 type)
      )
    (Witness-Declaration (wdecl)
      (witness src exported? function-name (type-param* ...) (arg* ...) type) =>
        (witness exported? function-name (type-param* ...) (arg* 0 ...) 4 type)
      )
    (External-Contract-Declaration (ecdecl)
      (external-contract src exported? contract-name ecdecl-circuit* ...) =>
        (external-contract exported? contract-name #f ecdecl-circuit* ...)
      )
    (External-Contract-Circuit (ecdecl-circuit)
      (src pure-dcl function-name (arg* ...) type) =>
        (pure-dcl function-name (arg* 0 ...) 4 type)
      )
    (Structure-Definition (structdef)
      (struct src exported? struct-name (type-param* ...) arg* ...) =>
        (struct exported? struct-name (type-param* ...) #f arg* ...)
      )
    (Enum-Definition (enumdef)
      (enum src exported? enum-name elt-name elt-name* ...) =>
        (enum exported? enum-name #f elt-name #f elt-name* ...)
      )
    (Type-Definition (tdefn)
      (typedef src exported? nominal? type-name (type-param* ...) type) =>
        (typedef exported? nominal? type-name (type-param* ...) #f type)
      )
    (Type-Param (type-param)
      (nat-valued src tvar-name) => (nat-valued tvar-name)
      (type-valued src tvar-name) => tvar-name)
    (Pattern-Argument (parg)
      (src pattern type) => (bracket pattern type))
    (Argument (arg)
      (src var-name type) => (bracket var-name type)
      )
    (Const-Binding (cbinding)
      (src pattern type expr) => (bracket pattern 0 type 0 expr))
    (Statement (stmt)
      (statement-expression src expr)    => expr
      (return src expr)                  => (return expr)
      (const src cbinding cbinding* ...) => (const (cbinding 0 cbinding* ...))
      (if src expr stmt1 stmt2)          => (if expr 3 stmt1 3 stmt2)
      (for src var-name expr stmt)       => (for var-name expr #f stmt)
      (block src stmt* ...)              => (block #f stmt* ...)
      )
    (Pattern (pattern)
      var-name
      (tuple src (maybe pattern?*) ...)      => (pattern?* ...)
      (struct src (pattern* elt-name*) ...)  => ((pattern* elt-name*) ...)
      )
    (Expression (expr index)
      (quote src datum)                                   => datum
      (var-ref src var-name)                              => var-name
      (default src type)                                  => (default type)
      (if src expr0 expr1 expr2)                          => (if expr0 3 expr1 3 expr2)
      (elt-ref src expr elt-name)                         => (elt-ref expr elt-name)
      (elt-call src expr elt-name expr* ...)              => (elt-call expr elt-name expr* ...)
      (= src expr1 expr2)                                 => (= expr1 expr2)
      (+= src expr1 expr2)                                => (+= expr1 3 expr2)
      (-= src expr1 expr2)                                => (-= expr1 3 expr2)
      (tuple src tuple-arg* ...)                          => (tuple tuple-arg* ...)
      (bytes src bytes-arg* ...)                          => (bytes bytes-arg* ...)
      (tuple-ref src expr index)                          => (tuple-ref #f expr #f index)
      (tuple-slice src expr index tsize)                  => (tuple-slice #f expr #f index #f tsize)
      (+ src expr1 expr2)                                 => (+ expr1 expr2)
      (- src expr1 expr2)                                 => (- expr1 expr2)
      (* src expr1 expr2)                                 => (* expr1 expr2)
      (or src expr1 expr2)                                => (or expr1 3 expr2)
      (and src expr1 expr2)                               => (and expr1 4 expr2)
      (not src expr)                                      => (not expr)
      (< src expr1 expr2)                                 => (< expr1 expr2)
      (<= src expr1 expr2)                                => (<= expr1 3 expr2)
      (> src expr1 expr2)                                 => (> expr1 expr2)
      (>= src expr1 expr2)                                => (>= expr1 3 expr2)
      (== src expr1 expr2)                                => (== expr1 3 expr2)
      (!= src expr1 expr2)                                => (!= expr1 3 expr2)
      (map src fun expr expr* ...)                        => (map fun #f expr #f expr* ...)
      (fold src fun expr0 expr expr* ...)                 => (fold fun #f expr0 #f expr #f expr* ...)
      (call src fun expr* ...)                            => (call fun #f expr* ...)
      (new src tref new-field* ...)                       => (new tref #f new-field* ...)
      (seq src expr* ... expr)                            => (seq #f expr* ... #f expr)
      (cast src type expr)                                => (cast type #f expr)
      (disclose src expr)                                 => (disclose expr)
      (assert src expr mesg)                              => (assert #f expr #f mesg)
      )
    (Function (fun)
      ; could replace both fref forms with (fref src function-name targ* ...)
      ; but this allows us to suppress the fref wrapper in the human-readable
      ; form when targ* is empty
      (fref src function-name)               => function-name
      (fref src function-name (targ* ...))   => (fref function-name #f targ* ...)
      (circuit src (parg* ...) type stmt)    => (circuit (parg* 0 ...) 4 type #f stmt)
      )
    (Tuple-Argument (tuple-arg bytes-arg)
      (single src expr)                      => expr
      (spread src expr)                      => (spread expr)
      )
    (New-Field (new-field)
      (spread src expr)                      => (spread expr)
      (positional src expr)                  => expr
      (named src elt-name expr)              => (elt-name expr)
      )
    (Type (type)
      tref
      (tboolean src)                         => (tboolean)
      (tfield src)                           => (tfield)
      (tunsigned src tsize)                  => (tunsigned tsize)        ; range from 0 to 2^{tsize}-1
      (tunsigned src tsize tsize^)           => (tunsigned tsize tsize^) ; range from tsize (inclusive) to tsize^ (exclusive)
      (tbytes src tsize)                     => (tbytes tsize)
      (topaque src opaque-type)              => (topaque opaque-type)
      (tvector src tsize type)               => (tvector tsize type)
      (ttuple src type* ...)                 => (ttuple type* ...)
      (tundeclared)                          => (tundeclared)
      )
    (Type-Ref (tref)
      (type-ref src tvar-name targ* ...)     => (type-ref tvar-name #f targ* ...)
      )
    (Type-Size (tsize)
      (type-size src nat)                    => nat
      (type-size-ref src tsize-name)         => (type-size-ref tsize-name)
      )
    (Type-Argument (targ)
      (targ-size src nat)                    => nat
      (targ-type src type)                   => type
      )
  )

  (define-language/pretty Lnoinclude (extends Lsrc)
    (Program-Element (pelt)
      (- incld))
    (Include (incld)
      (- (include src file))))

  (define-language/pretty Lsingleconst (extends Lnoinclude)
    (Const-Binding (cbinding)
      (- (src pattern type expr)))
    (Statement (stmt)
      (- (const src cbinding cbinding* ...))
      (+ (const src pattern type expr) => (const pattern type expr)
         (seq src stmt* ...)  => (seq stmt* ...))
      )
    )

  (define-language/pretty Lnopattern (extends Lsingleconst)
    (Ledger-Constructor (lconstructor)
      (- (constructor src (parg* ...) stmt))
      (+ (constructor src (arg* ...) stmt) => (constructor (arg* ...) stmt)))
    (Circuit-Definition (cdefn)
      (- (circuit src exported? pure-dcl? function-name (type-param* ...) (parg* ...) type stmt))
      (+ (circuit src exported? pure-dcl? function-name (type-param* ...) (arg* ...) type stmt) =>
           (circuit exported? pure-dcl? function-name (type-param* ...) (arg* 0 ...) 4 type #f stmt)))
    (Pattern-Argument (parg)
      (- (src pattern type)))
    (Statement (stmt)
      (- (const src pattern type expr))
      (+ (const src var-name type expr) => (const var-name type expr)))
    (Function (fun)
      (- (circuit src (parg* ...) type stmt))
      (+ (circuit src (arg* ...) type stmt) => (circuit (arg* 0 ...) 4 type #f stmt)))
    (Pattern (pattern)
      (- var-name)
      (- (tuple src (maybe pattern?*) ...))
      (- (struct src (pattern* elt-name*) ...))
      )
    )

  (define-language/pretty Lhoisted (extends Lnopattern)
    (Statement (stmt)
      (- (const src var-name type expr)
         (block src stmt* ...))
      (+ (= src var-name type expr)                  => (= var-name type expr)
         (block src (var-name* ...) stmt* ...)       => (block (var-name* ...) #f stmt* ...)
         )))

  (define-language/pretty Lexpr (extends Lhoisted)
    (Ledger-Constructor (lconstructor)
      (- (constructor src (arg* ...) stmt))
      (+ (constructor src (arg* ...) expr) => (constructor (arg* 0 ...) #f expr)))
    (Circuit-Definition (cdefn)
      (- (circuit src exported? pure-dcl? function-name (type-param* ...) (arg* ...) type stmt))
      (+ (circuit src exported? pure-dcl? function-name (type-param* ...) (arg* ...) type expr) =>
           (circuit exported? pure-dcl? function-name (type-param* ...) (arg* 0 ...) 4 type #f expr)
      ))
    (Statement (stmt)
      (- (statement-expression src expr)
         (return src expr)
         (= src var-name type expr)
         (if src expr stmt1 stmt2)
         (for src var-name expr stmt)
         (seq src stmt* ...)
         (block src (var-name* ...) stmt* ...)))
    (Expression (expr index)
      (+ (let* src ([arg* expr*] ...) expr)      => (let* ([bracket arg* 0 expr*] 0 ...) #f expr)
         (for src var-name expr1 expr2)          => (for var-name expr1 #f expr2)
         (block src (var-name* ...) expr)        => (block (var-name* 0 ...) #f expr)
         (return src expr)                       => expr
         ))
    (Function (fun)
      (- (circuit src (arg* ...) type stmt))
      (+ (circuit src (arg* ...) type expr) =>
           (circuit (arg* 0 ...) 4 type #f expr))))

  (define-language/pretty Lnoandornot (extends Lexpr)
    (Expression (expr index)
      (- (and src expr1 expr2)
         (or src expr1 expr2)
         (not src expr))))

  (define-language/pretty Lpreexpand (extends Lnoandornot)
    (terminals
      (- (symbol (var-name name module-name function-name contract-name struct-name enum-name tvar-name tsize-name elt-name ledger-field-name type-name))
         (string (prefix mesg opaque-type file)))
      (+ (symbol (var-name name module-name function-name contract-name struct-name enum-name tvar-name tsize-name elt-name ledger-field-name ledger-op ledger-op-class adt-name adt-formal type-name))
         (string (prefix mesg opaque-type file discloses))
         (procedure (result-type runtime-code))
         (vm-expr (vm-expr))
         (vm-code (vm-code))))
    (Program-Element (pelt)
      (+ adt-defn
         circuit-alias-defn))
    (ADT-Definition (adt-defn)
      (+ (define-adt src exported? adt-name (type-param* ...) vm-expr (adt-op* ...) (adt-rt-op* ...)) =>
           (define-adt exported? adt-name #f (type-param* 0 ...) #f (adt-op* 0 ...) #f (adt-rt-op* 0 ...))))
    (Type-Param (type-param)
      (+ (non-adt-type-valued src tvar-name)))
    (ADT-Runtime-Op (adt-rt-op)
      (+ (ledger-op ((var-name* type*) ...) result-type runtime-code) =>
           ledger-op))
    (ADT-Op (adt-op)
      (+ (ledger-op op-class ((var-name* type* (maybe discloses?)) ...) type vm-code adt-op-cond* ...) =>
           ledger-op))
    (ADT-Op-Class (op-class)
      (+ ledger-op-class
         (ledger-op-class nat nat^)))
    (ADT-Op-Condition (adt-op-cond)
      (+ (= tvar-name type)))
    (Circuit-Alias-Definition (circuit-alias-defn)
      ; (circuit-alias alias-name actual-name)
      (+ (circuit-alias function-name^ function-name)))
    )

  (module (id-counter make-source-id make-temp-id id? id-src id-sym id-uniq id-refcount id-refcount-set! id-temp? id-exported? id-exported?-set! id-pure? id-pure?-set! id-sealed? id-sealed?-set! id-prefix)
    (define id-prefix (make-parameter "%"))
    (define id-counter (make-parameter 0))
    (define-record-type id
      (nongenerative)
      (fields src sym (mutable refcount) (mutable flags) (mutable uniq $id-uniq $id-uniq-set!))
      (protocol
        (lambda (new)
          (lambda (src sym)
            (unless (source-object? src) (errorf 'make-id "~s is not a source object" src))
            (unless (symbol? sym) (errorf 'make-id "~s is not a symbol" sym))
            (new src sym 0 0 #f)))))
    (module (id-exported? id-exported?-set!
             id-pure? id-pure?-set!
             id-sealed? id-sealed?-set!
             id-temp? id-temp?-set!)
      (define-syntax define-flag
        (syntax-rules ()
          [(_ k getter setter)
           (begin
             (define (getter id) (fxbit-set? (id-flags id) k))
             (define (setter id set?) (id-flags-set! id ((if set? fxlogbit1 fxlogbit0) k (id-flags id)))))]))
      (define-flag 0 id-exported? id-exported?-set!)
      (define-flag 1 id-sealed? id-sealed?-set!)
      (define-flag 2 id-pure? id-pure?-set!)
      (define-flag 3 id-temp? id-temp?-set!))
    (define (make-source-id src sym) (make-id src sym))
    (define (make-temp-id src sym)
      (let ([id (make-id src sym)])
        (id-temp?-set! id #t)
        id))
    (define (id-uniq id)
      (or ($id-uniq id)
          (let ([uniq (id-counter)])
            ($id-uniq-set! id uniq)
            (id-counter (+ uniq 1))
            uniq)))
    (record-writer (record-type-descriptor id)
      (lambda (x p wr)
        (fprintf p "~a~s.~s" (id-prefix) (id-sym x) (id-uniq x)))))

  (define-language/pretty Lexpanded (extends Lpreexpand)
    (terminals
      (+ (len (len)))
      (- (symbol (var-name name module-name function-name contract-name struct-name enum-name tvar-name tsize-name elt-name ledger-field-name ledger-op ledger-op-class adt-name adt-formal type-name))
         (boolean (exported sealed pure-dcl nominal))
         (string (prefix mesg opaque-type file discloses)))
      (+ (symbol (export-name contract-name struct-name enum-name type-name tvar-name elt-name opaque-type-name ledger-op ledger-op-class adt-name adt-formal symbolic-function-name generic-kind))
         (boolean (pure-dcl nominal))
         (id (name var-name function-name ledger-field-name))
         (string (mesg opaque-type file discloses))
         (native-entry (native-entry))))
    (Program (p)
      (- (program src pelt* ...))
      (+ (program src ((export-name* name*) ...) (unused-pelt* ...) (ecdecl* ...) pelt* ...)
           => (program ((export-name* name*) 0 ...) #f pelt* ...)))
    (Program-Element (pelt unused-pelt)
      (- mdefn
         idecl
         xdecl
         ecdecl
         structdef
         enumdef
         tdefn
         adt-defn
         circuit-alias-defn)
      (+ export-tdefn))
    (ADT-Definition (adt-defn)
      (- (define-adt src exported? adt-name (type-param* ...) vm-expr (adt-op* ...) (adt-rt-op* ...))))
    (Circuit-Alias-Definition (circuit-alias-defn)
      (- (circuit-alias function-name^ function-name)))
    (Ledger-Declaration (ldecl)
      (- (public-ledger-declaration src exported? sealed? ledger-field-name type))
      (+ (public-ledger-declaration src ledger-field-name public-adt) =>
           (public-ledger-declaration #f ledger-field-name #f public-adt)))
    (Public-Ledger-ADT (public-adt)
      (+ (src adt-name ([adt-formal* generic-value*] ...) vm-expr (adt-op* ...) (adt-rt-op* ...)) =>
           (adt-name #f generic-value* ...)))
    (Circuit-Definition (cdefn)
      (- (circuit src exported? pure-dcl? function-name (type-param* ...) (arg* ...) type expr))
      (+ (circuit src function-name (arg* ...) type expr) =>
           (circuit function-name (arg* 0 ...) 4 type #f expr)))
    (External-Contract-Declaration (ecdecl)
      (- (external-contract src exported? contract-name ecdecl-circuit* ...))
      (+ (external-contract src contract-name ecdecl-circuit* ...) =>
           (external-contract contract-name ecdecl-circuit* ...)))
    (External-Contract-Circuit (ecdecl-circuit)
      (- (src pure-dcl function-name (arg* ...) type))
      (+ (src pure-dcl elt-name (arg* ...) type) =>
           (pure-dcl elt-name (arg* ...) type)))
    (Module-Definition (mdefn)
      (- (module src exported? module-name (type-param* ...) pelt* ...)))
    (Import-Declaration (idecl)
      (- (import src import-name (targ* ...) prefix)
         (import src import-name (targ* ...) prefix (ielt* ...))))
    (Import-Name (import-name)
      (- module-name)
      (- file))
    (Export-Declaration (xdecl)
      (- (export src (src* name*) ...)))
    (External-Declaration (edecl)
      (- (external src exported? function-name (type-param* ...) (arg* ...) type))
      (+ (external src function-name native-entry (arg* ...) type) =>
           (external function-name (arg* 0 ...) 4 type)))
    (Witness-Declaration (wdecl)
      (- (witness src exported? function-name (type-param* ...) (arg* ...) type))
      (+ (witness src function-name (arg* ...) type) =>
           (witness function-name (arg* 0 ...) 4 type)))
    (Structure-Definition (structdef)
      (- (struct src exported? struct-name (type-param* ...) arg* ...)))
    (Enum-Definition (enumdef)
      (- (enum src exported? enum-name elt-name elt-name* ...)))
    (Type-Definition (tdefn)
      (- (typedef src exported? nominal? type-name (type-param* ...) type)))
    (Export-Type-Definition (export-tdefn)
      (+ (export-typedef src type-name (tvar-name* ...) type) =>
           (export-typedef type-name (tvar-name* ...) #f type)))
    (ADT-Runtime-Op (adt-rt-op)
      (+ (ledger-op (arg* ...) result-type runtime-code) =>
           ledger-op))
    (ADT-Op (adt-op)
      (- (ledger-op op-class ((var-name* type* (maybe discloses?)) ...) type vm-code adt-op-cond* ...))
      (+ (ledger-op op-class ((var-name* type* (maybe discloses?)) ...) type vm-code) =>
           ledger-op))
    (ADT-Op-Condition (adt-op-cond)
      (- (= tvar-name type)))
    (Type-Param (type-param)
      (- (nat-valued src tvar-name))
      (- (type-valued src tvar-name))
      (- (non-adt-type-valued src tvar-name)))
    (Argument (arg)
      (- (src var-name type))
      (+ (var-name type) => (bracket var-name type)))
    (Expression (expr index)
      (- (block src (var-name* ...) expr)
         (new src tref new-field* ...)
         (tuple-slice src expr index tsize))
      (+ (ledger-ref src ledger-field-name) => ledger-field-name
         (new src type new-field* ...)      => (new type #f new-field* ...)
         (enum-ref src type elt-name)       => (enum-ref type elt-name)
         (tuple-slice src expr index len)   => (tuple-slice #f expr #f index #f len)))
    (Function (fun)
      (- (fref src function-name)
         (fref src function-name (targ* ...)))
      (+ (fref src symbolic-function-name (([symbolic-function-name** function-name**] ...) ...)
               (generic-value* ...)
               ((src* generic-kind** ...) ...)) =>
           (fref ((function-name** ...) ...))))
    (Generic-Value (generic-value)
      (+ nat
         type))
    (Type (type)
      (- tref
         (tunsigned src tsize)
         (tunsigned src tsize tsize^)
         (tvector src tsize type)
         (tbytes src tsize))
      (+ tvar-name
         (tunsigned src nat)    => (tunsigned nat) ; nat = max value
         (tvector src len type) => (tvector len type)
         (tbytes src len)       => (tbytes len)
         (tcontract src contract-name (elt-name* pure-dcl* (type** ...) type*) ...) =>
           (tcontract contract-name #f (elt-name* pure-dcl* (type** ...) #f type*) ...)
         (tstruct src struct-name (elt-name* type*) ...) =>
           (tstruct struct-name #f (elt-name* type*) ...)
         (tenum src enum-name elt-name elt-name* ...) =>
           (tenum enum-name #f elt-name #f elt-name* ...)
         (talias src nominal? type-name type) => (talias nominal? type-name #f type)
         public-adt))
    (Type-Ref (tref)
      (- (type-ref src tvar-name targ* ...)))
    (Type-Size (tsize)
      (- (type-size src nat)
         (type-size-ref src tsize-name)))
    (Type-Argument (targ)
      (- (targ-size src nat)
         (targ-type src type))))

  (define-language/pretty Ltypes (entry Program)
    (terminals
      (field (nat kindex))
      (len (len))
      (maybe-bits (mbits))
      (symbol (export-name contract-name struct-name enum-name type-name tvar-name elt-name ledger-op ledger-op-class adt-name adt-formal))
      (boolean (pure-dcl nominal))
      (id (name var-name function-name ledger-field-name))
      (string (mesg opaque-type file discloses sugar))
      (datum (datum))
      (source-object (src))
      (procedure (result-type runtime-code))
      (vm-expr (vm-expr))
      (vm-code (vm-code))
      (native-entry (native-entry))
      )
    (Program (p)
      (program src (contract-name* ...) ((export-name* name*) ...) pelt* ...) => (program #f pelt* ...))
    (Program-Element (pelt)
      cdefn
      edecl
      wdecl
      ldecl
      lconstructor
      export-tdefn)
    (Circuit-Definition (cdefn)
      (circuit src function-name (arg* ...) type expr) =>
        (circuit function-name (arg* 0 ...) 4 type #f expr))
    (External-Declaration (edecl)
      (external src function-name native-entry (arg* ...) type) =>
        (external function-name (arg* 0 ...) 4 type))
    (Witness-Declaration (wdecl)
      (witness src function-name (arg* ...) type) =>
        (witness function-name (arg* 0 ...) 4 type))
    (Export-Type-Definition (export-tdefn)
      (export-typedef src type-name (tvar-name* ...) type) =>
        (export-typedef type-name (tvar-name* ...) #f type))
    (Ledger-Declaration (ldecl)
      (public-ledger-declaration src ledger-field-name public-adt) =>
        (public-ledger-declaration #f ledger-field-name #f public-adt))
    (Ledger-Constructor (lconstructor)
      (constructor src (arg* ...) expr)      => (constructor (arg* 0 ...) #f expr))
    (Public-Ledger-ADT (public-adt)
      (src adt-name ([adt-formal* adt-arg*] ...) vm-expr (adt-op* ...) (adt-rt-op* ...)) => (adt-name #f adt-arg* ...)
      )
    (ADT-Runtime-Op (adt-rt-op)
      (ledger-op (arg* ...) result-type runtime-code) =>
        ledger-op)
    (ADT-Op (adt-op)
      (ledger-op op-class ((var-name* adt-type* (maybe discloses?)) ...) adt-type vm-code) =>
        ledger-op)
    (ADT-Op-Class (op-class)
      ledger-op-class
      (ledger-op-class nat nat^))
    (Public-Ledger-ADT-Arg (adt-arg)
      nat
      adt-type)
    (Public-Ledger-ADT-Type (adt-type)
      type
      public-adt)
    (Argument (arg)
      (var-name type) => (bracket var-name type))
    (Local (local)
      (var-name adt-type) => (bracket var-name adt-type))
    (Expression (expr index)
      (quote src datum)                       => datum
      (var-ref src var-name)                  => var-name
      (ledger-ref src ledger-field-name)      => ledger-field-name
      (default src adt-type)                  => (default adt-type)
      (if src expr0 expr1 expr2)              => (if expr0 3 expr1 3 expr2)
      (elt-ref src expr elt-name nat)         => (elt-ref expr elt-name nat)
      (enum-ref src type elt-name)            => (enum-ref type elt-name)
      ; for tuple, the elements can have different, even unrelated types
      (tuple src tuple-arg* ...)              => (tuple tuple-arg* ...)
      ; for vector, the elements must all have the same type
      (vector src tuple-arg* ...)             => (vector tuple-arg* ...)
      ; for tuple-ref and tuple-slice, the index (nat) is constant, and expr's elements can have different, even unrelated types
      (tuple-ref src expr kindex)             => (tuple-ref #f expr #f kindex)
      (tuple-slice src type expr kindex len)  => (tuple-slice #f expr #f kindex #f len)
      ; for vector-ref and vector-slice, index is an arbitrary expression and expr's elements must all have the same type
      ; NB: index must eventually reduce to a constant, but that manifests in a later language.  for now, it is constrained
      ; only to have some Uint type
      (vector-ref src type expr index)        => (vector-ref #f expr #f index)
      (vector-slice src type expr index len)  => (vector-slice #f expr #f index #f len)
      ; for bytes-ref and bytes-slice, index is an arbitrary expression and expr must have a tbytes type
      ; NB: index must eventually reduce to a constant, but that manifests in a later language.  for now, it is constrained
      ; only to have some Uint type
      (bytes-ref src type expr index)         => (bytes-ref #f expr #f index)
      (bytes-slice src type expr index len)   => (bytes-slice #f expr #f index #f len)
      (+ src mbits expr1 expr2)               => (+ mbits expr1 expr2)
      (- src mbits expr1 expr2)               => (- mbits expr1 expr2)
      (* src mbits expr1 expr2)               => (* mbits expr1 expr2)
      (< src mbits expr1 expr2)               => (< expr1 expr2)
      (<= src mbits expr1 expr2)              => (<= expr1 3 expr2)
      (> src mbits expr1 expr2)               => (> expr1 expr2)
      (>= src mbits expr1 expr2)              => (>= expr1 3 expr2)
      (== src type expr1 expr2)               => (== expr1 3 expr2)
      (!= src type expr1 expr2)               => (!= expr1 3 expr2)
      (map src len fun map-arg map-arg* ...) =>
        (map #f fun #f map-arg #f map-arg* ...)
      (fold src len fun (expr0 type0) map-arg map-arg* ...) =>
        (fold #f fun #f expr0 #f map-arg #f map-arg* ...)
      (call src fun expr* ...)                => (call fun #f expr* ...)
      (new src type expr* ...)                => (new type #f expr* ...)
      (seq src expr* ... expr)                => (seq #f expr* ... #f expr)
      (let* src ([local* expr*] ...) expr)    => (let* ([bracket local* 0 expr*] 0 ...) #f expr)
      (assert src expr mesg)                  => (assert expr mesg)
      (field->bytes src len expr)             => (field->bytes len expr)
      (cast-from-bytes src type len expr)     => (cast-from-bytes type len #f expr)
      (vector->bytes src len expr)            => (vector->bytes len expr)
      (bytes->vector src len expr)            => (bytes->vector len expr)
      (cast-from-enum src type type^ expr)    => (cast-from-enum type type^ #f expr) ; type is tfield or tunsigned, type^ is tenum
      (cast-to-enum src type type^ expr)      => (cast-to-enum type type^ #f expr) ; type is tenum, type^ is tfield or tunsigned
      (safe-cast src type type^ expr)         => (safe-cast type 10 type^ #f expr) ; type^ < type
      (downcast-unsigned src nat expr)        => (downcast-unsigned nat #f expr)
      (disclose src expr)                     => (disclose expr)
      (ledger-call src ledger-op (maybe sugar) expr expr* ...) =>
        (ledger-call ledger-op #f expr #f expr* ...)
      (contract-call src elt-name (expr type) expr* ...) =>
        (contract-call elt-name 4 (expr 0 type) #f expr* ...)
      (return src expr)                       => expr
      )
    (Map-Argument (map-arg)
      ; type = expr's type; type^ = type to which each element of expr's value must be cast
      (expr type type^)                  => expr
      )
    (Tuple-Argument (tuple-arg)
      (single src expr)                      => expr
      (spread src nat expr)                  => (spread nat expr)
      )
    (Function (fun)
      (fref src function-name)               => function-name
      (circuit src (arg* ...) type expr)     => (circuit (arg* 0 ...) 4 type #f expr))
    (Type (type)
      tvar-name
      (tboolean src)                         => (tboolean)
      (tfield src)                           => (tfield)
      (tunsigned src nat)                    => (tunsigned nat)
      (tbytes src len)                       => (tbytes len)
      (topaque src opaque-type)              => (topaque opaque-type)
      (tvector src len type)                 => (tvector len type)
      (ttuple src type* ...)                 => (ttuple type* ...)
      (tcontract src contract-name (elt-name* pure-dcl* (type** ...) type*) ...) =>
        (tcontract contract-name #f (elt-name* pure-dcl* (type** ...) #f type*) ...)
      (tstruct src struct-name (elt-name* type*) ...) =>
        (tstruct struct-name #f (elt-name* type*) ...)
      (tenum src enum-name elt-name elt-name* ...) =>
        (tenum enum-name #f elt-name #f elt-name* ...)
      (talias src nominal type-name type) =>
        (talias nominal type-name #f type)
      (tundeclared)
      (tunknown)))

  (define-language/pretty Lnotundeclared (extends Ltypes)
    (Type (type)
      (- (tundeclared))))

  (define-language/pretty Loneledger (extends Lnotundeclared)
    (Program-Element (pelt)
      (- lconstructor)
      (+ kdecl))
    (Kernel-Declaration (kdecl)
      (+ (kernel-declaration public-binding)))
    (Ledger-Declaration (ldecl)
      (- (public-ledger-declaration src ledger-field-name public-adt))
      (+ (public-ledger-declaration public-binding* ... lconstructor) =>
           (public-ledger-declaration #f public-binding* ... #f lconstructor)))
    (Public-Ledger-Binding (public-binding)
      (+ (src ledger-field-name public-adt) => (ledger-field-name public-adt)))
    (Expression (expr index)
      (- (ledger-ref src ledger-field-name)
         (ledger-call src ledger-op (maybe sugar) expr expr* ...))
      (+ (public-ledger src ledger-field-name (maybe sugar) accessor* ...) =>
           (public-ledger ledger-field-name #f accessor* ...)))
    (Ledger-Accessor (accessor)
      (+ (src ledger-op expr* ...)              => (ledger-op #f expr* ...))))

  (define-language/pretty Lnodca (extends Loneledger)
    (Expression (expr index)
      (- (call src fun expr* ...))
      (+ (call src function-name expr* ...) => (call function-name #f expr* ...))))

  ; FIXME: maximum-ledger-segment-length should be defined by the ledger
  (define maximum-ledger-segment-length 15)
  (define (path-index? x)
    (and (fixnum? x)
         (fx>= x 0)
         (fx< x maximum-ledger-segment-length)))

  (define-language/pretty Lwithpaths0 (extends Lnodca)
    (terminals
      (+ (path-index (path-index))))
    (Ledger-Declaration (ldecl)
      (- (public-ledger-declaration public-binding* ... lconstructor))
      (+ (public-ledger-declaration pl-array lconstructor) =>
           (public-ledger-declaration #f pl-array #f lconstructor)))
    (Public-Ledger-Array (pl-array)
      (+ (public-ledger-array pl-array-elt ...) => (pl-array-elt 0 ...)))
    (Public-Ledger-Array-Element (pl-array-elt)
      (+ pl-array
         public-binding))
    (Public-Ledger-Binding (public-binding)
      (- (src ledger-field-name public-adt))
      (+ (src ledger-field-name (path-index* ...) public-adt) =>
           (ledger-field-name #f (path-index* ...) #f public-adt))))

  (define-language/pretty Lwithpaths (extends Lwithpaths0)
    (Expression (expr index)
      (- (public-ledger src ledger-field-name (maybe sugar) accessor* ...))
      ; for public ledger operation fldname.op1(...).op2(...).op3(), src is the src of fldname
      ; and src^ is the src of the "." before op3.  the src for the "." before op1
      ; and the src for the "." before op2 are recorded in the path-elts
      (+ (public-ledger src ledger-field-name (maybe sugar) (path-elt ...) src^ adt-op expr* ...) =>
           (public-ledger ledger-field-name (path-elt ...) adt-op #f expr* ...)))
    (ADT-Op (adt-op)
      (- (ledger-op op-class ((var-name* adt-type* (maybe discloses?)) ...) adt-type vm-code))
      (+ (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) ((var-name* adt-type* (maybe discloses?)) ...) adt-type vm-code) =>
           ledger-op))
    (Ledger-Accessor (accessor)
      (- (src ledger-op expr* ...)))
    (Path-Element (path-elt)
      (+ path-index
         (src type expr) => (type expr))))

  (define-language/pretty Lnodisclose (extends Lwithpaths)
    (ADT-Op (adt-op)
      (- (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) ((var-name* adt-type* (maybe discloses?)) ...) adt-type vm-code))
      (+ (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) ((var-name* adt-type*) ...) adt-type vm-code) =>
         ledger-op))
    (Expression (expr index)
      (- (disclose src expr))))

  (define-language/pretty Ltypescript (extends Lnodisclose)
    (terminals
      (- (id (name var-name function-name ledger-field-name)))
      (+ (id (name var-name function-name ledger-field-name descriptor-id))
         (hashtable (descriptor-table))))
    (Program (p)
      (- (program src (contract-name* ...) ((export-name* name*) ...) pelt* ...))
      (+ (program src ((export-name* name*) ...) tdescs pelt* ...) => (program #f tdescs #f pelt* ...)))
    (Type-Descriptors (tdescs)
      (+ (type-descriptors descriptor-table (descriptor-id* type*) ...) =>
           (type-descriptors #f (descriptor-id* type*) ...)))
    (Circuit-Definition (cdefn)
      (- (circuit src function-name (arg* ...) type expr))
      (+ (circuit src function-name (arg* ...) type stmt) =>
         (circuit function-name (arg* 0 ...) 4 type #f stmt)))
    (Ledger-Constructor (lconstructor)
      (- (constructor src (arg* ...) expr))
      (+ (constructor src (arg* ...) stmt)       => (constructor (arg* 0 ...) #f stmt)))
    (Function (fun)
      (- (circuit src (arg* ...) type expr))
      (+ (circuit src (arg* ...) type stmt)      => (circuit (arg* 0 ...) 4 type #f stmt)))
    (Expression (expr index)
      (- (let* src ([local* expr*] ...) expr)
         (return src expr))
      (+ (not src expr)                          => (not expr)
         (and src expr1 expr2)                   => (and expr1 4 expr2)
         (or src expr1 expr2)                    => (or expr1 3 expr2)
         (= src var-name expr)                   => (= var-name expr)))
    (Statement (stmt)
      (+ (if src expr0 stmt1)                    => (if expr0 3 stmt1)
         (if src expr0 stmt1 stmt2)              => (if expr0 3 stmt1 3 stmt2)
         (seq src stmt* ... stmt)                => (seq #f stmt* ... #f stmt)
         (const src local expr)                  => (const local #f expr)
         (const src (local* ...))                => (const (local* 0 ...))
         (statement-expression expr)             => expr)))

  (define-language/pretty Lposttypescript (extends Lnodisclose)
    (terminals
      (- (symbol (export-name contract-name struct-name enum-name type-name tvar-name elt-name ledger-op ledger-op-class adt-name adt-formal)))
      (+ (symbol (export-name contract-name struct-name enum-name elt-name ledger-op ledger-op-class adt-name adt-formal)))
      (- (boolean (pure-dcl nominal)))
      (+ (boolean (pure-dcl)))
      (- (procedure (result-type runtime-code))))
    (Program (p)
      (- (program src (contract-name* ...) ((export-name* name*) ...) pelt* ...))
      (+ (program src ((export-name* name*) ...) pelt* ...) => (program #f pelt* ...)))
    (Program-Element (pelt)
      (- export-tdefn))
    (Export-Type-Definition (export-tdefn)
      (- (export-typedef src type-name (tvar-name* ...) type)))
    (Ledger-Declaration (ldecl)
      (- (public-ledger-declaration pl-array lconstructor))
      (+ (public-ledger-declaration pl-array) =>
           (public-ledger-declaration #f pl-array)))
    (Ledger-Constructor (lconstructor)
      (- (constructor src (arg* ...) expr)))
    (Public-Ledger-ADT (public-adt)
      (- (src adt-name ([adt-formal* adt-arg*] ...) vm-expr (adt-op* ...) (adt-rt-op* ...)))
      (+ (src adt-name ([adt-formal* adt-arg*] ...) vm-expr (adt-op* ...)) =>
           (adt-name #f adt-arg* ...)))
    (ADT-Runtime-Op (adt-rt-op)
      (- (ledger-op (arg* ...) result-type runtime-code)))
    (Expression (expr index)
      (- (elt-ref src expr elt-name nat)
         (return src expr)
         (<= src mbits expr1 expr2)
         (> src mbits expr1 expr2)
         (>= src mbits expr1 expr2)
         (!= src type expr1 expr2)
         (cast-from-bytes src type len expr))
      (+ (elt-ref src expr elt-name) => (elt-ref expr elt-name)
         (bytes->field src len expr) => (bytes->field len expr)))
    (Type (type)
      (- tvar-name
         (talias src nominal type-name type))))

  (define-language/pretty Lnoenums (extends Lposttypescript)
    (terminals
      (- (symbol (export-name contract-name struct-name enum-name elt-name ledger-op ledger-op-class adt-name adt-formal)))
      (+ (symbol (export-name contract-name struct-name elt-name ledger-op ledger-op-class adt-name adt-formal))))
    (Expression (expr index)
      (- (enum-ref src type elt-name)
         (cast-from-enum src type type^ expr)
         (cast-to-enum src type type^ expr)))
    (Type (type)
      (- (tenum src enum-name elt-name elt-name* ...))))

  (define-language/pretty Lunrolled (extends Lnoenums)
    (Expression (expr index)
      (- (map src len fun map-arg map-arg* ...)
         (fold src len fun (expr0 type0) map-arg map-arg* ...))
      (+ (flet src function-name (src^ (arg* ...) type expr^) expr) =>
           (flet [bracket function-name 0 (circuit (arg* 0 ...) 4 type #f expr^)] #f expr)))
    (Map-Argument (map-arg)
      (- (expr type type^))
      )
    (Function (fun)
      (- (fref src function-name)
         (circuit src (arg* ...) type expr))))

  (define-language/pretty Linlined (extends Lunrolled)
    (Expression (expr index)
      (- (flet src function-name (src^ (arg* ...) type expr^) expr))))

  (define-language/pretty Lnosafecast (extends Linlined)
    (Expression (expr index)
      (- (safe-cast src type type^ expr))))

  (define-language/pretty Lnovectorref (extends Lnosafecast)
    (Expression (expr index)
      (- (bytes-ref src type expr index)
         (vector-ref src type expr index)
         (tuple-slice src type expr kindex len)
         (bytes-slice src type expr index len)
         (vector-slice src type expr index len))
      (+ (bytes-ref src expr kindex) => (bytes-ref expr kindex))))

  (define-language/pretty Lcircuit (entry Program)
    (terminals
      (field (nat))
      (len (len))
      (kindex (kindex))
      (maybe-bits (mbits))
      (boolean (pure-dcl))
      (symbol (export-name struct-name contract-name elt-name ledger-op ledger-op-class adt-name adt-formal))
      (id (name var-name function-name ledger-field-name))
      (string (mesg opaque-type file sugar))
      (datum (datum))
      (source-object (src))
      (path-index (path-index))
      (vm-expr (vm-expr))
      (vm-code (vm-code))
      (native-entry (native-entry))
      )
    (Program (p)
      (program src ((export-name* name*) ...) pelt* ...) => (program #f pelt* ...))
    (Program-Element (pelt) cdefn edecl wdecl kdecl ldecl)
    (External-Declaration (edecl)
      (external src function-name native-entry (arg* ...) type) => (external function-name (arg* 0 ...) 4 type))
    (Witness-Declaration (wdecl)
      (witness src function-name (arg* ...) type) => (witness function-name (arg* 0 ...) 4 type))
    (Circuit-Definition (cdefn)
      (circuit src function-name (arg* ...) type stmt* ... triv) => (circuit function-name (arg* 0 ...) 4 type #f stmt* ... #f triv))
    (Kernel-Declaration (kdecl)
      (kernel-declaration public-binding))
    (Ledger-Declaration (ldecl)
      (public-ledger-declaration pl-array) => (public-ledger-declaration #f pl-array))
    (Public-Ledger-Array (pl-array)
      (public-ledger-array pl-array-elt ...) => (pl-array-elt 0 ...))
    (Public-Ledger-Array-Element (pl-array-elt)
      pl-array
      public-binding)
    (Public-Ledger-Binding (public-binding)
      (src ledger-field-name (path-index* ...) public-adt) => (ledger-field-name #f (path-index* ...) #f public-adt)
      )
    (Public-Ledger-ADT (public-adt)
      (src adt-name ([adt-formal* adt-arg*] ...) vm-expr (adt-op* ...)) => (adt-name #f adt-arg* ...))
    (ADT-Op (adt-op)
      (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) ((var-name* adt-type*) ...) adt-type vm-code) =>
        ledger-op)
    (ADT-Op-Class (op-class)
      ledger-op-class
      (ledger-op-class nat nat^))
    (Public-Ledger-ADT-Arg (adt-arg)
      nat
      adt-type)
    (Public-Ledger-ADT-Type (adt-type)
      type
      public-adt)
    (Argument (arg)
      (var-name type) => (bracket var-name type))
    (Statement (stmt)
      (= var-name rhs)                  => (= var-name 2 rhs)
      (assert src test mesg)            => (assert test #f mesg))
    (Rhs (rhs)
      triv
      (+ mbits triv1 triv2)
      (- mbits triv1 triv2)
      (* mbits triv1 triv2)
      (< mbits triv1 triv2)
      (== triv1 triv2)                       => (== triv1 3 triv2)
      (select triv0 triv1 triv2)             => (select triv0 triv1 triv2)
      (tuple tuple-arg* ...)
      (vector tuple-arg* ...)
      (tuple-ref triv nat)
      (bytes-ref triv nat)
      (new type triv* ...)                   => (new type #f triv* ...)
      (elt-ref triv elt-name)
      (vector->bytes len triv)               => (vector->bytes len triv)
      (bytes->vector len triv)               => (bytes->vector len triv)
      (call src test function-name triv* ...) => (call test function-name #f triv* ...)
      (public-ledger src test ledger-field-name (maybe sugar) (path-elt* ...) src^ adt-op triv* ...) =>
        (public-ledger test ledger-field-name (path-elt* ...) adt-op #f triv* ...)
      (contract-call src test elt-name (triv type) triv* ...) =>
        (contract-call test elt-name 4 (triv 0 type) #f triv* ...)
      (field->bytes src test len triv)        => (field->bytes test len triv)
      (bytes->field src test len triv)        => (bytes->field test len triv)
      (downcast-unsigned src test nat triv)   => (downcast-unsigned test nat triv))
    (Triv (triv test)
      var-name
      (default adt-type)
      (quote datum)                          => datum
      )
    (Tuple-Argument (tuple-arg)
      (single src triv)                      => triv
      (spread src nat triv)                  => (spread nat triv)
      )
    (Path-Element (path-elt)
      path-index
      (src type triv) => (type triv))
    (Type (type)
      (tboolean src)                         => (tboolean)
      (tfield src)                           => (tfield)
      (tunsigned src nat)                    => (tunsigned nat)
      (tbytes src len)                       => (tbytes len)
      (topaque src opaque-type)              => (topaque opaque-type)
      (tvector src len type)                 => (tvector len type)
      (ttuple src type* ...)                 => (ttuple type* ...)
      (tcontract src contract-name (elt-name* pure-dcl* (type** ...) type*) ...) =>
        (tcontract contract-name #f (elt-name* pure-dcl* (type** ...) #f type*) ...)
      (tstruct src struct-name (elt-name* type*) ...) =>
        (tstruct struct-name #f (elt-name* type*) ...)
      (tunknown)))

  (define-language/pretty Lflattened (extends Lcircuit)
    (terminals
      (- (symbol (export-name struct-name contract-name elt-name ledger-op ledger-op-class adt-name adt-formal))
         (datum (datum)))
      (+ (symbol (export-name contract-name elt-name ledger-op ledger-op-class adt-name adt-formal ledger-op-formal))
         (field-bytes (nb))))
    (Circuit-Definition (cdefn)
      (- (circuit src function-name (arg* ...) type stmt* ... triv))
      (+ (circuit src function-name (arg* ...) type stmt* ... (triv* ...)) =>
            (circuit function-name (arg* 0 ...) 4 type #f stmt* ... #f (triv* ...))))
    (ADT-Op (adt-op)
      (- (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) ((var-name* adt-type*) ...) adt-type vm-code))
      (+ (ledger-op op-class (adt-name (adt-formal* adt-arg*) ...) (ledger-op-formal* ...) (type* ...) type vm-code) =>
           ledger-op))
    (Public-Ledger-ADT-Arg (adt-arg)
      (- adt-type)
      (+ type))
    (Public-Ledger-ADT-Type (adt-type)
      (- type
         public-adt))
    (Argument (arg)
      (- (var-name type))
      (+ (argument (var-name* ...) type)))
    (Statement (stmt)
      (- (= var-name rhs))
      ; nanopass limitation: swap the two clauses below and the (= (var-name ...) multiple) pattern
      ; is rejected. (reported to Andy Keep 01/02/2024)
      (+ (= (var-name* ...) multiple) =>  (= (var-name* 0 ...) 2 multiple)
         (= var-name single)          =>  (= var-name 2 single)))
    (Rhs (rhs)
      (- triv
         (+ mbits triv1 triv2)
         (- mbits triv1 triv2)
         (* mbits triv1 triv2)
         (< mbits triv1 triv2)
         (== triv1 triv2)
         (select triv0 triv1 triv2)
         (tuple tuple-arg* ...)
         (vector tuple-arg* ...)
         (tuple-ref triv nat)
         (bytes-ref triv nat)
         (new type triv* ...)
         (elt-ref triv elt-name)
         (vector->bytes len triv)
         (bytes->vector len triv)
         (call src test function-name triv* ...)
         (public-ledger src test ledger-field-name (maybe sugar) (path-elt* ...) src^ adt-op triv* ...)
         (contract-call src test elt-name (triv type) triv* ...)
         (field->bytes src test len triv)
         (bytes->field src test len triv)
         (downcast-unsigned src test nat triv)))
    (Single (single)
      (+ triv
         (+ mbits triv1 triv2)
         (- mbits triv1 triv2)
         (* mbits triv1 triv2)
         (< mbits triv1 triv2)
         (== triv1 triv2)                        => (== triv1 3 triv2)
         (select triv0 triv1 triv2)              => (select triv0 triv1 triv2)
         (bytes-ref triv nat)
         (bytes->field src test len triv1 triv2) => (bytes->field test len #f triv1 #f triv2)
         (vector->bytes triv triv* ...)          => (vector->bytes triv triv* ...) ; result holds one field's worth of bytes
         (downcast-unsigned src test nat triv)   => (downcast-unsigned test nat triv)))
    (Multiple (multiple)
      (+ (call src test function-name triv* ...) =>
           (call test function-name #f triv* ...)
         (field->bytes src test len triv)        => (field->bytes test len #f triv)
         (bytes->vector triv)                    => (bytes->vector #f triv) ; triv holds one field's worth of bytes
         (public-ledger src test ledger-field-name (maybe sugar) (path-elt* ...) src^ adt-op triv* ...) =>
           (public-ledger test ledger-field-name (path-elt* 0 ...) adt-op #f triv* ...)
         (contract-call src test elt-name (triv primitive-type) triv* ...) =>
           (contract-call test elt-name 4 (triv primitive-type) #f triv* ...)))
    (Triv (triv test)
      (- (quote datum)
         (default adt-type))
      (+ nat))
    (Tuple-Argument (tuple-arg)
      (- (single src triv)
         (spread src nat triv)))
    (Path-Element (path-elt)
      (- (src type triv))
      (+ (src type triv* ...) => (type triv* ...)))
    (Alignment (alignment)
      (+ (acompress)
         (abytes nat)
         (afield)
         (aadt)
         (acontract)))
    (Type (type)
      (- (tboolean src)
         (tfield src)
         (tunsigned src nat)
         (tbytes src len)
         (topaque src opaque-type)
         (tvector src len type)
         (ttuple src type* ...)
         (tstruct src struct-name (elt-name* type*) ...)
         (tcontract src contract-name (elt-name* pure-dcl* (type** ...) type*) ...)
         (tunknown))
      (+ (ty (alignment* ...) (primitive-type* ...))))
    (Primitive-Type (primitive-type)
      (+ (tfield)
         (tfield nat)
         (topaque opaque-type)
         (tcontract contract-name (elt-name* pure-dcl* (type** ...) type*) ...) =>
           (tcontract contract-name #f (elt-name* pure-dcl* (type** ...) #f type*) ...)
         public-adt)))

  (define-language/pretty Lzkir (entry Program)
    (terminals
      (field (arg-count var imm nat))
      (zkir-field-rep (fr))
      (source-object (src))
      (symbol (name))
      (Lflattened-Alignment (alignment)))
    (Program (p)
      (program src cdefn* ...) => (program #f cdefn* ...))
    (Circuit-Definition (cdefn)
      (circuit src (name* ...) arg-count instr* ...) => (circuit (name* ...) arg-count #f instr* ...))
    (Instruction (instr)
      (add var0 var1)
      (assert var)
      (cond_select var0 var1 var2)
      (constrain_bits var0 imm)
      (constrain_eq var0 var1)
      (constrain_to_boolean var)
      (copy var)
      (declare_pub_input var)
      (div_mod_power_of_two var imm)
      (ec_add var0 var1 var2 var3)
      (ec_mul var0 var1 var2)
      (ec_mul_generator var)
      (hash_to_curve var* ...)
      (less_than var0 var1 imm)
      (load_imm fr)
      (mul var0 var1)
      (neg var)
      (output var)
      (persistent_hash (alignment* ...) var* ...)
      (pi_skip var imm)
      (private_input)
      (private_input var)
      (public_input)
      (public_input var)
      (reconstitute_field var0 var1 imm)
      (test_eq var0 var1)
      (transient_hash var* ...)))
)
