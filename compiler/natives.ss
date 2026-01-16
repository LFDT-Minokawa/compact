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
  (export
    native-nat-case
    native-nat-value
    native-nat-param
    native-type-case
    native-type-boolean
    native-type-field
    native-type-unsigned
    native-type-opaque
    native-type-bytes
    native-type-vector
    native-type-struct
    native-type-alias
    native-type-void
    native-type-param
    native-entry?
    native-entry-name
    native-entry-class
    native-entry-disclosures
    native-entry-type-params
    native-entry-function
    native-entry-argument-types
    native-entry-result-type
    native-table)
  (import (except (chezscheme) errorf)
          (utils)
          (datatype)
          (field))

  (define-datatype native-nat
    (native-nat-value n)
    (native-nat-param name))

  (define-datatype native-type
    (native-type-boolean)
    (native-type-field)
    (native-type-unsigned native-nat)
    (native-type-opaque str)
    (native-type-bytes native-nat)
    (native-type-vector native-nat native-type)
    (native-type-struct native-type*)
    (native-type-alias name)
    (native-type-void)
    (native-type-param name))

  (define-record-type native-entry
    (nongenerative)
    (fields name class type-params function disclosures argument-types result-type))

  (define native-table (make-hashtable symbol-hash eq?))

  (define-syntax declare-native-entry
    (lambda (q)
      (define (f class name type-param* function argument-type* disclosure* result-type)
        (define (convert-native-nat type)
          (syntax-case type ()
            [id (memq (datum id) (map syntax->datum type-param*)) #'(native-nat-param 'id)]
            [nat (field? (datum nat)) #'(native-nat-value nat)]
            [other (syntax-error #'other "invalid nat")]))
        (define (convert-native-type type)
          (syntax-case type (Boolean Field Uint Opaque Bytes Vector Struct Void Alias)
            [id
             (memq (datum id) (map syntax->datum type-param*))
             #'(native-type-param 'id)]
            [Boolean #'(native-type-boolean)]
            [Field #'(native-type-field)]
            [(Uint nat)
             #`(native-type-unsigned #,(convert-native-nat #'nat))]
            [(Opaque str)
             #`(native-type-opaque str)]
            [(Bytes nat)
             #`(native-type-bytes #,(convert-native-nat #'nat))]
            [(Vector nat type)
             #`(native-type-vector #,(convert-native-nat #'nat) #,(convert-native-type #'type))]
            [(Struct type ...)
             #`(native-type-struct (list #,@(map convert-native-type #'(type ...))))]
            [(Alias name) #`(native-type-alias 'name)]
            [Void #`(native-type-void)]
            [other (syntax-error #'other "invalid native type")]))
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
        #`(hashtable-set! native-table '#,name
            (make-native-entry
              '#,name
              '#,(case (syntax->datum class)
                   [(external) class]
                   [(witness) class]
                   [else (syntax-error class "invalid class")])
              '#,type-param*
              #,function
              '#,(map parse-disclosure disclosure*)
              (list #,@(map convert-native-type argument-type*))
              #,(convert-native-type result-type))))
      (syntax-case q ()
        [(_ class name [type-param ...] function ([argument-type disclosure] ...) result-type)
         (f #'class #'name #'(type-param ...) #'function #'(argument-type ...) #'(disclosure ...) #'result-type)]
        [(_ class name function ([argument-type disclosure] ...) result-type)
         (f #'class #'name '() #'function #'(argument-type ...) #'(disclosure ...) #'result-type)])))

  (let ()
    (include "midnight-natives.ss")
    (void))
)
