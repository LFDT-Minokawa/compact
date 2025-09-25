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

(library (lparser)
  (export make-token token? token-src token-type token-value token-string
          Lparser unparse-Lparser Lparser-pretty-formats Lparser-Pragma?)
  (import (chezscheme) (nanopass) (nanopass-extension) (field) (langs))

  (module (make-token token? token-src token-type token-value token-string)
    (define-record-type token
      (nongenerative)
      (fields src type value string))
    (record-writer (record-type-descriptor token) ; for debugging
      (lambda (x p wr)
        (fprintf p "%~s" (token-string x)))))

  (define (field-token? x) (and (token? x) (eq? (token-type x) 'field)))
  (define (id-token? x) (and (token? x) (eq? (token-type x) 'id)))
  (define (string-token? x) (and (token? x) (eq? (token-type x) 'string)))
  (define (version-token? x) (and (token? x) (eq? (token-type x) 'version)))
  (define (eof-token? x) (and (token? x) (eq? (token-type x) 'eof)))
  (define (keyword-token? x) (and (token? x) (eq? (token-type x) 'id)))
  (define (op-token? x) (and (token? x) (eq? (token-type x) 'binop)))
  (define (punctuation-token? x) (and (token? x) (eq? (token-type x) 'punctuation)))

  (define-language/pretty Lparser
    (terminals
      (source-object (src))
      (field-token (nat start end))
      (id-token (var-name name module-name function-name contract-name struct-name enum-name tvar-name tsize-name elt-name ledger-field-name prefix))
      (string-token (str mesg opaque-type file))
      (version-token (version))
      (eof-token (eof))
      (keyword-token (kwd kwd-else kwd-const kwd-of kwd-export kwd-sealed kwd-pure kwd-prefix))
      (op-token (op langle rangle))
      (punctuation-token (dot dotdot dotdotdot comma semicolon colon hook lparen rparen lbracket rbracket lbrace rbrace arrow sep hashmark bang))
      )
    (Program (p)
      (program src pelt* ... eof) => (program #f pelt* ...)
      )
    (Program-Element (pelt)
      pdecl
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
      )
    (Pragma (pdecl)
      (pragma src kwd name version-expr semicolon) => (pragma name version-expr)
      )
    (Version-Expression (version-expr)
      version-atom
      (not bang version-atom)
      (< op version-atom)
      (<= op version-atom)
      (>= op version-atom)
      (> op version-atom)
      (and version-expr1 op version-expr2)
      (or version-expr1 op version-expr2)
      (parenthesized lparen version-expr rparen)
      )
    (Version-Atom (version-atom)
      nat
      version)
    (Include (incld)
      (include src kwd file semicolon) =>
        (include file)
      )
    (Module-Definition (mdefn)
      (module src (maybe kwd-export?) kwd module-name (maybe generic-param-list?) lbrace pelt* ... rbrace) =>
        (module kwd-export? module-name generic-param-list? #f pelt* ...)
      )
    (Import-Declaration (idecl)
      (import src kwd import-name (maybe generic-arg-list?) (maybe import-prefix?) semicolon) =>
        (import import-name generic-arg-list? #f import-prefix?)
      )
    (Import-Name (import-name)
      module-name
      file)
    (Import-Prefix (import-prefix)
      (kwd-prefix prefix) => prefix
      )
    (Export-Declaration (xdecl)
      (export src kwd lbrace (name* ...) (sep* ...) rbrace (maybe semicolon)) =>
        (export #f name* ...)
      )
    (Ledger-Declaration (ldecl)
      (public-ledger-declaration src (maybe kwd-export?) (maybe kwd-sealed?) kwd ledger-field-name colon type semicolon) =>
        (public-ledger-declaration kwd-export? kwd-sealed? #f ledger-field-name #f type)
      )
    (Ledger-Constructor (lconstructor)
      (constructor src kwd parg-list stmt) => (constructor parg-list #f stmt)
      )
    (Circuit-Definition (cdefn)
      (circuit src (maybe kwd-export?) (maybe kwd-pure?) kwd function-name (maybe generic-param-list?) parg-list return-type stmt) =>
        (circuit kwd-export? kwd-pure? function-name generic-param-list? parg-list 4 return-type #f stmt)
      )
    (External-Declaration (edecl)
      (external src (maybe kwd-export?) kwd function-name (maybe generic-param-list?) arg-list return-type semicolon) =>
        (external kwd-export? function-name generic-param-list? arg-list 4 return-type)
      )
    (Witness-Declaration (wdecl)
      (witness src (maybe kwd-export?) kwd function-name (maybe generic-param-list?) arg-list return-type semicolon) =>
        (witness kwd-export? function-name generic-param-list? arg-list 4 return-type)
      )
    (External-Contract-Declaration (ecdecl)
      (external-contract src (maybe kwd-export?) kwd contract-name lbrace (ecdecl-circuit* ...) (sep* ...) rbrace (maybe semicolon?)) =>
        (external-contract kwd-export? contract-name #f ecdecl-circuit* ...)
      )
    (External-Contract-Circuit (ecdecl-circuit)
      (src (maybe kwd-pure?) kwd function-name arg-list return-type) =>
        (kwd-pure? function-name arg-list 4 return-type)
      )
    (Structure-Definition (structdef)
      (struct src (maybe kwd-export?) kwd struct-name (maybe generic-param-list?) lbrace (arg* ...) (sep* ...) rbrace (maybe semicolon?)) =>
        (struct kwd-export? struct-name generic-param-list? #f arg* ...)
      )
    (Enum-Definition (enumdef)
      (enum src (maybe kwd-export?) kwd enum-name lbrace (elt-name elt-name* ...) (sep* ...) rbrace (maybe semicolon?)) =>
        (enum kwd-export? kwd enum-name #f elt-name #f elt-name* ...)
      )
    (Generic-Param (generic-param)
      (nat-valued src hashmark tvar-name) => (nat-valued tvar-name)
      (type-valued src tvar-name) => tvar-name
      )
    (Generic-Param-List (generic-param-list)
      (langle (generic-param* ...) (sep* ...) rangle) => (generic-param* ...)
      )
    (Generic-Arg (generic-arg)
      (generic-arg-size src nat) => nat
      (generic-arg-type src type) => type
      )
    (Generic-Arg-List (generic-arg-list)
      (langle (generic-arg* ...) (sep* ...) rangle) => (generic-arg* ...)
      )
    (Pattern-Argument (parg)
      (src pattern) => (bracket pattern)
      (src pattern colon type) => (bracket pattern type))
    (Const-Binding (cbinding)
      (src parg op expr) => (parg #f expr))
    (Pattern-Argument-List (parg-list)
      (lparen (parg* ...) (sep* ...) rparen) => (parg* 0 ...)
      )
    (Pattern (pattern)
      var-name
      (tuple src lbracket ((maybe pattern?*) ...) (comma* ...) rbracket) => (pattern?* ...)
      (struct src lbrace (pattern-struct-elt* ...) (comma* ...) rbrace) => (pattern-struct-elt* ...)
      )
    (Pattern-Struct-Elt (pattern-struct-elt)
      elt-name
      (elt-name colon pattern) => (elt-name pattern)
      )
    (Argument (arg)
      (src var-name colon type) => (bracket var-name type)
      )
    (Argument-List (arg-list)
      (lparen (arg* ...) (sep* ...) rparen) => (arg* 0 ...)
      )
    (Return-Type (return-type)
      (colon type) => type
      )
    (Statement (stmt)
      (statement-expression src expr semicolon) => expr
      (return src kwd semicolon) => (return)
      (return src kwd expr semicolon) => (return expr)
      (const src kwd (cbinding cbinding* ...) (comma* ...) semicolon) => (const #f cbinding #f cbinding* ...)
      (if src kwd lparen expr rparen stmt1 kwd-else stmt2) => (if expr 3 stmt1 3 stmt2)
      (if src kwd lparen expr rparen stmt) => (if expr 3 stmt)
      (for src kwd lparen kwd-const var-name kwd-of start dotdot end rparen stmt) => (for var-name start end #f stmt)
      (for src kwd lparen kwd-const var-name kwd-of expr rparen stmt) => (for var-name expr #f stmt)
      (block src lbrace stmt* ... rbrace) => (block #f stmt* ...)
      )
    (Expression (expr index)
      (true src kwd) => true
      (false src kwd) => false
      (field src nat) => nat
      (string src str) => str
      (pad src kwd lparen nat comma str rparen) => (pad nat str)
      (var-ref src var-name) => var-name
      (default src kwd langle type rangle) => (default type)
      (if src expr0 hook expr1 colon expr2) => (if expr0 3 expr1 3 expr2)
      (elt-ref src expr dot elt-name) => (elt-ref expr elt-name)
      (elt-call src expr dot elt-name lparen (expr* ...) (comma* ...) rparen) => (elt-call expr elt-name expr* ...)
      (= src expr1 op expr2) => (= expr1 expr2)
      (+= src expr1 op expr2) => (+= expr1 3 expr2)
      (-= src expr1 op expr2) => (-= expr1 3 expr2)
      (binop src expr1 op expr2) => (op expr1 expr2)
      (tuple src lbracket (tuple-arg* ...) (comma* ...) rbracket) => (tuple tuple-arg* ...)
      (bytes src kwd lbracket (bytes-arg* ...) (comma* ...) rbracket) => (bytes bytes-arg* ...)
      (tuple-ref src expr lbracket index rbracket) => (tuple-ref #f expr #f index)
      (tuple-slice src kwd langle tsize rangle lparen expr comma index rparen) => (tuple-slice #f expr #f index #f tsize)
      (not src bang expr) => (not expr)
      (map src kwd lparen fun comma (expr expr* ...) (comma* ...) rparen) => (map fun #f expr #f expr* ...)
      (fold src kwd lparen fun comma (expr0 expr expr* ...) (comma* ...) rparen) => (fold fun #f expr0 #f expr #f expr* ...)
      (call src fun lparen (expr* ...) (comma* ...) rparen) => (call fun #f expr* ...)
      (new src tref lbrace (new-field* ...) (comma* ...) rbrace) => (new tref #f new-field* ...)
      (seq src (expr* ...) (comma* ...) expr) => (seq #f expr* ... #f expr)
      (cast src type kwd expr) => (cast type #f expr)
      (parenthesized src lparen expr rparen) => (parenthesized expr)
      (disclose src kwd lparen expr rparen) => (disclose expr)
      (assert src kwd lparen expr comma mesg rparen) => (assert #f expr #f mesg)
      )
    (Function (fun)
      (fref src function-name (maybe generic-arg-list?)) => (fref function-name #f generic-arg-list?)
      (arrow-stmt src parg-list (maybe return-type?) arrow stmt) => (circuit parg-list 4 return-type? #f stmt)
      (arrow-expr src parg-list (maybe return-type?) arrow expr) => (circuit parg-list 4 return-type? #f expr)
      (parenthesized src lparen fun rparen) => (parenthesized fun)
      )
    (Tuple-Argument (tuple-arg bytes-arg)
      (single src expr) => expr
      (spread src dotdotdot expr) => (spread expr)
      )
    (New-Field (new-field)
      (spread src dotdotdot expr) => (spread expr)
      (positional src expr) => expr
      (named src elt-name colon expr) => (elt-name expr)
      )
    (Type (type)
      tref
      (tboolean src kwd) => (tboolean)
      (tfield src kwd) => (tfield)
      (tunsigned src kwd langle tsize rangle) => (tunsigned tsize)        ; range from 0 to 2^{tsize}-1
      (tunsigned src kwd langle tsize dotdot tsize^ rangle) => (tunsigned tsize tsize^) ; range from tsize to tsize^
      (tbytes src kwd langle tsize rangle) => (tbytes tsize)
      (topaque src kwd langle opaque-type rangle) => (topaque opaque-type)
      (tvector src kwd langle tsize comma type rangle) => (tvector tsize type)
      (ttuple src lbracket (type* ...) (comma* ...) rbracket) => (ttuple type* ...)
      )
    (Type-Ref (tref)
      (type-ref src tvar-name (maybe generic-arg-list?)) => (type-ref tvar-name #f generic-arg-list?)
      )
    (Type-Size (tsize)
      (type-size src nat) => nat
      (type-size-ref src tsize-name) => (type-size-ref tsize-name)
      )
  )
)
