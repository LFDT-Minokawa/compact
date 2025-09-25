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

(library (lparser-to-lsrc)
  (export Lparser->Lsrc)
  (import (except (chezscheme) errorf)
          (utils)
          (nanopass)
          (langs)
          (lparser))

  (define-pass Lparser->Lsrc : Lparser (ir) -> Lsrc ()
    (Program : Program (ir) -> Program ()
      [(program ,src ,pelt* ... ,eof)
       (let ([pelt* (map Program-Element (remp Lparser-Pragma? pelt*))])
         `(program ,src ,pelt* ...))])
    (Program-Element : Program-Element (ir) -> Program-Element ())
    (Include : Include (ir) -> Include ()
      [(include ,src ,kwd ,file ,semicolon)
       `(include ,src ,(token-value file))])
    (Module-Definition : Module-Definition (ir) -> Module-Definition ()
      [(module ,src ,kwd-export? ,kwd ,module-name ,generic-param-list? ,lbrace ,pelt* ... ,rbrace)
       (let ([type-param* (if generic-param-list? (Generic-Param-List generic-param-list?) '())]
             [pelt* (map Program-Element (remp Lparser-Pragma? pelt*))])
         `(module ,src ,(and kwd-export? #t) ,(token-value module-name) (,type-param* ...) ,pelt* ...))])
    (Import-Declaration : Import-Declaration (ir) -> Import-Declaration ()
      [(import ,src ,kwd ,[import-name] ,generic-arg-list? ,import-prefix? ,semicolon)
       (let ([targ* (if generic-arg-list? (Generic-Arg-List generic-arg-list?) '())]
             [prefix (if import-prefix? (Import-Prefix import-prefix?) "")])
         `(import ,src ,import-name (,targ* ...) ,prefix))])
    (Import-Name : Import-Name (ir) -> Import-Name ()
      [,module-name (token-value module-name)]
      [,file (token-value file)])
    (Import-Prefix : Import-Prefix (ir) -> * (prefix)
      [(,kwd-prefix ,prefix) (symbol->string (token-value prefix))])
    (Export-Declaration : Export-Declaration (ir) -> Export-Declaration ()
      [(export ,src ,kwd ,lbrace (,name* ...) (,sep* ...) ,rbrace ,semicolon)
       `(export ,src (,(map token-src name*) ,(map token-value name*)) ...)])
    (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
      [(public-ledger-declaration ,src ,kwd-export? ,kwd-sealed? ,kwd ,ledger-field-name ,colon ,[type] ,semicolon)
       `(public-ledger-declaration ,src ,(and kwd-export? #t) ,(and kwd-sealed? #t) ,(token-value ledger-field-name) ,type)])
    (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
      [(constructor ,src ,kwd ,parg-list ,[stmt])
       (let ([parg* (Pattern-Argument-List parg-list)])
         `(constructor ,src (,parg* ...) ,stmt))])
    (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
      [(circuit ,src ,kwd-export? ,kwd-pure? ,kwd ,function-name ,generic-param-list? ,parg-list ,[type] ,[stmt])
       (let ([type-param* (if generic-param-list? (Generic-Param-List generic-param-list?) '())]
             [parg* (Pattern-Argument-List parg-list)])
         `(circuit ,src ,(and kwd-export? #t) ,(and kwd-pure? #t) ,(token-value function-name) (,type-param* ...) (,parg* ...) ,type ,stmt))])
    (External-Declaration : External-Declaration (ir) -> External-Declaration ()
      [(external ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,[type] ,semicolon)
       (let ([type-param* (if generic-param-list? (Generic-Param-List generic-param-list?) '())]
             [arg* (Argument-List arg-list)])
         `(external ,src ,(and kwd-export? #t) ,(token-value function-name) (,type-param* ...) (,arg* ...) ,type))])
    (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
      [(witness ,src ,kwd-export? ,kwd ,function-name ,generic-param-list? ,arg-list ,[type] ,semicolon)
       (let ([type-param* (if generic-param-list? (Generic-Param-List generic-param-list?) '())]
             [arg* (Argument-List arg-list)])
         `(witness ,src ,(and kwd-export? #t) ,(token-value function-name) (,type-param* ...) (,arg* ...) ,type))])
    (External-Contract-Declaration : External-Contract-Declaration (ir) -> External-Contract-Declaration ()
      [(external-contract ,src ,kwd-export? ,kwd ,contract-name ,lbrace (,[ecdecl-circuit*] ...) (,sep* ...) ,rbrace ,semicolon?)
       `(external-contract ,src ,(and kwd-export? #t) ,(token-value contract-name) ,ecdecl-circuit* ...)])
    (External-Contract-Circuit : External-Contract-Circuit (ir) -> External-Contract-Circuit ()
      [(,src ,kwd-pure? ,kwd ,function-name ,arg-list ,[type])
       (let ([arg* (Argument-List arg-list)])
         `(,src ,(and kwd-pure? #t) ,(token-value function-name) (,arg* ...) ,type))])
    (Structure-Definition : Structure-Definition (ir) -> Structure-Definition ()
      [(struct ,src ,kwd-export? ,kwd ,struct-name ,generic-param-list? ,lbrace (,[arg*] ...) (,sep* ...) ,rbrace ,semicolon?)
       (let ([type-param* (if generic-param-list? (Generic-Param-List generic-param-list?) '())])
         `(struct ,src ,(and kwd-export? #t) ,(token-value struct-name) (,type-param* ...) ,arg* ...))])
    (Enum-Definition : Enum-Definition (ir) -> Enum-Definition ()
      [(enum ,src ,kwd-export? ,kwd ,enum-name ,lbrace (,elt-name ,elt-name* ...) (,sep* ...) ,rbrace ,semicolon?)
       `(enum ,src ,(and kwd-export? #t) ,(token-value enum-name) ,(token-value elt-name) ,(map token-value elt-name*) ...)])
    (Return-Type : Return-Type (ir) -> Type ()
      [(,colon ,[type]) type])
    (Generic-Param-List : Generic-Param-List (ir) -> * (type-param*)
      [(,langle (,[type-param*] ...) (,sep* ...) ,rangle) type-param*])
    (Type-Param : Generic-Param (ir) -> Type-Param ()
      [(nat-valued ,src ,hashmark ,tvar-name) `(nat-valued ,src ,(token-value tvar-name))]
      [(type-valued ,src ,tvar-name) `(type-valued ,src ,(token-value tvar-name))])
    (Generic-Arg-List : Generic-Arg-List (ir) -> * (targ*)
      [(,langle (,[targ*] ...) (,sep* ...) ,rangle) targ*])
    (Argument-List : Argument-List (ir) -> * (arg*)
      [(,lparen (,[arg*] ...) (,sep* ...) ,rparen) arg*])
    (Argument : Argument (ir) -> Argument ()
      [(,src ,var-name ,colon ,[type])
       `(,src ,(token-value var-name) ,type)])
    (Const-Binding : Const-Binding (ir) -> Const-Binding ()
      [(,src ,[parg] ,op ,[expr])
       (nanopass-case (Lsrc Pattern-Argument) parg
         [(,src^ ,pattern ,type)
          `(,src ,pattern ,type ,expr)])])
    (Pattern-Argument-List : Pattern-Argument-List (ir) -> * (parg*)
      [(,lparen (,[parg*] ...) (,sep* ...) ,rparen) parg*])
    (Pattern-Argument : Pattern-Argument (ir) -> Pattern-Argument ()
      [(,src ,[pattern]) `(,src ,pattern (tundeclared))]
      [(,src ,[pattern] ,colon ,[type]) `(,src ,pattern ,type)])
    (Pattern : Pattern (ir) -> Pattern ()
      [,var-name (token-value var-name)]
      [(tuple ,src ,lbracket (,pattern?* ...) (,comma* ...) ,rbracket)
       (let ([pattern?* (map (lambda (pattern?) (and pattern? (Pattern pattern?))) pattern?*)])
         `(tuple ,src ,pattern?* ...))]
      [(struct ,src ,lbrace (,[* pattern* elt-name*] ...) (,comma* ...) ,rbrace)
       `(struct ,src (,pattern* ,elt-name*) ...)])
    (Pattern-Struct-Elt : Pattern-Struct-Elt (ir) -> * (pattern elt-name)
      [,elt-name (let ([elt-name (token-value elt-name)]) (values elt-name elt-name))]
      [(,elt-name ,colon ,[pattern]) (values pattern (token-value elt-name))])
    (Statement : Statement (ir) -> Statement ()
      [(statement-expression ,src ,[expr] ,semicolon)
       `(statement-expression ,src ,expr)]
      [(return ,src ,kwd ,semicolon)
       `(return ,src (tuple ,src))]
      [(return ,src ,kwd ,[expr] ,semicolon)
       `(return ,src ,expr)]
      [(const ,src ,kwd (,[cbinding] ,[cbinding*] ...) (,comma* ...) ,semicolon)
       `(const ,src ,cbinding ,cbinding* ...)]
      [(if ,src ,kwd ,lparen ,[expr] ,rparen ,[stmt1] ,kwd-else ,[stmt2])
       `(if ,src ,expr ,stmt1 ,stmt2)]
      [(if ,src ,kwd ,lparen ,[expr] ,rparen ,[stmt])
       `(if ,src ,expr ,stmt (statement-expression ,src (tuple ,src)))]
      [(for ,src ,kwd ,lparen ,kwd-const ,var-name ,kwd-of ,start ,dotdot ,end ,rparen ,[stmt])
       (let ([start (token-value start)] [end (token-value end)])
         (define for-limit 1000)
         (when (< end start)
           (source-errorf src "end bound ~d is less than start bound ~s" end start))
         (let ([n (- end start)])
           (when (> n for-limit)
             (source-errorf src "difference ~s between end and start bounds is greater than the arbitrary compiler limit of ~s; use 'for ... in' syntax instead" (- end start) for-limit))
           `(for ,src ,(token-value var-name)
              (tuple ,src ,(map (lambda (i) `(single ,src (quote ,src ,(fx+ start i)))) (iota n)) ...)
              ,stmt)))]
      [(for ,src ,kwd ,lparen ,kwd-const ,var-name ,kwd-of ,[expr] ,rparen ,[stmt])
       `(for ,src ,(token-value var-name) ,expr ,stmt)]
      [(block ,src ,lbrace ,[stmt*] ... ,rbrace)
       `(block ,src ,stmt* ...)])
    (Expression : Expression (ir) -> Expression ()
      [(true ,src ,kwd) `(quote ,src #t)]
      [(false ,src ,kwd) `(quote ,src #f)]
      [(field ,src ,nat) `(quote ,src ,(token-value nat))]
      [(string ,src ,str) `(quote ,src ,(string->utf8 (token-value str)))]
      [(pad ,src ,kwd ,lparen ,nat ,comma ,str ,rparen)
       `(quote
          ,src
          ,(let* ([nat (token-value nat)]
                  [str (token-value str)]
                  [bv (string->utf8 str)]
                  [n (bytevector-length bv)])
             (cond
               [(= n nat) bv]
               [(< n nat)
                (let ([bv^ (make-bytevector nat 0)])
                  (bytevector-copy! bv 0 bv^ 0 n)
                  bv^)]
               [else (source-errorf src "cannot pad ~s to length ~s since it's utf8-equivalent already exceeds that length"
                                    str nat)])))]
      [(var-ref ,src ,var-name)
       `(var-ref ,src ,(token-value var-name))]
      [(default ,src ,kwd ,langle ,[type] ,rangle)
       `(default ,src ,type)]
      [(if ,src ,[expr0] ,hook ,[expr1] ,colon ,[expr2])
       `(if ,src ,expr0 ,expr1 ,expr2)]
      [(elt-ref ,src ,[expr] ,dot ,elt-name)
       `(elt-ref ,(token-src dot) ,expr ,(token-value elt-name))]
      [(elt-call ,src ,[expr] ,dot ,elt-name ,lparen (,[expr*] ...) (,comma* ...) ,rparen)
       `(elt-call ,(token-src dot) ,expr ,(token-value elt-name) ,expr* ...)]
      [(= ,src ,[expr1] ,op ,[expr2])
       `(= ,(token-src op) ,expr1 ,expr2)]
      [(+= ,src ,[expr1] ,op ,[expr2])
       `(+= ,(token-src op) ,expr1 ,expr2)]
      [(-= ,src ,[expr1] ,op ,[expr2])
       `(-= ,(token-src op) ,expr1 ,expr2)]
      [(binop ,src ,[expr1] ,op ,[expr2])
       (case (token-value op)
         [(#\+) `(+ ,src ,expr1 ,expr2)]
         [(#\-) `(- ,src ,expr1 ,expr2)]
         [(#\*) `(* ,src ,expr1 ,expr2)]
         [("||") `(or ,src ,expr1 ,expr2)]
         [("&&") `(and ,src ,expr1 ,expr2)]
         [(#\<) `(< ,src ,expr1 ,expr2)]
         [("<=") `(<= ,src ,expr1 ,expr2)]
         [(#\>) `(> ,src ,expr1 ,expr2)]
         [(">=") `(>= ,src ,expr1 ,expr2)]
         [("==") `(== ,src ,expr1 ,expr2)]
         [("!=") `(!= ,src ,expr1 ,expr2)]
         [else (internal-errorf 'binop "unexpected op ~s" op)])]
      [(tuple ,src ,lbracket (,[tuple-arg*] ...) (,comma* ...) ,rbracket)
       `(tuple ,src ,tuple-arg* ...)]
      [(bytes ,src ,kwd ,lbracket (,[bytes-arg*] ...) (,comma* ...) ,rbracket)
       `(bytes ,src ,bytes-arg* ...)]
      [(tuple-ref ,src ,[expr] ,lbracket ,[index] ,rbracket)
       `(tuple-ref ,src ,expr ,index)]
      [(tuple-slice ,src ,kwd ,langle ,[tsize] ,rangle ,lparen ,[expr] ,comma ,[index] ,rparen)
       `(tuple-slice ,src ,expr ,index ,tsize)]
      [(not ,src ,bang ,[expr])
       `(not ,src ,expr)]
      [(map ,src ,kwd ,lparen ,[fun] ,comma (,[expr] ,[expr*] ...) (,comma* ...) ,rparen)
       `(map ,src ,fun ,expr ,expr* ...)]
      [(fold ,src ,kwd ,lparen ,[fun] ,comma (,[expr0] ,[expr] ,[expr*] ...) (,comma* ...) ,rparen)
       `(fold ,src ,fun ,expr0 ,expr ,expr* ...)]
      [(call ,src ,[fun] ,lparen (,[expr*] ...) (,comma* ...) ,rparen)
       `(call ,src ,fun ,expr* ...)]
      [(new ,src ,[tref] ,lbrace (,[new-field*] ...) (,comma* ...) ,rbrace)
       `(new ,src ,tref ,new-field* ...)]
      [(seq ,src (,[expr*] ...) (,comma* ...) ,[expr])
       `(seq ,src ,expr* ... ,expr)]
      [(cast ,src ,[type] ,kwd ,[expr])
       `(cast ,src ,type ,expr)]
      [(parenthesized ,src ,lparen ,[expr] ,rparen) expr]
      [(disclose ,src ,kwd ,lparen ,[expr] ,rparen)
       `(disclose ,src ,expr)]
      [(assert ,src ,kwd ,lparen ,[expr] ,comma ,mesg ,rparen)
       `(assert ,src ,expr ,(token-value mesg))])
    (Function : Function (ir) -> Function ()
      (definitions
        (define (do-arrow src parg-list return-type? stmt)
          (let ([parg* (Pattern-Argument-List parg-list)]
                [type (if return-type?
                          (Return-Type return-type?)
                          (with-output-language (Lsrc Type)
                            `(tundeclared)))])
            (with-output-language (Lsrc Function)
              `(circuit ,src (,parg* ...) ,type ,stmt)))))
      [(fref ,src ,function-name ,generic-arg-list?)
       (if generic-arg-list?
           (let ([targ* (Generic-Arg-List generic-arg-list?)])
             `(fref ,src ,(token-value function-name) (,targ* ...)))
           `(fref ,src ,(token-value function-name)))]
      [(arrow-stmt ,src ,parg-list ,return-type? ,arrow ,[stmt])
       (do-arrow src parg-list return-type? stmt)]
      [(arrow-expr ,src ,parg-list ,return-type? ,arrow ,[expr])
       (do-arrow src parg-list return-type?
         (with-output-language (Lsrc Statement)
           `(return ,src ,expr)))]
      [(parenthesized ,src ,lparen ,[fun] ,rparen) fun])
    (Tuple-Argument : Tuple-Argument (ir) -> Tuple-Argument ()
      [(single ,src ,[expr])
       `(single ,src ,expr)]
      [(spread ,src ,dotdotdot ,[expr])
       `(spread ,src ,expr)])
    (New-Field : New-Field (ir) -> New-Field ()
      [(spread ,src ,dotdotdot ,[expr])
       `(spread ,src ,expr)]
      [(positional ,src ,[expr])
       `(positional ,src ,expr)]
      [(named ,src ,elt-name ,colon ,[expr])
       `(named ,src ,(token-value elt-name) ,expr)])
    (Type : Type (ir) -> Type ()
      [,tref (Type-Ref tref)]
      [(tboolean ,src ,kwd) `(tboolean ,src)]
      [(tfield ,src ,kwd) `(tfield ,src)]
      [(tunsigned ,src ,kwd ,langle ,[tsize] ,rangle)
       `(tunsigned ,src ,tsize)]
      [(tunsigned ,src ,kwd ,langle ,[tsize] ,dotdot ,[tsize^] ,rangle)
       `(tunsigned ,src ,tsize ,tsize^)]
      [(tbytes ,src ,kwd ,langle ,[tsize] ,rangle)
       `(tbytes ,src ,tsize)]
      [(topaque ,src ,kwd ,langle ,opaque-type ,rangle)
       `(topaque ,src ,(token-value opaque-type))]
      [(tvector ,src ,kwd ,langle ,[tsize] ,comma ,[type] ,rangle)
       `(tvector ,src ,tsize ,type)]
      [(ttuple ,src ,lbracket (,[type*] ...) (,comma* ...) ,rbracket)
       `(ttuple ,src ,type* ...)])
    (Type-Ref : Type-Ref (ir) -> Type-Ref ()
      [(type-ref ,src ,tvar-name ,generic-arg-list?)
       (let ([targ* (if generic-arg-list? (Generic-Arg-List generic-arg-list?) '())])
         `(type-ref ,src ,(token-value tvar-name) ,targ* ...))])
    (Type-Size : Type-Size (ir) -> Type-Size ()
      [(type-size ,src ,nat) `(type-size ,src ,(token-value nat))]
      [(type-size-ref ,src ,tsize-name) `(type-size-ref ,src ,(token-value tsize-name))])
    (Type-Argument : Generic-Arg (ir) -> Type-Argument ()
      [(generic-arg-size ,src ,nat) `(targ-size ,src ,(token-value nat))]
      [(generic-arg-type ,src ,[type]) `(targ-type ,src ,type)])
  )
)
