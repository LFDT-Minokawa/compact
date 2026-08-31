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

(define-pass expand-place-params : Lnoandornot (ir) -> Lnoplace ()
  ; This pass eliminates place references: &T in a type position and &e in an
  ; expression position.
  ;
  ; A place reference denotes a location in the ledger rather than a value.  Its
  ; static component -- which ledger field, and which accessors are applied to it --
  ; is a compile-time thing, resolved by monomorphization; its dynamic component is
  ; the tuple of Map keys along the access path, which is ordinary circuit data.  So
  ; a circuit parameter of type &T becomes a *generic* parameter plus an ordinary
  ; value parameter, and an argument &p becomes the matching pair of arguments:
  ;
  ;   circuit credit(acct: &Counter): [] { acct.increment(1); }
  ;   credit(&alice);
  ;
  ; becomes
  ;
  ;   circuit credit<place-valued acct>(): [] { acct.increment(1); }
  ;   credit<targ-place alice>();
  ;
  ; Note what does *not* happen: the body is not rewritten.  The parameter simply
  ; changes kind, keeping its name, and generic parameters and ordinary variables
  ; share one environment in expand-modules-and-types.  So `acct` in the body is
  ; bound to the caller's Info-ledger and resolves through the existing var-ref rule,
  ; which already turns an Info-ledger into a ledger-ref.
  ;
  ; The rewrite has to happen here rather than in expand-modules-and-types because it
  ; changes a circuit's signature: process-frob builds each specialized program
  ; element by running the transformer over the *raw* program element, whose parameter
  ; list is fixed.  expand-patterns is the precedent for a front-end pass that
  ; rewrites parameter lists.
  ;
  ; The pass is purely syntactic and cannot be otherwise: at this stage the compiler
  ; does not yet know whether the root of a place expression names a ledger field.
  ; ledger-ref does not exist until expand-modules-and-types resolves an identifier
  ; bound to Info-ledger.  That is fine -- & is syntactically marked, so the pass
  ; rewrites whatever appears under it and leaves validity to Type-Argument->info,
  ; which reports anything that turns out not to name a ledger field.
  ;
  ; Every diagnostic about & has to be produced here or in Type-Argument->info, in the
  ; user's own terms: after this pass the form no longer exists, so anything reported
  ; later would be phrased in terms of a desugared shape the user never wrote.
  (definitions
    ; ---------------------------------------------------------------------------
    ; Classifying rejections
    ;
    ; A user must be able to tell a restriction that will lift from one that never
    ; will, so every rejection carries its *reason*, not just its position.  See the
    ; table in place-references-impl-plan.md B4.  The four reasons:
    ;
    ;   no-runtime-rep    The position holds a runtime value and a place is not one *in
    ;                     this design*.  A place here is a compile-time coordinate (which
    ;                     field, which accessors) plus a key tuple, carried as a generic
    ;                     argument, so monomorphization erases the coordinate and nothing
    ;                     encodes it at runtime.
    ;
    ;                     Read the qualifier: this is a consequence of representing a
    ;                     place as a *type* argument, not a fact about places or about
    ;                     the ledger.  A representation in which a place is a value --
    ;                     a tag indexing the program's finite set of coordinate
    ;                     skeletons, paired with the keys -- would make these positions
    ;                     legal, at the cost of an n-way dispatch at every use.  §16
    ;                     works that through.  So the message must not promise the
    ;                     restriction is permanent, only that it is not a half-built
    ;                     feature waiting on more work in this design.
    ;
    ;   typescript        The other side of the boundary is TypeScript, so there is no
    ;                     call site in Compact at which to monomorphize.  Same reason
    ;                     expand-serialize.ss:205 refuses ADTs.
    ;
    ;   separate-contract The callee is a separately deployed contract.  Note that
    ;                     External-Contract-Circuit is a signature with no body field
    ;                     in every intermediate language: a returned place is computed
    ;                     from the callee's body, and here there is no body, in this
    ;                     compilation or any other.
    ;
    ;   not-yet           Coherent under this design, simply not built.  This covers
    ;                     compound types in a circuit signature -- [&Counter, Field],
    ;                     Vector<3, &Counter>, a struct field.  Those are *not*
    ;                     impossible: the place positions are statically known, so
    ;                     each could be hoisted to its own generic parameter exactly
    ;                     as a bare parameter is today.  What they additionally need
    ;                     is a rule that every projection out of the compound lands at
    ;                     a statically known position -- v[i] for runtime i would have
    ;                     to select a coordinate at runtime, which is the heap model
    ;                     again.  A struct also needs its own uses confined, since a
    ;                     struct holding a place can no longer reach the ledger or the
    ;                     TypeScript boundary.  None of that is designed yet, so the
    ;                     honest message is "not yet", not "never".
    ;
    ; place-context carries the (reason . position) in force for the type currently
    ; being traversed.  Every transformer that introduces a type position sets it; the
    ; default is deliberately the temporary reason, so a position this pass forgot to
    ; classify is under- rather than over-claimed.
    (define place-context (make-parameter (cons 'not-yet "this position")))

    (define (reject-place! src reason position)
      (case reason
        [(no-runtime-rep)
         (source-errorf src
           "a place reference (&T) may not appear in ~a: a place is a compile-time \
            coordinate, and this design gives it no runtime representation, so it can \
            be neither stored nor serialized"
           position)]
        [(typescript)
         (source-errorf src
           "a place reference (&T) may not appear in ~a: the caller is TypeScript, \
            which has no way to name a place in the ledger"
           position)]
        [(separate-contract)
         (source-errorf src
           "a place reference (&T) may not appear in ~a: the callee is a separately \
            deployed contract, so there is no body from which to resolve the place"
           position)]
        [(not-yet)
         (source-errorf src "a place reference (&T) is not yet supported in ~a" position)]
        [else
         (internal-errorf 'expand-place-params "unclassified place rejection ~s" reason)]))

    ; Run thunk with a type-position classification in force.
    (define (with-place-context reason position thunk)
      (parameterize ([place-context (cons reason position)]) (thunk)))

    ; The place parameters of the circuit whose body is being traversed.  A place
    ; expression rooted at one of these FORWARDS that place rather than starting a fresh
    ; one -- see section 13 of place-references-impl-plan.md.
    ;
    ; The test is on the name alone, and Compact permits a local to shadow a parameter,
    ; so at a shadowed use site this guesses "forward" wrongly.  That does not need
    ; fixing, because the guess is OUTCOME-EQUIVALENT rather than merely safe:
    ;
    ;   - guessing "fresh" wrongly cannot happen: place-param* IS the parameter list, so
    ;     a genuine place parameter is never missed;
    ;   - guessing "forward" wrongly changes only the keys expression, and at such a site
    ;     Type-Argument->info rejects the ROOT -- it resolves to the shadowing Info-var --
    ;     which depends on the binding in scope and not on which keys were emitted.  The
    ;     keys are well formed either way and are discarded with the failed resolution.
    ;
    ; So both guesses produce the same diagnostic from the same place, and tracking let*,
    ; block and for binders here would buy nothing.  test.ss pins this down: search for
    ; "A local shadowing a place parameter".
    (define place-param* '())

    (define (place-type? type)
      (nanopass-case (Lnoandornot Type) type
        [(tplace ,src ,type) #t]
        [else #f]))

    ; the T of a &T, which rides along on tkeys so that infer-types can check it against
    ; the store the access path actually reaches
    (define (place-inner-type type)
      (nanopass-case (Lnoandornot Type) type
        [(tplace ,src ,type) type]
        [else (internal-errorf 'expand-place-params "not a place type ~s" type)]))

    ; The name of the value parameter carrying a place parameter's keys.  Derived
    ; from the place parameter's own name so that expand-modules-and-types can find it
    ; again when it resolves a reference to the place: see the Info-place case there,
    ; which must derive the same name.
    (define (keys-parameter-name var-name)
      (string->symbol (string-append "__compact_place_keys_" (symbol->string var-name))))

    ; A place expression is a ledger field name followed by accessor calls.  Returns
    ; the field's source, its name, the accessor names root-to-leaf, and the key
    ; expressions in the same order.
    (define (parse-place src expr)
      (let loop ([expr expr] [elt-name* '()] [key* '()])
        (nanopass-case (Lnoandornot Expression) expr
          [(var-ref ,src^ ,var-name) (values src^ var-name elt-name* key*)]
          [(elt-call ,src^ ,expr^ ,elt-name ,expr^* ...)
           (unless (fx= (length expr^*) 1)
             (source-errorf src^
               "an accessor in a place reference must take exactly one key argument, \
                but ~s takes ~d"
               elt-name (length expr^*)))
           (loop expr^ (cons elt-name elt-name*) (cons (car expr^*) key*))]
          [else
           (source-errorf src
             "the operand of & must name a ledger field, optionally followed by \
              accessor calls")])))

    ; &p becomes a generic argument naming the place, plus an ordinary argument
    ; carrying its keys as a tuple.  The tuple is empty for a top-level field.
    (define (place->arguments src expr)
      (let-values ([(src^ var-name elt-name* key*) (parse-place src expr)])
        (values
          (with-output-language (Lnoplace Type-Argument)
            `(targ-place ,src^ ,var-name (,elt-name* ...)))
          (let* ([single* (map (lambda (key)
                                 (with-output-language (Lnoplace Tuple-Argument)
                                   `(single ,src ,(Expression key))))
                               key*)]
                 ; a forwarded place's keys are the caller's keys followed by any new
                 ; ones; a fresh place's are just the ones written here
                 [tuple-arg*
                  (if (memq var-name place-param*)
                      (cons (with-output-language (Lnoplace Tuple-Argument)
                              `(spread ,src^
                                 ,(with-output-language (Lnoplace Expression)
                                    `(var-ref ,src^ ,(keys-parameter-name var-name)))))
                            single*)
                      single*)])
            (with-output-language (Lnoplace Expression)
              `(tuple ,src ,tuple-arg* ...))))))

    ; Split a call's arguments into the place references, which become generic
    ; arguments plus key tuples, and everything else, which stays where it is.
    (define (split-place-arguments expr*)
      (let loop ([expr* expr*] [rtarg* '()] [rexpr* '()])
        (if (null? expr*)
            (values (reverse rtarg*) (reverse rexpr*))
            (nanopass-case (Lnoandornot Expression) (car expr*)
              [(place-ref ,src ,expr)
               (let-values ([(targ keys) (place->arguments src expr)])
                 (loop (cdr expr*) (cons targ rtarg*) (cons keys rexpr*)))]
              [else
               (loop (cdr expr*) rtarg* (cons (Expression (car expr*)) rexpr*))]))))

    ; call-src is the source of the enclosing call, used only to report a place
    ; argument passed to something other than a named circuit
    (define (add-generic-arguments call-src fun targ*)
      (if (null? targ*)
          (Function fun)
          (nanopass-case (Lnoandornot Function) fun
            [(fref ,src ,function-name)
             (with-output-language (Lnoplace Function)
               `(fref ,src ,function-name (,targ* ...)))]
            [(fref ,src ,function-name (,targ^* ...))
             (let ([targ^* (map Type-Argument targ^*)])
               (with-output-language (Lnoplace Function)
                 `(fref ,src ,function-name (,(append targ^* targ*) ...))))]
            [else
             (source-errorf call-src
               "a place reference may be passed only to a named circuit")]))))

  (Type-Param : Type-Param (ir) -> Type-Param ())
  (Type-Argument : Type-Argument (ir) -> Type-Argument ())
  (Argument : Argument (ir) -> Argument ())
  (Function : Function (ir) -> Function ())

  ; The single point at which a surviving &T is rejected.  Everything that introduces
  ; a type position classifies it first, so the message names the real reason.
  (Type : Type (ir) -> Type ()
    [(tplace ,src ,type)
     (let ([c (place-context)])
       (reject-place! src (car c) (cdr c)))])

  ; --- positions that hold runtime values, which a place is not in this design -----

  (Ledger-Declaration : Ledger-Declaration (ir) -> Ledger-Declaration ()
    [(public-ledger-declaration ,src ,exported? ,sealed? ,ledger-field-name ,type)
     `(public-ledger-declaration ,src ,exported? ,sealed? ,ledger-field-name
        ,(with-place-context 'no-runtime-rep "a ledger field's type"
           (lambda () (Type type))))])

  ; --- positions where the other side is TypeScript -------------------------------

  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,arg* ...) ,expr)
     (let ([arg* (with-place-context 'typescript "the ledger constructor's parameter list"
                   (lambda () (map Argument arg*)))])
       `(constructor ,src (,arg* ...) ,(Expression expr)))])

  (Witness-Declaration : Witness-Declaration (ir) -> Witness-Declaration ()
    [(witness ,src ,exported? ,function-name (,type-param* ...) (,arg* ...) ,type)
     (with-place-context 'typescript "a witness signature"
       (lambda ()
         (let ([type-param* (map Type-Param type-param*)]
               [arg* (map Argument arg*)])
           `(witness ,src ,exported? ,function-name
                     (,type-param* ...) (,arg* ...) ,(Type type)))))])

  ; --- positions where the callee is a separately deployed contract ---------------

  (External-Contract-Circuit : External-Contract-Circuit (ir) -> External-Contract-Circuit ()
    [(,src ,pure-dcl ,function-name (,arg* ...) ,type)
     (with-place-context 'separate-contract "a contract circuit's signature"
       (lambda ()
         (let ([arg* (map Argument arg*)])
           `(,src ,pure-dcl ,function-name (,arg* ...) ,(Type type)))))])

  (Contract-Implements-Declaration : Contract-Implements-Declaration (ir) -> Contract-Implements-Declaration ()
    [(contract-implements ,src ,type)
     `(contract-implements ,src
        ,(with-place-context 'separate-contract "a contract-implements declaration"
           (lambda () (Type type))))])

  ; --- positions that are coherent but not built ----------------------------------

  (Structure-Definition : Structure-Definition (ir) -> Structure-Definition ()
    [(struct ,src ,exported? ,struct-name (,type-param* ...) ,arg* ...)
     (with-place-context 'not-yet "a struct field's type"
       (lambda ()
         (let ([type-param* (map Type-Param type-param*)]
               [arg* (map Argument arg*)])
           `(struct ,src ,exported? ,struct-name (,type-param* ...) ,arg* ...))))])

  (Type-Definition : Type-Definition (ir) -> Type-Definition ()
    [(typedef ,src ,exported? ,nominal? ,type-name (,type-param* ...) ,type)
     (let ([type-param* (map Type-Param type-param*)])
       `(typedef ,src ,exported? ,nominal? ,type-name (,type-param* ...)
          ,(with-place-context 'not-yet "a type alias"
             (lambda () (Type type)))))])

  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,exported? ,pure-dcl? ,function-name (,type-param* ...) (,arg* ...) ,type ,expr)
     ; An exported circuit's whole signature faces TypeScript, so a place anywhere in
     ; it is permanently out.  An internal circuit's is merely not built yet: a bare
     ; &T return needs the returned store inferred from the body, and a nested one
     ; needs the compound-type rule described above.
     (let ([reason (if exported? 'typescript 'not-yet)]
           [what (if exported? "an exported circuit" "a circuit")])
       (let ([return-position (string-append what "'s return type")]
             [param-position (string-append what "'s parameter list")])
         (when (place-type? type) (reject-place! src reason return-position))
         (let loop ([arg* arg*] [rtype-param* '()] [rarg* '()] [rplace* '()])
           (if (null? arg*)
               (let ([type-param* (append (map Type-Param type-param*) (reverse rtype-param*))]
                     [arg* (reverse rarg*)])
                 `(circuit ,src ,exported? ,pure-dcl? ,function-name
                           (,type-param* ...) (,arg* ...)
                           ,(with-place-context reason return-position
                              (lambda () (Type type)))
                           ,(fluid-let ([place-param* (reverse rplace*)])
                              (Expression expr))))
               (nanopass-case (Lnoandornot Argument) (car arg*)
                 [(,src^ ,var-name ,type^)
                  (if (place-type? type^)
                      (begin
                        (when exported? (reject-place! src^ 'typescript param-position))
                        ; the place becomes a generic parameter, keeping its name so
                        ; that references to it in the body need no rewriting, plus an
                        ; ordinary parameter carrying its keys
                        (loop (cdr arg*)
                              (cons (with-output-language (Lnoplace Type-Param)
                                      `(place-valued ,src^ ,var-name))
                                    rtype-param*)
                              (cons (with-output-language (Lnoplace Argument)
                                      `(,src^ ,(keys-parameter-name var-name)
                                              (tkeys ,src^ ,var-name
                                                ,(with-place-context reason param-position
                                                   (lambda ()
                                                     (Type (place-inner-type type^)))))))
                                    rarg*)
                              (cons var-name rplace*)))
                      (loop (cdr arg*) rtype-param*
                            (cons (with-place-context reason param-position
                                    (lambda () (Argument (car arg*))))
                                  rarg*)
                            rplace*))])))))])

  (Expression : Expression (ir) -> Expression ()
    ; a place reference anywhere other than a call argument, handled below
    [(place-ref ,src ,expr)
     (source-errorf src
       "a place reference (&e) may appear only as an argument of a circuit call")]
    [(default ,src ,type)
     `(default ,src ,(with-place-context 'no-runtime-rep "the type argument of default"
                       (lambda () (Type type))))]
    [(cast ,src ,type ,[expr])
     `(cast ,src ,(with-place-context 'no-runtime-rep "the target type of a cast"
                    (lambda () (Type type)))
            ,expr)]
    [(call ,src ,fun ,expr* ...)
     (let-values ([(targ* expr^*) (split-place-arguments expr*)])
       (let ([fun^ (add-generic-arguments src fun targ*)])
         `(call ,src ,fun^ ,expr^* ...)))]))
