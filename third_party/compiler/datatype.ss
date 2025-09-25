;;; Copyright 2009 R. Kent Dybvig
;;;
;;; Licensed under the Apache License, Version 2.0 (the "License");
;;; you may not use this file except in compliance with the License.
;;; You may obtain a copy of the License at
;;;
;;;     http://www.apache.org/licenses/LICENSE-2.0
;;;
;;; Unless required by applicable law or agreed to in writing, software
;;; distributed under the License is distributed on an "AS IS" BASIS,
;;; WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
;;; See the License for the specific language governing permissions and
;;; limitations under the License.

;;; datatype.ss
;;; (datatype) library

#|

Description
-----------

A define-datatype form creates a new datatype with zero or more variants,
each with its own set of fields.  It produces definitions for a predicate,
constructors, and a case form.

Syntax:

  <datatype definition> -> (define-datatype <datatype name> <variant>*)

  <datatype name> -> identifier

  <variant> -> (<variant name> <field name>*)
  <variant name> -> identifier
  <field name> -> identifier

Products:
  The definition

    (define-datatype dtname (vname vfield ...))

  produces the following set of variable definitions:

    dtname?       a predicate true only of datatype instances
    variant ...   a set of constructors for the different variants
    dtname-case   a case construct for the datatype

  Each constructor accepts one argument for each field of the variant.
  The case construct has the following syntax:

    (dtname-case <expression> <clause> ...)

  where each <clause> is of the form:

    [(<variant name> <field name>*) <expression>+]

  except that the last must be an else clause of the form

    [else <expression>+]

  if any of the datatype's variants are not represented in the set of
  clauses.  The clauses may appear in any order and the field names
  need not be the same as those given in the datatype definition.
  (They are instead specified positionally.)
  
Example:

  (import (datatype))

  (define-datatype AST
    (Const datum)
    (Ref var)
    (If tst thn els)
    (Fun fmls body)
    (Call exp0 args))

  (define (parse x)
    (cond
      [(symbol? x) (Ref x)]
      [(pair? x)
       (case (car x)
         [(if) (If (parse (cadr x)) (parse (caddr x)) (parse (cadddr x)))]
         [(fun) (Fun (cadr x) (parse (caddr x)))]
         [else (Call (parse (car x)) (map parse (cdr x)))])]
      [else (Const x)]))
    
  (define (ev x r)
    (AST-case x
      [(Ref v) (cdr (assq v r))]
      [(Const x) x]
      [(If tst thn els) (ev (if (ev tst r) thn els) r)]
      [(Fun fmls body)
       (lambda args
         (ev body (append (map cons fmls args) r)))]
      [(Call proc actuals)
        (apply (ev proc r) (map (lambda (x) (ev x r)) actuals))]))
  
  (AST? (parse #'(fun (x) x)))

  (parse #'(fun (x) x)) ;=> (Const #<syntax (fun (x) x)>)

  (define (run x) (ev (parse x) `((- . ,-) (* . ,*) (= . ,=))))

  (run '((fun (f) (f f 10))
         (fun (f x)
           (if (= x 0)
               1
               (* x (f f (- x 1))))))) ;=> 3628800

|#

;; This could be in the file datatype-aux.chezscheme.sls
#;(library (datatype-aux)
  (export datatype-reader/writer when-safe)
  (import (chezscheme))

  (define-syntax datatype-reader/writer
    (syntax-rules ()
      [(_ record-name constructor-number constructor accessor ...)
       (module ()
         (record-reader 'constructor (record-type-descriptor record-name))
         (record-writer (record-type-descriptor record-name)
           (lambda (x p wr)
             (wr `(constructor ,@(map (lambda (a) (a x)) (list accessor ...))) p))
           #;(lambda (x p wr)
             (display "#[" p)
             (wr 'constructor p)
             (display " " p)
             (wr constructor-number p)
             (begin
               (display " " p)
               (wr (accessor x) p))
             ...
             (display "]" p))))]))

  (define-syntax when-safe
    (lambda (x)
      (syntax-case x ()
        [(_ e ...)
         (if (fx= (optimize-level) 3)
             #'(void)
             #'(begin e ...))])))
)

;; (datatype-aux) for systems other than Chez Scheme
;; This could be in the file datatype-aux.sls
#;(library (datatype-aux)
  (export datatype-reader/writer when-safe)
  (import (rnrs))

  (define-syntax datatype-reader/writer
    (syntax-rules ()
      [(_ record-name constructor-number constructor accessor ...)
       (begin)]))

  (define-syntax when-safe
    (syntax-rules ()
      [(_ e ...) (begin e ...)]))
)

(library
  (datatype)
  (export define-datatype)
  (import (rnrs) (datatype-aux))

;; TODO: why is "datatype" defined?
;;       (define-record-type (foo make-foo foo?))
;;       foo -> invalid syntax
;; TODO: record printer (don't print variant-number)
;; TODO: require some kind of with-datatype form to import constructors

(define-syntax define-datatype
  (lambda (x)
    ;; construct-name :: identifier * (string or identifier) ... -> identifier
    ;; builds args into a new identifier with the marks from template-identifier
    (define construct-name
      (lambda (template-identifier . args)
        (datum->syntax
          template-identifier
          (string->symbol
            (apply string-append
                   (map (lambda (x)
                          (cond
                            [(string? x) x]
                            [(symbol? x) (symbol->string x)]
                            [(identifier? x)
                             (symbol->string (syntax->datum x))]))
                        args))))))
    (define iota
      (case-lambda
        [(n) (iota 0 n)]
        [(i n) (if (= n 0) '() (cons i (iota (+ i 1) (- n 1))))]))
    (syntax-case x ()
      [(_ datatype (constructor fieldspec ...) ...)
       (and (identifier? #'datatype) (for-all identifier? #'(constructor ...)))
       (with-syntax ([(((field pred) ...) ...)
                      (map (lambda (x*)
                             (map (lambda (x)
                                    (syntax-case x ()
                                      [(field pred) x]
                                      [field (identifier? #'field) #'(field (lambda (x) #t))]))
                                  x*))
                           #'((fieldspec ...) ...))])
         (with-syntax
           ;; NOTE: only "datatype?" "datatype-case" and "constructor" are
           ;; visible outside
             ([datatype? (construct-name #'datatype #'datatype "?")]
              [datatype-case (construct-name #'datatype #'datatype "-case")]
              ;; internally used to access fields
              [((constructor-field ...) ...)
               (map (lambda (constructor fields)
                      (map (lambda (field)
                             (construct-name #'private constructor "-" field))
                           fields))
                    #'(constructor ...)
                    #'((field ...) ...))]
              [(constructor-number ...) (iota (length #'(constructor ...)))]
              [(variant-record-name ...)
               (map (lambda (x) (construct-name #'private x))
                    #'(constructor ...))]
              [(variant-record-predicate ...)
               (map (lambda (x) (construct-name #'private x "?"))
                    #'(constructor ...))])
           #'(begin
               ;; make-datatype and datatype-variant are introduced
               ;; vars and thus private
               (define-record-type (datatype make-datatype datatype?)
                 (fields (immutable variant datatype-variant))
                 (nongenerative))
               ;; TODO: (first) constructor is an introduced var and thus private
               ;; TODO: or should it be?
               ;; TODO: constructor-field is introduced and thus private
               (define-record-type (variant-record-name constructor variant-record-predicate)
                 (parent datatype)
                 (sealed #t)
                 (nongenerative)
                 (protocol
                  (lambda (parent)
                    (lambda (field ...)
                      (define who 'constructor)
                      (when-safe
                        (unless (pred field)
                          (assertion-violation who
                            (string-append "invalid value for " (symbol->string 'field))
                            field))
                        ...)
                      ((parent constructor-number) field ...))))
                 (fields (immutable field constructor-field) ...))
               ...
               (datatype-reader/writer variant-record-name constructor-number constructor constructor-field ...)
               ...
               (define-syntax datatype-case
                 (lambda (x)
                   ;; TODO: does this have an Andy/Kanren problem?
                   (define make-clause
                     (lambda (x)
                       (syntax-case x (constructor ...)
                         [(constructor (field ...) expr0 expr* (... ...))
                          #'[(constructor-number)
                             (let ([field (constructor-field tmp)] ...)
                               #f ;; force non-definition context (TODO: needed?)
                               expr0 expr* (... ...))]]
                         ...)))

                   (define make-clauses
                     (lambda (x)
                       (syntax-case x ()
                         [() #'()]
                         [(clause0 . clause*)
                          (with-syntax ([clause0 (make-clause #'clause0)]
                                        [clause* (make-clauses #'clause*)])
                            #'(clause0 . clause*))])))

                   ;; syntax of identifier * syntax of list of identifier -> bool
                   ;; returns true if x is free-identifier=? to any of xs
                   (define syntax-member
                     (lambda (x xs)
                       (syntax-case xs ()
                         [() #f]
                         [(y . ys) (or (free-identifier=? x #'y)
                                       (syntax-member x #'ys))])))

                   (syntax-case x (else)
                     [(_ test-expr
                         ;; must avoid capture by 'constructor' and 'field'
                         [(constr fld (... ...)) expr0 expr* (... ...)]
                         (... ...)
                         [else else-expr0 else-expr* (... ...)])
                      (with-syntax
                          ([(clauses (... ...))
                            (make-clauses
                             #'((constr (fld (... ...)) expr0 expr* (... ...))
                                (... ...)))])
                        #'(let ([tmp test-expr])
                            (case (datatype-variant tmp)
                              clauses (... ...)
                              [else else-expr0 else-expr* (... ...)])))]

                     [(_ test-expr
                         ;; must avoid capture by 'constructor' and 'field'
                         [(constr fld (... ...)) expr0 expr* (... ...)]
                         (... ...))

                      (for-all
                       (lambda (expect)
                         (or (syntax-member expect #'(constr (... ...)))
                             (syntax-violation
                              'datatype-case (string-append "unhandled variant " (symbol->string (syntax->datum expect))) x)))
                       (list #'constructor ...))

                      (with-syntax
                          ([(clauses (... ...))
                            (make-clauses
                             #'((constr (fld (... ...)) expr0 expr* (... ...))
                                (... ...)))])
                        #'(let ([tmp test-expr])
                            (case (datatype-variant tmp)
                              clauses (... ...))))]

                     ))))))]))))
