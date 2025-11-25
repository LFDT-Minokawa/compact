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

;;; Some portions of this code are adapted from Chez Scheme
;;; examples/ez-grammar-test.ss, which is covered by the following
;;; copyright notice:
;;;
;;; Copyright 2017 Cisco Systems, Inc.
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;; http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

(library (parser)
  (export parse-file parse-file/token-stream parser-keywords parser-passes)
  (import (except (chezscheme) errorf)
          (utils)
          (streams)
          (lexer)
          (nanopass)
          (lparser)
          (lparser-to-lsrc)
          (langs)
          (ledger)
          (sourcemaps)
          (pass-helpers)
          (only (version) Lversion make-version)
          (compiler-version)
          (language-version))

  (define parse-sfd (make-parameter #f))

  ; NB: check this list regularly.  ideally, we would generate it automatically.
  (define keywordBoolean '(
    true
    false))
  (define keywordImport '(
    export
    import
    from
    module))
  (define keywordControl '(
    as
    assert
    circuit
    constructor
    const
    contract
    default
    disclose
    else
    enum
    fold
    for
    if
    include
    ledger
    map
    new
    of
    pad
    pragma
    prefix
    pure
    return
    sealed
    slice
    struct
    type
    witness))
  (define keywordDataTypes '(
    Bytes
    Boolean
    Field
    Opaque
    Uint
    Vector))
  (define-syntax keywordReservedForFutureUse (identifier-syntax '(
    this ; use as an identifier can cause problems with generated Javascript code, so we reserve
    )))
  (define (parser-keywords)
    `((keywordBoolean ,keywordBoolean)
      (keywordImport ,keywordImport)
      (keywordControl ,keywordControl)
      (keywordDataTypes ,keywordDataTypes)))
  (define all-keywords (append keywordBoolean keywordImport keywordDataTypes keywordControl keywordReservedForFutureUse))

  (define keyword?
    (let ([ht (make-hashtable symbol-hash eq?)])
      (for-each (lambda (x) (hashtable-set! ht x #t)) all-keywords)
      (lambda (x) (hashtable-contains? ht x))))

  (define (unreserved? x)
    (and (not (keyword? x))
         ; identifiers named 'this' cause problems with generated Javascript code,
         ; so officially, we reserve it for future use
         (not (string-prefix? "__compact" (symbol->string x)))))

  (module (define-grammar is sat sat/what parse-consumed-all? parse-result-value grammar-trace)
    (meta define seen-keywords (box keywordReservedForFutureUse))
    (module ()
      (define-syntax a (lambda (x) #`'#,(datum->syntax #'* seen-keywords)))
      (define symbol<? (lambda (x y) (string<? (symbol->string x) (symbol->string y))))
      (define (dedup sym*)
        (let loop ([sym* sym*] [last #f])
          (if (null? sym*)
              '()
              (let* ([sym (car sym*)]
                     [sym* (loop (cdr sym*) sym)])
                (if (eq? sym last) sym* (cons sym sym*))))))
      (let loop ([seen* (dedup (sort symbol<? (unbox a)))]
                 [decl* (sort symbol<? all-keywords)])
        (unless (equal? seen* decl*)
          (internal-errorf 'parser
                           "mismatch between seen and declared keywords: extra seen keywords = ~s, extra declared keywords = ~s"
                           (filter (lambda (x) (not (memq x decl*))) seen*)
                           (filter (lambda (x) (not (memq x seen*))) decl*)))))
    (meta define (constant? x)
      (syntax-case x ()
        [(?keyword ?sym)
         (and (eq? (datum ?keyword) 'KEYWORD) (symbol? (datum ?sym)))
         (begin
           (set-box! seen-keywords (cons (datum ?sym) (unbox seen-keywords)))
           #t)]
        [_ (let ([x (syntax->datum x)]) (or (string? x) (char? x)))]))
    (meta define (suppress-constant? x) #f)
    (meta define (constant->parser x)
      (syntax-case x ()
        [(?keyword ?sym)
         (eq? (datum ?keyword) 'KEYWORD)
         #`(sat/what #,(format "\"~s\"" (datum ?sym))
             (lambda (x)
               (and (eq? (token-type x) 'id)
                    (eq? (token-value x) '?sym))))]
        [?k
         #`(sat/what #,(format "\"~a\"" (datum ?k))
             (lambda (x)
               (and (memq (token-type x) '(punctuation binop))
                    (equal? (token-value x) '?k))))]))
    (meta define (constant->html const)
      (format "<b><tt>~a</tt></b>"
        (cond
          [(pair? const)
           (assert (and (list? const)
                        (= (length const) 2)
                        (eq? (car const) 'KEYWORD)))
           (cadr const)]
          [else const])))
    (define (src0) (make-source-object (parse-sfd) 0 0 1 1))
    (define (make-src bsrc esrc)
      (if (eq? bsrc esrc)
          bsrc
          (make-source-object
            (parse-sfd)
            (source-object-bfp bsrc)
            (source-object-efp esrc)
            (source-object-line bsrc)
            (source-object-column bsrc))))
    (define (src>? src1 src2)
      (> (source-object-bfp src1)
         (source-object-bfp src2)))
    (include "third_party/compiler/ez-grammar.ss"))

;;  (define waste (grammar-trace #t))

  (define end-of-file (sat/what "end of file" (lambda (x) (eq? (token-type x) 'eof))))

  (define identifier (sat/what "an identifier" (lambda (x) (and (eq? (token-type x) 'id) (unreserved? (token-value x))))))

  (define field-literal (sat/what "a non-negative numeric constant" (lambda (x) (eq? (token-type x) 'field))))

  (define string-literal (sat/what "a string" (lambda (x) (eq? (token-type x) 'string))))

  (define version-literal (sat/what "a version string" (lambda (x) (eq? (token-type x) 'version))))

  (define (make-binop src expr1 op expr2)
    (with-output-language (Lparser Expression)
      `(binop ,src ,expr1 ,op ,expr2)))

  (define (split-sep x*)
    (letrec ([odds (lambda (x* tail) (if (null? x*) tail (cons (car x*) (evens (cdr x*) tail))))]
             [evens (lambda (x* tail) (if (null? x*) tail (odds (cdr x*) tail)))])
      (values (odds x* '()) (evens x* '()))))

  (define-grammar Compact
    (options (html-directory "doc") (first-match #f))
    (GRAMMAR "Compact Grammar"
             (EVAL (let () (import (language-version)) (format "Compact language version ~a." language-version-string)))
             (HTML
               "Notational note: In the grammar productions below, ellipses are used to specify repetition."
               "The notation <em>X</em> ... <em>X</em>, where <em>X</em> is a grammar symbol, represents zero or more occurrences of <em>X</em>."
               "The notation <em>X</em> <em>s</em> ... <em>s</em> <em>X</em>, where <em>X</em> is a grammar symbol and <em>s</em> is a separator such as a comma or or semicolon, represents zero or more occurrences of <em>X</em> separated by <em>s</em>."
               "In either case, when the ellipsis is marked with the superscript 1, the notation represents a sequence containing at least one <em>X</em>."
               "When such a sequence is followed by <em>s</em><sup>opt</sup>, an optional trailing separator is allowed, but only if there is at least one <em>X</em>."
               "For example, id &mldr; id represents zero or more ids, and expr , &mldr;&sup1; , expr ,<sup>opt</sup> represents one or more comma-separated exprs possibly followed by an extra comma."))
    (TERMINALS
      (end-of-file (eof)
        (DESCRIPTION
          ("end of file")))
      (identifier (id module-name function-name struct-name enum-name contract-name tvar-name type-name)
        (DESCRIPTION
          ("identifiers have the same syntax as Typescript identifiers")))
      (field-literal (nat)
        (DESCRIPTION
          ("a field literal is 0 or a natural number formed from a sequence of digits starting with 1-9, e.g. 723, whose value does not exceed the maximum field value")))
      (string-literal (str file)
        (DESCRIPTION
          ("a string literal has the same syntax as a Typescript string")))
      (version-literal (version)
        (DESCRIPTION
          ("a version literal takes the form nat or nat.nat or nat.nat.nat, e.g., 1.2 or 1.2.3, representing major, minor, and bugfix versions"))))
    (Compact (program)
      [program :: src (K* pelt) eof =>
       (lambda (src pelt* eof)
         (with-output-language (Lparser Program)
           `(program ,src ,pelt* ... ,eof)))])
    (Program-element (pelt)
      [program-element-pragma :: pragma => values]
      [program-element-include :: incld => values]
      [program-element-module-definition :: mdefn => values]
      [program-element-import-declaration :: idecl => values]
      [program-element-export-declaration :: xdecl => values]
      [program-element-ledger-declaration :: ldecl => values]
      [program-element-ledger-constructor :: lconstructor => values]
      [program-element-circuit-definition :: cdefn => values]
      [program-element-external-declaration :: edecl => values]
      [program-element-witness-declaration :: wdecl => values]
      [program-element-contract-declaration :: ecdecl => values]
      [program-element-struct-declaration :: struct => values]
      [program-element-enum-declaration :: enumdef => values]
      [program-element-type-declaration :: tdefn => values])
    (Pragma (pragma)
      [pragma :: src (KEYWORD pragma) id version-expr #\; =>
       (lambda (src kwd id ve semicolon)
         (define-pass lversion : (Lparser Version-Expression) (ir) -> Lversion ()
           (Version-Expression : Version-Expression (ir) -> Version-Expression ()
             [(< ,op ,[version]) `(< ,version)]
             [(<= ,op ,[version]) `(<= ,version)]
             [(>= ,op ,[version]) `(>= ,version)]
             [(> ,op ,[version]) `(> ,version)]
             [(not ,bang ,[version]) `(not ,version)]
             [(and ,[ve1] ,op ,[ve2]) `(and ,ve1 ,ve2)]
             [(or ,[ve1] ,op ,[ve2]) `(or ,ve1 ,ve2)]
             [(parenthesized ,lparen ,[ve] ,rparen) ve])
           (Version-Atom : Version-Atom (ir) -> version ()
             [,nat (make-version '* (token-value nat) '* '*)]
             [,version (token-value version)]))
         (let ([sym (token-value id)])
           (case sym
             ; NB: might want to suppress these checks in fixup and maybe formatter
             [(language_version) (check-language-version src (lversion ve)) '()]
             [(compiler_version) (check-compiler-version src (lversion ve)) '()]
             [else (source-errorf src "unrecognized pragma setting ~s" sym)]))
         (with-output-language (Lparser Pragma)
           `(pragma ,src ,kwd ,id ,ve ,semicolon)))])
    (Version-expression (version-expr)
      ["version || expression" :: version-expr "||" version-expr0 =>
       (lambda (ve1 op ve2)
         (with-output-language (Lparser Version-Expression)
           `(or ,ve1 ,op ,ve2)))]
      [#f :: version-expr0 => values])
    (Version-expression0 (version-expr0)
      ["version && expression" :: version-expr0 "&&" version-term =>
       (lambda (ve1 op ve2)
         (with-output-language (Lparser Version-Expression)
           `(and ,ve1 ,op ,ve2)))]
      [#f :: version-term => values])
    (Version-Term (version-term)
      [version-term-atom :: version-atom => values]
      [version-term-not :: #\! version-atom =>
       (lambda (bang vt) (with-output-language (Lparser Version-Expression) `(not ,bang ,vt)))]
      [version-term-lt :: #\< version-atom =>
       (lambda (op v) (with-output-language (Lparser Version-Expression) `(< ,op ,v)))]
      [version-term-le :: "<=" version-atom =>
       (lambda (op v) (with-output-language (Lparser Version-Expression) `(<= ,op ,v)))]
      [version-term-ge :: ">=" version-atom =>
       (lambda (op v) (with-output-language (Lparser Version-Expression) `(>= ,op ,v)))]
      [version-term-gt :: #\> version-atom =>
       (lambda (op v) (with-output-language (Lparser Version-Expression) `(> ,op ,v)))]
      [version-term-parens :: #\( version-expr #\) =>
       (lambda (lparen ve rparen) (with-output-language (Lparser Version-Expression) `(parenthesized ,lparen ,ve ,rparen)))])
    (Version-atom (version-atom)
      [version-term-nat :: nat => values]
      [version-term-version :: version => values])
    (Include (incld)
      [include :: src (KEYWORD include) file #\; =>
        (lambda (src kwd file semicolon)
          (with-output-language (Lparser Include)
            `(include ,src ,kwd ,file ,semicolon)))])
    (Module-definition (mdefn)
      [module-definition :: src (OPT (KEYWORD export) #f) (KEYWORD module) module-name (OPT gparams #f) #\{ (K* pelt) #\} =>
       (lambda (src kwd-export? kwd module-name generic-param-list? lbrace pelt* rbrace)
         (with-output-language (Lparser Module-Definition)
           `(module ,src ,kwd-export? ,kwd ,module-name ,generic-param-list? ,lbrace ,pelt* ... ,rbrace)))])
    (Generic-parameter-list (gparams)
      [generic-param-list :: #\< (SEP* generic-param #\, #t) #\> =>
       (lambda (langle gparam-sep* rangle)
         (let-values ([(gparam* sep*) (split-sep gparam-sep*)])
           (with-output-language (Lparser Generic-Param-List)
             `(,langle (,gparam* ...) (,sep* ...) ,rangle))))])
    (Generic-parameter (generic-param)
      [generic-param-nat :: src #\# tvar-name =>
       (lambda (src hashmark tvar-name)
         (with-output-language (Lparser Generic-Param)
           `(nat-valued ,src ,hashmark ,tvar-name)))]
      [generic-param-type :: src tvar-name =>
       (lambda (src tvar-name)
         (with-output-language (Lparser Generic-Param)
           `(type-valued ,src ,tvar-name)))])
    (Import-declaration (idecl)
      [import-declaration :: src (KEYWORD import) (OPT import-selection #f) import-name (OPT gargs #f) (OPT import-prefix #f) #\; =>
       (lambda (src kwd import-selection? module-name generic-arg-list? prefix semicolon)
         (with-output-language (Lparser Import-Declaration)
           `(import ,src ,kwd ,import-selection? ,module-name ,generic-arg-list? ,prefix ,semicolon)))])
    (Import-selection (import-selection)
      [import-selection :: #\{ (SEP* import-element #\, #t) #\} (KEYWORD from) =>
       (lambda (lbrace ielt-sep* rbrace kwd-from)
         (let-values ([(ielt* sep*) (split-sep ielt-sep*)])
           (with-output-language (Lparser Import-Selection)
             `(,lbrace (,ielt* ...) (,sep* ...) ,rbrace ,kwd-from))))])
    (Import-element (import-element)
      [import-element-name :: src id =>
       (lambda (src name)
         (with-output-language (Lparser Import-Element)
           `(,src ,name)))]
      [import-element-rename :: src id (KEYWORD as) id =>
       (lambda (src name kwd-as name^)
         (with-output-language (Lparser Import-Element)
           `(,src ,name ,kwd-as ,name^)))])
    (Import-name (import-name)
      [import-name-id :: id => values]
      [import-name-file :: file => values])
    (Import-prefix (import-prefix)
      [import-prefix :: (KEYWORD prefix) id =>
       (lambda (kwd id)
         (with-output-language (Lparser Import-Prefix)
           `(,kwd ,id)))])
    (Generic-argument-list (gargs)
      [generic-args :: #\< (SEP* garg #\, #t) #\> =>
       (lambda (langle garg-sep* rangle)
         (let-values ([(garg* sep*) (split-sep garg-sep*)])
           (with-output-language (Lparser Generic-Arg-List)
             `(,langle (,garg* ...) (,sep* ...) ,rangle))))])
    (Generic-argument (garg)
      [generic-argument-size :: src nat =>
       (lambda (src nat)
         (with-output-language (Lparser Generic-Arg)
           `(generic-arg-size ,src ,nat)))]
      [generic-argument-type :: src type =>
       (lambda (src type)
         (with-output-language (Lparser Generic-Arg)
           `(generic-arg-type ,src ,type)))])
    (Export-declaration (xdecl)
      [export-declaration :: src (KEYWORD export) #\{ (SEP* id #\, #t) #\} (OPT #\; #f) =>
       (lambda (src kwd lbrace id-sep* rbrace semicolon?)
         (with-output-language (Lparser Export-Declaration)
           (let-values ([(id* sep*) (split-sep id-sep*)])
             `(export ,src ,kwd ,lbrace (,id* ...) (,sep* ...) ,rbrace ,semicolon?))))])
    (Ledger-declaration (ldecl)
      [public-ledger-declaration :: src (OPT (KEYWORD export) #f) (OPT (KEYWORD sealed) #f) (KEYWORD ledger) id #\: type #\; =>
       (lambda (src kwd-export? kwd-sealed? kwd id colon type semicolon)
         (with-output-language (Lparser Ledger-Declaration)
           `(public-ledger-declaration ,src ,kwd-export? ,kwd-sealed? ,kwd ,id ,colon ,type ,semicolon)))])
    (Constructor (lconstructor)
      [ledger-constructor :: src (KEYWORD constructor) pattern-parameter-list block =>
       (lambda (src kwd pattern-param-list blck)
         (with-output-language (Lparser Ledger-Constructor)
           `(constructor ,src ,kwd ,pattern-param-list ,blck)))])
    (Circuit-definition (cdefn)
      [circuit-definition :: src (OPT (KEYWORD export) #f) (OPT (KEYWORD pure) #f) (KEYWORD circuit) function-name (OPT gparams #f) pattern-parameter-list #\: type block =>
       (lambda (src kwd-export? kwd-pure? kwd function-name generic-param-list? pattern-param-list colon type block)
         (with-output-language (Lparser Circuit-Definition)
           `(circuit ,src ,kwd-export? ,kwd-pure? ,kwd ,function-name ,generic-param-list? ,pattern-param-list (,colon ,type) ,block)))])
    (External-declaration (edecl)
      [external-declaration :: src (OPT (KEYWORD export) #f) (KEYWORD circuit) id (OPT gparams #f) simple-parameter-list #\: type #\; =>
       (lambda (src kwd-export? kwd id generic-param-list? simple-param-list colon type semicolon)
         (with-output-language (Lparser External-Declaration)
           `(external ,src ,kwd-export? ,kwd ,id ,generic-param-list? ,simple-param-list (,colon ,type) ,semicolon)))])
    (Witness-declaration (wdecl)
      [witness-declaration :: src (OPT (KEYWORD export) #f) (KEYWORD witness) id (OPT gparams #f) simple-parameter-list #\: type #\; =>
       (lambda (src kwd-export? kwd id generic-param-list? simple-param-list colon type semicolon)
         (with-output-language (Lparser Witness-Declaration)
           `(witness ,src ,kwd-export? ,kwd ,id ,generic-param-list? ,simple-param-list (,colon ,type) ,semicolon)))])
    (External-contract-declaration (ecdecl)
      [contract-declaration/semicolons :: src (OPT (KEYWORD export) #f) (KEYWORD contract) contract-name #\{ (SEP* ecdecl-circuit #\; #t) #\} (OPT #\; #f) =>
       (lambda (src kwd-export? kwd contract-name lbrace ecdecl-circuit-sep* rbrace semicolon?)
         (with-output-language (Lparser External-Contract-Declaration)
           (let-values ([(ecdecl-circuit* sep*) (split-sep ecdecl-circuit-sep*)])
             `(external-contract ,src ,kwd-export? ,kwd ,contract-name ,lbrace (,ecdecl-circuit* ...) (,sep* ...) ,rbrace ,semicolon?))))]
      [contract-declaration/commas :: src (OPT (KEYWORD export) #f) (KEYWORD contract) contract-name #\{ (SEP* ecdecl-circuit #\, #t) #\} (OPT #\; #f) =>
       (lambda (src kwd-export? kwd contract-name lbrace ecdecl-circuit-sep* rbrace semicolon?)
         (with-output-language (Lparser External-Contract-Declaration)
           (let-values ([(ecdecl-circuit* sep*) (split-sep ecdecl-circuit-sep*)])
             `(external-contract ,src ,kwd-export? ,kwd ,contract-name ,lbrace (,ecdecl-circuit* ...) (,sep* ...) ,rbrace ,semicolon?))))])
    (External-contract-circuit (ecdecl-circuit)
      [external-contract-circuit :: src (OPT (KEYWORD pure) #f) (KEYWORD circuit) id simple-parameter-list #\: type =>
       (lambda (src kwd-pure? kwd id simple-param-list colon type)
         (with-output-language (Lparser External-Contract-Circuit)
           `(,src ,kwd-pure? ,kwd ,id ,simple-param-list (,colon ,type))))])
    (Structure-definition (struct)
      [structure-definition/semicolons :: src (OPT (KEYWORD export) #f) (KEYWORD struct) struct-name (OPT gparams #f) #\{ (SEP* typed-identifier #\; #t) #\} (OPT #\; #f) =>
       (lambda (src kwd-export? kwd struct-name generic-param-list? lbrace arg-sep* rbrace semicolon?)
         (with-output-language (Lparser Structure-Definition)
           (let-values ([(arg* sep*) (split-sep arg-sep*)])
             `(struct ,src ,kwd-export? ,kwd ,struct-name ,generic-param-list? ,lbrace (,arg* ...) (,sep* ...) ,rbrace ,semicolon?))))]
      [structure-definition/commas :: src (OPT (KEYWORD export) #f) (KEYWORD struct) struct-name (OPT gparams #f) #\{ (SEP* typed-identifier #\, #t) #\} (OPT #\; #f) =>
       (lambda (src kwd-export? kwd struct-name generic-param-list? lbrace arg-sep* rbrace semicolon?)
         (with-output-language (Lparser Structure-Definition)
           (let-values ([(arg* sep*) (split-sep arg-sep*)])
             `(struct ,src ,kwd-export? ,kwd ,struct-name ,generic-param-list? ,lbrace (,arg* ...) (,sep* ...) ,rbrace ,semicolon?))))])
    (Enum-definition (enumdef)
      [enum-definition :: src (OPT (KEYWORD export) #f) (KEYWORD enum) enum-name #\{ (SEP+ id #\, #t) #\} (OPT #\; #f) =>
       (lambda (src kwd-export? kwd enum-name lbrace elt-name-sep+ rbrace semicolon?)
         (assert (not (null? elt-name-sep+)))
         (with-output-language (Lparser Enum-Definition)
           (let-values ([(elt-name+ sep*) (split-sep elt-name-sep+)])
             `(enum ,src ,kwd-export? ,kwd ,enum-name ,lbrace (,(car elt-name+) ,(cdr elt-name+) ...) (,sep* ...) ,rbrace ,semicolon?))))])
    (Type-definition (tdefn)
      ; FIXME: consider eliminating struct syntax and supporting { x: type, ... } as a type
      [type-definition :: src (OPT (KEYWORD export) #f) (OPT (KEYWORD new) #f) (KEYWORD type) type-name (OPT gparams #f) #\= type #\; =>
       (lambda (src kwd-export? kwd-new? kwd type-name generic-param-list? op type semicolon)
         (with-output-language (Lparser Type-Definition)
           `(typedef ,src ,kwd-export? ,kwd-new? ,kwd ,type-name ,generic-param-list? ,op ,type ,semicolon)))])
    (Typed-identifier (typed-identifier)
      [typed-identifier :: src id #\: type =>
       (lambda (src id colon type)
         (with-output-language (Lparser Argument)
           `(,src ,id ,colon ,type)))])
    (Simple-parameter-list (simple-parameter-list)
      [parameter-list :: #\( (SEP* typed-identifier #\, #t) #\) =>
       (lambda (langle arg-sep* rangle)
         (let-values ([(arg* sep*) (split-sep arg-sep*)])
           (with-output-language (Lparser Argument-List)
             `(,langle (,arg* ...) (,sep* ...) ,rangle))))])
    (Typed-pattern (typed-pattern)
      [typed-pattern :: src pattern #\: type =>
       (lambda (src pattern colon type)
         (with-output-language (Lparser Pattern-Argument)
           `(,src ,pattern ,colon ,type)))])
    (Pattern-parameter-list (pattern-parameter-list)
      [pattern-parameter-list :: #\( (SEP* typed-pattern #\, #t) #\) =>
       (lambda (langle parg-sep* rangle)
         (let-values ([(parg* sep*) (split-sep parg-sep*)])
           (with-output-language (Lparser Pattern-Argument-List)
             `(,langle (,parg* ...) (,sep* ...) ,rangle))))])
    (Type (type)
      [type-ref :: tref => values]
      [type-boolean :: src (KEYWORD Boolean) =>
       (lambda (src kwd)
         (with-output-language (Lparser Type)
           `(tboolean ,src ,kwd)))]
      [type-field :: src (KEYWORD Field) =>
       (lambda (src kwd)
         (with-output-language (Lparser Type)
           `(tfield ,src ,kwd)))]
      [type-unsigned-integer-bits :: src (KEYWORD Uint) #\< tsize #\> =>
       (lambda (src kwd langle tsize rangle)
         (with-output-language (Lparser Type)
           `(tunsigned ,src ,kwd ,langle ,tsize ,rangle)))]
      [type-unsigned-integer-max :: src (KEYWORD Uint) #\< tsize ".." tsize #\> =>
       (lambda (src kwd langle tsize dotdot tsize^ rangle)
         (with-output-language (Lparser Type)
           `(tunsigned ,src ,kwd ,langle ,tsize ,dotdot ,tsize^ ,rangle)))]
      [type-bytes :: src (KEYWORD Bytes) #\< tsize #\> =>
       (lambda (src kwd langle tsize rangle)
         (with-output-language (Lparser Type)
           `(tbytes ,src ,kwd ,langle ,tsize ,rangle)))]
      [type-opaque :: src (KEYWORD Opaque) #\< str #\> =>
       (lambda (src kwd langle str rangle)
         (with-output-language (Lparser Type)
           `(topaque ,src ,kwd ,langle ,str ,rangle)))]
      [type-vector :: src (KEYWORD Vector) #\< tsize #\, type #\> =>
       (lambda (src kwd langle tsize comma type rangle)
         (with-output-language (Lparser Type)
           `(tvector ,src ,kwd ,langle ,tsize ,comma ,type ,rangle)))]
      [type-tuple :: src #\[ (SEP* type #\, #t) #\] =>
       (lambda (src lbracket type-sep* rbracket)
         (let-values ([(type* sep*) (split-sep type-sep*)])
           (with-output-language (Lparser Type)
             `(ttuple ,src ,lbracket (,type* ...) (,sep* ...) ,rbracket))))])
    (Type-reference (tref)
      [type-ref :: src id (OPT gargs #f) =>
       (lambda (src id generic-arg-list?)
         (with-output-language (Lparser Type)
           `(type-ref ,src ,id ,generic-arg-list?)))])
    (Type-size (tsize)
      [type-size-field :: src nat =>
       (lambda (src nat)
         (with-output-language (Lparser Type-Size)
           `(type-size ,src ,nat)))]
      [type-size-type-ref :: src id =>
       (lambda (src id)
         (with-output-language (Lparser Type-Size)
           `(type-size-ref ,src ,id)))])
    (Block (block)
      [block :: src #\{ (K* stmt) #\} =>
       (lambda (src lbrace stmt* rbrace)
         (with-output-language (Lparser Block)
           `(block ,src ,lbrace ,stmt* ... ,rbrace)))])
    (Statement (stmt)
      [statement-expr :: src expr-seq #\; =>
       (lambda (src expr semicolon)
         (with-output-language (Lparser Statement)
           `(statement-expression ,src ,expr ,semicolon)))]
      [statement-return-value :: src (KEYWORD return) expr-seq #\; =>
       (lambda (src kwd expr semicolon)
         (with-output-language (Lparser Statement)
           `(return ,src ,kwd ,expr ,semicolon)))]
      [statement-return-no-value :: src (KEYWORD return) #\; =>
       (lambda (src kwd semicolon)
         (with-output-language (Lparser Statement)
           `(return ,src ,kwd ,semicolon)))]
      ; see ez-grammar.ss left-factoring note related to the ordering of the "if" clauses
      [statement-if :: src (KEYWORD if) #\( expr-seq #\) stmt (KEYWORD else) stmt =>
       (lambda (src kwd lparen expr rparen stmt1 kwd-else stmt2)
         (with-output-language (Lparser Statement)
           `(if ,src ,kwd ,lparen ,expr ,rparen ,stmt1 ,kwd-else ,stmt2)))]
      [statement-one-armed-if :: src (KEYWORD if) #\( expr-seq #\) stmt =>
       (lambda (src kwd lparen expr rparen stmt)
         (with-output-language (Lparser Statement)
           `(if ,src ,kwd ,lparen ,expr ,rparen ,stmt)))]
      [statement-for1 :: src (KEYWORD for) #\( (KEYWORD const) id (KEYWORD of) nat ".." nat #\) stmt =>
       (lambda (src kwd lparen kwd-const id kwd-of start dotdot end rparen stmt)
         (with-output-language (Lparser Statement)
           `(for ,src ,kwd ,lparen ,kwd-const ,id ,kwd-of ,start ,dotdot ,end ,rparen ,stmt)))]
      [statement-for2 :: src (KEYWORD for) #\( (KEYWORD const) id (KEYWORD of) expr-seq #\) stmt =>
       (lambda (src kwd lparen kwd-const id kwd-of expr rparen stmt)
         (with-output-language (Lparser Statement)
           `(for ,src ,kwd ,lparen ,kwd-const ,id ,kwd-of ,expr ,rparen ,stmt)))]
      [statement-const :: src (KEYWORD const) (SEP+ cbinding #\, #f) #\; =>
       (lambda (src kwd cbinding-sep+ semicolon)
         (with-output-language (Lparser Statement)
           (let-values ([(cbinding+ sep*) (split-sep cbinding-sep+)])
             `(const ,src ,kwd (,(car cbinding+) ,(cdr cbinding+) ...) (,sep* ...) ,semicolon))))]
      [statement-block :: block =>
       (lambda (block) block)])
    (Pattern (pattern)
      [pattern-id :: id => values]
      [pattern-tuple :: src #\[ (SEP* (OPT pattern #f) #\, #t) #\] =>
       (lambda (src lbracket pattern?-sep* rbracket)
         (let-values ([(pattern?* sep*) (split-sep pattern?-sep*)])
           (with-output-language (Lparser Pattern)
             `(tuple ,src ,lbracket (,pattern?* ...) (,sep* ...) ,rbracket))))]
      [pattern-struct :: src #\{ (SEP* pattern-struct-elt #\, #t) #\} =>
       (lambda (src lbrace pattern-struct-elt-sep* rbrace)
         (let-values ([(pattern-struct-elt* sep*) (split-sep pattern-struct-elt-sep*)])
           (with-output-language (Lparser Pattern)
             `(struct ,src ,lbrace (,pattern-struct-elt* ...) (,sep* ...) ,rbrace))))])
    (Pattern-tuple-element (pattern-tuple-elt)
      [pattern-tuple-elt-nada :: => (lambda () #f)]
      [pattern-tuple-elt-pattern :: pattern => values])
    (Pattern-struct-element (pattern-struct-elt)
      [pattern-struct-elt-id :: id => values]
      [pattern-struct-elt-pattern :: id #\: pattern =>
       (lambda (id colon pattern)
         (with-output-language (Lparser Pattern-Struct-Elt)
           `(,id ,colon ,pattern)))])
    (Expression-sequence (expr-seq)
      [expr-seq-one :: expr => values]
      [expr-seq-many :: src (SEP+ expr #\,) #\, expr =>
       (lambda (src expr-sep+ comma expr)
         (let-values ([(expr+ sep*) (split-sep expr-sep+)])
           (with-output-language (Lparser Expression)
             `(seq ,src (,expr+ ...) (,sep* ... ,comma) ,expr))))])
    (Expression (expr)
      ["conditional expression" :: src expr0 #\? expr #\: expr =>
       (lambda (src e0 hook e1 colon e2)
         (with-output-language (Lparser Expression)
           `(if ,src ,e0 ,hook ,e1 ,colon ,e2)))]
      ["assignment expression" :: src expr0 #\= expr =>
       (lambda (src expr1 op-assign expr2)
         (with-output-language (Lparser Expression)
           `(= ,src ,expr1 ,op-assign ,expr2)))]
      ["increment expression" :: src expr0 "+=" expr =>
       (lambda (src expr1 op-incr expr2)
         (with-output-language (Lparser Expression)
           `(+= ,src ,expr1 ,op-incr ,expr2)))]
      ["decrement expression" :: src expr0 "-=" expr =>
       (lambda (src expr1 op-decr expr2)
         (with-output-language (Lparser Expression)
           `(-= ,src ,expr1 ,op-decr ,expr2)))]
      [#f :: expr0 => values])
    (Expression0 (expr0)
      ["|| expression" :: src expr0 "||" expr1 => make-binop]
      [#f :: expr1 => values])
    (Expression1 (expr1)
      ["&& expression" :: src expr1 "&&" expr2 => make-binop]
      [#f :: expr2 => values])
    (Expression2 (expr2)
      ["== expression" :: src expr2 "==" expr3 => make-binop]
      ["!= expression" :: src expr2 "!=" expr3 => make-binop]
      [#f :: expr3 => values])
    (Expression3 (expr3)
      ["< expression" :: src expr4 #\< expr4 => make-binop]
      ["<= expression" :: src expr4 "<=" expr4 => make-binop]
      [">= expression" :: src expr4 ">=" expr4 => make-binop]
      ["> expression" :: src expr4 #\> expr4 => make-binop]
      [#f :: expr4 => values])
    (Expression4 (expr4)
      [expression1-cast :: src expr4 (KEYWORD as) type =>
       (lambda (src e kwd type)
         (with-output-language (Lparser Expression)
           `(cast ,src ,type ,kwd ,e)))]
      [#f :: expr5 => values])
    (Expression5 (expr5)
      ["addition expression" :: src expr5 #\+ expr6 => make-binop]
      ["subtraction expression" :: src expr5 #\- expr6 => make-binop]
      [#f :: expr6 => values])
    (Expression6 (expr6)
      ["multiplication expression" :: src expr6 #\* expr7 => make-binop]
      [#f :: expr7 => values])
    (Expression7 (expr7)
      ["not expression" :: src #\! expr7 =>
       (lambda (src bang e)
         (with-output-language (Lparser Expression)
           `(not ,src ,bang ,e)))]
      [#f :: expr8 => values])
    (Expression8 (expr8)
      ["tuple/vector reference" :: src expr8 #\[ expr #\] =>
       (lambda (src e lbracket index rbracket)
         (with-output-language (Lparser Expression)
           `(tuple-ref ,src ,e ,lbracket ,index ,rbracket)))]
      ["element reference" :: src expr8 #\. id =>
       (lambda (src e dot id)
         (with-output-language (Lparser Expression)
           `(elt-ref ,src ,e ,dot ,id)))]
      ["element call" :: src expr8 #\. id #\( (SEP* expr #\, #t) #\) =>
       (lambda (src e dot id lparen expr-sep* rparen)
         (let-values ([(expr* sep*) (split-sep expr-sep*)])
           (with-output-language (Lparser Expression)
             `(elt-call ,src ,e ,dot ,id ,lparen (,expr* ...) (,sep* ...) ,rparen))))]
      [#f :: expr9 => values])
    (Expression9 (expr9)
      [term-call :: src fun #\( (SEP* expr #\, #t) #\) =>
       (lambda (src fun lparen expr-sep* rparen)
         (let-values ([(expr* sep*) (split-sep expr-sep*)])
           (with-output-language (Lparser Expression)
             `(call ,src ,fun ,lparen (,expr* ...) (,sep* ...) ,rparen))))]
      [term-map :: src (KEYWORD map) #\( fun #\, (SEP+ expr #\, #t) #\) =>
       (lambda (src kwd lparen fun comma expr-sep+ rparen)
         (let-values ([(expr+ sep*) (split-sep expr-sep+)])
           (with-output-language (Lparser Expression)
             `(map ,src ,kwd ,lparen ,fun ,comma (,(car expr+) ,(cdr expr+) ...) (,sep* ...) ,rparen))))]
      [term-fold :: src (KEYWORD fold) #\( fun #\, expr #\, (SEP+ expr #\, #t) #\) =>
       (lambda (src kwd lparen fun comma1 expr comma2 expr-sep+ rparen)
         (let-values ([(expr+ sep*) (split-sep expr-sep+)])
           (with-output-language (Lparser Expression)
             `(fold ,src ,kwd ,lparen ,fun ,comma1 (,expr ,(car expr+) ,(cdr expr+) ...) (,comma2 ,sep* ...) ,rparen))))]
      [term-slice :: src (KEYWORD slice) #\< tsize #\> #\( expr #\, expr #\) =>
       (lambda (src kwd langle tsize rangle lparen expr comma index rparen)
         (with-output-language (Lparser Expression)
           `(tuple-slice ,src ,kwd ,langle ,tsize ,rangle ,lparen ,expr ,comma ,index ,rparen)))]
      [term-tuple :: src #\[ (SEP* tuple-arg #\, #t) #\] =>
       (lambda (src lbracket tuple-arg-sep* rbracket)
         (let-values ([(tuple-arg* sep*) (split-sep tuple-arg-sep*)])
           (with-output-language (Lparser Expression)
             `(tuple ,src ,lbracket (,tuple-arg* ...) (,sep* ...) ,rbracket))))]
      [term-bytes :: src (KEYWORD Bytes) #\[ (SEP* bytes-arg #\, #t) #\] =>
       (lambda (src kwd lbracket bytes-arg-sep* rbracket)
         (let-values ([(bytes-arg* sep*) (split-sep bytes-arg-sep*)])
           (with-output-language (Lparser Expression)
             `(bytes ,src ,kwd ,lbracket (,bytes-arg* ...) (,sep* ...) ,rbracket))))]
      [term-struct :: src tref #\{ (SEP* struct-arg #\, #t) #\} =>
       (lambda (src tref lbrace new-field-sep* rbrace)
         (let-values ([(new-field* sep*) (split-sep new-field-sep*)])
           (with-output-language (Lparser Expression)
             `(new ,src ,tref ,lbrace (,new-field* ...) (,sep* ...) ,rbrace))))]
      [term-assert :: src (KEYWORD assert) #\( expr #\, str #\) =>
       (lambda (src kwd lparen e comma str rparen)
         (with-output-language (Lparser Expression)
           `(assert ,src ,kwd ,lparen ,e ,comma ,str ,rparen)))]
      [term-disclose :: src (KEYWORD disclose) #\( expr #\) =>
       (lambda (src kwd lparen expr rparen)
         (with-output-language (Lparser Expression)
           `(disclose ,src ,kwd ,lparen ,expr ,rparen)))]
      [#f :: term => values])
    (Term (term)
      [term-ref :: src id =>
       (lambda (src id)
         (with-output-language (Lparser Expression)
          `(var-ref ,src ,id)))]
      [term-true :: src (KEYWORD true) =>
       (lambda (src kwd)
         (with-output-language (Lparser Expression)
           `(true ,src ,kwd)))]
      [term-false :: src (KEYWORD false) =>
       (lambda (src kwd)
         (with-output-language (Lparser Expression)
           `(false ,src ,kwd)))]
      [term-element-field :: src nat =>
       (lambda (src nat)
         (with-output-language (Lparser Expression)
           `(field ,src ,nat)))]
      [term-element-string :: src str =>
       (lambda (src str)
         (with-output-language (Lparser Expression)
           `(string ,src ,str)))]
      [term-element-padded-string :: src (KEYWORD pad) #\( nat #\, str #\) =>
       (lambda (src kwd lparen nat comma str rparen)
         (with-output-language (Lparser Expression)
           `(pad ,src ,kwd ,lparen ,nat ,comma ,str ,rparen)))]
      [term-element-default :: src (KEYWORD default) #\< type #\> =>
       (lambda (src kwd langle type rangle)
         (with-output-language (Lparser Expression)
           `(default ,src ,kwd ,langle ,type ,rangle)))]
      [term-parenthesized :: src #\( expr-seq #\) =>
       (lambda (src lparen expr rparen)
         (with-output-language (Lparser Expression)
           `(parenthesized ,src ,lparen ,expr ,rparen)))])
    (Tuple-argument (tuple-arg bytes-arg)
      [tuple-arg-expression :: src expr =>
       (lambda (src expr)
         (with-output-language (Lparser Tuple-Argument)
           `(single ,src ,expr)))]
      [tuple-arg-spread :: src "..." expr =>
       (lambda (src dotdotdot expr)
         (with-output-language (Lparser Tuple-Argument)
           `(spread ,src ,dotdotdot ,expr)))])
    (Structure-argument (struct-arg)
      [struct-arg-positional :: src expr =>
       (lambda (src expr)
         (with-output-language (Lparser New-Field)
           `(positional ,src ,expr)))]
      [struct-arg-named :: src id #\: expr =>
       (lambda (src elt-name colon expr)
         (with-output-language (Lparser New-Field)
           `(named ,src ,elt-name ,colon ,expr)))]
      [struct-arg-spread :: src "..." expr =>
       (lambda (src dotdotdot expr)
         (with-output-language (Lparser New-Field)
           `(spread ,src ,dotdotdot ,expr)))])
    (Function (fun)
      [function-ref :: src id (OPT gargs #f) =>
       (lambda (src id generic-arg-list?)
         (with-output-language (Lparser Function)
           `(fref ,src ,id ,generic-arg-list?)))]
      ; NB. Compact doesn't currently have expressions that begin with curly braces
      ; (struct allocation begins with the struct type) so there should be no ambiguity
      ; between the two forms of arrow expressions (block vs expr)
      [function-arrow-block :: src arrow-parameter-list (OPT return-type #f) "=>" block =>
       (lambda (src pattern-param-list return-type? arrow blck)
         (with-output-language (Lparser Function)
           `(arrow-block ,src ,pattern-param-list ,return-type? ,arrow ,blck)))]
      [function-arrow-expr :: src arrow-parameter-list (OPT return-type #f) "=>" expr =>
       (lambda (src pattern-param-list return-type? arrow expr)
         (with-output-language (Lparser Function)
           `(arrow-expr ,src ,pattern-param-list ,return-type? ,arrow ,expr)))]
      [parenthesized-function :: src #\( fun #\) =>
       (lambda (src lparen fun rparen)
         (with-output-language (Lparser Function)
           `(parenthesized ,src ,lparen ,fun ,rparen)))])
    (Return-type (return-type)
      [return-type-decl :: #\: type =>
       (lambda (colon type)
         (with-output-language (Lparser Return-Type)
           `(,colon ,type)))])
    (Optionally-typed-pattern (optionally-typed-pattern)
      [untyped-pattern :: src pattern =>
       (lambda (src pattern)
         (with-output-language (Lparser Pattern-Argument)
           `(,src ,pattern)))]
      [typed-pattern :: typed-pattern => values])
    (Const-Binding (cbinding)
      [const-binding :: src optionally-typed-pattern #\= expr =>
       (lambda (src optionally-typed-pattern op-assign expr)
         (with-output-language (Lparser Const-Binding)
           `(,src ,optionally-typed-pattern ,op-assign ,expr)))])
    (Arrow-parameter-list (arrow-parameter-list)
      [arrow-parameter-list :: #\( (SEP* optionally-typed-pattern #\, #t) #\) =>
       (lambda (langle parg-sep* rangle)
         (let-values ([(parg* sep*) (split-sep parg-sep*)])
           (with-output-language (Lparser Pattern-Argument-List)
             `(,langle (,parg* ...) (,sep* ...) ,rangle))))])
  )

  (define (parse token-stream)
    ;;; return the first result, if any, for which the input stream was entirely consumed.
    (Compact token-stream
      (lambda (res+)
        (let ([res (stream-car res+)])
          (assert (parse-consumed-all? res))
          (parse-result-value res)))
      (lambda (last-token failure*)
        (define (remove-dups failure+)
          (fold-right
            (lambda (x failure*)
              (if (member x failure*)
                  failure*
                  (cons x failure*)))
            '()
            failure+))
        (define (format-input-token token)
          (if (eq? (token-type token) 'eof)
              "end of file"
              (format "~s" (token-string token))))
        (define (format-failure failure)
          (define (format-nonterminal-name nt)
            (format "~a ~a"
              (if (memq (string-ref (symbol->string nt) 0)
                        '(#\a #\e #\i #\o #\u #\A #\E #\I #\O #\U))
                  "an"
                  "a")
              (let* ([s (symbol->string nt)] [n (string-length s)])
                (let ([s^ (make-string n)])
                  (do ([i 0 (fx+ i 1)])
                    ((fx= i n))
                    (let ([c (string-ref s i)])
                      (string-set! s^ i (if (char=? c #\-) #\space (char-downcase c)))))
                  s^))))
          (if (pair? failure)
              (format-nonterminal-name (car failure))
              failure))
        (source-errorf (token-src last-token) "parse error: found ~a looking for~?"
          (format-input-token last-token)
          "~#[ nothing~; ~a~; ~a or ~a~:;~@{~#[~; or~] ~a~^,~}~]"
          (map format-failure
               (remove-dups
                 (if (and (= (length failure*) 1)
                          (pair? (car failure*))
                          (eq? (caar failure*) 'Compact))
                     (cdar failure*)
                     failure*)))))))

  (define (parse-file/token-stream fn)
    (register-source-pathname! fn)
    (let* ([ip (guard (c [else (error-accessing-file c "opening source file")])
                 (when (file-directory? fn)
                   (raise
                     (condition
                       (make-assertion-violation)
                       (make-format-condition)
                       (make-message-condition "~a is a directory")
                       (make-irritants-condition (list fn)))))
                 (open-file-input-port fn))]
           [sfd (guard (c [else (error-accessing-file c "reading source file")])
                  (make-source-file-descriptor fn ip #t))]
           [ip (guard (c [else (error-accessing-file c "reading source file")])
                 (transcoded-port ip compact-input-transcoder))]
           [file-content (guard (c [else (error-accessing-file c "reading source file")])
                           (get-string-all ip))]
           [file-content (if (eof-object? file-content) "" file-content)]
           [waste (guard (c [else (error-accessing-file c "closing source file")])
                    (close-input-port ip))]
           [token-stream (lexer sfd file-content)])
      (values
        token-stream
        (parameterize ([parse-sfd sfd])
          (parse (stream-filter
                   token-stream
                   (lambda (token)
                     (not (memq (token-type token)
                                '(whitespace line-comment block-comment))))))))))

  (define (parse-file fn)
    (let-values ([(token-stream ir) (parse-file/token-stream fn)])
      (Lparser->Lsrc ir)))

  (define-passes parser-passes
    (parse-file        Lsrc))
)
