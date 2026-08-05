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

;; Desugar cross-contract `contract-call`s into explicit transientCommit +
;; kernel.claimContractCall operations:
;;
;; A statement
;;   (= test (V* ...) (contract-call ... ((recv* ...) tcontract) triv* ...))
;; becomes three statements:
;;   (= test (V* ... cc-rand ep-mod ep-div) (contract-call ... tcontract'))
;;     -- tcontract' extends the callee's return type by cc-rand : Field and
;;        the two circuit name limbs ep-mod : Field<2^8>, ep-div : Field<2^248>
;;   (= test (comm) (call <transientCommit> triv* ... V* ... cc-rand))
;;     -- the communication commitment;
;;   (= test () (public-ledger ... claimContractCall recv* ... ep-mod ep-div comm)).
(define-pass desugar-contract-calls : Lflattened (ir) -> Lflattened ()
  (definitions
    (define synth-natives '())
    (define kernel-ledger-field-name #f)
    (define kernel-claim-adt-op #f)
    (define (type-aligns ty)
      (nanopass-case (Lflattened Type) ty
        [(ty (,alignment* ...) (,primitive-type* ...)) alignment*]))
    (define (type-prims ty)
      (nanopass-case (Lflattened Type) ty
        [(ty (,alignment* ...) (,primitive-type* ...)) primitive-type*]))
    ;; Record the kernel's ledger field-name and its claimContractCall ADT-op.
    (define (register-kernel! pelt)
      (nanopass-case (Lflattened Program-Element) pelt
        [(kernel-declaration ,public-binding)
         (nanopass-case (Lflattened Public-Ledger-Binding) public-binding
           [(,src ,ledger-field-name (,path-index* ...) ,primitive-type)
            (set! kernel-ledger-field-name ledger-field-name)
            (nanopass-case (Lflattened Primitive-Type) primitive-type
              [(tadt ,src^ ,adt-name ([,adt-formal* ,adt-arg*] ...) ,vm-expr (,adt-op* ...))
               (for-each
                 (lambda (adt-op)
                   (nanopass-case (Lflattened ADT-Op) adt-op
                     [(,ledger-op ,op-class (,adt-name (,adt-formal* ,adt-arg*) ...)
                                  (,ledger-op-formal* ...) (,type* ...) ,type ,vm-code)
                      (when (eq? ledger-op 'claimContractCall)
                        (set! kernel-claim-adt-op adt-op))]))
                 adt-op*)]
              [else (void)])])]
        [else (void)]))
    ;; Create a transientCommit native committing to
    ;; (args ++ results) for circuit `elt-name`, push it, return its name.
    (define (synth-tc-native! src elt-name primitive-type)
      (nanopass-case (Lflattened Primitive-Type) primitive-type
        [(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
         (let loop ([elt-name* elt-name*] [type** type**] [type* type*])
           (cond
             [(null? elt-name*)
              (internal-errorf 'desugar-contract-calls
                "contract-call references unknown circuit ~s" elt-name)]
             [(eq? (car elt-name*) elt-name)
              (let* ([all-tys (append (car type**) (list (car type*)))]
                     [aligns (apply append (map type-aligns all-tys))]
                     [prims  (apply append (map type-prims all-tys))]
                     [value-vars (map (lambda (_) (make-temp-id src 'v)) prims)]
                     [nm (make-temp-id src 'transientCommit)])
                (set! synth-natives
                  (cons
                    (with-output-language (Lflattened Native-Declaration)
                      `(native ,src ,nm
                         ,(make-native-entry "__compactRuntime.transientCommit"
                                             'circuit '(#f #f) '(#f #f #f))
                         ((argument (,value-vars ...) (ty (,aligns ...) (,prims ...)))
                          (argument (,(make-temp-id src 'rand))
                                    (ty ((afield)) ((tfield (field-native))))))
                         (ty ((afield)) ((tfield (field-native))))))
                    synth-natives))
                nm)]
             [else (loop (cdr elt-name*) (cdr type**) (cdr type*))]))]
        [else
         (internal-errorf 'desugar-contract-calls
           "contract-call primitive-type is not a tcontract")]))
    ;; Extend a return type by [cc-rand : Field, ep-mod : Field<2^8>, ep-div : Field<2^248>]
    (define (extend-ret-type ret-ty)
      (nanopass-case (Lflattened Type) ret-ty
        [(ty (,alignment* ...) (,primitive-type* ...))
         (with-output-language (Lflattened Type)
           `(ty (,alignment* ... (afield) (afield) (afield))
                (,primitive-type* ...
                 (tfield (field-native))
                 (tunsigned ,(max 0 (- (expt 2 8) 1)))
                 (tunsigned ,(max 0 (- (expt 2 (* (field-bytes) 8)) 1))))))]))
    ;; Rebuild a tcontract with circuit `elt-name`'s return type extended.
    (define (extend-tcontract elt-name primitive-type)
      (nanopass-case (Lflattened Primitive-Type) primitive-type
        [(tcontract ,contract-name (,elt-name* ,pure-dcl* (,type** ...) ,type*) ...)
         (let ([new-type*
                (map (lambda (en t) (if (eq? en elt-name) (extend-ret-type t) t))
                     elt-name* type*)])
           (with-output-language (Lflattened Primitive-Type)
             `(tcontract ,contract-name
                (,elt-name* ,pure-dcl* (,type** ...) ,new-type*) ...)))]
        [else
         (internal-errorf 'desugar-contract-calls
           "contract-call primitive-type is not a tcontract")]))

    (define (rewrite-stmt stmt)
      (nanopass-case (Lflattened Statement) stmt
        [(= ,test (,var-name* ...)
            (contract-call ,src ,elt-name ((,recv* ...) ,primitive-type) ,triv* ...))
         (unless kernel-claim-adt-op
           (internal-errorf 'desugar-contract-calls
             "no kernel-declaration with a claimContractCall ADT-op"))
         (let ([tc-name (synth-tc-native! src elt-name primitive-type)]
               [cc-rand (make-temp-id src 'cc-rand)]
               [ep-mod  (make-temp-id src 'ep-mod)]
               [ep-div  (make-temp-id src 'ep-div)]
               [comm    (make-temp-id src 'comm)]
               [tc^     (extend-tcontract elt-name primitive-type)])
           (with-output-language (Lflattened Statement)
             (list
               `(= ,test (,var-name* ... ,cc-rand ,ep-mod ,ep-div)
                   (contract-call ,src ,elt-name ((,recv* ...) ,tc^) ,triv* ...))
               `(= ,test (,comm)
                   (call ,src ,tc-name ,triv* ... ,var-name* ... ,cc-rand))
               `(= ,test ()
                   (public-ledger ,src ,kernel-ledger-field-name #f () ,src
                     ,kernel-claim-adt-op ,recv* ... ,ep-mod ,ep-div ,comm)))))]
        [else (list stmt)]))
    (define (rewrite-pelt pelt)
      (nanopass-case (Lflattened Program-Element) pelt
        [(circuit ,src ,function-name (,arg* ...) ,type ,stmt* ... (,triv* ...))
         (with-output-language (Lflattened Circuit-Definition)
           `(circuit ,src ,function-name (,arg* ...) ,type
              ,(apply append (map rewrite-stmt stmt*)) ...
              (,triv* ...)))]
        [else pelt])))
  (Program : Program (ir) -> Program ()
    [(program ,src ((,export-name* ,name*) ...) ,pelt* ...)
     (for-each register-kernel! pelt*)
     (let ([new-pelt* (map rewrite-pelt pelt*)])
       `(program ,src ((,export-name* ,name*) ...) ,synth-natives ... ,new-pelt* ...))])
  (Program ir))
