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

(library (pass-helpers)
  (export target-ports get-target-port target-directory source-directory source-file-name
          contract-ht
          define-passes define-checker checkers
          passrec-name passrec-pass passrec-unparse passrec-pretty-formats
          no-communications-commitment)
  (import (except (chezscheme) errorf)
          (utils))

  (define no-communications-commitment (make-parameter #f))

  (define target-ports (make-parameter '()))
  (define (get-target-port x)
    (cond
      [(assq x (target-ports)) => cdr]
      [else (internal-errorf 'get-target-port "~s not found" x)]))
  (define target-directory (make-parameter #f))
  (define source-directory (make-parameter #f))
  ; source-file-name is used for getting the contract name from the source file
  ; for the print-TS pass.
  (define source-file-name (make-parameter #f))

  (define contract-ht (make-parameter #f))

  (define-record-type passrec
    (nongenerative)
    (fields name pass unparse pretty-formats))

  (define-syntax define-passes
    (lambda (x)
      (define (do-clause clause)
        (syntax-case clause ()
          [(pass lang)
           (with-syntax ([unparse (datum->syntax #'lang (string->symbol (format "unparse-~a" (datum lang))))]
                         [pretty-formats (datum->syntax #'lang (string->symbol (format "~a-pretty-formats" (datum lang))))])
             #'(make-passrec 'pass pass unparse (pretty-formats)))]))
      (syntax-case x ()
        [(_ name clause ...)
         #`(define name (list #,@(map do-clause #'(clause ...))))])))

  (module (define-checker checkers)
    (define checkers (make-eq-hashtable))
    (define-syntax define-checker
      (lambda (x)
        (define (unparser lang)
          (datum->syntax lang (string->symbol (format "unparse-~a" (syntax->datum lang)))))
        (syntax-case x ()
          [(_ pass lang)
           (with-syntax ([unparse (datum->syntax #'lang (string->symbol (format "unparse-~a" (datum lang))))])
             #`(hashtable-set! checkers unparse pass))])))
    (indirect-export define-checker checkers))
)
