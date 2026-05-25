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

(library (inlines)
  (export inline-declarations)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs))

  (define (inline-declarations)
    (define inline-decl* '())
    (define inline-src (make-source-object (assert (stdlib-sfd)) 0 0 1 1))

    (define-syntax declare-inline-entry
      (lambda (q)
        (define (f name type-param* argument-name* argument-type* result-type)
          (define (convert-type-param type-param)
            (syntax-case type-param (nat)
              [(nat n) (identifier? #'n)  #`(nat-valued  ,inline-src n)]
              [t (identifier? #'t) #`(type-valued ,inline-src t)]
              [other (syntax-error #'other "type-param must be an identifier or (nat <id>)")]))
          (define (convert-type type)
            (syntax-case type (Bytes)
              [id (identifier? #'id) #'(type-ref ,inline-src id)]
              [(Bytes nat) (identifier? #'nat) #`(tbytes ,inline-src (type-size-ref ,inline-src nat))]
              [other (syntax-error #'other "unrecognized inline type")]))
          (define (convert-inline-argument name type)
            #`(,inline-src #,name #,(convert-type type)))
          (unless (identifier? name) (syntax-error name "non-identifier name"))
          (let ([result-type (convert-type result-type)])
            #`(set! inline-decl*
                (cons
                  (with-output-language (Lpreexpand Circuit-Definition)
                    `(circuit ,inline-src
                              #t                                        ; exported?
                              #t                                        ; pure-dcl?
                              #,name                                    ; function-name
                              (#,@(map convert-type-param type-param*)) ; type-params
                              (#,@(map convert-inline-argument argument-name* argument-type*)) ; args
                              #,result-type                             ; return-type
                              (return ,inline-src (default ,inline-src #,result-type)))) ; expr (body returns a default value of return type, this will be filled in later in ?? pass)
                  inline-decl*))))
          (syntax-case q ()
          [(_ name [type-param ...] ([argument-name argument-type] ...) result-type)
           (f #'name #'(type-param ...) #'(argument-name ...) #'(argument-type ...) #'result-type)])))
    (include "midnight-inlines.ss")
    (reverse inline-decl*))
)
