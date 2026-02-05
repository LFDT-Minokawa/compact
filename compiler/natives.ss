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

(library (natives) 
  (export native-declarations)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (nanopass)
          (langs))

  (define (native-declarations)
    (define ndecl* '())
    (define native-src (make-source-object (assert (stdlib-sfd)) 0 0 1 1))

    (define-syntax declare-native-entry
      (lambda (q)
        (define (f class name type-param* function argument-name* argument-type* disclosure* result-type)
          (define (convert-outer-type type)
            (define (convert-native-type type)
              (define (convert-native-targ targ)
                #`(targ-type ,native-src #,(convert-native-type targ)))
              (syntax-case type (TypeRef Boolean Field Bytes Void)
                [(TypeRef id targ ...) #`(type-ref ,native-src id #,@(map convert-native-targ #'(targ ...)))]
                [Boolean #'(tboolean ,native-src)]
                [Field #'(tfield ,native-src)]
                [(Bytes nat) (field? (datum nat)) #`(tbytes ,native-src (type-size ,native-src ,nat))]
                [Void #`(ttuple ,native-src)]
                [other (syntax-error #'other "unrecognized native type")]))
            (syntax-case type ()
              [id (memq (datum id) (map syntax->datum type-param*)) #'(type-ref ,native-src id)]
              [else (convert-native-type type)]))
          (define (convert-native-argument name type)
            #`(,native-src #,name #,(convert-outer-type type)))
          (define (convert-type-param tvar-name)
            #`(type-valued ,native-src #,tvar-name))
          (define (maybe-type-param type)
            (syntax-case type ()
              [id (memq (datum id) (map syntax->datum type-param*)) #'id]
              [else #f]))
          (define (parse-disclosure disclosure)
            (syntax-case disclosure (discloses nothing)
              [(discloses nothing) #f]
              [(discloses what) (string? (datum what)) #'what]
              [other (syntax-error #'other "invalid discloses syntax")]))
          (unless (identifier? name) (syntax-error name "non-identifier name"))
          (for-each
            (lambda (type-param)
              (unless (identifier? type-param) (syntax-error type-param "non-identifier type-param")))
            type-param*)
          (unless (string? (syntax->datum function)) (syntax-error function "non-string function"))
          #`(set! ndecl*
              (cons
                (with-output-language (Lpreexpand Native-Declaration)
                  `(native ,native-src #t #,name
                     ,(make-native-entry
                        #,function
                        '#,(case (syntax->datum class)
                             [(circuit) class]
                             [(witness) class]
                             [else (syntax-error class "invalid class")])
                        '#,(map parse-disclosure disclosure*)
                        '#,(map maybe-type-param (append argument-type* (list result-type))))
                     (#,@(map convert-type-param type-param*))
                     (#,@(map convert-native-argument argument-name* argument-type*))
                     #,(convert-outer-type result-type)))
                ndecl*)))
        (syntax-case q ()
          [(_ class name [type-param ...] function ([argument-name argument-type disclosure] ...) result-type)
           (f #'class #'name #'(type-param ...) #'function #'(argument-name ...) #'(argument-type ...) #'(disclosure ...) #'result-type)]
          [(_ class name function ([argument-name argument-type disclosure] ...) result-type)
           (f #'class #'name '() #'function #'(argument-name ...) #'(argument-type ...) #'(disclosure ...) #'result-type)])))
    (include "midnight-natives.ss")
    (reverse ndecl*))
)
