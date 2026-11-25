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

;;; guard-enum-inputs asserts the validity of every enum value that enters a circuit
;;; from outside, i.e., as an argument of an exported circuit or the constructor, as
;;; the result of a witness or contract call, or from deserialize.  It knows where
;;; values enter but not what makes one valid: variant-valid is expanded by lower-enums.

(define-pass guard-enum-inputs : Lnodisclose (ir) -> Lguarded ()
  (definitions
    (define exported-ht (make-eq-hashtable))
    ; maps the name of each witness to its (Lguarded) arguments and return type
    (define witness-ht (make-eq-hashtable))
    (define (witness-result-message function-name)
      (format "the result of witness ~a" (id-sym function-name)))
    (define (de-alias type)
      (nanopass-case (Lguarded Type) type
        [(talias ,src ,nominal? ,type-name ,type) (de-alias type)]
        [else type]))
    (define (contains-enum? type)
      (nanopass-case (Lguarded Type) type
        [(tsum ,src ,enum-name ,ledger-layout? (,elt-name* ,type** ...) ...) #t]
        [(tstruct ,src ,struct-name (,elt-name* ,type*) ...) (ormap contains-enum? type*)]
        [(ttuple ,src ,type* ...) (ormap contains-enum? type*)]
        [(tvector ,src ,len ,type) (contains-enum? type)]
        [(talias ,src ,nominal? ,type-name ,type) (contains-enum? type)]
        [else #f]))
    (define (guard-arguments src arg* expr what)
      (with-output-language (Lguarded Expression)
        (let ([guard* (fold-right
                        (lambda (arg guard*)
                          (nanopass-case (Lguarded Argument) arg
                            [(,var-name ,type)
                             (if (contains-enum? type)
                                 (cons `(variant-valid ,src ,type (var-ref ,src ,var-name)
                                          ,(format "argument ~a of ~a contains an invalid enum value"
                                                   (id-sym var-name)
                                                   what))
                                       guard*)
                                 guard*)]))
                        '()
                        arg*)])
          (if (null? guard*)
              expr
              `(seq ,src ,guard* ... ,expr)))))
    (define (guard-result src type expr what)
      (if (contains-enum? type)
          (with-output-language (Lguarded Expression)
            (let ([t (make-temp-id src 't)])
              `(let* ,src ([(,t ,type) ,expr])
                 (seq ,src
                   (variant-valid ,src ,type (var-ref ,src ,t)
                     ,(format "~a contains an invalid enum value" what))
                   (var-ref ,src ,t)))))
          expr))
    )
  (Program : Program (ir) -> Program ()
    [(program ,src (,[contract-type*] ...) ((,struct-name* ,[type*]) ...) ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each (lambda (name) (eq-hashtable-set! exported-ht name #t)) name*)
     (for-each Record-Witness! pelt*)
     `(program ,src (,contract-type* ...) ((,struct-name* ,type*) ...) ((,export-name* ,name*) ...)
        ,(map Program-Element pelt*) ...)])
  (Record-Witness! : Program-Element (ir) -> * (void)
    [(witness ,src ,function-name (,[arg*] ...) ,[type])
     (eq-hashtable-set! witness-ht function-name (cons arg* type))]
    [(native ,src ,function-name ,native-entry (,[arg*] ...) ,[type])
     (when (eq? (native-entry-class native-entry) 'witness)
       (eq-hashtable-set! witness-ht function-name (cons arg* type)))]
    [else (void)])
  (Program-Element : Program-Element (ir) -> Program-Element ())
  (Circuit-Definition : Circuit-Definition (ir) -> Circuit-Definition ()
    [(circuit ,src ,function-name (,[arg*] ...) ,[type] ,[expr])
     `(circuit ,src ,function-name (,arg* ...) ,type
        ,(if (eq-hashtable-ref exported-ht function-name #f)
             (guard-arguments src arg* expr (format "circuit ~a" (id-sym function-name)))
             expr))])
  (Ledger-Constructor : Ledger-Constructor (ir) -> Ledger-Constructor ()
    [(constructor ,src (,[arg*] ...) ,[expr])
     `(constructor ,src (,arg* ...) ,(guard-arguments src arg* expr "the constructor"))])
  (Type : Type (ir) -> Type ())
  (Argument : Argument (ir) -> Argument ())
  (Function : Function (ir) -> Function ()
    ; a witness given to map or fold is called without a call form, so it is replaced by
    ; a circuit that makes the call and guards its result
    [(fref ,src ,function-name)
     (let ([a (eq-hashtable-ref witness-ht function-name #f)])
       (if (and a (contains-enum? (cdr a)))
           (let ([var-name* (map (lambda (arg)
                                   (nanopass-case (Lguarded Argument) arg
                                     [(,var-name ,type) (make-temp-id src (id-sym var-name))]))
                                 (car a))]
                 [type* (map (lambda (arg)
                               (nanopass-case (Lguarded Argument) arg
                                 [(,var-name ,type) type]))
                             (car a))])
             `(circuit ,src ((,var-name* ,type*) ...) ,(cdr a)
                ,(guard-result src (cdr a)
                   (with-output-language (Lguarded Expression)
                     `(call ,src ,function-name ,(map (lambda (var-name) `(var-ref ,src ,var-name)) var-name*) ...))
                   (witness-result-message function-name))))
           `(fref ,src ,function-name)))])
  (Expression : Expression (ir) -> Expression ()
    [(call ,src ,function-name ,[expr*] ...)
     (let ([expr `(call ,src ,function-name ,expr* ...)])
       (cond
         [(eq-hashtable-ref witness-ht function-name #f) =>
          (lambda (a) (guard-result src (cdr a) expr (witness-result-message function-name)))]
         [else expr]))]
    [(contract-call ,src ,elt-name (,[expr] ,[type]) ,[expr*] ...)
     (guard-result src
       (nanopass-case (Lguarded Type) (de-alias type)
         [(tcontract ,src^ ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
          (cond
            [(assq elt-name (map cons elt-name* type*)) => cdr]
            [else (assert cannot-happen)])]
         [else (assert cannot-happen)])
       `(contract-call ,src ,elt-name (,expr ,type) ,expr* ...)
       (format "the result of contract circuit ~a" elt-name))]
    [(deserialize ,src ,len ,[type] ,[expr])
     (guard-result src type `(deserialize ,src ,len ,type ,expr) "the deserialized value")]))
