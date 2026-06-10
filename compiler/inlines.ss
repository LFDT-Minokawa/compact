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
        (define (f name type-param* argument-name* argument-type* result-type body)
          (define (convert-type-param type-param)
            (syntax-case type-param (nat)
              [(nat n) (identifier? #'n)  #`(nat-valued  ,inline-src n)]
              [t (identifier? #'t)        #`(type-valued ,inline-src t)]
              [other (syntax-error #'other "type-param must be an identifier or (nat <id>)")]))
          (define (convert-type type)
            (syntax-case type (Bytes)
              [id (identifier? #'id) #'(type-ref ,inline-src id)]
              [(Bytes nat) (identifier? #'nat) #`(tbytes ,inline-src (type-size-ref ,inline-src nat))]
              [other (syntax-error #'other "unrecognized inline type")]))
          (define (convert-inline-argument name type)
            #`(,inline-src #,name #,(convert-type type)))

          ;; Build a symbol table from the inline's declared names.
          ;; This is used by `walk' below to decide how to rewrite each
          ;; identifier leaf in the DSL body.
          (define symbol-table
            (let ([t (make-eq-hashtable)])
              (hashtable-set! t 'src 'src)
              (for-each
                (lambda (tp)
                  (syntax-case tp (nat)
                    [(nat id) (identifier? #'id)
                     (hashtable-set! t (syntax->datum #'id) 'nat-tp)]
                    [id (identifier? #'id)
                     (hashtable-set! t (syntax->datum #'id) 'type-tp)]))
                type-param*)
              (for-each
                (lambda (an)
                  (hashtable-set! t (syntax->datum an) 'arg))
                argument-name*)
              t))

          ;; Walks a DSL body expression. Returns a syntax object that goes
          ;; INSIDE a nanopass quasiquote — list heads stay literal (they're
          ;; Lpreexpand form names), and identifier leaves get rewritten into
          ;; the appropriate reference form. The (unquote inline-src) outputs
          ;; are how the resulting nanopass quasiquote will substitute
          ;; inline-src at runtime.
          (define (walk e)
            (syntax-case e ()
              ;; Identifier leaf: look up its kind in the symbol table.
              [id (identifier? #'id)
               (let ([kind (hashtable-ref symbol-table (syntax->datum #'id) #f)])
                 (case kind
                   [(src)     #'(unquote inline-src)]
                   [(nat-tp)  #`(type-size-ref (unquote inline-src) #,#'id)]
                   [(type-tp) #`(type-ref      (unquote inline-src) #,#'id)]
                   [(arg)     #`(var-ref       (unquote inline-src) #,#'id)]
                   [else (syntax-error #'id
                           (format "unbound identifier `~a' in inline body"
                                   (syntax->datum #'id)))]))]
              ;; Compound: keep the head, walk each slot.
              [(head slot ...)
               (identifier? #'head)
               (with-syntax ([(slot^ ...) (map walk (syntax->list #'(slot ...)))])
                 #'(head slot^ ...))]
              ;; Constants pass through.
              [k (or (number?  (syntax->datum #'k))
                     (boolean? (syntax->datum #'k))
                     (string?  (syntax->datum #'k)))
               #'k]
              [other (syntax-error #'other "unsupported form in inline body")]))

          (unless (identifier? name) (syntax-error name "non-identifier name"))
          (let ([result-type (convert-type result-type)]
                [walked-body (walk body)])
            #`(set! inline-decl*
                (cons
                  ;; Construct the body IR via with-output-language at runtime,
                  ;; then bind it via let so the outer Circuit-Definition's
                  ;; nanopass quasiquote can splice it with ,body.
                  (let ([body (with-output-language (Lpreexpand Expression)
                                (quasiquote #,walked-body))])
                    (with-output-language (Lpreexpand Circuit-Definition)
                      `(circuit ,inline-src
                                #t                                        ; exported?
                                #t                                        ; pure-dcl?
                                #,name                                    ; function-name
                                (#,@(map convert-type-param type-param*)) ; type-params
                                (#,@(map convert-inline-argument argument-name* argument-type*)) ; args
                                #,result-type                             ; return-type
                                (block ,inline-src ()
                                  (return ,inline-src ,body)))))
                  inline-decl*))))

        (syntax-case q ()
          [(_ name [type-param ...] ([argument-name argument-type] ...) result-type body)
           (f #'name #'(type-param ...) #'(argument-name ...) #'(argument-type ...) #'result-type #'body)])))

    (include "midnight-inlines.ss")
    (reverse inline-decl*))
)
